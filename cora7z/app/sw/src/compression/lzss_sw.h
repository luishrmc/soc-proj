/**
 * @file lzss_sw.h
 * @brief High-Performance Zero-Dynamic-Allocation LZSS Compression Engine for ARM Cortex-A9.
 *
 * Implements a sliding-window LZSS compressor and decompressor optimized for
 * embedded telemetry frames (64 B to 1024 B). Adheres to MISRA-C guidelines
 * with zero heap allocation (malloc-free) and 32-bit D-cache alignment.
 */

#ifndef LZSS_SW_H
#define LZSS_SW_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Return Status Codes */
#define LZSS_SUCCESS                 0
#define LZSS_ERR_BUFFER_OVERFLOW    -1
#define LZSS_ERR_INVALID_PARAM      -2
#define LZSS_ERR_CORRUPT_DATA       -3

/* Window and Match Constraints */
#define LZSS_WINDOW_SIZE            256U   /* 8-bit back-reference window (256 B) */
#define LZSS_MIN_MATCH              3U     /* Minimum match length (bytes) */
#define LZSS_MAX_MATCH              258U   /* Maximum match length (3 + 255) */
#define LZSS_MAX_FRAME_SIZE         2048U  /* Maximum supported frame capacity */

/**
 * @brief Pre-allocated static workspace for LZSS compression.
 *        Explicitly 32-bit aligned to optimize Cortex-A9 L1 data cache lines.
 */
typedef struct __attribute__((aligned(4))) {
    uint32_t scratch_word;                     /* Alignment padding */
    uint8_t  window[LZSS_WINDOW_SIZE];         /* Sliding window reference buffer */
} lzss_workspace_t;

/**
 * @brief Compress a raw byte stream using sliding-window LZSS.
 *
 * Encodes the uncompressed length into a 16-bit Big-Endian header, followed
 * by a bitstream of 8-token chunks governed by a 1-byte flag mask:
 *   - Flag bit = 0: 1-byte literal token.
 *   - Flag bit = 1: 2-byte match token (distance-1, length-3).
 *
 * @param[in]  src      Pointer to raw input buffer.
 * @param[in]  src_len  Length of input buffer in bytes (up to 65535).
 * @param[out] dst      Pointer to destination buffer for compressed stream.
 * @param[in,out] dst_len On entry: maximum capacity of dst buffer.
 *                        On exit: actual bytes written to dst buffer.
 * @param[in]  ws       Pointer to static workspace structure (zero heap).
 * @return LZSS_SUCCESS on success, or negative error code.
 */
int lzss_compress(const uint8_t *src,
                  size_t src_len,
                  uint8_t *dst,
                  size_t *dst_len,
                  lzss_workspace_t *ws);

/**
 * @brief Decompress an LZSS-encoded byte stream back to original raw bytes.
 *
 * Reads the 16-bit uncompressed length header and reproduces the exact
 * original data stream without requiring dynamic memory or external workspace.
 *
 * @param[in]  src      Pointer to compressed input buffer.
 * @param[in]  src_len  Length of compressed stream in bytes.
 * @param[out] dst      Pointer to destination buffer for reconstructed raw data.
 * @param[in,out] dst_len On entry: maximum capacity of dst buffer.
 *                        On exit: actual uncompressed bytes reconstructed.
 * @return LZSS_SUCCESS on success, or negative error code.
 */
int lzss_decompress(const uint8_t *src,
                    size_t src_len,
                    uint8_t *dst,
                    size_t *dst_len);

#ifdef __cplusplus
}
#endif

#endif /* LZSS_SW_H */
