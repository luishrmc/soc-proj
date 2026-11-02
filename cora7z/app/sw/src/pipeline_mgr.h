/**
 * @file pipeline_mgr.h
 * @brief Autonomous Pure-Software Compress-then-Encrypt (LZSS + AES-128-CTR) Pipeline Manager.
 *
 * Implements the software baseline execution pipeline on the ARM Cortex-A9:
 *   1. Compresses raw telemetry frames using sliding-window LZSS.
 *   2. Encrypts compressed payloads using AES-128-CTR.
 *   3. Instruments latency, ARM PMU cycles, compression ratio, and throughput.
 */

#ifndef PIPELINE_MGR_H
#define PIPELINE_MGR_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PIPELINE_SUCCESS             0
#define PIPELINE_ERR_PARAM          -1
#define PIPELINE_ERR_COMPRESSION    -2
#define PIPELINE_ERR_ENCRYPTION     -3
#define PIPELINE_ERR_OVERFLOW       -4

#define PIPELINE_MAX_FRAME_SIZE     2048U

/**
 * @brief Performance and telemetry metrics structure.
 */
typedef struct {
    uint32_t raw_len;           /* Original uncompressed payload length (bytes) */
    uint32_t comp_len;          /* LZSS compressed length (bytes) */
    uint32_t crypt_len;         /* AES-128-CTR ciphertext length (bytes) */
    uint32_t comp_cycles;       /* Cortex-A9 CPU cycles consumed by compression */
    uint32_t crypt_cycles;      /* Cortex-A9 CPU cycles consumed by encryption */
    uint32_t total_cycles;      /* Total pipeline processing CPU cycles */
    uint32_t comp_time_us;      /* Elapsed compression time in microseconds */
    uint32_t crypt_time_us;     /* Elapsed encryption time in microseconds */
    uint32_t total_time_us;     /* Total elapsed pipeline time in microseconds */
    float    compression_ratio; /* CR = 1.0 - (comp_len / raw_len) */
    float    throughput_mbs;    /* Throughput in MB/s based on raw payload */
} pipeline_metrics_t;

/**
 * @brief Initialize the software pipeline, verify self-tests, and load keys.
 * @return PIPELINE_SUCCESS (0) on success, negative error code on failure.
 */
int pipeline_init(void);

/**
 * @brief Execute the Compress-then-Encrypt software pipeline on a raw telemetry frame.
 *
 * Steps:
 *   1. Compress raw_in -> internal intermediate compressed buffer via lzss_compress().
 *   2. Encrypt intermediate buffer -> cipher_out via aes_128_ctr_crypt().
 *   3. Record PMU cycle counters and Global Timer timestamps for each stage.
 *
 * @param[in]  raw_in       Pointer to input raw telemetry buffer.
 * @param[in]  raw_len      Length of input payload in bytes.
 * @param[out] cipher_out   Destination buffer for final ciphertext.
 * @param[in]  max_out_len  Capacity of cipher_out buffer.
 * @param[out] final_len    Pointer receiving final ciphertext length in bytes.
 * @param[out] metrics      Pointer receiving stage cycle/time/ratio measurements.
 * @return PIPELINE_SUCCESS on success, negative on error.
 */
int pipeline_process_frame(const uint8_t *raw_in,
                           size_t raw_len,
                           uint8_t *cipher_out,
                           size_t max_out_len,
                           size_t *final_len,
                           pipeline_metrics_t *metrics);

/**
 * @brief Execute reverse pipeline (Decrypt-then-Decompress) for loopback verification.
 *
 * @param[in]  cipher_in    Pointer to input ciphertext.
 * @param[in]  cipher_len   Length of ciphertext in bytes.
 * @param[out] raw_out      Destination buffer for recovered raw telemetry.
 * @param[in]  max_out_len  Capacity of raw_out buffer.
 * @param[out] recovered_len Actual recovered raw bytes.
 * @return PIPELINE_SUCCESS on success, negative on error.
 */
int pipeline_reverse_frame(const uint8_t *cipher_in,
                           size_t cipher_len,
                           uint8_t *raw_out,
                           size_t max_out_len,
                           size_t *recovered_len);

#ifdef __cplusplus
}
#endif

#endif /* PIPELINE_MGR_H */
