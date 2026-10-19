/**
 * @file lz4_simple.c
 * @brief Simplified standard LZ4 lossless compression reference implementation.
 */

#include "lz4_simple.h"
#include <string.h>

#define LZ4_HASH_BITS 11U
#define LZ4_TABLE_ENTRIES (1U << LZ4_HASH_BITS) /* 2048 entries = 4 KB */

static inline uint32_t lz4_read32(const uint8_t *ptr) {
    return (uint32_t)ptr[0] |
           ((uint32_t)ptr[1] << 8) |
           ((uint32_t)ptr[2] << 16) |
           ((uint32_t)ptr[3] << 24);
}

static inline uint32_t lz4_hash32(uint32_t val) {
    return (val * 2654435761U) >> (32U - LZ4_HASH_BITS);
}

size_t lz4_compress(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_max_len) {
    if (src == NULL || dst == NULL || dst_max_len == 0) {
        return 0;
    }

    if (src_len == 0) {
        return 0;
    }

    /* Small buffer: emit pure literals token.
     * Standard LZ4 requires at least 12 bytes to attempt match finding
     * (5 bytes trailing literals + 4 bytes match + 3 bytes).
     * For src_len < 12, emit a pure literals block.
     */
    if (src_len < 12) {
        if (dst_max_len < src_len + 1) return 0;
        dst[0] = (uint8_t)(src_len << 4);
        memcpy(&dst[1], src, src_len);
        return src_len + 1;
    }

    /* Hash table storing byte offsets */
    static uint16_t hash_table[LZ4_TABLE_ENTRIES];
    memset(hash_table, 0, sizeof(hash_table));

    const uint8_t *ip = src;
    const uint8_t *const iend = src + src_len;
    const uint8_t *const mflimit = iend - 5; /* Match finding limit */
    const uint8_t *anchor = ip;

    uint8_t *op = dst;
    uint8_t *const oend = dst + dst_max_len;

    while (ip < mflimit) {
        uint32_t h = lz4_hash32(lz4_read32(ip));
        const uint8_t *ref = src + hash_table[h];
        hash_table[h] = (uint16_t)(ip - src);

        /* Check candidate match */
        if (ref < ip && (size_t)(ip - ref) <= LZ4_MAX_DISTANCE && lz4_read32(ref) == lz4_read32(ip)) {
            /* Match found! Determine match length without encroaching on mflimit */
            size_t match_len = 4;
            while ((ip + match_len < mflimit) && (ref[match_len] == ip[match_len])) {
                match_len++;
            }

            /* Emit sequence: [Token][Literals][Offset][MatchLen extension] */
            size_t lit_len = (size_t)(ip - anchor);
            uint8_t *token = op++;
            if (op >= oend) return 0;

            /* 1. Literal length encoding */
            if (lit_len >= 15) {
                *token = (uint8_t)(15U << 4);
                size_t l = lit_len - 15;
                while (l >= 255) {
                    if (op >= oend) return 0;
                    *op++ = 255;
                    l -= 255;
                }
                if (op >= oend) return 0;
                *op++ = (uint8_t)l;
            } else {
                *token = (uint8_t)(lit_len << 4);
            }

            /* 2. Copy literals */
            if (op + lit_len > oend) return 0;
            memcpy(op, anchor, lit_len);
            op += lit_len;

            /* 3. Emit 16-bit offset (little-endian) */
            uint16_t offset = (uint16_t)(ip - ref);
            if (op + 2 > oend) return 0;
            *op++ = (uint8_t)(offset & 0xFFU);
            *op++ = (uint8_t)((offset >> 8) & 0xFFU);

            /* 4. Match length encoding */
            size_t m = match_len - 4;
            if (m >= 15) {
                *token |= 15U;
                m -= 15;
                while (m >= 255) {
                    if (op >= oend) return 0;
                    *op++ = 255;
                    m -= 255;
                }
                if (op >= oend) return 0;
                *op++ = (uint8_t)m;
            } else {
                *token |= (uint8_t)m;
            }

            /* Advance pointers */
            ip += match_len;
            anchor = ip;
        } else {
            ip++;
        }
    }

    /* Emit final remaining literals */
    size_t last_lit_len = (size_t)(iend - anchor);
    if (last_lit_len > 0) {
        uint8_t *token = op++;
        if (op >= oend) return 0;

        if (last_lit_len >= 15) {
            *token = (uint8_t)(15U << 4);
            size_t l = last_lit_len - 15;
            while (l >= 255) {
                if (op >= oend) return 0;
                *op++ = 255;
                l -= 255;
            }
            if (op >= oend) return 0;
            *op++ = (uint8_t)l;
        } else {
            *token = (uint8_t)(last_lit_len << 4);
        }

        if (op + last_lit_len > oend) return 0;
        memcpy(op, anchor, last_lit_len);
        op += last_lit_len;
    }

    return (size_t)(op - dst);
}

size_t lz4_decompress(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_max_len) {
    if (src == NULL || dst == NULL || src_len == 0 || dst_max_len == 0) {
        return 0;
    }

    const uint8_t *ip = src;
    const uint8_t *const iend = src + src_len;
    uint8_t *op = dst;
    uint8_t *const oend = dst + dst_max_len;

    while (ip < iend) {
        uint8_t token = *ip++;

        /* 1. Literals */
        size_t lit_len = (size_t)(token >> 4);
        if (lit_len == 15) {
            uint8_t s;
            do {
                if (ip >= iend) return 0;
                s = *ip++;
                lit_len += s;
            } while (s == 255);
        }

        if (op + lit_len > oend || ip + lit_len > iend) {
            return 0;
        }
        memcpy(op, ip, lit_len);
        op += lit_len;
        ip += lit_len;

        if (ip >= iend) {
            break; /* End of block */
        }

        /* 2. Match offset */
        if (ip + 2 > iend) return 0;
        uint16_t offset = (uint16_t)ip[0] | ((uint16_t)ip[1] << 8);
        ip += 2;
        if (offset == 0 || (size_t)(op - dst) < offset) {
            return 0; /* Invalid offset */
        }

        /* 3. Match length */
        size_t match_len = (size_t)(token & 0x0FU) + 4;
        if ((token & 0x0FU) == 15) {
            uint8_t s;
            do {
                if (ip >= iend) return 0;
                s = *ip++;
                match_len += s;
            } while (s == 255);
        }

        if (op + match_len > oend) {
            return 0;
        }

        /* Copy matched bytes (may overlap, so copy byte-by-byte) */
        const uint8_t *ref = op - offset;
        for (size_t i = 0; i < match_len; i++) {
            *op++ = *ref++;
        }
    }

    return (size_t)(op - dst);
}
