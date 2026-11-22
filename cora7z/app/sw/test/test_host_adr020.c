/**
 * @file test_host_adr020.c
 * @brief Host-Executable C11 Verification & Behavioral Hardware Mock Suite for ADR-020.
 *
 * Compiles natively with gcc (-std=c11 -Wall -Wextra -Werror) against bare-metal
 * SW sources using host_mock_read32/host_mock_write32 to statically validate:
 *   1. Standard test_sw_pipeline_run_all() & test_sw_pipeline_benchmark_sweep()
 *   2. All 30 Embedded Dataset frames (10 Quiescent, 10 Dynamic, 10 Chaotic @ 1024 B)
 *      across Cases 1..4 with Space Savings % ordering and 1154 B expansion bounds
 *   3. Wire-level 1035 B TelemetryFrame -> axi_spi_read_frame() -> axi_spi_stage_ack()
 *      CRC-16-CCITT & framing fidelity matching esp32/main/spi_injector_master.c
 */

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "comms/axi_spi_receiver.h"
#include "comms/spi_frame.h"
#include "compression/lzss_sw.h"
#include "crypto/aes_ctr_sw.h"
#include "pipeline/pipeline_mgr.h"
#include "utils/axi_io.h"
#include "utils/telemetry_dataset.h"
#include "utils/test_sw_pipeline.h"

/* ========================================================================= */
/* Behavioral Hardware Model for Dual-Port BRAM, CSRs, and AXI Quad SPI      */
/* ========================================================================= */

static uint8_t s_lzss_bram_in[ACCEL_BRAM_CAPACITY_BYTES];
static uint8_t s_lzss_bram_out[ACCEL_BRAM_CAPACITY_BYTES];
static uint32_t s_lzss_src_len = 0U;
static uint32_t s_lzss_dst_len = 0U;
static uint32_t s_lzss_cycles = 0U;
static uint32_t s_lzss_status = 0U;
static uint32_t s_lzss_poll_delay = 0U;

static uint8_t s_aes_bram_in[ACCEL_BRAM_CAPACITY_BYTES];
static uint8_t s_aes_bram_out[ACCEL_BRAM_CAPACITY_BYTES];
static uint32_t s_aes_src_len = 0U;
static uint32_t s_aes_cycles = 0U;
static uint32_t s_aes_status = 0U;
static uint32_t s_aes_poll_delay = 0U;
static uint32_t s_aes_key[4];
static uint32_t s_aes_iv[4];

#define MOCK_SPI_FIFO_CAP 4096U
static uint8_t s_spi_rx_fifo[MOCK_SPI_FIFO_CAP];
static size_t s_spi_rx_head = 0U;
static size_t s_spi_rx_tail = 0U;
static uint8_t s_spi_tx_fifo[256];
static size_t s_spi_tx_len = 0U;

static void mock_spi_reset_rx(void) {
    s_spi_rx_head = 0U;
    s_spi_rx_tail = 0U;
}

static void mock_spi_reset_tx(void) {
    s_spi_tx_len = 0U;
}

static void mock_spi_push_rx_bytes(const uint8_t *buf, size_t len) {
    for (size_t i = 0; i < len; i++) {
        assert(s_spi_rx_tail < MOCK_SPI_FIFO_CAP);
        s_spi_rx_fifo[s_spi_rx_tail++] = buf[i];
    }
}

/* Faithful model of lzss_accel.vhdl (window=256, lookahead=16, min_match=3) */
static size_t ref_lzss_hw_compress(const uint8_t *src, size_t src_len, uint8_t *dst) {
    dst[0] = (uint8_t)((src_len >> 8) & 0xFFU);
    dst[1] = (uint8_t)(src_len & 0xFFU);
    size_t out_idx = 2U;
    size_t in_idx = 0U;

    while (in_idx < src_len) {
        size_t flag_idx = out_idx++;
        uint8_t flag_mask = 0U;

        for (int bit = 0; bit < 8 && in_idx < src_len; bit++) {
            size_t la_len = src_len - in_idx;
            if (la_len > 16U) {
                la_len = 16U;
            }
            size_t best_len = 0U;
            size_t best_dist = 0U;
            if (la_len >= 3U) {
                size_t win_start = (in_idx > 256U) ? (in_idx - 256U) : 0U;
                for (size_t cand = win_start; cand < in_idx; cand++) {
                    if (src[cand] != src[in_idx]) {
                        continue;
                    }
                    size_t mlen = 1U;
                    while (mlen < la_len && src[cand + mlen] == src[in_idx + mlen]) {
                        mlen++;
                    }
                    if (mlen >= 3U && mlen > best_len) {
                        best_len = mlen;
                        best_dist = in_idx - cand;
                        if (best_len == la_len) {
                            break;
                        }
                    }
                }
            }
            if (best_len >= 3U) {
                flag_mask |= (uint8_t)(1U << bit);
                dst[out_idx++] = (uint8_t)((best_dist - 1U) & 0xFFU);
                dst[out_idx++] = (uint8_t)((best_len - 3U) & 0xFFU);
                in_idx += best_len;
            } else {
                dst[out_idx++] = src[in_idx++];
            }
        }
        dst[flag_idx] = flag_mask;
    }
    return out_idx;
}

static void write_be32(uint8_t *dst, uint32_t v) {
    dst[0] = (uint8_t)((v >> 24) & 0xFFU);
    dst[1] = (uint8_t)((v >> 16) & 0xFFU);
    dst[2] = (uint8_t)((v >> 8) & 0xFFU);
    dst[3] = (uint8_t)(v & 0xFFU);
}

static uint32_t bram_read_le32(const uint8_t *mem, size_t offset) {
    return ((uint32_t)mem[offset + 0U])        |
           (((uint32_t)mem[offset + 1U]) << 8)  |
           (((uint32_t)mem[offset + 2U]) << 16) |
           (((uint32_t)mem[offset + 3U]) << 24);
}

static void bram_write_le32(uint8_t *mem, size_t offset, uint32_t val) {
    mem[offset + 0U] = (uint8_t)(val & 0xFFU);
    mem[offset + 1U] = (uint8_t)((val >> 8) & 0xFFU);
    mem[offset + 2U] = (uint8_t)((val >> 16) & 0xFFU);
    mem[offset + 3U] = (uint8_t)((val >> 24) & 0xFFU);
}

uint32_t host_mock_read32(uintptr_t addr) {
    if (addr >= LZSS_BRAM_IN_BASEADDR && addr < LZSS_BRAM_IN_BASEADDR + ACCEL_BRAM_CAPACITY_BYTES) {
        return bram_read_le32(s_lzss_bram_in, (size_t)(addr - LZSS_BRAM_IN_BASEADDR));
    }
    if (addr >= LZSS_BRAM_OUT_BASEADDR && addr < LZSS_BRAM_OUT_BASEADDR + ACCEL_BRAM_CAPACITY_BYTES) {
        return bram_read_le32(s_lzss_bram_out, (size_t)(addr - LZSS_BRAM_OUT_BASEADDR));
    }
    if (addr >= AES_BRAM_IN_BASEADDR && addr < AES_BRAM_IN_BASEADDR + ACCEL_BRAM_CAPACITY_BYTES) {
        return bram_read_le32(s_aes_bram_in, (size_t)(addr - AES_BRAM_IN_BASEADDR));
    }
    if (addr >= AES_BRAM_OUT_BASEADDR && addr < AES_BRAM_OUT_BASEADDR + ACCEL_BRAM_CAPACITY_BYTES) {
        return bram_read_le32(s_aes_bram_out, (size_t)(addr - AES_BRAM_OUT_BASEADDR));
    }
    if (addr >= LZSS_CSR_BASEADDR && addr < LZSS_CSR_BASEADDR + 0x100U) {
        uintptr_t off = addr - LZSS_CSR_BASEADDR;
        if (off == ACCEL_REG_STATUS) {
            if (s_lzss_poll_delay > 0U) {
                s_lzss_poll_delay--;
                return ACCEL_STATUS_BUSY;
            }
            return s_lzss_status;
        }
        if (off == ACCEL_REG_INPUT_LEN) return s_lzss_src_len;
        if (off == ACCEL_REG_OUTPUT_LEN) return s_lzss_dst_len;
        if (off == ACCEL_REG_CYCLES) return s_lzss_cycles;
        return 0U;
    }
    if (addr >= AES_CSR_BASEADDR && addr < AES_CSR_BASEADDR + 0x100U) {
        uintptr_t off = addr - AES_CSR_BASEADDR;
        if (off == ACCEL_REG_STATUS) {
            if (s_aes_poll_delay > 0U) {
                s_aes_poll_delay--;
                return ACCEL_STATUS_BUSY;
            }
            return s_aes_status;
        }
        if (off == ACCEL_REG_INPUT_LEN) return s_aes_src_len;
        if (off == ACCEL_REG_CYCLES) return s_aes_cycles;
        return 0U;
    }
    if (addr >= AXI_SPI_DEFAULT_BASEADDR && addr < AXI_SPI_DEFAULT_BASEADDR + 0x100U) {
        uintptr_t off = addr - AXI_SPI_DEFAULT_BASEADDR;
        if (off == SPI_REG_SPISR) {
            return (s_spi_rx_head >= s_spi_rx_tail) ? SPI_SR_RX_EMPTY_MASK : 0U;
        }
        if (off == SPI_REG_RX_FIFO_OCY) {
            return (s_spi_rx_tail > s_spi_rx_head) ? (uint32_t)(s_spi_rx_tail - s_spi_rx_head - 1U) : 0U;
        }
        if (off == SPI_REG_DRR) {
            if (s_spi_rx_head < s_spi_rx_tail) {
                return (uint32_t)s_spi_rx_fifo[s_spi_rx_head++];
            }
            return 0U;
        }
        return 0U;
    }
    return 0U;
}

void host_mock_write32(uintptr_t addr, uint32_t val) {
    if (addr >= LZSS_BRAM_IN_BASEADDR && addr < LZSS_BRAM_IN_BASEADDR + ACCEL_BRAM_CAPACITY_BYTES) {
        bram_write_le32(s_lzss_bram_in, (size_t)(addr - LZSS_BRAM_IN_BASEADDR), val);
        return;
    }
    if (addr >= LZSS_BRAM_OUT_BASEADDR && addr < LZSS_BRAM_OUT_BASEADDR + ACCEL_BRAM_CAPACITY_BYTES) {
        bram_write_le32(s_lzss_bram_out, (size_t)(addr - LZSS_BRAM_OUT_BASEADDR), val);
        return;
    }
    if (addr >= AES_BRAM_IN_BASEADDR && addr < AES_BRAM_IN_BASEADDR + ACCEL_BRAM_CAPACITY_BYTES) {
        bram_write_le32(s_aes_bram_in, (size_t)(addr - AES_BRAM_IN_BASEADDR), val);
        return;
    }
    if (addr >= AES_BRAM_OUT_BASEADDR && addr < AES_BRAM_OUT_BASEADDR + ACCEL_BRAM_CAPACITY_BYTES) {
        bram_write_le32(s_aes_bram_out, (size_t)(addr - AES_BRAM_OUT_BASEADDR), val);
        return;
    }
    if (addr >= LZSS_CSR_BASEADDR && addr < LZSS_CSR_BASEADDR + 0x100U) {
        uintptr_t off = addr - LZSS_CSR_BASEADDR;
        if (off == ACCEL_REG_INPUT_LEN) {
            s_lzss_src_len = val;
        } else if (off == ACCEL_REG_CTRL) {
            if ((val & ACCEL_CTRL_RESET) != 0U) {
                s_lzss_status = 0U;
                s_lzss_dst_len = 0U;
                s_lzss_cycles = 0U;
            }
            if ((val & ACCEL_CTRL_START) != 0U) {
                s_lzss_dst_len = (uint32_t)ref_lzss_hw_compress(s_lzss_bram_in, (size_t)s_lzss_src_len, s_lzss_bram_out);
                s_lzss_cycles = s_lzss_src_len * 100U;
                s_lzss_poll_delay = 1U;
                s_lzss_status = ACCEL_STATUS_DONE;
            }
        }
        return;
    }
    if (addr >= AES_CSR_BASEADDR && addr < AES_CSR_BASEADDR + 0x100U) {
        uintptr_t off = addr - AES_CSR_BASEADDR;
        if (off == ACCEL_REG_INPUT_LEN) s_aes_src_len = val;
        else if (off == AES_REG_KEY0) s_aes_key[0] = val;
        else if (off == AES_REG_KEY1) s_aes_key[1] = val;
        else if (off == AES_REG_KEY2) s_aes_key[2] = val;
        else if (off == AES_REG_KEY3) s_aes_key[3] = val;
        else if (off == AES_REG_IV0) s_aes_iv[0] = val;
        else if (off == AES_REG_IV1) s_aes_iv[1] = val;
        else if (off == AES_REG_IV2) s_aes_iv[2] = val;
        else if (off == AES_REG_CTR_INIT) s_aes_iv[3] = val;
        else if (off == ACCEL_REG_CTRL) {
            if ((val & ACCEL_CTRL_RESET) != 0U) {
                s_aes_status = 0U;
                s_aes_cycles = 0U;
            }
            if ((val & ACCEL_CTRL_START) != 0U) {
                uint8_t key[16];
                uint8_t iv[16];
                for (int i = 0; i < 4; i++) {
                    write_be32(&key[i * 4], s_aes_key[i]);
                    write_be32(&iv[i * 4], s_aes_iv[i]);
                }
                assert(aes_128_ctr_crypt(key, iv, s_aes_bram_in, s_aes_bram_out, (size_t)s_aes_src_len) == 0);
                s_aes_cycles = ((s_aes_src_len + 15U) / 16U) * 18U;
                s_aes_poll_delay = 1U;
                s_aes_status = ACCEL_STATUS_DONE;
            }
        }
        return;
    }
    if (addr >= AXI_SPI_DEFAULT_BASEADDR && addr < AXI_SPI_DEFAULT_BASEADDR + 0x100U) {
        uintptr_t off = addr - AXI_SPI_DEFAULT_BASEADDR;
        if (off == SPI_REG_SRR && val == 0x0000000AU) {
            mock_spi_reset_rx();
            mock_spi_reset_tx();
        } else if (off == SPI_REG_SPICR) {
            if ((val & SPI_CR_TXFIFO_RST_MASK) != 0U) mock_spi_reset_tx();
            if ((val & SPI_CR_RXFIFO_RST_MASK) != 0U) mock_spi_reset_rx();
        } else if (off == SPI_REG_DTR) {
            assert(s_spi_tx_len < sizeof(s_spi_tx_fifo));
            s_spi_tx_fifo[s_spi_tx_len++] = (uint8_t)(val & 0xFFU);
        }
    }
}

/* ========================================================================= */
/* Additional ADR-020 Validation Routines                                    */
/* ========================================================================= */

static int verify_full_30_frame_dataset(void) {
    printf("[HOST TEST] Exhaustive 30-frame ADR-020 dataset validation across 4 scenarios...\n");

    float sum_cr[3] = {0.0f, 0.0f, 0.0f};
    uint32_t max_comp_len = 0U;

    for (size_t i = 0; i < TELEMETRY_DATASET_FRAME_COUNT; i++) {
        const telemetry_dataset_entry_t *entry = &g_telemetry_dataset[i];
        pipeline_4scen_result_t res;
        memset(&res, 0, sizeof(res));

        int rc = pipeline_verify_profile_scenarios(
            telemetry_profile_name(entry->profile),
            (uint16_t)(i + 1U),
            entry->payload,
            TELEMETRY_PAYLOAD_SIZE,
            true,
            &res
        );
        if (rc != PIPELINE_SUCCESS || !res.pl_tested) {
            fprintf(stderr, "FAIL: frame %u verification error (rc=%d, pl=%d)\n",
                    (unsigned int)i, rc, (int)res.pl_tested);
            return 1;
        }

        if (res.scen[1].comp_len > max_comp_len) {
            max_comp_len = res.scen[1].comp_len;
        }
        sum_cr[(size_t)entry->profile] += res.scen[1].compression_ratio * 100.0f;
    }

    float q_cr = sum_cr[TELEMETRY_PROFILE_QUIESCENT] / (float)TELEMETRY_FRAMES_PER_PROFILE;
    float d_cr = sum_cr[TELEMETRY_PROFILE_DYNAMIC] / (float)TELEMETRY_FRAMES_PER_PROFILE;
    float c_cr = sum_cr[TELEMETRY_PROFILE_CHAOTIC] / (float)TELEMETRY_FRAMES_PER_PROFILE;

    printf("  -> Mean Space Savings %% (HW LZSS): Quiescent=%.2f%%, Dynamic=%.2f%%, Chaotic=%.2f%% (max comp=%u B)\n",
           q_cr, d_cr, c_cr, (unsigned int)max_comp_len);

    assert(q_cr > 40.0f);
    assert(d_cr > 0.0f && d_cr < q_cr);
    assert(c_cr < 0.0f);
    assert(max_comp_len <= 1154U && max_comp_len <= ACCEL_BRAM_CAPACITY_BYTES);

    return 0;
}

static int verify_spi_wire_frame_contract(void) {
    printf("[HOST TEST] SPI 1035 B TelemetryFrame + 15 B ACK wire contract round-trip...\n");
    assert(TELEMETRY_FRAME_TOTAL_SIZE == 1035U);
    assert(axi_spi_init(AXI_SPI_DEFAULT_BASEADDR) == 0);

    static const size_t sample_idx[3] = {
        0U,
        TELEMETRY_FRAMES_PER_PROFILE,
        2U * TELEMETRY_FRAMES_PER_PROFILE
    };

    for (size_t k = 0; k < 3U; k++) {
        uint16_t seq = (uint16_t)(k + 1U);
        const telemetry_dataset_entry_t *entry = &g_telemetry_dataset[sample_idx[k]];

        /* Serialize wire frame identically to esp32/main/spi_injector_master.c */
        TelemetryFrame tx;
        tx.preamble = SPI_FRAME_PREAMBLE;
        tx.pkt_type = SPI_PKT_TYPE_TELEMETRY;
        tx.seq_id = htons(seq);
        tx.payload_len = htons((uint16_t)TELEMETRY_PAYLOAD_SIZE);
        tx.reserved_align = 0U;
        memcpy(tx.payload, entry->payload, TELEMETRY_PAYLOAD_SIZE);
        uint16_t crc = compute_crc16_ccitt((const uint8_t *)&tx, 8U + TELEMETRY_PAYLOAD_SIZE);
        tx.crc16 = htons(crc);
        tx.eof_delim = SPI_FRAME_EOF_DELIM;

        mock_spi_reset_rx();
        mock_spi_push_rx_bytes((const uint8_t *)&tx, sizeof(tx));

        TelemetryFrame rx;
        memset(&rx, 0, sizeof(rx));
        int rc = axi_spi_read_frame(AXI_SPI_DEFAULT_BASEADDR, &rx, 10000U);
        assert(rc == 0);
        assert(rx.preamble == SPI_FRAME_PREAMBLE);
        assert(rx.pkt_type == SPI_PKT_TYPE_TELEMETRY);
        assert(ntohs(rx.seq_id) == seq);
        assert(ntohs(rx.payload_len) == TELEMETRY_PAYLOAD_SIZE);
        assert(memcmp(rx.payload, entry->payload, TELEMETRY_PAYLOAD_SIZE) == 0);

        /* Verify staged 15-byte ACK frame */
        assert(axi_spi_stage_ack(AXI_SPI_DEFAULT_BASEADDR, seq, 0x00U) == 0);
        assert(s_spi_tx_len == 15U);
        assert(s_spi_tx_fifo[0] == SPI_FRAME_PREAMBLE);
        assert(s_spi_tx_fifo[1] == SPI_PKT_TYPE_ACK);
        assert(s_spi_tx_fifo[2] == (uint8_t)((seq >> 8) & 0xFFU));
        assert(s_spi_tx_fifo[3] == (uint8_t)(seq & 0xFFU));
        assert(s_spi_tx_fifo[14] == SPI_FRAME_EOF_DELIM);
        uint16_t ack_crc = compute_crc16_ccitt(s_spi_tx_fifo, 12U);
        assert(s_spi_tx_fifo[12] == (uint8_t)((ack_crc >> 8) & 0xFFU));
        assert(s_spi_tx_fifo[13] == (uint8_t)(ack_crc & 0xFFU));
    }

    /* Verify oversized payload_len returns distinct -4 length error */
    {
        uint8_t bad_hdr[8] = {
            SPI_FRAME_PREAMBLE, SPI_PKT_TYPE_TELEMETRY,
            0x00U, 0x63U, 0x04U, 0x01U, 0x00U, 0x00U /* payload_len = 1025 */
        };
        TelemetryFrame bad_rx;
        memset(&bad_rx, 0, sizeof(bad_rx));
        mock_spi_reset_rx();
        mock_spi_push_rx_bytes(bad_hdr, sizeof(bad_hdr));
        assert(axi_spi_read_frame(AXI_SPI_DEFAULT_BASEADDR, &bad_rx, 1000U) == -4);
    }

    printf("  -> All 3 profile wire frames (1035 B), ACKs (15 B), and -4 length guard verified.\n");
    return 0;
}

int main(void) {
    pipeline_set_pmu_overhead(28U);
    int fails = 0;
    fails += test_sw_pipeline_run_all();
    fails += test_sw_pipeline_benchmark_sweep();
    fails += verify_full_30_frame_dataset();
    fails += verify_spi_wire_frame_contract();

    if (fails != 0) {
        fprintf(stderr, "[HOST SUITE FAIL] failures=%d\n", fails);
        return 1;
    }
    printf("[HOST SUITE PASS] All ADR-020 host verification tests succeeded.\n");
    return 0;
}
