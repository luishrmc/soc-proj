/**
 * @file lzss_sw.c
 * @brief High-Performance Zero-Dynamic-Allocation LZSS Compression Engine Implementation.
 */

#include "lzss_sw.h"
#include <string.h>

int lzss_compress(const uint8_t *src,
                  size_t src_len,
                  uint8_t *dst,
                  size_t *dst_len,
                  lzss_workspace_t *ws) {
    (void)ws; /* Window lookup is performed in-place over src buffer */

    if (src == NULL || dst == NULL || dst_len == NULL) {
        return LZSS_ERR_INVALID_PARAM;
    }
    if (src_len > 65535U) {
        return LZSS_ERR_INVALID_PARAM;
    }

    size_t max_dst = *dst_len;
    if (max_dst < 2U) {
        return LZSS_ERR_BUFFER_OVERFLOW;
    }

    /* 1. Write 16-bit uncompressed length header (Big-Endian network order) */
    dst[0] = (uint8_t)((src_len >> 8) & 0xFFU);
    dst[1] = (uint8_t)(src_len & 0xFFU);
    size_t out_idx = 2U;

    if (src_len == 0U) {
        *dst_len = out_idx;
        return LZSS_SUCCESS;
    }

    /* 2. Encode stream in 8-token flag chunks */
    size_t in_idx = 0U;

    while (in_idx < src_len) {
        if (out_idx >= max_dst) {
            return LZSS_ERR_BUFFER_OVERFLOW;
        }

        /* Reserve 1 byte for 8-token flag bitmask */
        size_t flag_byte_idx = out_idx++;
        uint8_t flag_mask = 0U;

        for (int bit = 0; bit < 8 && in_idx < src_len; bit++) {
            /* Determine sliding window bounds [win_start, in_idx) */
            size_t win_start = (in_idx > LZSS_WINDOW_SIZE) ? (in_idx - LZSS_WINDOW_SIZE) : 0U;
            size_t best_len = 0U;
            size_t best_dist = 0U;

            size_t max_search_len = src_len - in_idx;
            if (max_search_len > LZSS_MAX_MATCH) {
                max_search_len = LZSS_MAX_MATCH;
            }

            /* Longest-match search within sliding history window */
            if (max_search_len >= LZSS_MIN_MATCH) {
                for (size_t cand = win_start; cand < in_idx; cand++) {
                    size_t match_len = 0U;
                    while (match_len < max_search_len &&
                           src[cand + match_len] == src[in_idx + match_len]) {
                        match_len++;
                    }

                    if (match_len >= LZSS_MIN_MATCH && match_len > best_len) {
                        best_len = match_len;
                        best_dist = in_idx - cand;
                        if (best_len == max_search_len) {
                            break; /* Reached maximum possible lookahead */
                        }
                    }
                }
            }

            if (best_len >= LZSS_MIN_MATCH) {
                /* MATCH TOKEN: Set flag bit = 1, emit 2-byte token (dist-1, len-3) */
                if (out_idx + 2U > max_dst) {
                    return LZSS_ERR_BUFFER_OVERFLOW;
                }
                flag_mask |= (uint8_t)(1U << bit);
                dst[out_idx++] = (uint8_t)((best_dist - 1U) & 0xFFU);
                dst[out_idx++] = (uint8_t)((best_len - LZSS_MIN_MATCH) & 0xFFU);
                in_idx += best_len;
            } else {
                /* LITERAL TOKEN: Flag bit = 0, emit single uncompressed byte */
                if (out_idx + 1U > max_dst) {
                    return LZSS_ERR_BUFFER_OVERFLOW;
                }
                dst[out_idx++] = src[in_idx++];
            }
        }

        dst[flag_byte_idx] = flag_mask;
    }

    *dst_len = out_idx;
    return LZSS_SUCCESS;
}

int lzss_decompress(const uint8_t *src,
                    size_t src_len,
                    uint8_t *dst,
                    size_t *dst_len) {
    if (src == NULL || dst == NULL || dst_len == NULL) {
        return LZSS_ERR_INVALID_PARAM;
    }
    if (src_len < 2U) {
        return LZSS_ERR_INVALID_PARAM;
    }

    /* 1. Parse 16-bit uncompressed length header */
    uint16_t expected_orig_len = (uint16_t)(((uint16_t)src[0] << 8) | src[1]);
    size_t max_dst = *dst_len;

    if ((size_t)expected_orig_len > max_dst) {
        return LZSS_ERR_BUFFER_OVERFLOW;
    }

    if (expected_orig_len == 0U) {
        *dst_len = 0U;
        return LZSS_SUCCESS;
    }

    size_t in_idx = 2U;
    size_t out_idx = 0U;

    /* 2. Decode 8-token flag chunks */
    while (out_idx < (size_t)expected_orig_len && in_idx < src_len) {
        uint8_t flag_mask = src[in_idx++];

        for (int bit = 0; bit < 8 && out_idx < (size_t)expected_orig_len; bit++) {
            if ((flag_mask & (1U << bit)) != 0U) {
                /* MATCH TOKEN */
                if (in_idx + 2U > src_len) {
                    return LZSS_ERR_CORRUPT_DATA;
                }
                size_t dist = (size_t)src[in_idx++] + 1U;
                size_t len = (size_t)src[in_idx++] + LZSS_MIN_MATCH;

                if (dist > out_idx) {
                    return LZSS_ERR_CORRUPT_DATA; /* Distance points before start of stream */
                }
                if (out_idx + len > (size_t)expected_orig_len) {
                    return LZSS_ERR_CORRUPT_DATA; /* Match exceeds declared stream size */
                }

                /* Copy byte-by-byte to correctly resolve overlapping RLE-style runs */
                for (size_t k = 0U; k < len; k++) {
                    dst[out_idx] = dst[out_idx - dist];
                    out_idx++;
                }
            } else {
                /* LITERAL TOKEN */
                if (in_idx >= src_len) {
                    return LZSS_ERR_CORRUPT_DATA;
                }
                dst[out_idx++] = src[in_idx++];
            }
        }
    }

    if (out_idx != (size_t)expected_orig_len) {
        return LZSS_ERR_CORRUPT_DATA;
    }

    *dst_len = out_idx;
    return LZSS_SUCCESS;
}
