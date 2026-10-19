/**
 * @file chacha20.h
 * @brief IETF RFC 8439 ChaCha20 stream cipher reference implementation.
 *
 * Implements 20-round (10 double-rounds) ChaCha20 stream cipher using
 * 256-bit key, 96-bit nonce, and 32-bit block counter.
 *
 * Fully bare-metal compliant and host-verifiable (zero dynamic allocation).
 */

#ifndef CHACHA20_H
#define CHACHA20_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CHACHA20_KEY_SIZE    32U /* 256 bits */
#define CHACHA20_NONCE_SIZE  12U /* 96 bits */
#define CHACHA20_BLOCK_SIZE  64U /* 512 bits */

typedef struct {
    uint32_t state[16];         /* 16 x 32-bit state matrix */
} chacha20_ctx_t;

/**
 * @brief Initialize ChaCha20 context with key, nonce, and starting block counter.
 *
 * @param ctx Pointer to ChaCha20 context.
 * @param key 32-byte (256-bit) encryption key.
 * @param nonce 12-byte (96-bit) initialization vector/nonce.
 * @param counter Initial 32-bit block counter (typically 1 for RFC 8439 AEAD, 0 or 1 for raw stream).
 */
void chacha20_init(chacha20_ctx_t *ctx, const uint8_t key[CHACHA20_KEY_SIZE],
                   const uint8_t nonce[CHACHA20_NONCE_SIZE], uint32_t counter);

/**
 * @brief Encrypt or decrypt arbitrary length data stream with ChaCha20.
 *
 * @param ctx Pointer to initialized ChaCha20 context.
 * @param src Pointer to input data.
 * @param dst Pointer to destination buffer.
 * @param len Length in bytes.
 */
void chacha20_crypt(chacha20_ctx_t *ctx, const uint8_t *src, uint8_t *dst, size_t len);

/**
 * @brief Generate a single 64-byte keystream block without XORing data.
 *
 * @param ctx Pointer to ChaCha20 context (counter will be incremented).
 * @param keystream Pointer to 64-byte output buffer.
 */
void chacha20_keystream_block(chacha20_ctx_t *ctx, uint8_t keystream[CHACHA20_BLOCK_SIZE]);

#ifdef __cplusplus
}
#endif

#endif /* CHACHA20_H */
