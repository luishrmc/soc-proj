/**
 * @file benchmark_ps.c
 * @brief Benchmark suite implementation for Cortex-A9 Pure Software (Scenario 1).
 */

#include "benchmark_ps.h"
#include "rle.h"
#include "lz4_simple.h"
#include "aes_ctr.h"
#include "chacha20.h"
#include <string.h>

#if defined(__arm__) || defined(__aarch64__)
#include "xil_printf.h"
#define B_PRINTF xil_printf
#else
#include <stdio.h>
#define B_PRINTF printf
#endif

/* Static Benchmark Working Buffers in DDR (32-byte cache-line aligned) */
static uint8_t s_buf_64b[64]           __attribute__((aligned(32)));
static uint8_t s_buf_1kb[1024]         __attribute__((aligned(32)));
static uint8_t s_buf_64kb[65536]       __attribute__((aligned(32)));
static uint8_t s_out_64kb[65536 + 256] __attribute__((aligned(32)));

static inline uint32_t pmu_get_cycles(void) {
#if defined(__arm__) || defined(__aarch64__)
    uint32_t cycles;
    __asm__ volatile("isb; mrc p15, 0, %0, c9, c13, 0; isb" : "=r"(cycles) :: "memory");
    return cycles;
#else
    return 1000;
#endif
}

static uint32_t isqrt(uint32_t n) {
    uint32_t root = 0;
    uint32_t bit = 1U << 30;
    while (bit > n) bit >>= 2;
    while (bit != 0) {
        if (n >= root + bit) {
            n -= root + bit;
            root = (root >> 1) + bit;
        } else {
            root >>= 1;
        }
        bit >>= 2;
    }
    return root;
}

static void compute_stats(const uint32_t samples[BENCHMARK_RUNS], uint32_t *mean, uint32_t *stddev) {
    uint64_t sum = 0;
    for (uint32_t i = 0; i < BENCHMARK_RUNS; i++) {
        sum += samples[i];
    }
    uint32_t avg = (uint32_t)(sum / BENCHMARK_RUNS);
    *mean = avg;

    uint64_t var_sum = 0;
    for (uint32_t i = 0; i < BENCHMARK_RUNS; i++) {
        int64_t diff = (int64_t)samples[i] - (int64_t)avg;
        var_sum += (uint64_t)(diff * diff);
    }
    *stddev = isqrt((uint32_t)(var_sum / BENCHMARK_RUNS));
}

static void init_test_patterns(void) {
    /* 1. 64 B High Redundancy Pattern */
    memset(s_buf_64b, 0xAA, sizeof(s_buf_64b));

    /* 2. 1 KB Pseudo-Random Pattern (Xorshift32) */
    uint32_t seed = 0x13579BDFU;
    for (size_t i = 0; i < sizeof(s_buf_1kb); i++) {
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        s_buf_1kb[i] = (uint8_t)(seed & 0xFFU);
    }

    /* 3. 64 KB Structured Telemetry Pattern */
    uint32_t seq = 0;
    size_t offset = 0;
    while (offset < sizeof(s_buf_64kb)) {
        char rec[96];
        int w = 0;
#if defined(__arm__) || defined(__aarch64__)
        /* Minimal integer formatting */
        w = 32;
        memset(rec, 'T', sizeof(rec));
        rec[0] = 'S'; rec[1] = 'E'; rec[2] = 'Q'; rec[3] = '=';
        rec[31] = '\n';
        seq++;
#else
        w = snprintf(rec, sizeof(rec), "SEQ=%06lu;TMP=%02d.%02d;PRS=%05lu;STAT=OK\n",
                     (unsigned long)seq++, (int)(20 + (seq % 15)), (int)(seq % 100),
                     (unsigned long)(101325 + (seq % 300)));
#endif
        if (w <= 0) break;
        size_t copy_sz = (size_t)w;
        if (offset + copy_sz > sizeof(s_buf_64kb)) {
            copy_sz = sizeof(s_buf_64kb) - offset;
        }
        memcpy(&s_buf_64kb[offset], rec, copy_sz);
        offset += copy_sz;
    }
}

void benchmark_ps_run_all(uint32_t cpu_freq_hz) {
    if (cpu_freq_hz == 0) {
        cpu_freq_hz = 650000000U; /* Default Cora Z7 Cortex-A9 650 MHz per xparameters.h */
    }

    init_test_patterns();

    B_PRINTF("\r\n");
    B_PRINTF("================================================================================\r\n");
    B_PRINTF("  Scenario 1: Pure Software (PS) Benchmarking on Cortex-A9 Core 0\r\n");
    B_PRINTF("  CPU Frequency: %d MHz | Statistical Sample: %d runs\r\n", (int)(cpu_freq_hz / 1000000U), (int)BENCHMARK_RUNS);
    B_PRINTF("================================================================================\r\n");

    uint32_t samples[BENCHMARK_RUNS];
    uint32_t mean = 0, stddev = 0;
    uint32_t t_start, t_end;

    /* ---------------------------------------------------------------------- */
    /* 1. RLE Compression (64 B High Redundancy)                              */
    /* ---------------------------------------------------------------------- */
    size_t rle_out_sz = 0;
    for (uint32_t r = 0; r < BENCHMARK_RUNS; r++) {
        t_start = pmu_get_cycles();
        rle_out_sz = rle_compress(s_buf_64b, sizeof(s_buf_64b), s_out_64kb, 128U);
        t_end = pmu_get_cycles();
        samples[r] = (t_end >= t_start) ? (t_end - t_start) : (0xFFFFFFFFU - t_start + t_end);
    }
    compute_stats(samples, &mean, &stddev);
    float rle_us = ((float)mean * 1000000.0f) / (float)cpu_freq_hz;
    float rle_mbps = ((float)sizeof(s_buf_64b) / (1024.0f * 1024.0f)) / (rle_us / 1000000.0f);
    float rle_ratio = (float)sizeof(s_buf_64b) / (float)rle_out_sz;

    B_PRINTF("[BENCH] RLE (64 B):       Cycles: %u +/- %u | Latency: %d us | Throughput: %d KB/s | Ratio: %d:1\r\n",
             (unsigned int)mean, (unsigned int)stddev, (int)rle_us, (int)(rle_mbps * 1024.0f), (int)rle_ratio);

    /* ---------------------------------------------------------------------- */
    /* 2. LZ4 Compression (1 KB Pseudo-Random)                                */
    /* ---------------------------------------------------------------------- */
    size_t lz4_out_sz = 0;
    for (uint32_t r = 0; r < BENCHMARK_RUNS; r++) {
        t_start = pmu_get_cycles();
        lz4_out_sz = lz4_compress(s_buf_1kb, sizeof(s_buf_1kb), s_out_64kb, 2048U);
        t_end = pmu_get_cycles();
        samples[r] = (t_end >= t_start) ? (t_end - t_start) : (0xFFFFFFFFU - t_start + t_end);
    }
    compute_stats(samples, &mean, &stddev);
    float lz4_us = ((float)mean * 1000000.0f) / (float)cpu_freq_hz;
    float lz4_mbps = ((float)sizeof(s_buf_1kb) / (1024.0f * 1024.0f)) / (lz4_us / 1000000.0f);

    B_PRINTF("[BENCH] LZ4 (1 KB):       Cycles: %u +/- %u | Latency: %d us | Throughput: %d KB/s | Out: %u B\r\n",
             (unsigned int)mean, (unsigned int)stddev, (int)lz4_us, (int)(lz4_mbps * 1024.0f), (unsigned int)lz4_out_sz);

    /* ---------------------------------------------------------------------- */
    /* 3. AES-128-CTR (64 KB Telemetry)                                       */
    /* ---------------------------------------------------------------------- */
    const uint8_t aes_key[16] = {0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F};
    const uint8_t aes_iv[16]  = {0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,0xF8,0xF9,0xFA,0xFB,0xFC,0xFD,0xFE,0xFF};

    for (uint32_t r = 0; r < BENCHMARK_RUNS; r++) {
        aes128_ctr_ctx_t aes_ctx;
        aes128_ctr_init(&aes_ctx, aes_key, aes_iv);

        t_start = pmu_get_cycles();
        aes128_ctr_crypt(&aes_ctx, s_buf_64kb, s_out_64kb, sizeof(s_buf_64kb));
        t_end = pmu_get_cycles();
        samples[r] = (t_end >= t_start) ? (t_end - t_start) : (0xFFFFFFFFU - t_start + t_end);
    }
    compute_stats(samples, &mean, &stddev);
    float aes_us = ((float)mean * 1000000.0f) / (float)cpu_freq_hz;
    float aes_mbps = ((float)sizeof(s_buf_64kb) / (1024.0f * 1024.0f)) / (aes_us / 1000000.0f);

    B_PRINTF("[BENCH] AES-128-CTR (64K): Cycles: %u +/- %u | Latency: %d ms | Throughput: %d.%02d MB/s\r\n",
             (unsigned int)mean, (unsigned int)stddev, (int)(aes_us / 1000.0f), (int)aes_mbps, (int)((aes_mbps - (int)aes_mbps) * 100));

    /* ---------------------------------------------------------------------- */
    /* 4. ChaCha20 (64 B and 64 KB Telemetry)                                 */
    /* ---------------------------------------------------------------------- */
    uint8_t chacha_key[32];
    for (int i = 0; i < 32; i++) chacha_key[i] = (uint8_t)i;
    uint8_t chacha_nonce[12] = {0,0,0,9,0,0,0,0x4A,0,0,0,0};

    /* ChaCha20 64 B */
    for (uint32_t r = 0; r < BENCHMARK_RUNS; r++) {
        chacha20_ctx_t chacha_ctx;
        chacha20_init(&chacha_ctx, chacha_key, chacha_nonce, 1);

        t_start = pmu_get_cycles();
        chacha20_crypt(&chacha_ctx, s_buf_64b, s_out_64kb, sizeof(s_buf_64b));
        t_end = pmu_get_cycles();
        samples[r] = (t_end >= t_start) ? (t_end - t_start) : (0xFFFFFFFFU - t_start + t_end);
    }
    compute_stats(samples, &mean, &stddev);
    float chacha_64_us = ((float)mean * 1000000.0f) / (float)cpu_freq_hz;
    float chacha_64_mbps = ((float)sizeof(s_buf_64b) / (1024.0f * 1024.0f)) / (chacha_64_us / 1000000.0f);

    B_PRINTF("[BENCH] ChaCha20 (64 B):   Cycles: %u +/- %u | Latency: %d us | Throughput: %d KB/s\r\n",
             (unsigned int)mean, (unsigned int)stddev, (int)chacha_64_us, (int)(chacha_64_mbps * 1024.0f));

    /* ChaCha20 64 KB */
    for (uint32_t r = 0; r < BENCHMARK_RUNS; r++) {
        chacha20_ctx_t chacha_ctx;
        chacha20_init(&chacha_ctx, chacha_key, chacha_nonce, 1);

        t_start = pmu_get_cycles();
        chacha20_crypt(&chacha_ctx, s_buf_64kb, s_out_64kb, sizeof(s_buf_64kb));
        t_end = pmu_get_cycles();
        samples[r] = (t_end >= t_start) ? (t_end - t_start) : (0xFFFFFFFFU - t_start + t_end);
    }
    compute_stats(samples, &mean, &stddev);
    float chacha_64k_us = ((float)mean * 1000000.0f) / (float)cpu_freq_hz;
    float chacha_64k_mbps = ((float)sizeof(s_buf_64kb) / (1024.0f * 1024.0f)) / (chacha_64k_us / 1000000.0f);

    B_PRINTF("[BENCH] ChaCha20 (64 KB):  Cycles: %u +/- %u | Latency: %d ms | Throughput: %d.%02d MB/s\r\n",
             (unsigned int)mean, (unsigned int)stddev, (int)(chacha_64k_us / 1000.0f), (int)chacha_64k_mbps, (int)((chacha_64k_mbps - (int)chacha_64k_mbps) * 100));

    B_PRINTF("================================================================================\r\n");
    B_PRINTF("  [RESULT] All Scenario 1 Software Benchmarks Completed Successfully\r\n");
    B_PRINTF("================================================================================\r\n\r\n");
}
