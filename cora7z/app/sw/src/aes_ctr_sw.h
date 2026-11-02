/**
 * @file aes_ctr_sw.h
 * @brief High-Performance NIST SP 800-38A Compliant AES-128-CTR Cryptography Engine.
 *
 * Implements FIPS-197 compliant AES-128 in Counter Mode (CTR) with standard
 * Big-Endian 128-bit counter incrementation. Provides stream-cipher capability
 * (zero padding overhead) and integrated NIST self-test vectors.
 */

#ifndef AES_CTR_SW_H
#define AES_CTR_SW_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AES_CTR_KEY_SIZE    16U   /* 128-bit symmetric key (16 bytes) */
#define AES_CTR_BLOCK_SIZE  16U   /* 128-bit block size (16 bytes) */

#define AES_CTR_SUCCESS      0
#define AES_CTR_ERR_PARAM   -1
#define AES_CTR_ERR_SELFTEST -2

/**
 * @brief Encrypt or decrypt an arbitrary-length byte stream using AES-128-CTR.
 *
 * In Counter (CTR) mode, encryption and decryption are symmetric operations
 * (XORing with the AES keystream generated from the incrementing 128-bit counter).
 * Arbitrary stream lengths are handled without requiring block padding.
 *
 * @param[in]  key           16-byte AES-128 symmetric encryption key.
 * @param[in]  nonce_counter 16-byte initial counter block (IV / Nonce + Counter).
 * @param[in]  src           Pointer to input data buffer (plaintext or ciphertext).
 * @param[out] dst           Pointer to destination buffer (ciphertext or plaintext).
 * @param[in]  len           Length of data in bytes.
 * @return AES_CTR_SUCCESS on success, or negative error code.
 */
int aes_128_ctr_crypt(const uint8_t key[AES_CTR_KEY_SIZE],
                      const uint8_t nonce_counter[AES_CTR_BLOCK_SIZE],
                      const uint8_t *src,
                      uint8_t *dst,
                      size_t len);

/**
 * @brief Run built-in self-test against NIST SP 800-38A Section F.5.1 test vectors.
 *
 * Validates all 4 standard 16-byte blocks using the official NIST key and IV.
 *
 * @return AES_CTR_SUCCESS (0) on bit-exact match across all blocks, negative on failure.
 */
int aes_128_ctr_self_test(void);

#ifdef __cplusplus
}
#endif

#endif /* AES_CTR_SW_H */
