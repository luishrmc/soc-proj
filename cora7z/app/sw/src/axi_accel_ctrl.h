/**
 * @file axi_accel_ctrl.h
 * @brief Unified AXI4-Lite Control Driver for PL Accelerator IP Cores.
 *
 * Controls RLE Engine (0x43C00000), LZ4 Engine (0x43C10000),
 * AES-128-CTR Coprocessor (0x43C20000), and ChaCha20 Coprocessor (0x43C30000).
 *
 * Fully adheres to cora7z/app/hw/src/INTERFACES.md register definitions
 * and Xilinx AXI4-Lite slave specifications.
 */

#ifndef AXI_ACCEL_CTRL_H
#define AXI_ACCEL_CTRL_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Accelerator Base Addresses (Synchronized with INTERFACES.md)              */
/* ========================================================================= */
#define ACCEL_BASE_RLE       0x43C00000U
#define ACCEL_BASE_LZ4       0x43C10000U
#define ACCEL_BASE_AES_CTR   0x43C20000U
#define ACCEL_BASE_CHACHA20  0x43C30000U
#define ACCEL_BASE_STREAM_MUX 0x43C40000U

/* Stream Multiplexer Route Selection */
#define ACCEL_MUX_ROUTE_AUTO     0U
#define ACCEL_MUX_ROUTE_RLE      1U
#define ACCEL_MUX_ROUTE_LZ4      2U
#define ACCEL_MUX_ROUTE_AES_CTR  3U
#define ACCEL_MUX_ROUTE_CHACHA   4U

/* ========================================================================= */
/* Standard Accelerator Common Register Offsets                              */
/* ========================================================================= */
#define ACCEL_REG_CONTROL     0x00U  /* R/W: Bit 0=START, Bit 1=RESET, Bit 2=IRQ_EN */
#define ACCEL_REG_STATUS      0x04U  /* RO:  Bit 0=BUSY,  Bit 1=DONE,  Bit 2=ERR */
#define ACCEL_REG_SRC_LEN     0x08U  /* R/W: Input length in bytes */
#define ACCEL_REG_DST_LEN     0x0CU  /* RO:  Output length in bytes */
#define ACCEL_REG_CYCLE_COUNT 0x10U  /* RO:  Active hardware latency clock cycles */

/* CONTROL Register Bit Masks */
#define ACCEL_CTRL_START_MASK      (1U << 0)
#define ACCEL_CTRL_RESET_MASK      (1U << 1)
#define ACCEL_CTRL_IRQ_EN_MASK     (1U << 2)

/* STATUS Register Bit Masks */
#define ACCEL_STAT_BUSY_MASK       (1U << 0)
#define ACCEL_STAT_DONE_MASK       (1U << 1)
#define ACCEL_STAT_ERR_MASK        (1U << 2)

/* ========================================================================= */
/* AES-128-CTR Specific Register Offsets (Base: 0x43C20000)                  */
/* ========================================================================= */
#define AES_REG_KEY_0         0x14U  /* R/W: Key bits [31:0] */
#define AES_REG_KEY_1         0x18U  /* R/W: Key bits [63:32] */
#define AES_REG_KEY_2         0x1CU  /* R/W: Key bits [95:64] */
#define AES_REG_KEY_3         0x20U  /* R/W: Key bits [127:96] */
#define AES_REG_IV_0          0x24U  /* R/W: IV / Nonce bits [31:0] */
#define AES_REG_IV_1          0x28U  /* R/W: IV / Nonce bits [63:32] */
#define AES_REG_IV_2          0x2CU  /* R/W: IV / Nonce bits [95:64] */
#define AES_REG_COUNTER_INIT  0x30U  /* R/W: Initial 32-bit counter value */

/* ========================================================================= */
/* ChaCha20 Specific Register Offsets (Base: 0x43C30000)                     */
/* ========================================================================= */
#define CHACHA_REG_KEY_0      0x14U  /* R/W: Key bits [31:0] */
#define CHACHA_REG_KEY_1      0x18U  /* R/W: Key bits [63:32] */
#define CHACHA_REG_KEY_2      0x1CU  /* R/W: Key bits [95:64] */
#define CHACHA_REG_KEY_3      0x20U  /* R/W: Key bits [127:96] */
#define CHACHA_REG_KEY_4      0x24U  /* R/W: Key bits [159:128] */
#define CHACHA_REG_KEY_5      0x28U  /* R/W: Key bits [191:160] */
#define CHACHA_REG_KEY_6      0x2CU  /* R/W: Key bits [223:192] */
#define CHACHA_REG_KEY_7      0x30U  /* R/W: Key bits [255:224] */
#define CHACHA_REG_NONCE_0    0x34U  /* R/W: Nonce bits [31:0] */
#define CHACHA_REG_NONCE_1    0x38U  /* R/W: Nonce bits [63:32] */
#define CHACHA_REG_NONCE_2    0x3CU  /* R/W: Nonce bits [95:64] */
#define CHACHA_REG_BLOCK_CNT  0x40U  /* R/W: Initial block counter (starts at 1) */

/* ========================================================================= */
/* Function Prototypes                                                       */
/* ========================================================================= */

/**
 * @brief Perform a synchronous soft reset on the target accelerator.
 * @param base_addr Accelerator AXI base address.
 */
void axi_accel_reset(uintptr_t base_addr);

/**
 * @brief Configure input length and initiate processing on the accelerator.
 * @param base_addr Accelerator AXI base address.
 * @param src_len_bytes Input data length in bytes.
 */
void axi_accel_start(uintptr_t base_addr, uint32_t src_len_bytes);

/**
 * @brief Read the raw 32-bit status register of an accelerator.
 * @param base_addr Accelerator AXI base address.
 * @return Value of ACCEL_REG_STATUS.
 */
uint32_t axi_accel_get_status(uintptr_t base_addr);

/**
 * @brief Check if the accelerator datapath is currently busy.
 * @param base_addr Accelerator AXI base address.
 * @return true if BUSY bit is set, false otherwise.
 */
bool axi_accel_is_busy(uintptr_t base_addr);

/**
 * @brief Check if the accelerator has completed its last processing run.
 * @param base_addr Accelerator AXI base address.
 * @return true if DONE bit is set, false otherwise.
 */
bool axi_accel_is_done(uintptr_t base_addr);

/**
 * @brief Check if the accelerator reported an error.
 * @param base_addr Accelerator AXI base address.
 * @return true if ERR bit is set, false otherwise.
 */
bool axi_accel_is_error(uintptr_t base_addr);

/**
 * @brief Poll accelerator until completion or timeout.
 * @param base_addr Accelerator AXI base address.
 * @param max_poll_cycles Maximum poll iterations before timeout.
 * @param[out] dst_len Processed output length in bytes (optional, may be NULL).
 * @param[out] hw_cycles Active hardware latency in clock cycles (optional, may be NULL).
 * @return 0 on success (DONE), -1 on timeout, -2 on hardware error (ERR).
 */
int axi_accel_poll_done(uintptr_t base_addr,
                        uint32_t max_poll_cycles,
                        uint32_t *dst_len,
                        uint32_t *hw_cycles);

/**
 * @brief Configure AES-128-CTR key, IV/nonce, and initial counter value.
 * @param base_addr AES accelerator base address (typically ACCEL_BASE_AES_CTR).
 * @param key 16-byte AES-128 key.
 * @param iv 12-byte initialization vector / nonce.
 * @param counter_init Initial counter value (typically 1).
 */
void axi_accel_set_aes_key_iv(uintptr_t base_addr,
                              const uint8_t key[16],
                              const uint8_t iv[12],
                              uint32_t counter_init);

/**
 * @brief Configure ChaCha20 key, nonce, and initial block counter.
 * @param base_addr ChaCha20 accelerator base address (typically ACCEL_BASE_CHACHA20).
 * @param key 32-byte 256-bit encryption key.
 * @param nonce 12-byte 96-bit nonce.
 * @param block_counter Initial block counter value (1 per RFC 8439).
 */
void axi_accel_set_chacha_key_nonce(uintptr_t base_addr,
                                    const uint8_t key[32],
                                    const uint8_t nonce[12],
                                    uint32_t block_counter);

/**
 * @brief Select active accelerator core route on the AXI4-Stream multiplexer.
 * @param route_id ACCEL_MUX_ROUTE_* (0=Auto by core BUSY, 1=RLE, 2=LZ4, 3=AES, 4=ChaCha20).
 */
void axi_accel_set_stream_route(uint32_t route_id);

#ifdef __cplusplus
}
#endif

#endif /* AXI_ACCEL_CTRL_H */
