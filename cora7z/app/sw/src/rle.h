/**
 * @file rle.h
 * @brief Run-Length Encoding (RLE) lossless compression reference implementation.
 *
 * Implements the exact token format used by rle_engine.vhdl:
 * Each run is encoded as a 2-byte tuple: [run_count (1..255), symbol_byte].
 *
 * Fully host-verifiable and bare-metal compliant (zero dynamic allocation).
 */

#ifndef RLE_H
#define RLE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RLE_MAX_RUN_LEN 255U

/**
 * @brief Compress an input buffer using Run-Length Encoding.
 *
 * @param src Pointer to input uncompressed buffer.
 * @param src_len Number of bytes in input buffer.
 * @param dst Pointer to destination buffer for compressed tokens.
 * @param dst_max_len Maximum capacity of destination buffer.
 * @return size_t Number of bytes written to dst, or 0 if dst buffer overflows.
 */
size_t rle_compress(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_max_len);

/**
 * @brief Decompress an RLE-encoded buffer back to uncompressed data.
 *
 * @param src Pointer to compressed RLE token buffer.
 * @param src_len Number of bytes in compressed buffer (must be even).
 * @param dst Pointer to destination buffer for reconstructed data.
 * @param dst_max_len Maximum capacity of destination buffer.
 * @return size_t Number of reconstructed bytes written to dst, or 0 on error.
 */
size_t rle_decompress(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_max_len);

#ifdef __cplusplus
}
#endif

#endif /* RLE_H */
