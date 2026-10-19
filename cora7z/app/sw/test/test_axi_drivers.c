/**
 * @file test_axi_drivers.c
 * @brief Host-Side Unit Verification Test Suite for AXI Communication Drivers.
 *
 * Implements a memory-mapped I/O mock engine simulating AXI DMA, Quad SPI,
 * and Accelerator hardware registers to achieve 100% test coverage under GCC.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#include "axi_io.h"
#include "axi_accel_ctrl.h"
#include "axi_dma_driver.h"
#include "axi_spi_receiver.h"
#include "pipeline_mgr.h"

/* ========================================================================= */
/* Mock MMIO Storage & Simulation Engine                                     */
/* ========================================================================= */
#define MOCK_MAP_SIZE 1024

typedef struct {
    uintptr_t addr;
    uint32_t  val;
} mock_reg_entry_t;

static mock_reg_entry_t s_mock_regs[MOCK_MAP_SIZE];
static size_t s_mock_reg_count = 0;

/* Simulated hardware behavior states */
static uint32_t s_dma_mm2s_poll_count = 0;
static uint32_t s_dma_s2mm_poll_count = 0;
static uint32_t s_accel_poll_count = 0;

static uint8_t  s_mock_spi_rx_fifo[256];
static size_t   s_mock_spi_rx_head = 0;
static size_t   s_mock_spi_rx_tail = 0;

static void mock_reset_all(void) {
    memset(s_mock_regs, 0, sizeof(s_mock_regs));
    s_mock_reg_count = 0;
    s_dma_mm2s_poll_count = 0;
    s_dma_s2mm_poll_count = 0;
    s_accel_poll_count = 0;
    s_mock_spi_rx_head = 0;
    s_mock_spi_rx_tail = 0;
}

static mock_reg_entry_t* mock_find_entry(uintptr_t addr) {
    for (size_t i = 0; i < s_mock_reg_count; i++) {
        if (s_mock_regs[i].addr == addr) {
            return &s_mock_regs[i];
        }
    }
    if (s_mock_reg_count < MOCK_MAP_SIZE) {
        s_mock_regs[s_mock_reg_count].addr = addr;
        s_mock_regs[s_mock_reg_count].val = 0U;
        return &s_mock_regs[s_mock_reg_count++];
    }
    return NULL;
}

uint32_t host_mock_read32(uintptr_t addr) {
    /* Dynamic hardware behavior simulation */

    /* 1. DMA Status Register Reads */
    if (addr == (AXI_DMA_DEFAULT_BASEADDR + DMA_REG_MM2S_DMASR)) {
        s_dma_mm2s_poll_count++;
        /* Simulate busy for 1 cycle, then IDLE */
        if (s_dma_mm2s_poll_count >= 2) {
            return DMA_SR_IDLE_MASK;
        }
        return 0U;
    }

    if (addr == (AXI_DMA_DEFAULT_BASEADDR + DMA_REG_S2MM_DMASR)) {
        s_dma_s2mm_poll_count++;
        if (s_dma_s2mm_poll_count >= 2) {
            return DMA_SR_IDLE_MASK;
        }
        return 0U;
    }

    /* 2. Accelerator Status Register Reads */
    if (addr == (ACCEL_BASE_RLE + ACCEL_REG_STATUS) ||
        addr == (ACCEL_BASE_LZ4 + ACCEL_REG_STATUS) ||
        addr == (ACCEL_BASE_AES_CTR + ACCEL_REG_STATUS) ||
        addr == (ACCEL_BASE_CHACHA20 + ACCEL_REG_STATUS)) {
        s_accel_poll_count++;
        if (s_accel_poll_count >= 2) {
            return ACCEL_STAT_DONE_MASK;
        }
        return ACCEL_STAT_BUSY_MASK;
    }

    if (addr == (ACCEL_BASE_RLE + ACCEL_REG_DST_LEN)) {
        return 32U; /* Simulated compressed size */
    }

    if (addr == (ACCEL_BASE_RLE + ACCEL_REG_CYCLE_COUNT)) {
        return 64U; /* Simulated clock cycles */
    }

    /* 3. SPI Status and FIFO Reads */
    if (addr == (AXI_SPI_DEFAULT_BASEADDR + SPI_REG_SPISR)) {
        uint32_t sr = 0;
        if (s_mock_spi_rx_head == s_mock_spi_rx_tail) {
            sr |= SPI_SR_RX_EMPTY_MASK;
        }
        sr |= SPI_SR_TX_EMPTY_MASK;
        return sr;
    }

    if (addr == (AXI_SPI_DEFAULT_BASEADDR + SPI_REG_RX_FIFO_OCY)) {
        if (s_mock_spi_rx_head >= s_mock_spi_rx_tail) {
            size_t count = s_mock_spi_rx_head - s_mock_spi_rx_tail;
            return (count > 0) ? (uint32_t)(count - 1) : 0U;
        }
        return 0U;
    }

    if (addr == (AXI_SPI_DEFAULT_BASEADDR + SPI_REG_DRR)) {
        if (s_mock_spi_rx_head != s_mock_spi_rx_tail) {
            uint8_t b = s_mock_spi_rx_fifo[s_mock_spi_rx_tail++];
            return (uint32_t)b;
        }
        return 0U;
    }

    /* Standard mapped read */
    mock_reg_entry_t *entry = mock_find_entry(addr);
    return entry ? entry->val : 0U;
}

void host_mock_write32(uintptr_t addr, uint32_t val) {
    mock_reg_entry_t *entry = mock_find_entry(addr);
    if (entry) {
        entry->val = val;
    }

    /* Auto-clear reset bits to simulate hardware completion */
    if (addr == (AXI_DMA_DEFAULT_BASEADDR + DMA_REG_MM2S_DMACR)) {
        if ((val & DMA_CR_RESET_MASK) != 0U) {
            entry->val &= ~DMA_CR_RESET_MASK; /* Reset cleared */
        }
    }

    if (addr == (AXI_DMA_DEFAULT_BASEADDR + DMA_REG_S2MM_DMACR)) {
        if ((val & DMA_CR_RESET_MASK) != 0U) {
            entry->val &= ~DMA_CR_RESET_MASK;
        }
    }

    if (addr == (AXI_DMA_DEFAULT_BASEADDR + DMA_REG_MM2S_LENGTH)) {
        s_dma_mm2s_poll_count = 0;
    }

    if (addr == (AXI_DMA_DEFAULT_BASEADDR + DMA_REG_S2MM_LENGTH)) {
        s_dma_s2mm_poll_count = 0;
    }

    if (addr == (ACCEL_BASE_RLE + ACCEL_REG_CONTROL)) {
        if ((val & ACCEL_CTRL_START_MASK) != 0U) {
            s_accel_poll_count = 0;
        }
    }
}

static void mock_spi_push_rx(const uint8_t *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        s_mock_spi_rx_fifo[s_mock_spi_rx_head++] = data[i];
    }
}

/* ========================================================================= */
/* Test Cases                                                                */
/* ========================================================================= */

static void test_axi_dma_driver(void) {
    printf("[TEST] Testing AXI DMA v7.1 Simple Mode Driver...\n");
    mock_reset_all();

    /* 1. Test DMA initialization and reset sequence */
    int rc = axi_dma_init(AXI_DMA_DEFAULT_BASEADDR);
    assert(rc == 0);
    printf("  -> AXI DMA Init & Soft Reset: PASS\n");

    /* 2. Test MM2S Start & Wait */
    uint8_t tx_buf[64];
    memset(tx_buf, 0x55, sizeof(tx_buf));
    rc = axi_dma_start_mm2s(AXI_DMA_DEFAULT_BASEADDR, (uintptr_t)tx_buf, sizeof(tx_buf));
    assert(rc == 0);

    /* Verify programmed address and length */
    mock_reg_entry_t *sa_entry = mock_find_entry(AXI_DMA_DEFAULT_BASEADDR + DMA_REG_MM2S_SA);
    assert(sa_entry != NULL && sa_entry->val == (uint32_t)(uintptr_t)tx_buf);
    mock_reg_entry_t *len_entry = mock_find_entry(AXI_DMA_DEFAULT_BASEADDR + DMA_REG_MM2S_LENGTH);
    assert(len_entry != NULL && len_entry->val == sizeof(tx_buf));

    rc = axi_dma_wait_mm2s(AXI_DMA_DEFAULT_BASEADDR, 100);
    assert(rc == 0);
    printf("  -> AXI DMA MM2S (Transmit): PASS\n");

    /* 3. Test S2MM Start & Wait */
    uint8_t rx_buf[64];
    rc = axi_dma_start_s2mm(AXI_DMA_DEFAULT_BASEADDR, (uintptr_t)rx_buf, sizeof(rx_buf));
    assert(rc == 0);

    mock_reg_entry_t *da_entry = mock_find_entry(AXI_DMA_DEFAULT_BASEADDR + DMA_REG_S2MM_DA);
    assert(da_entry != NULL && da_entry->val == (uint32_t)(uintptr_t)rx_buf);

    rc = axi_dma_wait_s2mm(AXI_DMA_DEFAULT_BASEADDR, (uintptr_t)rx_buf, sizeof(rx_buf), 100);
    assert(rc == 0);
    printf("  -> AXI DMA S2MM (Receive): PASS\n");

    /* 4. Test Synchronous Round-trip */
    rc = axi_dma_transfer_sync(AXI_DMA_DEFAULT_BASEADDR,
                               (uintptr_t)tx_buf, sizeof(tx_buf),
                               (uintptr_t)rx_buf, sizeof(rx_buf),
                               100);
    assert(rc == 0);
    printf("  -> AXI DMA Synchronous Transfer: PASS\n");
}

static void test_axi_accel_ctrl(void) {
    printf("[TEST] Testing AXI Accelerator Control Driver...\n");
    mock_reset_all();

    /* 1. Common accelerator reset, start and polling */
    axi_accel_reset(ACCEL_BASE_RLE);
    mock_reg_entry_t *ctrl_entry = mock_find_entry(ACCEL_BASE_RLE + ACCEL_REG_CONTROL);
    assert(ctrl_entry != NULL && ctrl_entry->val == 0U); /* De-asserted */

    axi_accel_start(ACCEL_BASE_RLE, 64U);
    mock_reg_entry_t *src_entry = mock_find_entry(ACCEL_BASE_RLE + ACCEL_REG_SRC_LEN);
    assert(src_entry != NULL && src_entry->val == 64U);

    uint32_t dst_len = 0;
    uint32_t hw_cyc = 0;
    int rc = axi_accel_poll_done(ACCEL_BASE_RLE, 100, &dst_len, &hw_cyc);
    assert(rc == 0);
    assert(dst_len == 32U);
    assert(hw_cyc == 64U);
    printf("  -> Accelerator Common Registers & Polling: PASS\n");

    /* 2. AES-128-CTR Specific Registers */
    const uint8_t aes_key[16] = {0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F};
    const uint8_t aes_iv[12]  = {0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,0xF8,0xF9,0xFA,0xFB};
    axi_accel_set_aes_key_iv(ACCEL_BASE_AES_CTR, aes_key, aes_iv, 1U);

    mock_reg_entry_t *k0 = mock_find_entry(ACCEL_BASE_AES_CTR + AES_REG_KEY_0);
    assert(k0 != NULL && k0->val == 0x03020100U);
    mock_reg_entry_t *iv0 = mock_find_entry(ACCEL_BASE_AES_CTR + AES_REG_IV_0);
    assert(iv0 != NULL && iv0->val == 0xF3F2F1F0U);
    mock_reg_entry_t *cnt = mock_find_entry(ACCEL_BASE_AES_CTR + AES_REG_COUNTER_INIT);
    assert(cnt != NULL && cnt->val == 1U);
    printf("  -> AES-128-CTR Key & IV Register Configuration: PASS\n");

    /* 3. ChaCha20 Specific Registers */
    uint8_t chacha_key[32];
    for (int i = 0; i < 32; i++) chacha_key[i] = (uint8_t)i;
    uint8_t chacha_nonce[12] = {0,0,0,9,0,0,0,0x4A,0,0,0,0};
    axi_accel_set_chacha_key_nonce(ACCEL_BASE_CHACHA20, chacha_key, chacha_nonce, 1U);

    mock_reg_entry_t *ck0 = mock_find_entry(ACCEL_BASE_CHACHA20 + CHACHA_REG_KEY_0);
    assert(ck0 != NULL && ck0->val == 0x03020100U);
    mock_reg_entry_t *cn0 = mock_find_entry(ACCEL_BASE_CHACHA20 + CHACHA_REG_NONCE_0);
    assert(cn0 != NULL && cn0->val == 0x09000000U);
    mock_reg_entry_t *bcnt = mock_find_entry(ACCEL_BASE_CHACHA20 + CHACHA_REG_BLOCK_CNT);
    assert(bcnt != NULL && bcnt->val == 1U);
    printf("  -> ChaCha20 Key, Nonce & Block Counter Configuration: PASS\n");
}

static void test_axi_spi_receiver(void) {
    printf("[TEST] Testing AXI Quad SPI Receiver Driver & Frame Parser...\n");
    mock_reset_all();

    /* 1. SPI Init */
    int rc = axi_spi_init(AXI_SPI_DEFAULT_BASEADDR);
    assert(rc == 0);
    printf("  -> AXI Quad SPI Slave Mode Init: PASS\n");

    /* 2. CRC-16-CCITT Verification against standard vector "123456789" -> 0x29B1 */
    const uint8_t test_vec[] = "123456789";
    uint16_t crc = axi_spi_crc16(test_vec, 9, 0xFFFFU);
    assert(crc == 0x29B1U);
    printf("  -> CRC-16-CCITT Standard Vector (0x29B1): PASS\n");

    /* 3. Build synthetic SPI frame conforming to INTERFACES.md */
    uint8_t frame_buf[32];
    frame_buf[0] = SPI_PREAMBLE_BYTE0;
    frame_buf[1] = SPI_PREAMBLE_BYTE1;
    frame_buf[2] = SPI_TYPE_TELEMETRY;
    frame_buf[3] = SPI_FLAG_COMPRESS_EN | SPI_FLAG_COMP_ALGO_SEL; /* LZ4 */
    frame_buf[4] = 0; frame_buf[5] = 0; frame_buf[6] = 0; frame_buf[7] = 4; /* 4 B */
    frame_buf[8] = 0x11; frame_buf[9] = 0x22; frame_buf[10] = 0x33; frame_buf[11] = 0x44;

    uint16_t computed_crc = axi_spi_crc16(frame_buf, 12, 0xFFFFU);
    frame_buf[12] = (uint8_t)((computed_crc >> 8) & 0xFFU);
    frame_buf[13] = (uint8_t)(computed_crc & 0xFFU);

    /* 4. Test Packet Parsing */
    uint8_t payload_out[16];
    spi_frame_t frame_out;
    rc = axi_spi_parse_packet(frame_buf, 14, payload_out, sizeof(payload_out), &frame_out);
    assert(rc == 0);
    assert(frame_out.crc_valid == true);
    assert(frame_out.header.payload_type == SPI_TYPE_TELEMETRY);
    assert(frame_out.header.payload_len == 4);
    assert(payload_out[0] == 0x11 && payload_out[3] == 0x44);
    printf("  -> SPI Packet Parser & CRC Validation: PASS\n");

    /* 5. Test Corrupted CRC Rejection */
    frame_buf[13] ^= 0xFF; /* Corrupt CRC */
    rc = axi_spi_parse_packet(frame_buf, 14, payload_out, sizeof(payload_out), &frame_out);
    assert(rc == -3); /* CRC mismatch */
    printf("  -> Corrupted CRC Rejection: PASS\n");

    /* 6. Test Stream Drain from Mock FIFO */
    frame_buf[13] ^= 0xFF; /* Restore CRC */
    mock_spi_push_rx(frame_buf, 14);

    rc = axi_spi_drain_frame(AXI_SPI_DEFAULT_BASEADDR, payload_out, sizeof(payload_out), &frame_out, 100);
    assert(rc == 0);
    assert(frame_out.crc_valid == true);
    assert(frame_out.header.payload_len == 4);
    printf("  -> SPI Hardware FIFO Drain & Auto-Framing: PASS\n");
}

static void test_pipeline_mgr(void) {
    printf("[TEST] Testing Pipeline Manager Orchestrator...\n");
    mock_reset_all();

    /* 1. Self-test routine */
    int rc = pipeline_mgr_self_test();
    assert(rc == 0);
    printf("  -> Pipeline Manager Self-Test: PASS\n");

    /* 2. Pipeline Init */
    rc = pipeline_mgr_init();
    assert(rc == 0);
    printf("  -> Pipeline Manager Hardware Arming: PASS\n");

    /* 3. Scenario 1 (PS Pure) Verification through Pipeline Manager */
    uint8_t test_data[64];
    memset(test_data, 0xAA, sizeof(test_data));
    uint8_t out_buf[128];
    pipeline_metrics_t metrics;

    rc = pipeline_mgr_process(SCENARIO_PS_PURE, ALGO_RLE, test_data, sizeof(test_data),
                              out_buf, sizeof(out_buf), &metrics);
    assert(rc == 0);
    assert(metrics.success == true);
    assert(metrics.output_length == 2); /* 64 0xAA -> [64, 0xAA] */
    printf("  -> Pipeline Scenario 1 (PS Pure RLE): PASS\n");

    /* 4. Scenario 2 (PL Acceleration) Verification through Pipeline Manager */
    rc = pipeline_mgr_process(SCENARIO_PL_PURE, ALGO_RLE, test_data, sizeof(test_data),
                              out_buf, sizeof(out_buf), &metrics);
    assert(rc == 0);
    assert(metrics.success == true);
    assert(metrics.output_length == 32);
    assert(metrics.hw_cycles == 64);
    printf("  -> Pipeline Scenario 2 (PL Accelerated RLE via DMA): PASS\n");
}

int main(void) {
    printf("\n");
    printf("================================================================\n");
    printf("  AXI Communication Drivers Unit Verification Test Suite        \n");
    printf("  Target: Digilent Cora Z7-10 (Xilinx Zynq-7010 SoC)            \n");
    printf("================================================================\n");

    test_axi_dma_driver();
    test_axi_accel_ctrl();
    test_axi_spi_receiver();
    test_pipeline_mgr();

    printf("================================================================\n");
    printf("  ALL AXI COMMUNICATION DRIVER TESTS PASSED 100%% (PASS)        \n");
    printf("================================================================\n\n");
    return 0;
}
