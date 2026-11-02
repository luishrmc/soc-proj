/******************************************************************************
* Company:       UFMG / Embedded Systems & SoC Laboratory
* Engineer:      Antigravity Agentic Assistant & User
* Project:       Zynq-7010 PS/PL Compression & Encryption Benchmark
* Target SoC:    Xilinx Zynq-7010 (Digilent Cora Z7-10)
* Tool Version:  Vitis 2026.1 Unified / ARM GCC 13.x
* File:          main.c
* Description:   Bare-metal baseline verification firmware for Cortex-A9.
*                Performs PMU calibration, self-checks reference AES-CTR software
*                model against NIST SP 800-38A golden vectors, manages autonomous
*                ESP32 hardware triggering via PMOD JA1, and ingests SPI telemetry.
******************************************************************************/

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h"
#include "sleep.h"
#include "axi_spi_receiver.h"
#include "aes_ctr.h"
#include "pipeline_mgr.h"
#include "test_sw_pipeline.h"

/* ========================================================================= */
/* PS EMIO GPIO Hardware Trigger for ESP32 Data Injector                     */
/* PMOD JA Pin 1 (Package Pin Y18, Bank 34, 3.3V LVCMOS)                     */
/* Active-Low pulse sent to ESP32 BTN_TRIGGER (GPIO 32)                      */
/* ========================================================================= */
#define PS_GPIO_BASEADDR       0xE000A000U
#define PS_GPIO_DATA_2_OFFSET  0x0048U  /* Bank 2 Data (EMIO [31:0]) */
#define PS_GPIO_DIRM_2_OFFSET  0x0284U  /* Bank 2 Direction Mode */
#define PS_GPIO_OEN_2_OFFSET   0x0288U  /* Bank 2 Output Enable */

static void esp32_trigger_init(void) {
    /* Set Bank 2 bit 0 (EMIO pin 0) as Output */
    uint32_t dirm = Xil_In32(PS_GPIO_BASEADDR + PS_GPIO_DIRM_2_OFFSET);
    Xil_Out32(PS_GPIO_BASEADDR + PS_GPIO_DIRM_2_OFFSET, dirm | 0x01U);

    /* Enable Output for Bank 2 bit 0 */
    uint32_t oen = Xil_In32(PS_GPIO_BASEADDR + PS_GPIO_OEN_2_OFFSET);
    Xil_Out32(PS_GPIO_BASEADDR + PS_GPIO_OEN_2_OFFSET, oen | 0x01U);

    /* Idle State: HIGH (inactive for active-low button with pull-up) */
    uint32_t data = Xil_In32(PS_GPIO_BASEADDR + PS_GPIO_DATA_2_OFFSET);
    Xil_Out32(PS_GPIO_BASEADDR + PS_GPIO_DATA_2_OFFSET, data | 0x01U);
}

static void trigger_esp32_burst(void) {
    /* Drive LOW (simulates button press) */
    uint32_t data = Xil_In32(PS_GPIO_BASEADDR + PS_GPIO_DATA_2_OFFSET);
    Xil_Out32(PS_GPIO_BASEADDR + PS_GPIO_DATA_2_OFFSET, data & ~0x01U);

    /* Hold LOW for 30 ms (debouncer threshold on ESP32 is 20ms) */
    usleep(30000);

    /* Release back to HIGH (idle) */
    data = Xil_In32(PS_GPIO_BASEADDR + PS_GPIO_DATA_2_OFFSET);
    Xil_Out32(PS_GPIO_BASEADDR + PS_GPIO_DATA_2_OFFSET, data | 0x01U);
}

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
/* Cryptographic Software Baseline Self-Test                                 */
/* ========================================================================= */

static bool test_software_aes_ctr(void) {
    /* NIST SP 800-38A Section F.5.1 Golden Vector (128-bit key) */
    static const uint8_t key[16] = {
        0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
        0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c
    };
    static const uint8_t iv[16] = {
        0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7,
        0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
    };
    static const uint8_t plaintext[16] = {
        0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96,
        0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a
    };
    static const uint8_t expected_cipher[16] = {
        0x87, 0x4d, 0x61, 0x91, 0xb6, 0x20, 0xe3, 0x26,
        0x1b, 0xef, 0x68, 0x64, 0x99, 0x0d, 0xb6, 0xce
    };

    uint8_t ciphertext[16];
    aes128_ctr_ctx_t ctx;

    aes128_ctr_init(&ctx, key, iv);
    aes128_ctr_crypt(&ctx, plaintext, ciphertext, 16);

    if (memcmp(ciphertext, expected_cipher, 16) == 0) {
        xil_printf("[TEST] SW AES-128-CTR NIST SP 800-38A Golden Vector: PASS\r\n");
        return true;
    } else {
        xil_printf("[TEST] SW AES-128-CTR NIST SP 800-38A Golden Vector: FAIL\r\n");
        return false;
    }
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
    xil_printf("[PMU] Average PMCCNTR read overhead: %d CPU cycles\r\n\r\n", (int)pmu_overhead);

    /* Check FPGA fabric state */
    if (is_pl_programmed()) {
        xil_printf("[DEVCFG] FPGA fabric (PL) is programmed (PCFG_DONE = 1).\r\n");
    } else {
        xil_printf("[DEVCFG] Note: FPGA fabric (PL) is not yet programmed.\r\n");
    }

    /* Run baseline cryptographic software test */
    test_software_aes_ctr();

    /* Run Comprehensive Pure-Software Pipeline Test Suite */
    test_sw_pipeline_run_all();

    /* Initialize Compress-then-Encrypt Software Pipeline */
    pipeline_init();

    /* Initialize Autonomous ESP32 Trigger Line (PMOD JA Pin 1 -> ESP32 GPIO 32) */
    esp32_trigger_init();
    xil_printf("[TRIGGER] PS EMIO GPIO Initialized on PMOD JA Pin 1 (Package Pin Y18).\r\n");
    xil_printf("[TRIGGER] Connected to ESP32 GPIO 32 for automatic burst control.\r\n\r\n");

    /* Active SPI Ingestion and Benchmark Loop */
    xil_printf("================================================================\r\n");
    xil_printf("  [SPI_RX] Listening for incoming packets from ESP32 on J7...\r\n");
    xil_printf("  Pinout: SCLK=H15 (J7.3), MOSI=T12 (J7.4), MISO=W15 (J7.1), SS=F16 (J7.5)\r\n");
    xil_printf("================================================================\r\n\r\n");

    /* Verify PL programming state before accessing AXI Quad SPI over M_AXI_GP0 */
    if (!is_pl_programmed()) {
        xil_printf("[AXI_SPI] WARNING: PL bitstream is NOT loaded (PCFG_DONE=0).\r\n");
        xil_printf("[AXI_SPI] Cannot initialize AXI Quad SPI at 0x%08X without PL bitstream.\r\n",
                   (unsigned int)AXI_SPI_DEFAULT_BASEADDR);
        xil_printf("[AXI_SPI] Waiting for PL to be programmed via JTAG/DevC...\r\n");
        while (!is_pl_programmed()) {
            usleep(100000);
        }
        xil_printf("[AXI_SPI] PL bitstream detected! Proceeding with initialization.\r\n");
    }

    /* Initialize AXI Quad SPI in Slave Mode 0 */
    axi_spi_init(AXI_SPI_DEFAULT_BASEADDR);
    xil_printf("[AXI_SPI] AXI Quad SPI core at 0x%08X initialized in Slave Mode 0.\r\n",
               (unsigned int)AXI_SPI_DEFAULT_BASEADDR);

    /* Trigger initial burst automatically */
    xil_printf("[TRIGGER] Emitting initial active-low pulse (30 ms) to ESP32 on PMOD JA1...\r\n");
    trigger_esp32_burst();

    static TelemetryFrame rx_frame;
    static axi_spi_metrics_t metrics = {0};
    uint32_t hb_ticks = 0;

    while (1) {
        int rc = axi_spi_read_frame(AXI_SPI_DEFAULT_BASEADDR, &rx_frame, 5000U);
        if (rc == 0) {
            metrics.total_packets_received++;
            metrics.valid_packets++;
            uint16_t rx_seq = ntohs(rx_frame.seq_id);
            uint16_t rx_len = ntohs(rx_frame.payload_len);

            /* Stage ACK response (0x81) into TX FIFO with mirrored seq_id */
            axi_spi_stage_ack(AXI_SPI_DEFAULT_BASEADDR, rx_seq, 0x00U);

            /* Execute Pure-Software Compress-then-Encrypt Pipeline */
            static uint8_t s_ciphertext[PIPELINE_MAX_FRAME_SIZE];
            size_t cipher_len = 0;
            pipeline_metrics_t pm = {0};

            int pipe_rc = pipeline_process_frame(rx_frame.payload,
                                                 (size_t)rx_len,
                                                 s_ciphertext,
                                                 sizeof(s_ciphertext),
                                                 &cipher_len,
                                                 &pm);

            if (pipe_rc == PIPELINE_SUCCESS) {
                int cr_pct = (int)(pm.compression_ratio * 100.0f);
                int tp_int = (int)pm.throughput_mbs;
                int tp_frac = (int)((pm.throughput_mbs - (float)tp_int) * 100.0f);
                if (tp_frac < 0) tp_frac = -tp_frac;

                xil_printf("[SPI_RX #%u] Seq: %u | Raw: %u B -> Comp: %u B -> Cipher: %u B | T_comp: %u us (%u cyc), T_crypt: %u us (%u cyc) | CR: %d%% | %d.%02d MB/s\r\n",
                           (unsigned int)metrics.valid_packets,
                           (unsigned int)rx_seq,
                           (unsigned int)pm.raw_len,
                           (unsigned int)pm.comp_len,
                           (unsigned int)pm.crypt_len,
                           (unsigned int)pm.comp_time_us,
                           (unsigned int)pm.comp_cycles,
                           (unsigned int)pm.crypt_time_us,
                           (unsigned int)pm.crypt_cycles,
                           cr_pct,
                           tp_int,
                           tp_frac);
            } else {
                xil_printf("[SPI_RX #%u] Seq: %u | Pipeline Processing Error: %d\r\n",
                           (unsigned int)metrics.valid_packets,
                           (unsigned int)rx_seq,
                           pipe_rc);
            }
        } else if (rc == -2) {
            metrics.total_packets_received++;
            metrics.frame_errors++;
            xil_printf("[SPI_RX] Frame Error! Bad EOF delimiter (expected 0x5A, got 0x%02X) [Err: %u/%u]\r\n",
                       (unsigned int)rx_frame.eof_delim,
                       (unsigned int)metrics.frame_errors,
                       (unsigned int)metrics.total_packets_received);
        } else if (rc == -3) {
            metrics.total_packets_received++;
            metrics.crc_mismatches++;
            xil_printf("[SPI_RX] Checksum Error! CRC mismatch (Recv: 0x%04X) [CRC Err: %u/%u]\r\n",
                       (unsigned int)ntohs(rx_frame.crc16),
                       (unsigned int)metrics.crc_mismatches,
                       (unsigned int)metrics.total_packets_received);
        }

        hb_ticks++;
        if (hb_ticks >= 2000U) {
            hb_ticks = 0;
            uint32_t spisr = Xil_In32(AXI_SPI_DEFAULT_BASEADDR + SPI_REG_SPISR);
            uint32_t fifo_cnt = axi_spi_rx_count(AXI_SPI_DEFAULT_BASEADDR);
            xil_printf("[CORA_Z7] Standby | J7 SPI Listening | SPISR=0x%02X | FIFO=%u | Valid: %u | CRC Err: %u | Frame Err: %u\r\n",
                       (unsigned int)spisr,
                       (unsigned int)fifo_cnt,
                       (unsigned int)metrics.valid_packets,
                       (unsigned int)metrics.crc_mismatches,
                       (unsigned int)metrics.frame_errors);

            /* Periodically pulse the trigger line if waiting for frames */
            xil_printf("[CORA_Z7] Triggering burst on ESP32 via PMOD JA1...\r\n");
            trigger_esp32_burst();
        }
    }

    return 0;
}
