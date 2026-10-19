/**
 * @file rle.c
 * @brief Run-Length Encoding (RLE) lossless compression reference implementation.
 */

#include "rle.h"

size_t rle_compress(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_max_len) {
    if (src == NULL || dst == NULL || src_len == 0 || dst_max_len < 2) {
        return 0;
    }

    size_t in_idx = 0;
    size_t out_idx = 0;

    while (in_idx < src_len) {
        uint8_t current_byte = src[in_idx];
        size_t run_len = 1;

        while ((in_idx + run_len < src_len) &&
               (src[in_idx + run_len] == current_byte) &&
               (run_len < RLE_MAX_RUN_LEN)) {
            run_len++;
        }

        if (out_idx + 2 > dst_max_len) {
            return 0; /* Destination buffer overflow */
        }

        dst[out_idx++] = (uint8_t)run_len;
        dst[out_idx++] = current_byte;

        in_idx += run_len;
    }

    return out_idx;
}

size_t rle_decompress(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_max_len) {
    if (src == NULL || dst == NULL || (src_len % 2) != 0 || dst_max_len == 0) {
        return 0;
    }

    size_t in_idx = 0;
    size_t out_idx = 0;

    while (in_idx < src_len) {
        uint8_t count = src[in_idx++];
        uint8_t symbol = src[in_idx++];

        if (out_idx + count > dst_max_len) {
            return 0; /* Output buffer overflow */
        }

        for (uint8_t i = 0; i < count; i++) {
            dst[out_idx++] = symbol;
        }
    }

    return out_idx;
}
