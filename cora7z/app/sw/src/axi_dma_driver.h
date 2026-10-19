/**
 * @file axi_dma_driver.h
 * @brief Simple DMA Mode Driver for Xilinx AXI DMA v7.1 LogiCORE IP.
 *
 * Implements high-throughput MM2S (Memory-Mapped to Stream) and S2MM
 * (Stream to Memory-Mapped) transfers complying with Xilinx PG021 specification,
 * including L1/L2 cache coherency flushes and invalidations for ARM Cortex-A9.
 */

#ifndef AXI_DMA_DRIVER_H
#define AXI_DMA_DRIVER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Default AXI DMA Base Address from INTERFACES.md */
#define AXI_DMA_DEFAULT_BASEADDR 0x40400000U

/* ========================================================================= */
/* AXI DMA Register Offsets (Xilinx PG021 Table 2-2)                         */
/* ========================================================================= */
/* MM2S (Transmit: Memory -> Stream) Registers */
#define DMA_REG_MM2S_DMACR       0x00U  /* MM2S DMA Control Register */
#define DMA_REG_MM2S_DMASR       0x04U  /* MM2S DMA Status Register */
#define DMA_REG_MM2S_SA          0x18U  /* MM2S Source Address */
#define DMA_REG_MM2S_SA_MSB      0x1CU  /* MM2S Source Address MSB (64-bit addr) */
#define DMA_REG_MM2S_LENGTH      0x28U  /* MM2S Transfer Length (Writing triggers xfer) */

/* S2MM (Receive: Stream -> Memory) Registers */
#define DMA_REG_S2MM_DMACR       0x30U  /* S2MM DMA Control Register */
#define DMA_REG_S2MM_DMASR       0x34U  /* S2MM DMA Status Register */
#define DMA_REG_S2MM_DA          0x48U  /* S2MM Destination Address */
#define DMA_REG_S2MM_DA_MSB      0x4CU  /* S2MM Destination Address MSB */
#define DMA_REG_S2MM_LENGTH      0x58U  /* S2MM Transfer Length (Writing triggers xfer) */

/* ========================================================================= */
/* DMACR / DMASR Bit Definitions                                             */
/* ========================================================================= */
/* DMACR Bits */
#define DMA_CR_RS_MASK           (1U << 0)   /* Run/Stop: 1=Run, 0=Stop */
#define DMA_CR_RESET_MASK        (1U << 2)   /* Soft Reset: 1=Reset core */
#define DMA_CR_KEYHOLE_MASK      (1U << 3)   /* Keyhole mode */
#define DMA_CR_CYCLIC_MASK       (1U << 4)   /* Cyclic BD mode */
#define DMA_CR_IOC_IRQEN_MASK    (1U << 12)  /* Interrupt on Complete Enable */
#define DMA_CR_DLY_IRQEN_MASK    (1U << 13)  /* Interrupt on Delay Enable */
#define DMA_CR_ERR_IRQEN_MASK    (1U << 14)  /* Interrupt on Error Enable */

/* DMASR Bits */
#define DMA_SR_HALTED_MASK       (1U << 0)   /* Channel Halted */
#define DMA_SR_IDLE_MASK         (1U << 1)   /* Channel Idle */
#define DMA_SR_SGINCLD_MASK      (1U << 3)   /* Scatter-Gather Included */
#define DMA_SR_ERR_INTERNAL_MASK (1U << 4)   /* DMA Internal Error */
#define DMA_SR_ERR_SLAVE_MASK    (1U << 5)   /* DMA Slave Error */
#define DMA_SR_ERR_DECODE_MASK   (1U << 6)   /* DMA Decode Error */
#define DMA_SR_SG_INT_ERR_MASK   (1U << 8)   /* SG Internal Error */
#define DMA_SR_SG_SLV_ERR_MASK   (1U << 9)   /* SG Slave Error */
#define DMA_SR_SG_DEC_ERR_MASK   (1U << 10)  /* SG Decode Error */
#define DMA_SR_IOC_IRQ_MASK      (1U << 12)  /* Interrupt on Complete Status (W1C) */
#define DMA_SR_DLY_IRQ_MASK      (1U << 13)  /* Interrupt on Delay Status (W1C) */
#define DMA_SR_ERR_IRQ_MASK      (1U << 14)  /* Interrupt on Error Status (W1C) */

#define DMA_SR_ERR_ALL_MASK      (DMA_SR_ERR_INTERNAL_MASK | \
                                  DMA_SR_ERR_SLAVE_MASK    | \
                                  DMA_SR_ERR_DECODE_MASK)

/* ========================================================================= */
/* Driver Function Prototypes                                                */
/* ========================================================================= */

/**
 * @brief Initialize and soft-reset both MM2S and S2MM channels of the AXI DMA.
 * @param base_addr Base address of AXI DMA IP (e.g. AXI_DMA_DEFAULT_BASEADDR).
 * @return 0 on success, -1 on timeout waiting for reset completion.
 */
int axi_dma_init(uintptr_t base_addr);

/**
 * @brief Initiate an asynchronous MM2S transfer (DDR3 -> Stream).
 *
 * Flushes the source buffer range from L1/L2 caches to DDR3 before
 * starting the DMA engine.
 *
 * @param base_addr AXI DMA base address.
 * @param src_phys_addr Physical/virtual address of source buffer.
 * @param length_bytes Number of bytes to transfer.
 * @return 0 on success, negative on error.
 */
int axi_dma_start_mm2s(uintptr_t base_addr,
                       uintptr_t src_phys_addr,
                       uint32_t length_bytes);

/**
 * @brief Initiate an asynchronous S2MM transfer (Stream -> DDR3).
 *
 * Invalidates the destination buffer range in L1/L2 caches to prepare
 * for fresh DMA writes from hardware.
 *
 * @param base_addr AXI DMA base address.
 * @param dst_phys_addr Physical/virtual address of destination buffer.
 * @param length_bytes Maximum number of bytes expected to receive.
 * @return 0 on success, negative on error.
 */
int axi_dma_start_s2mm(uintptr_t base_addr,
                       uintptr_t dst_phys_addr,
                       uint32_t length_bytes);

/**
 * @brief Wait for MM2S transfer to complete.
 * @param base_addr AXI DMA base address.
 * @param max_poll_cycles Timeout counter limit.
 * @return 0 on success (transfer completed and channel idle), -1 on timeout, -2 on error.
 */
int axi_dma_wait_mm2s(uintptr_t base_addr, uint32_t max_poll_cycles);

/**
 * @brief Wait for S2MM transfer to complete.
 *
 * Upon completion, executes a final cache invalidation across the destination
 * buffer to guarantee CPU read coherency.
 *
 * @param base_addr AXI DMA base address.
 * @param dst_phys_addr Destination buffer address for cache invalidation.
 * @param length_bytes Length of destination buffer.
 * @param max_poll_cycles Timeout counter limit.
 * @return 0 on success, -1 on timeout, -2 on error.
 */
int axi_dma_wait_s2mm(uintptr_t base_addr,
                      uintptr_t dst_phys_addr,
                      uint32_t length_bytes,
                      uint32_t max_poll_cycles);

/**
 * @brief Perform a complete synchronous round-trip transfer (MM2S + S2MM).
 *
 * Arms the S2MM channel first to guarantee no loss of incoming stream beats,
 * then triggers MM2S, and blocks until both channels finish.
 *
 * @param base_addr AXI DMA base address.
 * @param src_phys_addr Source data buffer in DDR3.
 * @param src_len Number of bytes to send.
 * @param dst_phys_addr Destination data buffer in DDR3.
 * @param dst_max_len Maximum bytes to receive.
 * @param max_poll_cycles Timeout counter limit per channel.
 * @return 0 on success, negative on error or timeout.
 */
int axi_dma_transfer_sync(uintptr_t base_addr,
                          uintptr_t src_phys_addr,
                          uint32_t src_len,
                          uintptr_t dst_phys_addr,
                          uint32_t dst_max_len,
                          uint32_t max_poll_cycles);

/**
 * @brief Query raw status register for MM2S or S2MM channel.
 * @param base_addr AXI DMA base address.
 * @param is_s2mm false for MM2S, true for S2MM.
 * @return 32-bit status register value.
 */
uint32_t axi_dma_get_status(uintptr_t base_addr, bool is_s2mm);

#ifdef __cplusplus
}
#endif

#endif /* AXI_DMA_DRIVER_H */
