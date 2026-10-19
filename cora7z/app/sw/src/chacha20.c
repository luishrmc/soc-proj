/**
 * @file chacha20.c
 * @brief IETF RFC 8439 ChaCha20 stream cipher reference implementation.
 */

#include "chacha20.h"
#include <string.h>

#define ROTL32(v, n) (((v) << (n)) | ((v) >> (32 - (n))))

#define CHACHA20_QUARTERROUND(a, b, c, d) \
    do { \
        a += b; d ^= a; d = ROTL32(d, 16); \
        c += d; b ^= c; b = ROTL32(b, 12); \
        a += b; d ^= a; d = ROTL32(d, 8);  \
        c += d; b ^= c; b = ROTL32(b, 7);  \
    } while (0)

static inline uint32_t load32_le(const uint8_t *p) {
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static inline void store32_le(uint8_t *p, uint32_t val) {
    p[0] = (uint8_t)(val & 0xFFU);
    p[1] = (uint8_t)((val >> 8) & 0xFFU);
    p[2] = (uint8_t)((val >> 16) & 0xFFU);
    p[3] = (uint8_t)((val >> 24) & 0xFFU);
}

void chacha20_init(chacha20_ctx_t *ctx, const uint8_t key[CHACHA20_KEY_SIZE],
                   const uint8_t nonce[CHACHA20_NONCE_SIZE], uint32_t counter) {
    if (ctx == NULL || key == NULL || nonce == NULL) {
        return;
    }

    /* Constants "expand 32-byte k" */
    ctx->state[0]  = 0x61707865U;
    ctx->state[1]  = 0x3320646eU;
    ctx->state[2]  = 0x79622d32U;
    ctx->state[3]  = 0x6b206574U;

    /* 256-bit Key */
    ctx->state[4]  = load32_le(&key[0]);
    ctx->state[5]  = load32_le(&key[4]);
    ctx->state[6]  = load32_le(&key[8]);
    ctx->state[7]  = load32_le(&key[12]);
    ctx->state[8]  = load32_le(&key[16]);
    ctx->state[9]  = load32_le(&key[20]);
    ctx->state[10] = load32_le(&key[24]);
    ctx->state[11] = load32_le(&key[28]);

    /* 32-bit Counter */
    ctx->state[12] = counter;

    /* 96-bit Nonce */
    ctx->state[13] = load32_le(&nonce[0]);
    ctx->state[14] = load32_le(&nonce[4]);
    ctx->state[15] = load32_le(&nonce[8]);
}

void chacha20_keystream_block(chacha20_ctx_t *ctx, uint8_t keystream[CHACHA20_BLOCK_SIZE]) {
    if (ctx == NULL || keystream == NULL) {
        return;
    }

    uint32_t x[16];
    for (int i = 0; i < 16; i++) {
        x[i] = ctx->state[i];
    }

    /* 10 Double Rounds = 20 Rounds */
    for (int r = 0; r < 10; r++) {
        /* Column Round */
        CHACHA20_QUARTERROUND(x[0], x[4], x[8],  x[12]);
        CHACHA20_QUARTERROUND(x[1], x[5], x[9],  x[13]);
        CHACHA20_QUARTERROUND(x[2], x[6], x[10], x[14]);
        CHACHA20_QUARTERROUND(x[3], x[7], x[11], x[15]);

        /* Diagonal Round */
        CHACHA20_QUARTERROUND(x[0], x[5], x[10], x[15]);
        CHACHA20_QUARTERROUND(x[1], x[6], x[11], x[12]);
        CHACHA20_QUARTERROUND(x[2], x[7], x[8],  x[13]);
        CHACHA20_QUARTERROUND(x[3], x[4], x[9],  x[14]);
    }

    /* Add back the initial state */
    for (int i = 0; i < 16; i++) {
        x[i] += ctx->state[i];
        store32_le(&keystream[i * 4], x[i]);
    }

    /* Increment block counter */
    ctx->state[12]++;
}

void chacha20_crypt(chacha20_ctx_t *ctx, const uint8_t *src, uint8_t *dst, size_t len) {
    if (ctx == NULL || src == NULL || dst == NULL || len == 0) {
        return;
    }

    uint8_t keystream[CHACHA20_BLOCK_SIZE];
    size_t offset = 0;

    while (offset < len) {
        chacha20_keystream_block(ctx, keystream);

        size_t block_bytes = (len - offset < CHACHA20_BLOCK_SIZE) ? (len - offset) : CHACHA20_BLOCK_SIZE;
        for (size_t i = 0; i < block_bytes; i++) {
            dst[offset + i] = src[offset + i] ^ keystream[i];
        }
        offset += block_bytes;
    }
}
