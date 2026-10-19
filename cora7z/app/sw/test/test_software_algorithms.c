/**
 * @file test_software_algorithms.c
 * @brief Host-based automated unit verification for Cortex-A9 pure software algorithms.
 *
 * Validates RLE, LZ4, AES-CTR, and ChaCha20 against NIST SP 800-38A and
 * IETF RFC 8439 official golden vectors prior to target execution.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "rle.h"
#include "lz4_simple.h"
#include "aes_ctr.h"
#include "chacha20.h"

static void test_rle_golden(void) {
    printf("[TEST] Running RLE Golden Vector Validation...\n");

    /* 64 bytes of identical characters (0xAA) */
    uint8_t input_64b[64];
    memset(input_64b, 0xAA, sizeof(input_64b));

    uint8_t compressed[128];
    size_t comp_len = rle_compress(input_64b, sizeof(input_64b), compressed, sizeof(compressed));

    /* Expected: 1 run of 64 x 0xAA -> [0x40, 0xAA] = 2 bytes */
    assert(comp_len == 2);
    assert(compressed[0] == 64);
    assert(compressed[1] == 0xAA);

    /* Decompress and verify round-trip */
    uint8_t decompressed[128];
    size_t decomp_len = rle_decompress(compressed, comp_len, decompressed, sizeof(decompressed));
    assert(decomp_len == 64);
    assert(memcmp(input_64b, decompressed, 64) == 0);

    /* Test multiple distinct runs: 4x0x11, 8x0x22, 4x0x33 */
    uint8_t multi[16];
    memset(&multi[0], 0x11, 4);
    memset(&multi[4], 0x22, 8);
    memset(&multi[12], 0x33, 4);

    comp_len = rle_compress(multi, 16, compressed, sizeof(compressed));
    assert(comp_len == 6); /* 3 runs * 2 bytes */
    assert(compressed[0] == 4 && compressed[1] == 0x11);
    assert(compressed[2] == 8 && compressed[3] == 0x22);
    assert(compressed[4] == 4 && compressed[5] == 0x33);

    decomp_len = rle_decompress(compressed, comp_len, decompressed, sizeof(decompressed));
    assert(decomp_len == 16);
    assert(memcmp(multi, decompressed, 16) == 0);

    printf("  -> RLE PASS (Round-trip and token format verified)\n");
}

static void test_lz4_golden(void) {
    printf("[TEST] Running LZ4 Golden Vector Validation...\n");

    /* 1. Pure literals test (8 bytes) */
    uint8_t lit_in[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    uint8_t comp_buf[256];
    size_t comp_len = lz4_compress(lit_in, sizeof(lit_in), comp_buf, sizeof(comp_buf));
    assert(comp_len > 0);

    uint8_t decomp_buf[256];
    size_t decomp_len = lz4_decompress(comp_buf, comp_len, decomp_buf, sizeof(decomp_buf));
    assert(decomp_len == sizeof(lit_in));
    assert(memcmp(lit_in, decomp_buf, sizeof(lit_in)) == 0);

    /* 2. Structured repeating pattern (1024 bytes) */
    uint8_t pattern_in[1024];
    uint8_t comp_buf_1k[1024];
    uint8_t decomp_buf_1k[1024];
    for (size_t i = 0; i < sizeof(pattern_in); i++) {
        pattern_in[i] = (uint8_t)(i % 16);
    }

    comp_len = lz4_compress(pattern_in, sizeof(pattern_in), comp_buf_1k, sizeof(comp_buf_1k));
    assert(comp_len > 0);
    assert(comp_len < sizeof(pattern_in)); /* Compression ratio must be > 1.0 */

    decomp_len = lz4_decompress(comp_buf_1k, comp_len, decomp_buf_1k, sizeof(decomp_buf_1k));
    assert(decomp_len == sizeof(pattern_in));
    assert(memcmp(pattern_in, decomp_buf_1k, sizeof(pattern_in)) == 0);

    printf("  -> LZ4 PASS (Compression ratio: %.2fx, Round-trip verified)\n",
           (float)sizeof(pattern_in) / (float)comp_len);
}

static void test_aes_ctr_nist(void) {
    printf("[TEST] Running AES-128-CTR NIST SP 800-38A Golden Vector Validation...\n");

    /* NIST SP 800-38A Section F.5.1 */
    /* Key: 2b7e151628aed2a6abf7158809cf4f3c */
    const uint8_t key[16] = {
        0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
        0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c
    };

    /* Initial Counter Block: f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff */
    const uint8_t iv[16] = {
        0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7,
        0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
    };

    /* Plaintext Block 1: 6bc1bee22e409f96e93d7e117393172a */
    const uint8_t pt[16] = {
        0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96,
        0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a
    };

    /* Expected Ciphertext 1: 874d6191b620e3261bef6864990db6ce */
    const uint8_t expected_ct[16] = {
        0x87, 0x4d, 0x61, 0x91, 0xb6, 0x20, 0xe3, 0x26,
        0x1b, 0xef, 0x68, 0x64, 0x99, 0x0d, 0xb6, 0xce
    };

    uint8_t ct[16];
    aes128_ctr_ctx_t ctx;
    aes128_ctr_init(&ctx, key, iv);
    aes128_ctr_crypt(&ctx, pt, ct, sizeof(pt));

    assert(memcmp(ct, expected_ct, 16) == 0);

    /* Decrypt back */
    uint8_t decrypted[16];
    aes128_ctr_init(&ctx, key, iv);
    aes128_ctr_crypt(&ctx, ct, decrypted, sizeof(ct));
    assert(memcmp(decrypted, pt, 16) == 0);

    printf("  -> AES-128-CTR PASS (NIST SP 800-38A matched 100%%)\n");
}

static void test_chacha20_rfc8439(void) {
    printf("[TEST] Running ChaCha20 IETF RFC 8439 Section 2.3.2 Golden Vector Validation...\n");

    /* RFC 8439 Section 2.3.2 Test Vector */
    /* Key: 00:01:02:03:04:05:06:07:...:1e:1f */
    uint8_t key[32];
    for (int i = 0; i < 32; i++) key[i] = (uint8_t)i;

    /* Nonce: 00:00:00:09:00:00:00:4a:00:00:00:00 */
    uint8_t nonce[12] = {
        0x00, 0x00, 0x00, 0x09,
        0x00, 0x00, 0x00, 0x4a,
        0x00, 0x00, 0x00, 0x00
    };

    /* Initial counter: 1 */
    uint32_t counter = 1;

    /* Expected first 64-byte keystream from RFC 8439 Section 2.3.2 (matching tb_chacha20_engine.vhdl) */
    const uint8_t expected_keystream[64] = {
        0x10, 0xf1, 0xe7, 0xe4, 0xd1, 0x3b, 0x59, 0x15,
        0x50, 0x0f, 0xdd, 0x1f, 0xa3, 0x20, 0x71, 0xc4,
        0xc7, 0xd1, 0xf4, 0xc7, 0x33, 0xc0, 0x68, 0x03,
        0x04, 0x22, 0xaa, 0x9a, 0xc3, 0xd4, 0x6c, 0x4e,
        0xd2, 0x82, 0x64, 0x46, 0x07, 0x9f, 0xaa, 0x09,
        0x14, 0xc2, 0xd7, 0x05, 0xd9, 0x8b, 0x02, 0xa2,
        0xb5, 0x12, 0x9c, 0xd1, 0xde, 0x16, 0x4e, 0xb9,
        0xcb, 0xd0, 0x83, 0xe8, 0xa2, 0x50, 0x3c, 0x4e
    };

    chacha20_ctx_t ctx;
    chacha20_init(&ctx, key, nonce, counter);

    uint8_t keystream[64];
    chacha20_keystream_block(&ctx, keystream);

    assert(memcmp(keystream, expected_keystream, 64) == 0);

    /* Encrypt 64 bytes of zeros (0 XOR keystream = keystream) */
    uint8_t zeros[64] = {0};
    uint8_t ciphertext[64];
    chacha20_init(&ctx, key, nonce, counter);
    chacha20_crypt(&ctx, zeros, ciphertext, 64);
    assert(memcmp(ciphertext, expected_keystream, 64) == 0);

    printf("  -> ChaCha20 PASS (IETF RFC 8439 matched 100%%)\n");
}

int main(void) {
    printf("================================================================\n");
    printf("  Cortex-A9 Software Reference Algorithms Unit Verification     \n");
    printf("  Host Suite (MISRA-Aligned / Zero Dynamic Allocation)          \n");
    printf("================================================================\n");

    test_rle_golden();
    test_lz4_golden();
    test_aes_ctr_nist();
    test_chacha20_rfc8439();

    printf("================================================================\n");
    printf("  ALL 4 REFERENCE ALGORITHMS PASSED 100%% GOLDEN VERIFICATION   \n");
    printf("================================================================\n");
    return 0;
}
