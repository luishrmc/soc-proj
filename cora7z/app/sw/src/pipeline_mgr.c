/**
 * @file pipeline_mgr.c
 * @brief High-Level Pipeline Orchestrator Implementation for SPI, PL, and PS.
 */

#include "pipeline_mgr.h"
#include "axi_io.h"
#include "rle.h"
#include "lz4_simple.h"
#include "aes_ctr.h"
#include "chacha20.h"
#include <string.h>

#define DEVCFG_BASEADDR          0xF8007000U
#define DEVCFG_INT_STS_OFFSET    0x0CU
#define DEVCFG_PCFG_DONE_MASK    (1U << 2)

static inline bool is_fpga_configured(void) {
#if defined(__arm__) || defined(__aarch64__)
    uint32_t val = AXI_IO_READ32(DEVCFG_BASEADDR + DEVCFG_INT_STS_OFFSET);
    return ((val & DEVCFG_PCFG_DONE_MASK) != 0U);
#else
    return true; /* Simulated as programmed on host */
#endif
}

int pipeline_mgr_init(void) {
    /* 1. Prevent CPU bus stalls if PL is unprogrammed */
    if (!is_fpga_configured()) {
        return -1;
    }

    /* 2. Initialize AXI DMA */
    int rc = axi_dma_init(AXI_DMA_DEFAULT_BASEADDR);
    if (rc != 0) {
        return -2;
    }

    /* 3. Initialize AXI Quad SPI */
    rc = axi_spi_init(AXI_SPI_DEFAULT_BASEADDR);
    if (rc != 0) {
        return -3;
    }

    /* 4. Reset all accelerator datapaths */
    axi_accel_reset(ACCEL_BASE_RLE);
    axi_accel_reset(ACCEL_BASE_LZ4);
    axi_accel_reset(ACCEL_BASE_AES_CTR);
    axi_accel_reset(ACCEL_BASE_CHACHA20);

    return 0;
}

static inline uint32_t pmu_read_ccnt(void) {
#if defined(__arm__) || defined(__aarch64__)
    uint32_t val;
    __asm__ volatile("isb; mrc p15, 0, %0, c9, c13, 0; isb" : "=r"(val) :: "memory");
    return val;
#else
    return 1000U;
#endif
}

static uint32_t s_frame_seq = 1U;
static uint8_t  s_comp_buf[65536]; /* Intermediate buffer for PS chained pipelines */

int pipeline_mgr_process(pipeline_scenario_t scenario,
                         pipeline_algo_t algo,
                         const uint8_t *in_buf,
                         size_t in_len,
                         uint8_t *out_buf,
                         size_t max_out_len,
                         pipeline_metrics_t *metrics) {
    if (in_buf == NULL || out_buf == NULL || metrics == NULL || in_len == 0) {
        return -1;
    }

    metrics->cpu_cycles    = 0U;
    metrics->hw_cycles     = 0U;
    metrics->output_length = 0U;
    metrics->latency_us    = 0.0f;
    metrics->throughput_mbps = 0.0f;
    metrics->success       = false;

    /* Monotonic frame IV/Nonce diversification to prevent keystream reuse */
    uint32_t cur_seq = s_frame_seq++;

    /* ---------------------------------------------------------------------- */
    /* Scenario 1: Pure Software on ARM Cortex-A9                             */
    /* ---------------------------------------------------------------------- */
    if (scenario == SCENARIO_PS_PURE) {
        size_t produced = 0;
        uint32_t t_start = pmu_read_ccnt();

        switch (algo) {
            case ALGO_RLE:
                produced = rle_compress(in_buf, in_len, out_buf, max_out_len);
                break;

            case ALGO_LZ4:
                produced = lz4_compress(in_buf, in_len, out_buf, max_out_len);
                break;

            case ALGO_AES_CTR: {
                if (max_out_len < in_len) return -1;
                const uint8_t key[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
                uint8_t iv[16]        = {0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,0xF8,0xF9,0xFA,0xFB,
                                         (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                         (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                aes128_ctr_ctx_t ctx;
                aes128_ctr_init(&ctx, key, iv);
                aes128_ctr_crypt(&ctx, in_buf, out_buf, in_len);
                produced = in_len;
                break;
            }

            case ALGO_CHACHA20: {
                if (max_out_len < in_len) return -1;
                uint8_t key[32];
                for (int i = 0; i < 32; i++) key[i] = (uint8_t)i;
                uint8_t nonce[12] = {0,0,0,9, 0,0,0,0x4A,
                                     (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                     (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                chacha20_ctx_t ctx;
                chacha20_init(&ctx, key, nonce, 1U);
                chacha20_crypt(&ctx, in_buf, out_buf, in_len);
                produced = in_len;
                break;
            }

            case ALGO_RLE_AES_CTR: {
                size_t comp_len = rle_compress(in_buf, in_len, s_comp_buf, sizeof(s_comp_buf));
                if (comp_len == 0 || max_out_len < comp_len) return -1;
                const uint8_t key[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
                uint8_t iv[16]        = {0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,0xF8,0xF9,0xFA,0xFB,
                                         (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                         (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                aes128_ctr_ctx_t ctx;
                aes128_ctr_init(&ctx, key, iv);
                aes128_ctr_crypt(&ctx, s_comp_buf, out_buf, comp_len);
                produced = comp_len;
                break;
            }

            case ALGO_RLE_CHACHA20: {
                size_t comp_len = rle_compress(in_buf, in_len, s_comp_buf, sizeof(s_comp_buf));
                if (comp_len == 0 || max_out_len < comp_len) return -1;
                uint8_t key[32];
                for (int i = 0; i < 32; i++) key[i] = (uint8_t)i;
                uint8_t nonce[12] = {0,0,0,9, 0,0,0,0x4A,
                                     (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                     (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                chacha20_ctx_t ctx;
                chacha20_init(&ctx, key, nonce, 1U);
                chacha20_crypt(&ctx, s_comp_buf, out_buf, comp_len);
                produced = comp_len;
                break;
            }

            case ALGO_LZ4_AES_CTR: {
                size_t comp_len = lz4_compress(in_buf, in_len, s_comp_buf, sizeof(s_comp_buf));
                if (comp_len == 0 || max_out_len < comp_len) return -1;
                const uint8_t key[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
                uint8_t iv[16]        = {0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,0xF8,0xF9,0xFA,0xFB,
                                         (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                         (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                aes128_ctr_ctx_t ctx;
                aes128_ctr_init(&ctx, key, iv);
                aes128_ctr_crypt(&ctx, s_comp_buf, out_buf, comp_len);
                produced = comp_len;
                break;
            }

            case ALGO_LZ4_CHACHA20: {
                size_t comp_len = lz4_compress(in_buf, in_len, s_comp_buf, sizeof(s_comp_buf));
                if (comp_len == 0 || max_out_len < comp_len) return -1;
                uint8_t key[32];
                for (int i = 0; i < 32; i++) key[i] = (uint8_t)i;
                uint8_t nonce[12] = {0,0,0,9, 0,0,0,0x4A,
                                     (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                     (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                chacha20_ctx_t ctx;
                chacha20_init(&ctx, key, nonce, 1U);
                chacha20_crypt(&ctx, s_comp_buf, out_buf, comp_len);
                produced = comp_len;
                break;
            }

            default:
                return -1;
        }

        uint32_t t_end = pmu_read_ccnt();
        metrics->cpu_cycles    = (t_end >= t_start) ? (t_end - t_start) : 0U;
        metrics->hw_cycles     = 0U;
        metrics->output_length = produced;
        metrics->latency_us    = (float)metrics->cpu_cycles / 650.0f; /* Cortex-A9 @ 650 MHz */
        if (metrics->latency_us > 0.0f) {
            metrics->throughput_mbps = ((float)in_len / 1048576.0f) / (metrics->latency_us / 1000000.0f);
        }
        metrics->success = (produced > 0U);
        return metrics->success ? 0 : -1;
    }

    /* ---------------------------------------------------------------------- */
    /* Scenario 2 / 3: Hardware Acceleration on PL (DMA + Accelerator IP)     */
    /* ---------------------------------------------------------------------- */
    if (!is_fpga_configured()) {
        return -10; /* FPGA not programmed */
    }

    uintptr_t accel_base_primary = 0;
    uintptr_t accel_base_secondary = 0;
    uint32_t route_id = ACCEL_MUX_ROUTE_AUTO;

    switch (algo) {
        case ALGO_RLE:
            accel_base_primary = ACCEL_BASE_RLE;
            route_id           = ACCEL_MUX_ROUTE_RLE;
            break;

        case ALGO_LZ4:
            accel_base_primary = ACCEL_BASE_LZ4;
            route_id           = ACCEL_MUX_ROUTE_LZ4;
            break;

        case ALGO_AES_CTR:
            accel_base_primary = ACCEL_BASE_AES_CTR;
            route_id           = ACCEL_MUX_ROUTE_AES_CTR;
            {
                const uint8_t key[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
                uint8_t iv[12]        = {0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,
                                         (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                         (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                axi_accel_set_aes_key_iv(accel_base_primary, key, iv, cur_seq);
            }
            break;

        case ALGO_CHACHA20:
            accel_base_primary = ACCEL_BASE_CHACHA20;
            route_id           = ACCEL_MUX_ROUTE_CHACHA;
            {
                uint8_t key[32];
                for (int i = 0; i < 32; i++) key[i] = (uint8_t)i;
                uint8_t nonce[12] = {0,0,0,9, 0,0,0,0x4A,
                                     (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                     (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                axi_accel_set_chacha_key_nonce(accel_base_primary, key, nonce, cur_seq);
            }
            break;

        case ALGO_RLE_AES_CTR:
            accel_base_primary   = ACCEL_BASE_RLE;
            accel_base_secondary = ACCEL_BASE_AES_CTR;
            route_id             = ACCEL_MUX_ROUTE_RLE_AES_CTR;
            {
                const uint8_t key[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
                uint8_t iv[12]        = {0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,
                                         (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                         (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                axi_accel_set_aes_key_iv(accel_base_secondary, key, iv, cur_seq);
            }
            break;

        case ALGO_RLE_CHACHA20:
            accel_base_primary   = ACCEL_BASE_RLE;
            accel_base_secondary = ACCEL_BASE_CHACHA20;
            route_id             = ACCEL_MUX_ROUTE_RLE_CHACHA;
            {
                uint8_t key[32];
                for (int i = 0; i < 32; i++) key[i] = (uint8_t)i;
                uint8_t nonce[12] = {0,0,0,9, 0,0,0,0x4A,
                                     (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                     (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                axi_accel_set_chacha_key_nonce(accel_base_secondary, key, nonce, cur_seq);
            }
            break;

        case ALGO_LZ4_AES_CTR:
            accel_base_primary   = ACCEL_BASE_LZ4;
            accel_base_secondary = ACCEL_BASE_AES_CTR;
            route_id             = ACCEL_MUX_ROUTE_LZ4_AES_CTR;
            {
                const uint8_t key[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
                uint8_t iv[12]        = {0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,
                                         (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                         (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                axi_accel_set_aes_key_iv(accel_base_secondary, key, iv, cur_seq);
            }
            break;

        case ALGO_LZ4_CHACHA20:
            accel_base_primary   = ACCEL_BASE_LZ4;
            accel_base_secondary = ACCEL_BASE_CHACHA20;
            route_id             = ACCEL_MUX_ROUTE_LZ4_CHACHA;
            {
                uint8_t key[32];
                for (int i = 0; i < 32; i++) key[i] = (uint8_t)i;
                uint8_t nonce[12] = {0,0,0,9, 0,0,0,0x4A,
                                     (uint8_t)(cur_seq >> 24), (uint8_t)(cur_seq >> 16),
                                     (uint8_t)(cur_seq >> 8),  (uint8_t)(cur_seq & 0xFFU)};
                axi_accel_set_chacha_key_nonce(accel_base_secondary, key, nonce, cur_seq);
            }
            break;

        default:
            return -1;
    }

    /* 1. Configure stream multiplexer route */
    axi_accel_set_stream_route(route_id);

    /* 2. Reset accelerator datapaths */
    axi_accel_reset(accel_base_primary);
    if (accel_base_secondary != 0) {
        axi_accel_reset(accel_base_secondary);
    }

    /* 3. Configure input length and pulse start */
    if (accel_base_secondary != 0) {
        /* Chained pipeline: arm secondary cipher, then primary compressor */
        axi_accel_start(accel_base_secondary, (uint32_t)in_len);
    }
    axi_accel_start(accel_base_primary, (uint32_t)in_len);

    /* 4. Execute synchronized DMA transfer (S2MM armed first, then MM2S) */
    uint32_t t_dma_start = pmu_read_ccnt();
    int dma_rc = axi_dma_transfer_sync(AXI_DMA_DEFAULT_BASEADDR,
                                       (uintptr_t)in_buf,
                                       (uint32_t)in_len,
                                       (uintptr_t)out_buf,
                                       (uint32_t)max_out_len,
                                       10000000U);
    if (dma_rc != 0) {
        return -2; /* DMA failure */
    }

    /* 5. Poll accelerator completion and extract latency counters */
    uint32_t dst_len = 0;
    uint32_t hw_cyc = 0;
    uintptr_t final_core = (accel_base_secondary != 0) ? accel_base_secondary : accel_base_primary;
    int accel_rc = axi_accel_poll_done(final_core, 10000000U, &dst_len, &hw_cyc);
    if (accel_rc != 0) {
        return -3; /* Accelerator error/timeout */
    }
    uint32_t t_dma_end = pmu_read_ccnt();

    metrics->output_length = dst_len;
    metrics->hw_cycles     = hw_cyc;

    if (scenario == SCENARIO_PL_PURE) {
        /* Pure PL measurement: isolated hardware execution at 100 MHz */
        metrics->cpu_cycles  = 0U;
        metrics->latency_us  = (float)hw_cyc / 100.0f; /* 100 MHz PL clock */
    } else {
        /* Hybrid co-design: end-to-end CPU PMU cycles including DMA and caches */
        metrics->cpu_cycles  = (t_dma_end >= t_dma_start) ? (t_dma_end - t_dma_start) : 0U;
        metrics->latency_us  = (float)metrics->cpu_cycles / 650.0f; /* Cortex-A9 @ 650 MHz */
    }

    if (metrics->latency_us > 0.0f) {
        metrics->throughput_mbps = ((float)in_len / 1048576.0f) / (metrics->latency_us / 1000000.0f);
    }
    metrics->success = true;
    return 0;
}

int pipeline_mgr_self_test(void) {
    /* 1. Test CRC-16-CCITT algorithm against standard ASCII vector "123456789" -> 0x29B1 */
    const uint8_t test_vec[] = "123456789";
    uint16_t crc = axi_spi_crc16(test_vec, 9, 0xFFFFU);
    if (crc != 0x29B1U) {
        return -1; /* CRC-16 check failed */
    }

    /* 2. Test packet parsing logic with synthetic header */
    uint8_t raw_pkt[16];
    raw_pkt[0] = SPI_PREAMBLE_BYTE0;
    raw_pkt[1] = SPI_PREAMBLE_BYTE1;
    raw_pkt[2] = SPI_TYPE_REDUNDANT;
    raw_pkt[3] = SPI_FLAG_COMPRESS_EN;
    raw_pkt[4] = 0; raw_pkt[5] = 0; raw_pkt[6] = 0; raw_pkt[7] = 4; /* 4 bytes payload */
    raw_pkt[8] = 0xAA; raw_pkt[9] = 0xAA; raw_pkt[10] = 0xAA; raw_pkt[11] = 0xAA;
    uint16_t pkt_crc = axi_spi_crc16(raw_pkt, 12, 0xFFFFU);
    raw_pkt[12] = (uint8_t)((pkt_crc >> 8) & 0xFFU);
    raw_pkt[13] = (uint8_t)(pkt_crc & 0xFFU);

    uint8_t payload_out[16];
    spi_frame_t frame;
    int parse_rc = axi_spi_parse_packet(raw_pkt, 14, payload_out, sizeof(payload_out), &frame);
    if (parse_rc != 0 || !frame.crc_valid || frame.header.payload_len != 4) {
        return -2; /* Packet parser validation failed */
    }

    return 0;
}
