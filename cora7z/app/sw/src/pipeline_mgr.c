/**
 * @file pipeline_mgr.c
 * @brief Autonomous Pure-Software Compress-then-Encrypt Pipeline Manager Implementation.
 */

#include "pipeline_mgr.h"
#include "lzss_sw.h"
#include "aes_ctr_sw.h"
#include <string.h>

/* Cortex-A9 CPU Clock Frequency on Digilent Cora Z7-10: 666,666,667 Hz (667 MHz) */
#define CPU_CLOCK_FREQ_MHZ 667U

/* Pre-allocated static buffers (aligned to 32-bit cache boundaries) */
static uint8_t s_comp_buf[PIPELINE_MAX_FRAME_SIZE] __attribute__((aligned(4)));
static uint8_t s_dec_buf[PIPELINE_MAX_FRAME_SIZE] __attribute__((aligned(4)));
static lzss_workspace_t s_lzss_ws;

/* Standard 128-bit Symmetric Key and Base IV */
static const uint8_t s_pipeline_key[AES_CTR_KEY_SIZE] = {
    0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
    0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c
};

static const uint8_t s_pipeline_iv[AES_CTR_BLOCK_SIZE] = {
    0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7,
    0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
};

/* ARM PMU cycle reading inline helper */
static inline uint32_t read_pmu_cycles(void) {
#if defined(__arm__)
    uint32_t cycles;
    __asm__ volatile("isb; mrc p15, 0, %0, c9, c13, 0; isb" : "=r"(cycles) :: "memory");
    return cycles;
#else
    return 0U;
#endif
}

static inline uint32_t cycles_to_us(uint32_t cycles) {
    return cycles / CPU_CLOCK_FREQ_MHZ;
}

int pipeline_init(void) {
    /* Verify AES-128-CTR self-test on initialization */
    int rc = aes_128_ctr_self_test();
    if (rc != 0) {
        return PIPELINE_ERR_ENCRYPTION;
    }

    memset(s_comp_buf, 0, sizeof(s_comp_buf));
    memset(s_dec_buf, 0, sizeof(s_dec_buf));
    memset(&s_lzss_ws, 0, sizeof(s_lzss_ws));

    return PIPELINE_SUCCESS;
}

int pipeline_process_frame(const uint8_t *raw_in,
                           size_t raw_len,
                           uint8_t *cipher_out,
                           size_t max_out_len,
                           size_t *final_len,
                           pipeline_metrics_t *metrics) {
    if (raw_in == NULL || cipher_out == NULL || final_len == NULL) {
        return PIPELINE_ERR_PARAM;
    }
    if (raw_len > PIPELINE_MAX_FRAME_SIZE || raw_len == 0U) {
        return PIPELINE_ERR_PARAM;
    }

    /* --------------------------------------------------------------------- */
    /* Stage 1: LZSS Compression (Raw Buffer -> Compressed Buffer)           */
    /* --------------------------------------------------------------------- */
    uint32_t t_comp_start_cyc = read_pmu_cycles();

    size_t comp_len = sizeof(s_comp_buf);
    int comp_rc = lzss_compress(raw_in, raw_len, s_comp_buf, &comp_len, &s_lzss_ws);

    uint32_t t_comp_end_cyc = read_pmu_cycles();

    if (comp_rc != 0) {
        return PIPELINE_ERR_COMPRESSION;
    }

    if (comp_len > max_out_len) {
        return PIPELINE_ERR_OVERFLOW;
    }

    /* --------------------------------------------------------------------- */
    /* Stage 2: AES-128-CTR Encryption (Compressed Buffer -> Ciphertext)     */
    /* --------------------------------------------------------------------- */
    uint32_t t_crypt_start_cyc = read_pmu_cycles();

    int crypt_rc = aes_128_ctr_crypt(s_pipeline_key,
                                     s_pipeline_iv,
                                     s_comp_buf,
                                     cipher_out,
                                     comp_len);

    uint32_t t_crypt_end_cyc = read_pmu_cycles();

    if (crypt_rc != 0) {
        return PIPELINE_ERR_ENCRYPTION;
    }

    *final_len = comp_len;

    /* --------------------------------------------------------------------- */
    /* Stage 3: Instrumentation & Metric Consolidation                       */
    /* --------------------------------------------------------------------- */
    if (metrics != NULL) {
        metrics->raw_len      = (uint32_t)raw_len;
        metrics->comp_len     = (uint32_t)comp_len;
        metrics->crypt_len    = (uint32_t)comp_len;
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

        /* Calculate throughput in MB/s */
        float elapsed_sec = (float)metrics->total_cycles / 666666667.0f;
        metrics->throughput_mbs = (elapsed_sec > 0.0f) ?
                                  (((float)raw_len / (1024.0f * 1024.0f)) / elapsed_sec) : 0.0f;
    }

    return PIPELINE_SUCCESS;
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
