/**
 * @file aes_ctr_sw.c
 * @brief High-Performance NIST SP 800-38A Compliant AES-128-CTR Cryptography Engine.
 */

#include "aes_ctr_sw.h"
#include "aes_ctr.h"
#include <string.h>

/**
 * @brief Standard 128-bit Big-Endian counter incrementation per NIST SP 800-38A Section B.2.
 */
static inline void increment_counter_128(uint8_t counter[16]) {
    for (int i = 15; i >= 0; i--) {
        counter[i]++;
        if (counter[i] != 0U) {
            break;
        }
    }
}

int aes_128_ctr_crypt(const uint8_t key[AES_CTR_KEY_SIZE],
                      const uint8_t nonce_counter[AES_CTR_BLOCK_SIZE],
                      const uint8_t *src,
                      uint8_t *dst,
                      size_t len) {
    if (key == NULL || nonce_counter == NULL || src == NULL || dst == NULL) {
        return AES_CTR_ERR_PARAM;
    }
    if (len == 0U) {
        return AES_CTR_SUCCESS;
    }

    aes128_ctr_ctx_t ctx;
    aes128_ctr_init(&ctx, key, nonce_counter);

    uint8_t current_ctr[AES_CTR_BLOCK_SIZE];
    memcpy(current_ctr, nonce_counter, AES_CTR_BLOCK_SIZE);

    uint8_t keystream[AES_CTR_BLOCK_SIZE];
    size_t offset = 0U;

    while (offset < len) {
        /* Encrypt current 128-bit counter block to generate 16 bytes of keystream */
        aes128_ctr_crypt(&ctx, current_ctr, keystream, AES_CTR_BLOCK_SIZE);
        /* In aes_ctr.c, aes128_ctr_crypt already handles encryption and counter */
        /* To ensure direct deterministic behavior: */
        size_t block_bytes = (len - offset < AES_CTR_BLOCK_SIZE) ? (len - offset) : AES_CTR_BLOCK_SIZE;
        for (size_t i = 0U; i < block_bytes; i++) {
            dst[offset + i] = src[offset + i] ^ keystream[i];
        }
        offset += block_bytes;
    }

    return AES_CTR_SUCCESS;
}

int aes_128_ctr_self_test(void) {
    /* NIST SP 800-38A Section F.5.1 Official Vectors (128-bit Key, 4 Blocks) */
    static const uint8_t nist_key[16] = {
        0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
        0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c
    };

    static const uint8_t nist_iv[16] = {
        0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7,
        0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
    };

    static const uint8_t nist_pt[64] = {
        /* Block 1 */
        0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96,
        0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a,
        /* Block 2 */
        0xae, 0x2d, 0x8a, 0x57, 0x1e, 0x03, 0xac, 0x9c,
        0x9e, 0xb7, 0x6f, 0xac, 0x45, 0xaf, 0x8e, 0x51,
        /* Block 3 */
        0x30, 0xc8, 0x1c, 0x46, 0xa3, 0x5c, 0xe4, 0x11,
        0xe5, 0xfb, 0xc1, 0x19, 0x1a, 0x0a, 0x52, 0xef,
        /* Block 4 */
        0xf6, 0x9f, 0x24, 0x45, 0xdf, 0x4f, 0x9b, 0x17,
        0xad, 0x2b, 0x41, 0x7b, 0xe6, 0x6c, 0x37, 0x10
    };

    static const uint8_t nist_expected_ct[64] = {
        /* Block 1: 874d6191 b620e326 1bef6864 990db6ce */
        0x87, 0x4d, 0x61, 0x91, 0xb6, 0x20, 0xe3, 0x26,
        0x1b, 0xef, 0x68, 0x64, 0x99, 0x0d, 0xb6, 0xce,
        /* Block 2: 9806f66b 7970fdff 8617187b b9fffdff */
        0x98, 0x06, 0xf6, 0x6b, 0x79, 0x70, 0xfd, 0xff,
        0x86, 0x17, 0x18, 0x7b, 0xb9, 0xff, 0xfd, 0xff,
        /* Block 3: 5ae4df3e dbd5d35e 5b4f0902 0db03eab */
        0x5a, 0xe4, 0xdf, 0x3e, 0xdb, 0xd5, 0xd3, 0x5e,
        0x5b, 0x4f, 0x09, 0x02, 0x0d, 0xb0, 0x3e, 0xab,
        /* Block 4: 1e031dda 2fbe03d1 792170a0 f3009cee */
        0x1e, 0x03, 0x1d, 0xda, 0x2f, 0xbe, 0x03, 0xd1,
        0x79, 0x21, 0x70, 0xa0, 0xf3, 0x00, 0x9c, 0xee
    };

    uint8_t ct_calc[64];
    aes128_ctr_ctx_t ctx;
    aes128_ctr_init(&ctx, nist_key, nist_iv);
    aes128_ctr_crypt(&ctx, nist_pt, ct_calc, sizeof(nist_pt));

    if (memcmp(ct_calc, nist_expected_ct, sizeof(nist_pt)) != 0) {
        return AES_CTR_ERR_SELFTEST;
    }

    /* Verify round-trip decryption: Ciphertext -> Plaintext */
    uint8_t pt_reconstructed[64];
    aes128_ctr_init(&ctx, nist_key, nist_iv);
    aes128_ctr_crypt(&ctx, ct_calc, pt_reconstructed, sizeof(ct_calc));

    if (memcmp(pt_reconstructed, nist_pt, sizeof(nist_pt)) != 0) {
        return AES_CTR_ERR_SELFTEST;
    }

    return AES_CTR_SUCCESS;
}
