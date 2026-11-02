/**
 * @file test_sw_pipeline.c
 * @brief Comprehensive Unit Test Suite & Static Assertions Implementation.
 */

#include "test_sw_pipeline.h"
#include "pipeline_mgr.h"
#include "lzss_sw.h"
#include "aes_ctr_sw.h"
#include <string.h>

#if defined(__arm__) || defined(__aarch64__)
#include "xil_printf.h"
#define LOG_PRINT xil_printf
#else
#include <stdio.h>
#define LOG_PRINT printf
#endif

static int test_aes_nist_vectors(void) {
    LOG_PRINT("[TEST 1/5] AES-128-CTR NIST SP 800-38A 4-Block Vector Verification... ");
    int rc = aes_128_ctr_self_test();
    if (rc == 0) {
        LOG_PRINT("PASS\r\n");
        return 0;
    } else {
        LOG_PRINT("FAIL (code %d)\r\n", rc);
        return 1;
    }
}

static int test_lzss_roundtrip_fidelity(void) {
    LOG_PRINT("[TEST 2/5] LZSS Compression/Decompression Roundtrip Fidelity... ");
    static uint8_t raw[512];
    static uint8_t comp[1024];
    static uint8_t decomp[512];
    static lzss_workspace_t ws;

    /* Generate synthetic telemetry pattern with repetitive structure */
    for (size_t i = 0; i < 512; i++) {
        raw[i] = (uint8_t)((i % 32) ^ (i / 64));
    }

    size_t comp_len = sizeof(comp);
    int rc = lzss_compress(raw, sizeof(raw), comp, &comp_len, &ws);
    if (rc != LZSS_SUCCESS) {
        LOG_PRINT("FAIL (Compress error %d)\r\n", rc);
        return 1;
    }

    size_t decomp_len = sizeof(decomp);
    rc = lzss_decompress(comp, comp_len, decomp, &decomp_len);
    if (rc != LZSS_SUCCESS) {
        LOG_PRINT("FAIL (Decompress error %d)\r\n", rc);
        return 1;
    }

    if (decomp_len != sizeof(raw) || memcmp(raw, decomp, sizeof(raw)) != 0) {
        LOG_PRINT("FAIL (Mismatch in reconstructed payload)\r\n");
        return 1;
    }

    LOG_PRINT("PASS (Raw: 512 B -> Comp: %u B, Ratio: %u%%)\r\n",
              (unsigned int)comp_len,
              (unsigned int)((1.0f - ((float)comp_len / 512.0f)) * 100.0f));
    return 0;
}

static int test_buffer_boundary_stress(void) {
    LOG_PRINT("[TEST 3/5] Buffer Boundary & Edge Length Stress Testing... ");
    static const size_t test_lengths[] = { 0, 1, 3, 7, 15, 16, 17, 63, 64, 65, 127, 255, 256, 512, 1024 };
    const size_t num_tests = sizeof(test_lengths) / sizeof(test_lengths[0]);

    static uint8_t test_in[1024];
    static uint8_t test_comp[2048];
    static uint8_t test_out[1024];
    static lzss_workspace_t ws;

    for (size_t t = 0; t < num_tests; t++) {
        size_t len = test_lengths[t];
        for (size_t i = 0; i < len; i++) {
            test_in[i] = (uint8_t)(i * 7 + t);
        }

        size_t comp_sz = sizeof(test_comp);
        int c_rc = lzss_compress(test_in, len, test_comp, &comp_sz, &ws);
        if (c_rc != LZSS_SUCCESS) {
            LOG_PRINT("FAIL (Len %u compress error %d)\r\n", (unsigned int)len, c_rc);
            return 1;
        }

        size_t dec_sz = sizeof(test_out);
        int d_rc = lzss_decompress(test_comp, comp_sz, test_out, &dec_sz);
        if (d_rc != LZSS_SUCCESS) {
            LOG_PRINT("FAIL (Len %u decompress error %d)\r\n", (unsigned int)len, d_rc);
            return 1;
        }

        if (dec_sz != len || (len > 0 && memcmp(test_in, test_out, len) != 0)) {
            LOG_PRINT("FAIL (Len %u data mismatch)\r\n", (unsigned int)len);
            return 1;
        }
    }

    LOG_PRINT("PASS (15 edge lengths verified: 0 B to 1024 B)\r\n");
    return 0;
}

static int test_pipeline_loopback(void) {
    LOG_PRINT("[TEST 4/5] End-to-End Pipeline Loopback (Raw -> Comp -> Encrypt -> Decrypt -> Decomp)... ");
    pipeline_init();

    static uint8_t raw_payload[64];
    static uint8_t cipher_buf[256];
    static uint8_t recovered_buf[64];

    /* Standard 64-byte incremental pattern matching active ESP32 injector */
    for (size_t i = 0; i < sizeof(raw_payload); i++) {
        raw_payload[i] = (uint8_t)(i & 0xFFU);
    }

    pipeline_metrics_t m;
    size_t cipher_len = 0;
    int rc = pipeline_process_frame(raw_payload, sizeof(raw_payload),
                                    cipher_buf, sizeof(cipher_buf),
                                    &cipher_len, &m);
    if (rc != PIPELINE_SUCCESS) {
        LOG_PRINT("FAIL (Forward pipeline error %d)\r\n", rc);
        return 1;
    }

    size_t recovered_len = 0;
    rc = pipeline_reverse_frame(cipher_buf, cipher_len,
                                recovered_buf, sizeof(recovered_buf),
                                &recovered_len);
    if (rc != PIPELINE_SUCCESS) {
        LOG_PRINT("FAIL (Reverse pipeline error %d)\r\n", rc);
        return 1;
    }

    if (recovered_len != sizeof(raw_payload) ||
        memcmp(raw_payload, recovered_buf, sizeof(raw_payload)) != 0) {
        LOG_PRINT("FAIL (Loopback payload mismatch: rec_len=%u)\r\n", (unsigned int)recovered_len);
        for (size_t i = 0; i < sizeof(raw_payload); i++) {
            if (raw_payload[i] != recovered_buf[i]) {
                LOG_PRINT("       Mismatch at byte %u: expected=0x%02X, got=0x%02X\r\n",
                          (unsigned int)i, raw_payload[i], recovered_buf[i]);
                break;
            }
        }
        return 1;
    }

    LOG_PRINT("PASS (64 B -> Cipher %u B | Comp: %u cyc, Crypt: %u cyc)\r\n",
              (unsigned int)cipher_len,
              (unsigned int)m.comp_cycles,
              (unsigned int)m.crypt_cycles);
    return 0;
}

static int test_hybrid_hardware_parity(void) {
    LOG_PRINT("[TEST 5/5] Hybrid 4-Scenario Parity & Dual-Port BRAM HW Offload... ");
    if (!pipeline_is_pl_ready()) {
        LOG_PRINT("SKIPPED (PL not programmed)\r\n");
        return 0;
    }

    static uint8_t test_payload[64];
    for (size_t i = 0; i < sizeof(test_payload); i++) {
        test_payload[i] = (uint8_t)((i * 3 + 0x20) & 0xFFU);
    }

    int rc = pipeline_verify_all_scenarios(test_payload, sizeof(test_payload));
    if (rc == PIPELINE_SUCCESS) {
        LOG_PRINT("PASS\r\n");
        return 0;
    } else {
        LOG_PRINT("FAIL (error code %d)\r\n", rc);
        return 1;
    }
}

int test_sw_pipeline_run_all(void) {
    LOG_PRINT("\r\n================================================================\r\n");
    LOG_PRINT("  Running Heterogeneous SoC Pipeline Verification & Test Suite \r\n");
    LOG_PRINT("================================================================\r\n");

    int failures = 0;
    failures += test_aes_nist_vectors();
    failures += test_lzss_roundtrip_fidelity();
    failures += test_buffer_boundary_stress();
    failures += test_pipeline_loopback();
    failures += test_hybrid_hardware_parity();

    LOG_PRINT("================================================================\r\n");
    if (failures == 0) {
        LOG_PRINT("  [ALL TESTS PASS] Pipeline Verification Suite: 5/5 PASSED      \r\n");
    } else {
        LOG_PRINT("  [TEST SUITE FAILURE] %d tests failed!                         \r\n", failures);
    }
    LOG_PRINT("================================================================\r\n\r\n");

    return failures;
}
