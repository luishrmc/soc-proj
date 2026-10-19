/**
 * @file axi_accel_ctrl.c
 * @brief Unified AXI4-Lite Control Driver Implementation for PL Accelerators.
 */

#include "axi_accel_ctrl.h"
#include "axi_io.h"

static inline uint32_t pack_u32_le(const uint8_t *b) {
    return ((uint32_t)b[0]) |
           (((uint32_t)b[1]) << 8) |
           (((uint32_t)b[2]) << 16) |
           (((uint32_t)b[3]) << 24);
}

void axi_accel_reset(uintptr_t base_addr) {
    /* Assert soft reset */
    AXI_IO_WRITE32(base_addr + ACCEL_REG_CONTROL, ACCEL_CTRL_RESET_MASK);
    /* De-assert soft reset */
    AXI_IO_WRITE32(base_addr + ACCEL_REG_CONTROL, 0U);
}

void axi_accel_start(uintptr_t base_addr, uint32_t src_len_bytes) {
    /* Set source length in bytes */
    AXI_IO_WRITE32(base_addr + ACCEL_REG_SRC_LEN, src_len_bytes);
    /* Pulse START bit */
    AXI_IO_WRITE32(base_addr + ACCEL_REG_CONTROL, ACCEL_CTRL_START_MASK);
}

uint32_t axi_accel_get_status(uintptr_t base_addr) {
    return AXI_IO_READ32(base_addr + ACCEL_REG_STATUS);
}

bool axi_accel_is_busy(uintptr_t base_addr) {
    return (axi_accel_get_status(base_addr) & ACCEL_STAT_BUSY_MASK) != 0U;
}

bool axi_accel_is_done(uintptr_t base_addr) {
    return (axi_accel_get_status(base_addr) & ACCEL_STAT_DONE_MASK) != 0U;
}

bool axi_accel_is_error(uintptr_t base_addr) {
    return (axi_accel_get_status(base_addr) & ACCEL_STAT_ERR_MASK) != 0U;
}

int axi_accel_poll_done(uintptr_t base_addr,
                        uint32_t max_poll_cycles,
                        uint32_t *dst_len,
                        uint32_t *hw_cycles) {
    for (uint32_t i = 0; i < max_poll_cycles; i++) {
        uint32_t stat = axi_accel_get_status(base_addr);
        if ((stat & ACCEL_STAT_DONE_MASK) != 0U) {
            if (dst_len != NULL) {
                *dst_len = AXI_IO_READ32(base_addr + ACCEL_REG_DST_LEN);
            }
            if (hw_cycles != NULL) {
                *hw_cycles = AXI_IO_READ32(base_addr + ACCEL_REG_CYCLE_COUNT);
            }
            return 0; /* Success */
        }
        if ((stat & ACCEL_STAT_ERR_MASK) != 0U) {
            return -2; /* Hardware error flag set */
        }
    }
    return -1; /* Timeout */
}

void axi_accel_set_aes_key_iv(uintptr_t base_addr,
                              const uint8_t key[16],
                              const uint8_t iv[12],
                              uint32_t counter_init) {
    if (key != NULL) {
        AXI_IO_WRITE32(base_addr + AES_REG_KEY_0, pack_u32_le(&key[0]));
        AXI_IO_WRITE32(base_addr + AES_REG_KEY_1, pack_u32_le(&key[4]));
        AXI_IO_WRITE32(base_addr + AES_REG_KEY_2, pack_u32_le(&key[8]));
        AXI_IO_WRITE32(base_addr + AES_REG_KEY_3, pack_u32_le(&key[12]));
    }

    if (iv != NULL) {
        AXI_IO_WRITE32(base_addr + AES_REG_IV_0, pack_u32_le(&iv[0]));
        AXI_IO_WRITE32(base_addr + AES_REG_IV_1, pack_u32_le(&iv[4]));
        AXI_IO_WRITE32(base_addr + AES_REG_IV_2, pack_u32_le(&iv[8]));
    }

    AXI_IO_WRITE32(base_addr + AES_REG_COUNTER_INIT, counter_init);
}

void axi_accel_set_chacha_key_nonce(uintptr_t base_addr,
                                    const uint8_t key[32],
                                    const uint8_t nonce[12],
                                    uint32_t block_counter) {
    if (key != NULL) {
        for (int i = 0; i < 8; i++) {
            AXI_IO_WRITE32(base_addr + CHACHA_REG_KEY_0 + (uint32_t)(i * 4),
                           pack_u32_le(&key[i * 4]));
        }
    }

    if (nonce != NULL) {
        AXI_IO_WRITE32(base_addr + CHACHA_REG_NONCE_0, pack_u32_le(&nonce[0]));
        AXI_IO_WRITE32(base_addr + CHACHA_REG_NONCE_1, pack_u32_le(&nonce[4]));
        AXI_IO_WRITE32(base_addr + CHACHA_REG_NONCE_2, pack_u32_le(&nonce[8]));
    }

    AXI_IO_WRITE32(base_addr + CHACHA_REG_BLOCK_CNT, block_counter);
}

void axi_accel_set_stream_route(uint32_t route_id) {
    AXI_IO_WRITE32(ACCEL_BASE_STREAM_MUX, route_id);
}
