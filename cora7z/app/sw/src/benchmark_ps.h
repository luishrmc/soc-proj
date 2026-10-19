/**
 * @file benchmark_ps.h
 * @brief Benchmark suite for Cortex-A9 Pure Software (Scenario 1) Execution.
 *
 * Measures cycle-accurate execution time via the ARM PMU (CP15) for:
 *   1. RLE (64 B, High Redundancy)
 *   2. LZ4 (1 KB, Pseudo-Random)
 *   3. AES-128-CTR (64 KB, Telemetry)
 *   4. ChaCha20 (64 B & 64 KB, Telemetry)
 *
 * Implements statistical averaging over multiple runs per bare-metal standards.
 */

#ifndef BENCHMARK_PS_H
#define BENCHMARK_PS_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BENCHMARK_RUNS 10U

typedef struct {
    const char *algorithm_name;
    size_t      block_size_bytes;
    uint32_t    cycles_mean;
    uint32_t    cycles_stddev;
    float       latency_us;
    float       throughput_mbps;
    float       compression_ratio;
    bool        verified;
} benchmark_result_t;

/**
 * @brief Execute the full Scenario 1 (PS puro) benchmark matrix on Cortex-A9.
 *
 * @param cpu_freq_hz ARM Cortex-A9 CPU frequency in Hz (typically 666666667 Hz on Cora Z7).
 */
void benchmark_ps_run_all(uint32_t cpu_freq_hz);

#ifdef __cplusplus
}
#endif

#endif /* BENCHMARK_PS_H */
