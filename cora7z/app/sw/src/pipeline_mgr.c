/**
 * @file pipeline_mgr.c
 * @brief Heterogeneous PS/PL Compress-then-Encrypt Pipeline Manager Implementation.
 *
 * Implements bare-metal drivers for Dual-Port BRAM accelerators (LZSS and AES-128-CTR)
 * with ARM PMU cycle instrumentation, watchdog timeout protection, and automated
 * bit-exact parity verification across all 4 execution scenarios.
 */

#include "pipeline_mgr.h"
#include "lzss_sw.h"
#include "aes_ctr_sw.h"
#include "axi_io.h"
#include <string.h>

#if defined(__arm__) || defined(__aarch64__)
#include "xparameters.h"
#include "xil_printf.h"
#define PIPELINE_LOG xil_printf
#else
#include <stdio.h>
#define PIPELINE_LOG printf
#endif

/* Cortex-A9 CPU Clock Frequency on Digilent Cora Z7-10: 666,666,667 Hz (667 MHz) */
#define CPU_CLOCK_FREQ_MHZ 667U

/* Pre-allocated static buffers (aligned to 32-bit cache line boundaries) */
static uint8_t s_comp_buf[PIPELINE_MAX_FRAME_SIZE] __attribute__((aligned(4)));
static uint8_t s_dec_buf[PIPELINE_MAX_FRAME_SIZE] __attribute__((aligned(4)));
static lzss_workspace_t s_lzss_ws;

/* Standard 128-bit Symmetric Key and Base IV (NIST SP 800-38A compliant) */
static const uint8_t s_pipeline_key[AES_CTR_KEY_SIZE] = {
    0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
    0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c
};

static const uint8_t s_pipeline_iv[AES_CTR_BLOCK_SIZE] = {
    0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7,
    0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
};

/* ========================================================================= */
/* Low-Level Helper Functions                                                */
/* ========================================================================= */

/**
 * @brief Read ARM PMU 32-bit cycle counter (PMCCNTR).
 */
static inline uint32_t read_pmu_cycles(void) {
#if defined(__arm__)
    uint32_t cycles;
    __asm__ volatile("isb; mrc p15, 0, %0, c9, c13, 0; isb" : "=r"(cycles) :: "memory");
    return cycles;
#else
    return 0U;
#endif
}

/**
 * @brief Convert Cortex-A9 CPU cycles to microseconds.
 */
static inline uint32_t cycles_to_us(uint32_t cycles) {
    return cycles / CPU_CLOCK_FREQ_MHZ;
}

/**
 * @brief Check if FPGA fabric (PL) is programmed via DEVCFG status register.
 */
bool pipeline_is_pl_ready(void) {
#if defined(__arm__) || defined(__aarch64__)
    volatile uint32_t *pcfg_status = (volatile uint32_t *)0xF800700CU;
    return (*pcfg_status & (1U << 2)) != 0U;
#else
    return true; /* Host simulation assumes PL is ready */
#endif
}

/**
 * @brief Burst write a byte stream into Dual-Port BRAM using 32-bit words.
 *
 * Enforces strictly 32-bit aligned memory-mapped transactions across the AXI
 * Interconnect to eliminate unaligned bus faults or byte-enable stalls.
 *
 * @param[in] dest_bram_addr Physical base address of target BRAM aperture.
 * @param[in] src            Source buffer pointer.
 * @param[in] len            Payload length in bytes.
 */
static inline void bram_burst_write(uintptr_t dest_bram_addr, const uint8_t *src, size_t len) {
    size_t words = len / 4U;
    size_t rem   = len % 4U;
    const uint32_t *src32 = (const uint32_t *)src;

    if (((uintptr_t)src & 0x3U) == 0U) {
        for (size_t i = 0; i < words; i++) {
            AXI_IO_WRITE32(dest_bram_addr + (i * 4U), src32[i]);
        }
    } else {
        for (size_t i = 0; i < words; i++) {
            size_t b = i * 4U;
            uint32_t w = ((uint32_t)src[b + 0])        |
                         (((uint32_t)src[b + 1]) << 8)  |
                         (((uint32_t)src[b + 2]) << 16) |
                         (((uint32_t)src[b + 3]) << 24);
            AXI_IO_WRITE32(dest_bram_addr + b, w);
        }
    }

    if (rem > 0U) {
        size_t b = words * 4U;
        uint32_t w = 0U;
        for (size_t j = 0; j < rem; j++) {
            w |= (((uint32_t)src[b + j]) << (j * 8U));
        }
        AXI_IO_WRITE32(dest_bram_addr + b, w);
    }
}

/**
 * @brief Burst read a byte stream from Dual-Port BRAM using 32-bit words.
 *
 * @param[in]  src_bram_addr Physical base address of target BRAM aperture.
 * @param[out] dst           Destination buffer pointer.
 * @param[in]  len           Payload length in bytes.
 */
static inline void bram_burst_read(uintptr_t src_bram_addr, uint8_t *dst, size_t len) {
    size_t words = len / 4U;
    size_t rem   = len % 4U;
    uint32_t *dst32 = (uint32_t *)dst;

    if (((uintptr_t)dst & 0x3U) == 0U) {
        for (size_t i = 0; i < words; i++) {
            dst32[i] = AXI_IO_READ32(src_bram_addr + (i * 4U));
        }
    } else {
        for (size_t i = 0; i < words; i++) {
            uint32_t w = AXI_IO_READ32(src_bram_addr + (i * 4U));
            size_t b = i * 4U;
            dst[b + 0] = (uint8_t)(w & 0xFFU);
            dst[b + 1] = (uint8_t)((w >> 8) & 0xFFU);
            dst[b + 2] = (uint8_t)((w >> 16) & 0xFFU);
            dst[b + 3] = (uint8_t)((w >> 24) & 0xFFU);
        }
    }

    if (rem > 0U) {
        uint32_t w = AXI_IO_READ32(src_bram_addr + (words * 4U));
        size_t b = words * 4U;
        for (size_t j = 0; j < rem; j++) {
            dst[b + j] = (uint8_t)((w >> (j * 8U)) & 0xFFU);
        }
    }
}

/* ========================================================================= */
/* Pipeline Initialization & Self-Tests                                      */
/* ========================================================================= */

int pipeline_init(void) {
    /* Verify AES-128-CTR software self-test against NIST SP 800-38A */
    int rc = aes_128_ctr_self_test();
    if (rc != 0) {
        return PIPELINE_ERR_ENCRYPTION;
    }

    memset(s_comp_buf, 0, sizeof(s_comp_buf));
    memset(s_dec_buf, 0, sizeof(s_dec_buf));
    memset(&s_lzss_ws, 0, sizeof(s_lzss_ws));

    /* If PL is ready, execute soft reset on hardware coprocessors */
    if (pipeline_is_pl_ready()) {
        AXI_IO_WRITE32(LZSS_CSR_BASEADDR + ACCEL_REG_CTRL, ACCEL_CTRL_RESET);
        AXI_IO_WRITE32(AES_CSR_BASEADDR  + ACCEL_REG_CTRL, ACCEL_CTRL_RESET);
    }

    return PIPELINE_SUCCESS;
}

/* ========================================================================= */
/* Hardware Accelerator Offload Drivers                                      */
/* ========================================================================= */

int pipeline_lzss_hw_compress(const uint8_t *src,
                              size_t src_len,
                              uint8_t *dst,
                              size_t *dst_len,
                              uint32_t *hw_cycles) {
    if (src == NULL || dst == NULL || dst_len == NULL) {
        return PIPELINE_ERR_PARAM;
    }
    if (src_len == 0U || src_len > ACCEL_BRAM_CAPACITY_BYTES) {
        return PIPELINE_ERR_PARAM;
    }
    if (!pipeline_is_pl_ready()) {
        return PIPELINE_ERR_PL_NOT_READY;
    }

    /* 1. Flush source data from L1/L2 cache before BRAM staging */
    AXI_DCACHE_FLUSH(src, src_len);

    /* 2. Clear status and apply synchronous reset before new transaction */
    AXI_IO_WRITE32(LZSS_CSR_BASEADDR + ACCEL_REG_CTRL, ACCEL_CTRL_RESET);

    /* 3. Stage uncompressed payload into Input Dual-Port BRAM */
    bram_burst_write(LZSS_BRAM_IN_BASEADDR, src, src_len);

    /* 4. Configure input length register */
    AXI_IO_WRITE32(LZSS_CSR_BASEADDR + ACCEL_REG_INPUT_LEN, (uint32_t)src_len);

    /* 5. Pulse START bit in Control Register */
    AXI_IO_WRITE32(LZSS_CSR_BASEADDR + ACCEL_REG_CTRL, ACCEL_CTRL_START);

    /* 6. Wait for core to acknowledge START and clear previous DONE */
    uint32_t watchdog = 0U;
    uint32_t status = 0U;
    while (watchdog < 1000U) {
        status = AXI_IO_READ32(LZSS_CSR_BASEADDR + ACCEL_REG_STATUS);
        if ((status & ACCEL_STATUS_DONE) == 0U) {
            break;
        }
        watchdog++;
    }

    /* 7. Poll Status Register for DONE with bounded watchdog */
    watchdog = 0U;
    while (watchdog < ACCEL_WATCHDOG_MAX_ITERS) {
        status = AXI_IO_READ32(LZSS_CSR_BASEADDR + ACCEL_REG_STATUS);
        if ((status & ACCEL_STATUS_DONE) != 0U) {
            break;
        }
        if ((status & ACCEL_STATUS_ERROR) != 0U) {
            return PIPELINE_ERR_COMPRESSION;
        }
        watchdog++;
    }

    if (watchdog >= ACCEL_WATCHDOG_MAX_ITERS) {
        /* Watchdog timeout; reset core to restore system integrity */
        AXI_IO_WRITE32(LZSS_CSR_BASEADDR + ACCEL_REG_CTRL, ACCEL_CTRL_RESET);
        return PIPELINE_ERR_LZSS_TIMEOUT;
    }

    /* 7. Read compressed output length and cycle counter */
    uint32_t compressed_len = AXI_IO_READ32(LZSS_CSR_BASEADDR + ACCEL_REG_OUTPUT_LEN);
    uint32_t cycles = AXI_IO_READ32(LZSS_CSR_BASEADDR + ACCEL_REG_CYCLES);

    if (hw_cycles != NULL) {
        *hw_cycles = cycles;
    }

    if ((size_t)compressed_len > *dst_len) {
        return PIPELINE_ERR_OVERFLOW;
    }

    *dst_len = (size_t)compressed_len;

    /* 8. Burst read compressed bitstream from Output Dual-Port BRAM */
    bram_burst_read(LZSS_BRAM_OUT_BASEADDR, dst, (size_t)compressed_len);

    return PIPELINE_SUCCESS;
}

int pipeline_aes_hw_crypt(const uint8_t *key,
                          const uint8_t *iv,
                          const uint8_t *src,
                          size_t len,
                          uint8_t *dst,
                          uint32_t *hw_cycles) {
    if (key == NULL || iv == NULL || src == NULL || dst == NULL) {
        return PIPELINE_ERR_PARAM;
    }
    if (len == 0U) {
        if (hw_cycles != NULL) *hw_cycles = 0U;
        return PIPELINE_SUCCESS;
    }
    if (len > ACCEL_BRAM_CAPACITY_BYTES) {
        return PIPELINE_ERR_OVERFLOW;
    }
    if (!pipeline_is_pl_ready()) {
        return PIPELINE_ERR_PL_NOT_READY;
    }

    /* 1. Flush source buffer from L1/L2 cache */
    AXI_DCACHE_FLUSH(src, len);

    /* 2. Program 128-bit Key Registers in Big-Endian Word Layout */
    uint32_t k0 = (((uint32_t)key[0]) << 24) | (((uint32_t)key[1]) << 16) |
                  (((uint32_t)key[2]) << 8)  | ((uint32_t)key[3]);
    uint32_t k1 = (((uint32_t)key[4]) << 24) | (((uint32_t)key[5]) << 16) |
                  (((uint32_t)key[6]) << 8)  | ((uint32_t)key[7]);
    uint32_t k2 = (((uint32_t)key[8]) << 24) | (((uint32_t)key[9]) << 16) |
                  (((uint32_t)key[10]) << 8) | ((uint32_t)key[11]);
    uint32_t k3 = (((uint32_t)key[12]) << 24) | (((uint32_t)key[13]) << 16) |
                  (((uint32_t)key[14]) << 8) | ((uint32_t)key[15]);

    AXI_IO_WRITE32(AES_CSR_BASEADDR + AES_REG_KEY0, k0);
    AXI_IO_WRITE32(AES_CSR_BASEADDR + AES_REG_KEY1, k1);
    AXI_IO_WRITE32(AES_CSR_BASEADDR + AES_REG_KEY2, k2);
    AXI_IO_WRITE32(AES_CSR_BASEADDR + AES_REG_KEY3, k3);

    /* 3. Program 96-bit Nonce and 32-bit Counter Registers */
    uint32_t iv0 = (((uint32_t)iv[0]) << 24) | (((uint32_t)iv[1]) << 16) |
                   (((uint32_t)iv[2]) << 8)  | ((uint32_t)iv[3]);
    uint32_t iv1 = (((uint32_t)iv[4]) << 24) | (((uint32_t)iv[5]) << 16) |
                   (((uint32_t)iv[6]) << 8)  | ((uint32_t)iv[7]);
    uint32_t iv2 = (((uint32_t)iv[8]) << 24) | (((uint32_t)iv[9]) << 16) |
                   (((uint32_t)iv[10]) << 8) | ((uint32_t)iv[11]);
    uint32_t ctr = (((uint32_t)iv[12]) << 24) | (((uint32_t)iv[13]) << 16) |
                   (((uint32_t)iv[14]) << 8) | ((uint32_t)iv[15]);

    AXI_IO_WRITE32(AES_CSR_BASEADDR + AES_REG_IV0, iv0);
    AXI_IO_WRITE32(AES_CSR_BASEADDR + AES_REG_IV1, iv1);
    AXI_IO_WRITE32(AES_CSR_BASEADDR + AES_REG_IV2, iv2);
    AXI_IO_WRITE32(AES_CSR_BASEADDR + AES_REG_CTR_INIT, ctr);

    /* Clear status and apply synchronous reset before new transaction */
    AXI_IO_WRITE32(AES_CSR_BASEADDR + ACCEL_REG_CTRL, ACCEL_CTRL_RESET);

    /* 4. Stage Ingress Data into AES Input BRAM */
    bram_burst_write(AES_BRAM_IN_BASEADDR, src, len);

    /* 5. Set payload byte count */
    AXI_IO_WRITE32(AES_CSR_BASEADDR + ACCEL_REG_INPUT_LEN, (uint32_t)len);

    /* 6. Pulse START in Control Register */
    AXI_IO_WRITE32(AES_CSR_BASEADDR + ACCEL_REG_CTRL, ACCEL_CTRL_START);

    /* 7. Wait for core to acknowledge START and clear previous DONE */
    uint32_t watchdog = 0U;
    uint32_t status = 0U;
    while (watchdog < 1000U) {
        status = AXI_IO_READ32(AES_CSR_BASEADDR + ACCEL_REG_STATUS);
        if ((status & ACCEL_STATUS_DONE) == 0U) {
            break;
        }
        watchdog++;
    }

    /* 8. Poll Status Register for DONE */
    watchdog = 0U;
    while (watchdog < ACCEL_WATCHDOG_MAX_ITERS) {
        status = AXI_IO_READ32(AES_CSR_BASEADDR + ACCEL_REG_STATUS);
        if ((status & ACCEL_STATUS_DONE) != 0U) {
            break;
        }
        watchdog++;
    }

    if (watchdog >= ACCEL_WATCHDOG_MAX_ITERS) {
        AXI_IO_WRITE32(AES_CSR_BASEADDR + ACCEL_REG_CTRL, ACCEL_CTRL_RESET);
        return PIPELINE_ERR_AES_TIMEOUT;
    }

    /* 8. Read Hardware Cycle Counter */
    uint32_t cycles = AXI_IO_READ32(AES_CSR_BASEADDR + ACCEL_REG_CYCLES);
    if (hw_cycles != NULL) {
        *hw_cycles = cycles;
    }

    /* 9. Drain Ciphertext from AES Output BRAM */
    bram_burst_read(AES_BRAM_OUT_BASEADDR, dst, len);

    return PIPELINE_SUCCESS;
}

/* ========================================================================= */
/* 4-Scenario Benchmark Dispatcher                                           */
/* ========================================================================= */

int pipeline_process_frame_scenario(pipeline_scenario_t scenario,
                                    const uint8_t *raw_in,
                                    size_t raw_len,
                                    uint8_t *cipher_out,
                                    size_t max_out_len,
                                    size_t *final_len,
                                    pipeline_metrics_t *metrics) {
    if (raw_in == NULL || cipher_out == NULL || final_len == NULL) {
        return PIPELINE_ERR_PARAM;
    }
    if (raw_len == 0U || raw_len > PIPELINE_MAX_FRAME_SIZE) {
        return PIPELINE_ERR_PARAM;
    }

    size_t comp_len = sizeof(s_comp_buf);
    uint32_t comp_hw_cycles = 0U;
    uint32_t crypt_hw_cycles = 0U;

    /* --------------------------------------------------------------------- */
    /* Stage 1: Compression (SW or HW Offload)                               */
    /* --------------------------------------------------------------------- */
    uint32_t t_comp_start_cyc = read_pmu_cycles();
    int comp_rc;

    if (scenario == PIPELINE_SCENARIO_HW_SW || scenario == PIPELINE_SCENARIO_HW_HW) {
        comp_rc = pipeline_lzss_hw_compress(raw_in, raw_len, s_comp_buf, &comp_len, &comp_hw_cycles);
    } else {
        comp_rc = lzss_compress(raw_in, raw_len, s_comp_buf, &comp_len, &s_lzss_ws);
    }

    uint32_t t_comp_end_cyc = read_pmu_cycles();

    if (comp_rc != 0) {
        return (comp_rc == PIPELINE_ERR_LZSS_TIMEOUT) ? PIPELINE_ERR_LZSS_TIMEOUT : PIPELINE_ERR_COMPRESSION;
    }

    if (comp_len > max_out_len) {
        return PIPELINE_ERR_OVERFLOW;
    }

    /* --------------------------------------------------------------------- */
    /* Stage 2: Encryption (SW or HW Offload)                                */
    /* --------------------------------------------------------------------- */
    uint32_t t_crypt_start_cyc = read_pmu_cycles();
    int crypt_rc;

    if (scenario == PIPELINE_SCENARIO_SW_HW || scenario == PIPELINE_SCENARIO_HW_HW) {
        crypt_rc = pipeline_aes_hw_crypt(s_pipeline_key,
                                         s_pipeline_iv,
                                         s_comp_buf,
                                         comp_len,
                                         cipher_out,
                                         &crypt_hw_cycles);
    } else {
        crypt_rc = aes_128_ctr_crypt(s_pipeline_key,
                                     s_pipeline_iv,
                                     s_comp_buf,
                                     cipher_out,
                                     comp_len);
    }

    uint32_t t_crypt_end_cyc = read_pmu_cycles();

    if (crypt_rc != 0) {
        return (crypt_rc == PIPELINE_ERR_AES_TIMEOUT) ? PIPELINE_ERR_AES_TIMEOUT : PIPELINE_ERR_ENCRYPTION;
    }

    *final_len = comp_len;

    /* --------------------------------------------------------------------- */
    /* Stage 3: Instrumentation & Metric Consolidation                       */
    /* --------------------------------------------------------------------- */
    if (metrics != NULL) {
        metrics->scenario        = scenario;
        metrics->raw_len         = (uint32_t)raw_len;
        metrics->comp_len        = (uint32_t)comp_len;
        metrics->crypt_len       = (uint32_t)comp_len;
        metrics->comp_hw_cycles  = comp_hw_cycles;
        metrics->crypt_hw_cycles = crypt_hw_cycles;

        metrics->comp_cycles  = (t_comp_end_cyc >= t_comp_start_cyc) ?
                                (t_comp_end_cyc - t_comp_start_cyc) :
                                ((0xFFFFFFFFU - t_comp_start_cyc) + t_comp_end_cyc);
        metrics->crypt_cycles = (t_crypt_end_cyc >= t_crypt_start_cyc) ?
                                (t_crypt_end_cyc - t_crypt_start_cyc) :
                                ((0xFFFFFFFFU - t_crypt_start_cyc) + t_crypt_end_cyc);
        metrics->total_cycles = metrics->comp_cycles + metrics->crypt_cycles;

        metrics->comp_time_us  = cycles_to_us(metrics->comp_cycles);
        metrics->crypt_time_us = cycles_to_us(metrics->crypt_cycles);
        metrics->total_time_us = metrics->comp_time_us + metrics->crypt_time_us;

        if (raw_len > 0U) {
            metrics->compression_ratio = 1.0f - ((float)comp_len / (float)raw_len);
        } else {
            metrics->compression_ratio = 0.0f;
        }

        float elapsed_sec = (float)metrics->total_cycles / 666666667.0f;
        metrics->throughput_mbs = (elapsed_sec > 0.0f) ?
                                  (((float)raw_len / (1024.0f * 1024.0f)) / elapsed_sec) : 0.0f;
    }

    return PIPELINE_SUCCESS;
}

int pipeline_process_frame(const uint8_t *raw_in,
                           size_t raw_len,
                           uint8_t *cipher_out,
                           size_t max_out_len,
                           size_t *final_len,
                           pipeline_metrics_t *metrics) {
    /* If PL is ready, default to Case 4 (Full HW); otherwise fallback to Case 1 (Pure SW) */
    pipeline_scenario_t scen = pipeline_is_pl_ready() ?
                               PIPELINE_SCENARIO_HW_HW :
                               PIPELINE_SCENARIO_SW_SW;

    return pipeline_process_frame_scenario(scen,
                                           raw_in,
                                           raw_len,
                                           cipher_out,
                                           max_out_len,
                                           final_len,
                                           metrics);
}

int pipeline_reverse_frame(const uint8_t *cipher_in,
                           size_t cipher_len,
                           uint8_t *raw_out,
                           size_t max_out_len,
                           size_t *recovered_len) {
    if (cipher_in == NULL || raw_out == NULL || recovered_len == NULL || cipher_len == 0U) {
        return PIPELINE_ERR_PARAM;
    }
    if (cipher_len > sizeof(s_dec_buf)) {
        return PIPELINE_ERR_OVERFLOW;
    }

    /* 1. Decrypt ciphertext -> intermediate compressed stream */
    int crypt_rc = aes_128_ctr_crypt(s_pipeline_key,
                                     s_pipeline_iv,
                                     cipher_in,
                                     s_dec_buf,
                                     cipher_len);
    if (crypt_rc != 0) {
        return PIPELINE_ERR_ENCRYPTION;
    }

    /* 2. Decompress intermediate stream -> original raw payload */
    size_t decomp_len = max_out_len;
    int decomp_rc = lzss_decompress(s_dec_buf, cipher_len, raw_out, &decomp_len);
    if (decomp_rc != 0) {
        return PIPELINE_ERR_COMPRESSION;
    }

    *recovered_len = decomp_len;
    return PIPELINE_SUCCESS;
}

/* ========================================================================= */
/* Comprehensive 4-Scenario Bit-Exact Parity Verification Harness            */
/* ========================================================================= */

int pipeline_verify_all_scenarios(const uint8_t *raw_in, size_t raw_len) {
    if (raw_in == NULL || raw_len == 0U || raw_len > ACCEL_BRAM_CAPACITY_BYTES) {
        return PIPELINE_ERR_PARAM;
    }

    static uint8_t ct_sw_sw[PIPELINE_MAX_FRAME_SIZE];
    static uint8_t ct_hw_sw[PIPELINE_MAX_FRAME_SIZE];
    static uint8_t ct_sw_hw[PIPELINE_MAX_FRAME_SIZE];
    static uint8_t ct_hw_hw[PIPELINE_MAX_FRAME_SIZE];
    static uint8_t recovered[PIPELINE_MAX_FRAME_SIZE];

    size_t len_sw_sw = 0;
    size_t len_hw_sw = 0;
    size_t len_sw_hw = 0;
    size_t len_hw_hw = 0;
    size_t rec_len   = 0;

    pipeline_metrics_t m1 = {0};
    pipeline_metrics_t m2 = {0};
    pipeline_metrics_t m3 = {0};
    pipeline_metrics_t m4 = {0};

    /* Execute Case 1: Pure Software */
    int rc1 = pipeline_process_frame_scenario(PIPELINE_SCENARIO_SW_SW, raw_in, raw_len,
                                             ct_sw_sw, sizeof(ct_sw_sw), &len_sw_sw, &m1);
    if (rc1 != PIPELINE_SUCCESS) {
        PIPELINE_LOG("[VERIFY] Case 1 (SW/SW) failed: %d\r\n", rc1);
        return rc1;
    }

    /* If PL is not ready, we cannot test hardware offload cases */
    if (!pipeline_is_pl_ready()) {
        PIPELINE_LOG("[VERIFY] Warning: PL not programmed; skipping HW offload checks.\r\n");
        return PIPELINE_SUCCESS;
    }

    /* Execute Case 2: Compression Offload (HW LZSS -> SW AES) */
    int rc2 = pipeline_process_frame_scenario(PIPELINE_SCENARIO_HW_SW, raw_in, raw_len,
                                             ct_hw_sw, sizeof(ct_hw_sw), &len_hw_sw, &m2);
    if (rc2 != PIPELINE_SUCCESS) {
        PIPELINE_LOG("[VERIFY] Case 2 (HW/SW) failed: %d\r\n", rc2);
        return rc2;
    }

    /* Execute Case 3: Encryption Offload (SW LZSS -> HW AES) */
    int rc3 = pipeline_process_frame_scenario(PIPELINE_SCENARIO_SW_HW, raw_in, raw_len,
                                             ct_sw_hw, sizeof(ct_sw_hw), &len_sw_hw, &m3);
    if (rc3 != PIPELINE_SUCCESS) {
        PIPELINE_LOG("[VERIFY] Case 3 (SW/HW) failed: %d\r\n", rc3);
        return rc3;
    }

    /* Execute Case 4: Full Hardware Acceleration (HW LZSS -> HW AES) */
    int rc4 = pipeline_process_frame_scenario(PIPELINE_SCENARIO_HW_HW, raw_in, raw_len,
                                             ct_hw_hw, sizeof(ct_hw_hw), &len_hw_hw, &m4);
    if (rc4 != PIPELINE_SUCCESS) {
        PIPELINE_LOG("[VERIFY] Case 4 (HW/HW) failed: %d\r\n", rc4);
        return rc4;
    }

    /* Verify Parity: Case 3 (SW LZSS -> HW AES) must equal Case 1 (SW LZSS -> SW AES) */
    if (len_sw_hw != len_sw_sw || memcmp(ct_sw_hw, ct_sw_sw, len_sw_sw) != 0) {
        PIPELINE_LOG("[VERIFY] ERROR: Ciphertext mismatch between Case 3 (SW/HW) and Case 1 (SW/SW)!\r\n");
        PIPELINE_LOG("         len_sw_sw=%u, len_sw_hw=%u\r\n", (unsigned int)len_sw_sw, (unsigned int)len_sw_hw);
        PIPELINE_LOG("         s_comp_buf[0..15]:");
        for (size_t i = 0; i < 16 && i < len_sw_sw; i++) PIPELINE_LOG(" %02X", s_comp_buf[i]);
        PIPELINE_LOG("\r\n         ct_sw_sw  [0..15]:");
        for (size_t i = 0; i < 16 && i < len_sw_sw; i++) PIPELINE_LOG(" %02X", ct_sw_sw[i]);
        PIPELINE_LOG("\r\n         ct_sw_hw  [0..15]:");
        for (size_t i = 0; i < 16 && i < len_sw_hw; i++) PIPELINE_LOG(" %02X", ct_sw_hw[i]);
        PIPELINE_LOG("\r\n         AES_BRAM_IN [0..3]: 0x%08X 0x%08X 0x%08X 0x%08X\r\n",
                     (unsigned int)AXI_IO_READ32(AES_BRAM_IN_BASEADDR + 0),
                     (unsigned int)AXI_IO_READ32(AES_BRAM_IN_BASEADDR + 4),
                     (unsigned int)AXI_IO_READ32(AES_BRAM_IN_BASEADDR + 8),
                     (unsigned int)AXI_IO_READ32(AES_BRAM_IN_BASEADDR + 12));
        PIPELINE_LOG("         AES_BRAM_OUT[0..3]: 0x%08X 0x%08X 0x%08X 0x%08X\r\n",
                     (unsigned int)AXI_IO_READ32(AES_BRAM_OUT_BASEADDR + 0),
                     (unsigned int)AXI_IO_READ32(AES_BRAM_OUT_BASEADDR + 4),
                     (unsigned int)AXI_IO_READ32(AES_BRAM_OUT_BASEADDR + 8),
                     (unsigned int)AXI_IO_READ32(AES_BRAM_OUT_BASEADDR + 12));
        for (size_t i = 0; i < len_sw_sw; i++) {
            if (ct_sw_sw[i] != ct_sw_hw[i]) {
                PIPELINE_LOG("         First mismatch at byte %u: sw=0x%02X, hw=0x%02X (block %u, word %u, lane %u)\r\n",
                             (unsigned int)i, ct_sw_sw[i], ct_sw_hw[i],
                             (unsigned int)(i / 16), (unsigned int)((i % 16) / 4), (unsigned int)(i % 4));
                break;
            }
        }
        return PIPELINE_ERR_VERIFY_MISMATCH;
    }

    /* Verify Parity: Case 4 (HW LZSS -> HW AES) must equal Case 2 (HW LZSS -> SW AES) */
    if (len_hw_hw != len_hw_sw || memcmp(ct_hw_hw, ct_hw_sw, len_hw_sw) != 0) {
        PIPELINE_LOG("[VERIFY] ERROR: Ciphertext mismatch between Case 4 (HW/HW) and Case 2 (HW/SW)!\r\n");
        PIPELINE_LOG("         len_hw_sw=%u, len_hw_hw=%u\r\n", (unsigned int)len_hw_sw, (unsigned int)len_hw_hw);
        PIPELINE_LOG("         ct_hw_sw  [0..15]:");
        for (size_t i = 0; i < 16 && i < len_hw_sw; i++) PIPELINE_LOG(" %02X", ct_hw_sw[i]);
        PIPELINE_LOG("\r\n         ct_hw_hw  [0..15]:");
        for (size_t i = 0; i < 16 && i < len_hw_hw; i++) PIPELINE_LOG(" %02X", ct_hw_hw[i]);
        PIPELINE_LOG("\r\n");
        for (size_t i = 0; i < len_hw_sw; i++) {
            if (ct_hw_sw[i] != ct_hw_hw[i]) {
                PIPELINE_LOG("         First mismatch at byte %u: sw=0x%02X, hw=0x%02X (block %u, word %u, lane %u)\r\n",
                             (unsigned int)i, ct_hw_sw[i], ct_hw_hw[i],
                             (unsigned int)(i / 16), (unsigned int)((i % 16) / 4), (unsigned int)(i % 4));
                break;
            }
        }
        return PIPELINE_ERR_VERIFY_MISMATCH;
    }

    /* Verify Loopback: Decrypt & Decompress Case 4 output and verify bit-for-bit match with raw_in */
    int rc_rev = pipeline_reverse_frame(ct_hw_hw, len_hw_hw, recovered, sizeof(recovered), &rec_len);
    if (rc_rev != PIPELINE_SUCCESS || rec_len != raw_len || memcmp(raw_in, recovered, raw_len) != 0) {
        PIPELINE_LOG("[VERIFY] ERROR: Reverse loopback on Case 4 output failed or payload corrupted!\r\n");
        return PIPELINE_ERR_VERIFY_MISMATCH;
    }

    PIPELINE_LOG("[VERIFY] 4-Scenario Bit-Exact Parity & Loopback Verified! (Raw: %u B -> Comp: %u B)\r\n",
                 (unsigned int)raw_len, (unsigned int)len_hw_hw);
    PIPELINE_LOG("         Case 1 (SW/SW): %u CPU cyc\r\n", (unsigned int)m1.total_cycles);
    PIPELINE_LOG("         Case 2 (HW/SW): %u CPU cyc (LZSS PL: %u cyc)\r\n",
                 (unsigned int)m2.total_cycles, (unsigned int)m2.comp_hw_cycles);
    PIPELINE_LOG("         Case 3 (SW/HW): %u CPU cyc (AES  PL: %u cyc)\r\n",
                 (unsigned int)m3.total_cycles, (unsigned int)m3.crypt_hw_cycles);
    PIPELINE_LOG("         Case 4 (HW/HW): %u CPU cyc (LZSS PL: %u cyc, AES PL: %u cyc)\r\n",
                 (unsigned int)m4.total_cycles, (unsigned int)m4.comp_hw_cycles, (unsigned int)m4.crypt_hw_cycles);

    return PIPELINE_SUCCESS;
}
