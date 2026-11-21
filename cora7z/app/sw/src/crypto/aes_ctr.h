/**
 * @file aes_ctr.h
 * @brief AES-128 in Counter Mode (AES-CTR) reference implementation.
 *
 * Implements NIST SP 800-38A compliant AES-128 CTR encryption/decryption.
 * Bare-metal and host-verifiable with zero dynamic memory allocation.
 */

#ifndef AES_CTR_H
#define AES_CTR_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AES_BLOCK_SIZE     16U
#define AES128_KEY_SIZE    16U

typedef struct {
    uint32_t round_keys[44];    /* 11 round keys * 4 words */
    uint8_t  counter[AES_BLOCK_SIZE]; /* Current 128-bit counter block */
} aes128_ctr_ctx_t;

/**
 * @brief Initialize AES-128-CTR context with key and initial counter/IV.
 *
 * @param ctx Pointer to context structure to populate.
 * @param key 16-byte (128-bit) symmetric key.
 * @param iv  16-byte (128-bit) initial counter block (nonce + 32-bit counter).
 */
void aes128_ctr_init(aes128_ctr_ctx_t *ctx, const uint8_t key[AES128_KEY_SIZE], const uint8_t iv[AES_BLOCK_SIZE]);

/**
 * @brief Encrypt or decrypt data stream using AES-128-CTR.
 *        In CTR mode, encryption and decryption are symmetric operations.
 *
 * @param ctx Pointer to initialized AES-128-CTR context.
 * @param src Pointer to input data (plaintext or ciphertext).
 * @param dst Pointer to output buffer (ciphertext or plaintext).
 * @param len Length in bytes.
 */
void aes128_ctr_crypt(aes128_ctr_ctx_t *ctx, const uint8_t *src, uint8_t *dst, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* AES_CTR_H */
