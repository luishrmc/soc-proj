/**
 * @file test_sw_pipeline.h
 * @brief Comprehensive Unit Test Suite & Static Assertions for Pure-Software Pipeline.
 */

#ifndef TEST_SW_PIPELINE_H
#define TEST_SW_PIPELINE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Execute all unit tests and print assertion reports to console.
 *
 * Runs:
 *   1. NIST SP 800-38A AES-128-CTR 4-block verification.
 *   2. LZSS compression / decompression roundtrip fidelity test.
 *   3. Buffer boundary and stress test (0 B, 1 B, odd lengths, 1024 B).
 *   4. Full Compress-then-Encrypt -> Decrypt-then-Decompress loopback test.
 *
 * @return 0 if all tests pass, positive count of failures if any fail.
 */
int test_sw_pipeline_run_all(void);

#ifdef __cplusplus
}
#endif

#endif /* TEST_SW_PIPELINE_H */
