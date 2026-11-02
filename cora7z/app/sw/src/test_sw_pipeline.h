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

/**
 * @brief Execute comprehensive 12-combination benchmark sweep across 256B, 512B, and 1024B.
 *
 * Runs all 4 scenarios (SW/SW, HW/SW, SW/HW, HW/HW) across 3 canonical payload lengths
 * (256 B, 512 B, 1024 B), verifying bit-exact ciphertext parity, loopback recovery,
 * and reporting PMU CPU cycles alongside Dual-Port BRAM PL execution cycles.
 *
 * @return 0 if all 12 combinations pass, non-zero failure count otherwise.
 */
int test_sw_pipeline_benchmark_sweep(void);

#ifdef __cplusplus
}
#endif

#endif /* TEST_SW_PIPELINE_H */
