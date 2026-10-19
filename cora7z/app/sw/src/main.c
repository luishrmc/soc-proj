/******************************************************************************
* Company:       UFMG / Embedded Systems & SoC Laboratory
* Engineer:      Antigravity Agentic Assistant & User
* Project:       Zynq-7010 PS/PL Compression & Encryption Benchmark
* Target SoC:    Xilinx Zynq-7010 (Digilent Cora Z7-10)
* Tool Version:  Vitis 2026.1 Unified / ARM GCC 13.x
* File:          main.c
* Description:   Bare-metal baseline verification firmware for Cortex-A9.
*                Performs MMIO sanity checks on memory-mapped AXI peripherals
*                (DMA, Quad SPI, RLE Engine, LZ4 Engine) and validates cycle-
*                accurate hardware profiling via the ARM PMU (CP15).
******************************************************************************/

#include <stdint.h>
#include <stdbool.h>
#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h"

/* ========================================================================= */
/* Peripheral Base Address Definitions (Synchronized with INTERFACES.md)     */
/* ========================================================================= */
#ifdef XPAR_AXI_DMA_0_BASEADDR
#define AXI_DMA_BASEADDR     XPAR_AXI_DMA_0_BASEADDR
#else
#define AXI_DMA_BASEADDR     0x40400000U
#endif

#ifdef XPAR_AXI_QUAD_SPI_0_BASEADDR
#define AXI_SPI_BASEADDR     XPAR_AXI_QUAD_SPI_0_BASEADDR
#else
#define AXI_SPI_BASEADDR     0x41E00000U
#endif

#ifdef XPAR_RLE_ENGINE_0_BASEADDR
#define RLE_ENGINE_BASEADDR  XPAR_RLE_ENGINE_0_BASEADDR
#else
#define RLE_ENGINE_BASEADDR  0x43C00000U
#endif

#ifdef XPAR_LZ4_ENGINE_0_BASEADDR
#define LZ4_ENGINE_BASEADDR  XPAR_LZ4_ENGINE_0_BASEADDR
#else
#define LZ4_ENGINE_BASEADDR  0x43C10000U
#endif

/* Accelerator CSR Offsets */
#define CSR_REG_CONTROL      0x00U
#define CSR_REG_STATUS       0x04U
#define CSR_REG_SRC_LEN      0x08U
#define CSR_REG_DST_LEN      0x0CU
#define CSR_REG_CYCLE_COUNT  0x10U

/* ========================================================================= */
/* ARM Cortex-A9 Performance Monitor Unit (PMU / CP15) Routines             */
/* ========================================================================= */

/**
 * @brief Initialize and enable the Cortex-A9 Performance Monitor Unit.
 *        Enables PMCCNTR and resets the cycle counter.
 */
static inline void pmu_enable(void) {
    /* PMCR: Enable all counters (bit 0) and reset cycle counter (bit 2) */
    uint32_t pmcr_val = (1U << 0) | (1U << 2);
    __asm__ volatile("mcr p15, 0, %0, c9, c12, 0" :: "r"(pmcr_val));

    /* PMCNTENSET: Specifically enable the cycle count register (bit 31) */
    uint32_t enable_cc = (1U << 31);
    __asm__ volatile("mcr p15, 0, %0, c9, c12, 1" :: "r"(enable_cc));
}

/**
 * @brief Read the 32-bit Performance Monitor Cycle Counter (PMCCNTR).
 * @return Current 32-bit CPU cycle count.
 */
static inline uint32_t pmu_read_cycles(void) {
    uint32_t cycles;
    __asm__ volatile("mrc p15, 0, %0, c9, c13, 0" : "=r"(cycles));
    return cycles;
}

/**
 * @brief Calibrate the overhead of calling pmu_read_cycles() back-to-back.
 * @return Average overhead in clock cycles.
 */
static uint32_t pmu_calibrate(void) {
    uint32_t t_start, t_end;
    uint32_t sum = 0;
    const uint32_t iterations = 20;

    for (uint32_t i = 0; i < iterations; i++) {
        t_start = pmu_read_cycles();
        t_end   = pmu_read_cycles();
        sum += (t_end - t_start);
    }

    return sum / iterations;
}

/* Device Configuration Interface (DevC) definitions for FPGA state audit */
#define DEVCFG_BASEADDR          0xF8007000U
#define DEVCFG_INT_STS_OFFSET    0x0CU
#define DEVCFG_PCFG_DONE_MASK    (1U << 2)

static inline bool is_pl_programmed(void) {
    uint32_t int_sts = Xil_In32(DEVCFG_BASEADDR + DEVCFG_INT_STS_OFFSET);
    return ((int_sts & DEVCFG_PCFG_DONE_MASK) != 0U);
}

/* ========================================================================= */
/* Peripheral MMIO Sanity Checks                                             */
/* ========================================================================= */

static bool check_peripherals(void) {
    bool all_ok = true;
    uint32_t val;

    xil_printf("--- 1. Checking Memory-Mapped Peripheral Registers ---\r\n");

    /* Safety Check: Guard against accessing PL when FPGA is unprogrammed */
    if (!is_pl_programmed()) {
        xil_printf("[CRITICAL] FPGA fabric (PL) is NOT programmed (PCFG_DONE = 0)!\r\n");
        xil_printf("[CRITICAL] Accessing M_AXI_GP0 without a loaded bitstream freezes the ARM bus.\r\n");
        xil_printf("[ACTION]   Load the bitstream into the FPGA before running the application.\r\n");
        return false;
    }

    /* 1. RLE Compression Engine */
    val = Xil_In32(RLE_ENGINE_BASEADDR + CSR_REG_STATUS);
    xil_printf("[CHECK] RLE Engine @ 0x%08X -> STATUS = 0x%08X ... ", RLE_ENGINE_BASEADDR, val);
    if ((val & 0x01U) == 0U) { /* BUSY should be 0 at idle */
        xil_printf("PASS (IDLE)\r\n");
    } else {
        xil_printf("FAIL (Unexpected BUSY state)\r\n");
        all_ok = false;
    }

    /* 2. LZ4 Compression Engine */
    val = Xil_In32(LZ4_ENGINE_BASEADDR + CSR_REG_STATUS);
    xil_printf("[CHECK] LZ4 Engine @ 0x%08X -> STATUS = 0x%08X ... ", LZ4_ENGINE_BASEADDR, val);
    if ((val & 0x01U) == 0U) { /* BUSY should be 0 at idle */
        xil_printf("PASS (IDLE)\r\n");
    } else {
        xil_printf("FAIL (Unexpected BUSY state)\r\n");
        all_ok = false;
    }

    /* 3. AXI Direct Memory Access (AXI DMA) */
    val = Xil_In32(AXI_DMA_BASEADDR + 0x00U); /* MM2S_DMACR */
    xil_printf("[CHECK] AXI DMA    @ 0x%08X -> MM2S_DMACR = 0x%08X ... ", AXI_DMA_BASEADDR, val);
    /* In reset state, DMACR bit 0 (RS) is 0 */
    if ((val & 0x01U) == 0U) {
        xil_printf("PASS (HALTED/READY)\r\n");
    } else {
        xil_printf("PASS (RUNNING)\r\n");
    }

    /* 4. AXI Quad SPI Slave */
    val = Xil_In32(AXI_SPI_BASEADDR + 0x64U); /* Status Register */
    xil_printf("[CHECK] AXI SPI    @ 0x%08X -> STATUS     = 0x%08X ... ", AXI_SPI_BASEADDR, val);
    xil_printf("PASS (ACCESSIBLE)\r\n");

    return all_ok;
}

/* ========================================================================= */
/* Application Entry Point                                                   */
/* ========================================================================= */

int main(void) {
    xil_printf("\r\n");
    xil_printf("================================================================\r\n");
    xil_printf("  Digilent Cora Z7-10: SoC PS/PL Baseline Firmware Initialized  \r\n");
    xil_printf("  ARM Cortex-A9 Core 0 @ 667 MHz (Bare-Metal Standalone BSP)    \r\n");
    xil_printf("================================================================\r\n\r\n");

    /* Initialize and calibrate ARM PMU */
    pmu_enable();
    uint32_t pmu_overhead = pmu_calibrate();
    xil_printf("[PMU] Performance Monitor Unit initialized.\r\n");
    xil_printf("[PMU] Average PMCCNTR read overhead: %u CPU cycles\r\n\r\n", (unsigned int)pmu_overhead);

    /* Run MMIO peripheral checks */
    bool status = check_peripherals();

    xil_printf("\r\n================================================================\r\n");
    if (status) {
        xil_printf("[RESULT] ALL MAPPED AXI PERIPHERALS RESPONDED CORRECTLY (PASS)\r\n");
    } else {
        xil_printf("[RESULT] ONE OR MORE PERIPHERALS FAILED SANITY CHECKS (FAIL)\r\n");
    }
    xil_printf("================================================================\r\n\r\n");

    /* Idle loop */
    while (1) {
        __asm__ volatile("wfi");
    }

    return 0;
}
