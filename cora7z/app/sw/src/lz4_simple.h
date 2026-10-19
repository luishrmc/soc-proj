/**
 * @file lz4_simple.h
 * @brief Simplified LZ4 lossless compression reference implementation.
 *
 * Implements byte-aligned standard LZ4 sequence tokens:
 *   [Token (1B: High 4 bits = LitLen, Low 4 bits = MatchLen-4)]
 *   [Optional LitLen extension bytes]
 *   [Literal bytes]
 *   [Offset (2B Little-Endian)]
 *   [Optional MatchLen extension bytes]
 *
 * Fully bare-metal compliant (zero dynamic allocation, caller provides working buffer).
 */

#ifndef LZ4_SIMPLE_H
#define LZ4_SIMPLE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LZ4_MAX_DISTANCE   65535U
#define LZ4_MAX_OUTPUT_SIZE(n) ((size_t)(n) + ((size_t)(n) / 255U) + 16U)

/**
 * @brief Compress input buffer using standard LZ4 block format.
 *
 * @param src Pointer to uncompressed input data.
 * @param src_len Length of input data in bytes.
 * @param dst Pointer to destination buffer for compressed stream.
 * @param dst_max_len Maximum capacity of destination buffer.
 * @return size_t Compressed size in bytes, or 0 if output buffer was too small.
 */
size_t lz4_compress(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_max_len);

/**
 * @brief Decompress an LZ4 compressed block back to original data.
 *
 * @param src Pointer to compressed block.
 * @param src_len Length of compressed block in bytes.
 * @param dst Pointer to destination buffer for uncompressed output.
 * @param dst_max_len Maximum capacity of destination buffer.
 * @return size_t Number of decompressed bytes written, or 0 on corruption/error.
 */
size_t lz4_decompress(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_max_len);

#ifdef __cplusplus
}
#endif

#endif /* LZ4_SIMPLE_H */
