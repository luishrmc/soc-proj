/**
 * @file axi_dma_driver.c
 * @brief Simple DMA Mode Driver Implementation for Xilinx AXI DMA v7.1.
 */

#include "axi_dma_driver.h"
#include "axi_io.h"

int axi_dma_init(uintptr_t base_addr) {
    /* 1. Assert soft reset on both channels */
    AXI_IO_WRITE32(base_addr + DMA_REG_MM2S_DMACR, DMA_CR_RESET_MASK);
    AXI_IO_WRITE32(base_addr + DMA_REG_S2MM_DMACR, DMA_CR_RESET_MASK);

    /* 2. Wait for reset self-clearing (typically ~10 cycles) */
    uint32_t timeout = 10000U;
    while (timeout > 0U) {
        uint32_t mm2s_cr = AXI_IO_READ32(base_addr + DMA_REG_MM2S_DMACR);
        uint32_t s2mm_cr = AXI_IO_READ32(base_addr + DMA_REG_S2MM_DMACR);
        if (((mm2s_cr & DMA_CR_RESET_MASK) == 0U) &&
            ((s2mm_cr & DMA_CR_RESET_MASK) == 0U)) {
            break;
        }
        timeout--;
    }

    if (timeout == 0U) {
        return -1; /* Reset timeout */
    }

    /* 3. Clear any residual interrupt status flags (W1C) */
    AXI_IO_WRITE32(base_addr + DMA_REG_MM2S_DMASR, DMA_SR_IOC_IRQ_MASK | DMA_SR_ERR_IRQ_MASK);
    AXI_IO_WRITE32(base_addr + DMA_REG_S2MM_DMASR, DMA_SR_IOC_IRQ_MASK | DMA_SR_ERR_IRQ_MASK);

    return 0;
}

int axi_dma_start_mm2s(uintptr_t base_addr,
                       uintptr_t src_phys_addr,
                       uint32_t length_bytes) {
    if (length_bytes == 0U) {
        return -1;
    }

    /* 1. Flush source memory buffer to guarantee DDR coherency */
    AXI_DCACHE_FLUSH(src_phys_addr, length_bytes);

    /* 2. Enable Run/Stop bit in control register */
    uint32_t cr = AXI_IO_READ32(base_addr + DMA_REG_MM2S_DMACR);
    cr |= DMA_CR_RS_MASK;
    AXI_IO_WRITE32(base_addr + DMA_REG_MM2S_DMACR, cr);

    /* 3. Program 32-bit source address */
    AXI_IO_WRITE32(base_addr + DMA_REG_MM2S_SA, (uint32_t)src_phys_addr);
    AXI_IO_WRITE32(base_addr + DMA_REG_MM2S_SA_MSB, 0U);

    /* 4. Writing transfer length triggers the MM2S pipeline */
    AXI_IO_WRITE32(base_addr + DMA_REG_MM2S_LENGTH, length_bytes);

    return 0;
}

int axi_dma_start_s2mm(uintptr_t base_addr,
                       uintptr_t dst_phys_addr,
                       uint32_t length_bytes) {
    if (length_bytes == 0U) {
        return -1;
    }

    /* 1. Invalidate destination memory buffer before DMA write */
    AXI_DCACHE_INVAL(dst_phys_addr, length_bytes);

    /* 2. Enable Run/Stop bit in control register */
    uint32_t cr = AXI_IO_READ32(base_addr + DMA_REG_S2MM_DMACR);
    cr |= DMA_CR_RS_MASK;
    AXI_IO_WRITE32(base_addr + DMA_REG_S2MM_DMACR, cr);

    /* 3. Program 32-bit destination address */
    AXI_IO_WRITE32(base_addr + DMA_REG_S2MM_DA, (uint32_t)dst_phys_addr);
    AXI_IO_WRITE32(base_addr + DMA_REG_S2MM_DA_MSB, 0U);

    /* 4. Writing transfer length triggers the S2MM pipeline */
    AXI_IO_WRITE32(base_addr + DMA_REG_S2MM_LENGTH, length_bytes);

    return 0;
}

int axi_dma_wait_mm2s(uintptr_t base_addr, uint32_t max_poll_cycles) {
    for (uint32_t i = 0; i < max_poll_cycles; i++) {
        uint32_t sr = AXI_IO_READ32(base_addr + DMA_REG_MM2S_DMASR);

        if ((sr & DMA_SR_ERR_ALL_MASK) != 0U) {
            return -2; /* DMA bus error */
        }

        if ((sr & DMA_SR_IDLE_MASK) != 0U) {
            /* Clear IOC flag */
            AXI_IO_WRITE32(base_addr + DMA_REG_MM2S_DMASR, DMA_SR_IOC_IRQ_MASK);
            return 0; /* Completed */
        }
    }
    return -1; /* Timeout */
}

int axi_dma_wait_s2mm(uintptr_t base_addr,
                      uintptr_t dst_phys_addr,
                      uint32_t length_bytes,
                      uint32_t max_poll_cycles) {
    for (uint32_t i = 0; i < max_poll_cycles; i++) {
        uint32_t sr = AXI_IO_READ32(base_addr + DMA_REG_S2MM_DMASR);

        if ((sr & DMA_SR_ERR_ALL_MASK) != 0U) {
            return -2; /* DMA bus error */
        }

        if ((sr & DMA_SR_IDLE_MASK) != 0U) {
            /* Clear IOC flag */
            AXI_IO_WRITE32(base_addr + DMA_REG_S2MM_DMASR, DMA_SR_IOC_IRQ_MASK);
            /* Perform post-transfer cache invalidation for CPU view */
            AXI_DCACHE_INVAL(dst_phys_addr, length_bytes);
            return 0; /* Completed */
        }
    }
    return -1; /* Timeout */
}

int axi_dma_transfer_sync(uintptr_t base_addr,
                          uintptr_t src_phys_addr,
                          uint32_t src_len,
                          uintptr_t dst_phys_addr,
                          uint32_t dst_max_len,
                          uint32_t max_poll_cycles) {
    /* 1. Arm S2MM receiver first so incoming stream is immediately buffered */
    int rc = axi_dma_start_s2mm(base_addr, dst_phys_addr, dst_max_len);
    if (rc != 0) return rc;

    /* 2. Start MM2S transmitter */
    rc = axi_dma_start_mm2s(base_addr, src_phys_addr, src_len);
    if (rc != 0) return rc;

    /* 3. Wait for MM2S transmit completion */
    rc = axi_dma_wait_mm2s(base_addr, max_poll_cycles);
    if (rc != 0) return rc;

    /* 4. Wait for S2MM receive completion */
    rc = axi_dma_wait_s2mm(base_addr, dst_phys_addr, dst_max_len, max_poll_cycles);
    return rc;
}

uint32_t axi_dma_get_status(uintptr_t base_addr, bool is_s2mm) {
    uint32_t offset = is_s2mm ? DMA_REG_S2MM_DMASR : DMA_REG_MM2S_DMASR;
    return AXI_IO_READ32(base_addr + offset);
}
