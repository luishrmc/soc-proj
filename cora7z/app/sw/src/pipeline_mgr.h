/**
 * @file pipeline_mgr.h
 * @brief High-Level Pipeline Orchestrator Connecting SPI, PL Accelerators, and PS.
 *
 * Implements end-to-end data processing for Scenarios 1 (PS Pure),
 * 2 (PL Pure via DMA), and 3 (Hybrid Co-Design), adhering to ADR-012
 * bus fault prevention invariants.
 */

#ifndef PIPELINE_MGR_H
#define PIPELINE_MGR_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "axi_accel_ctrl.h"
#include "axi_dma_driver.h"
#include "axi_spi_receiver.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Execution Scenarios */
typedef enum {
    SCENARIO_PS_PURE = 1,
    SCENARIO_PL_PURE = 2,
    SCENARIO_HYBRID  = 3
} pipeline_scenario_t;

/* Algorithm Identifiers */
typedef enum {
    ALGO_RLE       = 0,
    ALGO_LZ4       = 1,
    ALGO_AES_CTR   = 2,
    ALGO_CHACHA20  = 3
} pipeline_algo_t;

typedef struct {
    uint32_t cpu_cycles;      /* Cortex-A9 PMU cycle count */
    uint32_t hw_cycles;       /* PL hardware accelerator cycle counter */
    size_t   output_length;   /* Resulting output bytes */
    float    latency_us;      /* Microseconds */
    float    throughput_mbps; /* Megabytes per second */
    bool     success;
} pipeline_metrics_t;

/**
 * @brief Initialize all AXI peripherals, verify PL bitstream state, and arm drivers.
 * @return 0 on success, negative if PL is unprogrammed or peripheral reset fails.
 */
int pipeline_mgr_init(void);

/**
 * @brief Process a data block across the specified scenario and algorithm.
 *
 * @param scenario SCENARIO_PS_PURE, SCENARIO_PL_PURE, or SCENARIO_HYBRID.
 * @param algo ALGO_RLE, ALGO_LZ4, ALGO_AES_CTR, or ALGO_CHACHA20.
 * @param in_buf Input buffer in memory.
 * @param in_len Input length in bytes.
 * @param out_buf Output buffer in memory.
 * @param max_out_len Output buffer capacity.
 * @param[out] metrics Pointer to performance and verification metrics.
 * @return 0 on success, negative on error.
 */
int pipeline_mgr_process(pipeline_scenario_t scenario,
                         pipeline_algo_t algo,
                         const uint8_t *in_buf,
                         size_t in_len,
                         uint8_t *out_buf,
                         size_t max_out_len,
                         pipeline_metrics_t *metrics);

/**
 * @brief Execute self-test on all AXI drivers and interfaces.
 * @return 0 if all tests pass, negative otherwise.
 */
int pipeline_mgr_self_test(void);

#ifdef __cplusplus
}
#endif

#endif /* PIPELINE_MGR_H */
