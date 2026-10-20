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
#include "benchmark_ps.h"
#include "pipeline_mgr.h"
#include "axi_spi_receiver.h"

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
    __asm__ volatile("isb; mrc p15, 0, %0, c9, c13, 0; isb" : "=r"(cycles) :: "memory");
    return cycles;
}

/**
 * @brief Calibrate the overhead of calling pmu_read_cycles() back-to-back.
 * @return Average overhead in clock cycles.
 */
static uint32_t pmu_calibrate(void) {
    uint32_t t_start, t_end;
    uint32_t sum = 0;
    uint32_t count = 0;
    const uint32_t iterations = 20;

    for (uint32_t i = 0; i < iterations; i++) {
        t_start = pmu_read_cycles();
        t_end   = pmu_read_cycles();
        if (t_end >= t_start) {
            sum += (t_end - t_start);
            count++;
        }
    }

    return (count > 0U) ? (sum / count) : 0U;
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
    val = Xil_In32(ACCEL_BASE_RLE + ACCEL_REG_STATUS);
    xil_printf("[CHECK] RLE Engine @ 0x%08X -> STATUS = 0x%08X ... ", ACCEL_BASE_RLE, val);
    if ((val & ACCEL_STAT_BUSY_MASK) == 0U) { /* BUSY should be 0 at idle */
        xil_printf("PASS (IDLE)\r\n");
    } else {
        xil_printf("FAIL (Unexpected BUSY state)\r\n");
        all_ok = false;
    }

    /* 2. LZ4 Compression Engine */
    val = Xil_In32(ACCEL_BASE_LZ4 + ACCEL_REG_STATUS);
    xil_printf("[CHECK] LZ4 Engine @ 0x%08X -> STATUS = 0x%08X ... ", ACCEL_BASE_LZ4, val);
    if ((val & ACCEL_STAT_BUSY_MASK) == 0U) { /* BUSY should be 0 at idle */
        xil_printf("PASS (IDLE)\r\n");
    } else {
        xil_printf("FAIL (Unexpected BUSY state)\r\n");
        all_ok = false;
    }

    /* 3. AES-CTR Coprocessor */
    val = Xil_In32(ACCEL_BASE_AES_CTR + ACCEL_REG_STATUS);
    xil_printf("[CHECK] AES Engine @ 0x%08X -> STATUS = 0x%08X ... ", ACCEL_BASE_AES_CTR, val);
    if ((val & ACCEL_STAT_BUSY_MASK) == 0U) { /* BUSY should be 0 at idle */
        xil_printf("PASS (IDLE)\r\n");
    } else {
        xil_printf("FAIL (Unexpected BUSY state)\r\n");
        all_ok = false;
    }

    /* 4. ChaCha20 Stream Cipher Coprocessor */
    val = Xil_In32(ACCEL_BASE_CHACHA20 + ACCEL_REG_STATUS);
    xil_printf("[CHECK] ChaCha Engine @ 0x%08X -> STATUS = 0x%08X ... ", ACCEL_BASE_CHACHA20, val);
    if ((val & ACCEL_STAT_BUSY_MASK) == 0U) { /* BUSY should be 0 at idle */
        xil_printf("PASS (IDLE)\r\n");
    } else {
        xil_printf("FAIL (Unexpected BUSY state)\r\n");
        all_ok = false;
    }

    /* 5. AXI Direct Memory Access (AXI DMA) */
    val = Xil_In32(AXI_DMA_DEFAULT_BASEADDR + DMA_REG_MM2S_DMACR);
    xil_printf("[CHECK] AXI DMA    @ 0x%08X -> MM2S_DMACR = 0x%08X ... ", AXI_DMA_DEFAULT_BASEADDR, val);
    /* In reset state, DMACR bit 0 (RS) is 0 */
    if ((val & DMA_CR_RS_MASK) == 0U) {
        xil_printf("PASS (HALTED/READY)\r\n");
    } else {
        xil_printf("PASS (RUNNING)\r\n");
    }

    /* 6. AXI Quad SPI Slave */
    val = Xil_In32(AXI_SPI_DEFAULT_BASEADDR + SPI_REG_SPISR);
    xil_printf("[CHECK] AXI SPI    @ 0x%08X -> STATUS     = 0x%08X ... ", AXI_SPI_DEFAULT_BASEADDR, val);
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
    xil_printf("  ARM Cortex-A9 Core 0 @ 650 MHz (Bare-Metal Standalone BSP)    \r\n");
    xil_printf("================================================================\r\n\r\n");

    /* Initialize and calibrate ARM PMU */
    pmu_enable();
    uint32_t pmu_overhead = pmu_calibrate();
    xil_printf("[PMU] Performance Monitor Unit initialized.\r\n");
    xil_printf("[PMU] Average PMCCNTR read overhead: %d CPU cycles\r\n\r\n", (int)pmu_overhead);

    /* Run MMIO peripheral checks */
    bool status = check_peripherals();

    xil_printf("\r\n================================================================\r\n");
    if (status) {
        xil_printf("[RESULT] ALL MAPPED AXI PERIPHERALS RESPONDED CORRECTLY (PASS)\r\n");
    } else {
        xil_printf("[RESULT] ONE OR MORE PERIPHERALS FAILED SANITY CHECKS (FAIL)\r\n");
    }
    xil_printf("================================================================\r\n\r\n");

    /* Run Scenario 1: Pure Software (PS) Reference Algorithms Benchmark */
    xil_printf("--- 2. Running Scenario 1 (PS Pure) Software Benchmarks ---\r\n");
#ifdef XPAR_CPU_CORE_CLOCK_FREQ_HZ
    benchmark_ps_run_all(XPAR_CPU_CORE_CLOCK_FREQ_HZ);
#else
    benchmark_ps_run_all(650000000U);
#endif

    /* Run AXI Communication Drivers Self-Test and Arming */
    xil_printf("--- 3. Testing and Initializing AXI Communication Drivers ---\r\n");
    int pipe_test_rc = pipeline_mgr_self_test();
    if (pipe_test_rc == 0) {
        xil_printf("[DRV_TEST] AXI Drivers and Frame Parser Self-Test: PASS\r\n");
    } else {
        xil_printf("[DRV_TEST] AXI Drivers Self-Test: FAIL (code %d)\r\n", pipe_test_rc);
    }

    if (status) {
        int pipe_init_rc = pipeline_mgr_init();
        if (pipe_init_rc == 0) {
            xil_printf("[DRV_INIT] AXI DMA, Quad SPI, and Accelerators Initialized & Armed: PASS\r\n");
        } else {
            xil_printf("[DRV_INIT] Pipeline Manager Init: FAIL (code %d)\r\n", pipe_init_rc);
        }
    }

    /* Active SPI Ingestion and Benchmark Loop */
    xil_printf("\r\n================================================================\r\n");
    xil_printf("  [SPI_RX] Listening for incoming packets from ESP32 on J7...\r\n");
    xil_printf("  Press BTN_TRIGGER (GPIO 32) on ESP32 to inject packets.\r\n");
    xil_printf("================================================================\r\n\r\n");

    static uint8_t s_rx_payload[65536];
    spi_frame_t rx_frame;
    uint32_t rx_packet_count = 0;
    uint32_t hb_ticks = 0;

    while (1) {
        int drain_rc = axi_spi_drain_frame(AXI_SPI_DEFAULT_BASEADDR,
                                           s_rx_payload,
                                           sizeof(s_rx_payload),
                                           &rx_frame,
                                           10000U);
        if (drain_rc == 0) {
            rx_packet_count++;
            xil_printf("[SPI_RX #%u] Frame Received! Type: 0x%02X | Flags: 0x%02X | Length: %u B | CRC: 0x%04X (VALID)\r\n",
                       (unsigned int)rx_packet_count,
                       (unsigned int)rx_frame.header.payload_type,
                       (unsigned int)rx_frame.header.flags,
                       (unsigned int)rx_frame.header.payload_len,
                       (unsigned int)rx_frame.crc16_received);
        } else if (drain_rc == -3) {
            xil_printf("[SPI_RX] Frame Error: CRC mismatch! (Recv: 0x%04X != Calc: 0x%04X)\r\n",
                       (unsigned int)rx_frame.crc16_received, (unsigned int)rx_frame.crc16_computed);
        }

        hb_ticks++;
        if (hb_ticks >= 2000U) {
            hb_ticks = 0;
            uint32_t spisr = Xil_In32(AXI_SPI_DEFAULT_BASEADDR + SPI_REG_SPISR);
            uint32_t fifo_cnt = axi_spi_rx_count(AXI_SPI_DEFAULT_BASEADDR);
            xil_printf("[CORA_Z7] Standby | J7 SPI Listening | SPISR=0x%02X | FIFO=%u | Pkts=%u\r\n",
                       (unsigned int)spisr,
                       (unsigned int)fifo_cnt,
                       (unsigned int)rx_packet_count);
        }
    }

    return 0;
}
