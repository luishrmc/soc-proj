/**
 * @file axi_spi_receiver.h
 * @brief High-Speed AXI Quad SPI v3.2 LogiCORE Slave Receiver Driver.
 *
 * Implements slave reception from the external ESP32 SPI data injector,
 * FIFO drain management, frame delimitation, and CRC-16-CCITT packet
 * verification per cora7z/app/hw/src/INTERFACES.md.
 */

#ifndef AXI_SPI_RECEIVER_H
#define AXI_SPI_RECEIVER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Default AXI Quad SPI Base Address from INTERFACES.md */
#define AXI_SPI_DEFAULT_BASEADDR 0x41E00000U

/* ========================================================================= */
/* AXI Quad SPI Register Offsets (Xilinx PG153 Table 2-4)                    */
/* ========================================================================= */
#define SPI_REG_SRR              0x40U  /* Software Reset Register (write 0xA to reset) */
#define SPI_REG_SPICR            0x60U  /* SPI Control Register */
#define SPI_REG_SPISR            0x64U  /* SPI Status Register */
#define SPI_REG_DTR              0x68U  /* Data Transmit Register */
#define SPI_REG_DRR              0x6CU  /* Data Receive Register */
#define SPI_REG_SPISSR           0x70U  /* Slave Select Register */
#define SPI_REG_TX_FIFO_OCY      0x74U  /* TX FIFO Occupancy */
#define SPI_REG_RX_FIFO_OCY      0x78U  /* RX FIFO Occupancy */
#define SPI_REG_DGIER            0x1CU  /* Device Global Interrupt Enable Register */
#define SPI_REG_IPISR            0x20U  /* IP Interrupt Status Register */
#define SPI_REG_IPIER            0x28U  /* IP Interrupt Enable Register */

/* ========================================================================= */
/* SPICR Register Bit Definitions                                            */
/* ========================================================================= */
#define SPI_CR_LOOP_MASK         (1U << 0)  /* Local loopback */
#define SPI_CR_SPE_MASK          (1U << 1)  /* SPI System Enable */
#define SPI_CR_MASTER_MASK       (1U << 2)  /* 1=Master, 0=Slave */
#define SPI_CR_CPOL_MASK         (1U << 3)  /* Clock Polarity */
#define SPI_CR_CPHA_MASK         (1U << 4)  /* Clock Phase */
#define SPI_CR_TXFIFO_RST_MASK   (1U << 5)  /* TX FIFO Reset */
#define SPI_CR_RXFIFO_RST_MASK   (1U << 6)  /* RX FIFO Reset */
#define SPI_CR_MANUAL_SS_MASK    (1U << 7)  /* Manual Slave Select */
#define SPI_CR_MASTER_INHIBIT    (1U << 8)  /* Master Transaction Inhibit */

/* ========================================================================= */
/* SPISR Register Bit Definitions                                            */
/* ========================================================================= */
#define SPI_SR_RX_EMPTY_MASK     (1U << 0)  /* RX FIFO Empty */
#define SPI_SR_RX_FULL_MASK      (1U << 1)  /* RX FIFO Full */
#define SPI_SR_TX_EMPTY_MASK     (1U << 2)  /* TX FIFO Empty */
#define SPI_SR_TX_FULL_MASK      (1U << 3)  /* TX FIFO Full */
#define SPI_SR_MODF_MASK         (1U << 4)  /* Mode Fault */

/* ========================================================================= */
/* SPI Packet Protocol Constants (INTERFACES.md Section 1.3)                 */
/* ========================================================================= */
#define SPI_PREAMBLE_BYTE0       0xAAU
#define SPI_PREAMBLE_BYTE1       0x55U

/* Payload Types */
#define SPI_TYPE_REDUNDANT       0x01U  /* Repetitive patterns (RLE/LZ4) */
#define SPI_TYPE_RANDOM          0x02U  /* High-entropy pseudo-random */
#define SPI_TYPE_TELEMETRY       0x03U  /* Structured sensor telemetry */

/* Header Flags */
#define SPI_FLAG_COMPRESS_EN     (1U << 0)  /* Bit 0: Enable compression */
#define SPI_FLAG_ENCRYPT_EN      (1U << 1)  /* Bit 1: Enable encryption */
#define SPI_FLAG_COMP_ALGO_SEL   (1U << 2)  /* Bit 2: 0=RLE, 1=LZ4 */
#define SPI_FLAG_CRYPTO_ALGO_SEL (1U << 3)  /* Bit 3: 0=AES-128-CTR, 1=ChaCha20 */

#define SPI_HEADER_SIZE          8U   /* Preamble (2) + Type (1) + Flags (1) + Length (4) */
#define SPI_TRAILER_SIZE         2U   /* CRC-16 (2) */

typedef struct {
    uint8_t  payload_type;
    uint8_t  flags;
    uint32_t payload_len;
} spi_header_t;

typedef struct {
    spi_header_t header;
    uint8_t      *payload;
    uint16_t     crc16_computed;
    uint16_t     crc16_received;
    bool         crc_valid;
} spi_frame_t;

/* ========================================================================= */
/* Driver Function Prototypes                                                */
/* ========================================================================= */

/**
 * @brief Initialize AXI Quad SPI IP in slave Mode 0 (CPOL=0, CPHA=0).
 * @param base_addr Base address of AXI Quad SPI core.
 * @return 0 on success, negative on error.
 */
int axi_spi_init(uintptr_t base_addr);

/**
 * @brief Check if the SPI RX FIFO currently has incoming bytes available.
 * @param base_addr AXI Quad SPI base address.
 * @return Number of unread bytes in RX FIFO.
 */
uint32_t axi_spi_rx_count(uintptr_t base_addr);

/**
 * @brief Read a single byte from the SPI RX FIFO.
 * @param base_addr AXI Quad SPI base address.
 * @param[out] byte_out Destination byte pointer.
 * @return 0 on success, -1 if FIFO is empty.
 */
int axi_spi_read_byte(uintptr_t base_addr, uint8_t *byte_out);

/**
 * @brief Write a single byte to the SPI TX FIFO (for response/loopback).
 * @param base_addr AXI Quad SPI base address.
 * @param byte_in Byte to transmit.
 * @return 0 on success, -1 if TX FIFO is full.
 */
int axi_spi_write_byte(uintptr_t base_addr, uint8_t byte_in);

/**
 * @brief Calculate CRC-16-CCITT checksum over a buffer.
 *
 * Polynomial: 0x1021 (x^16 + x^12 + x^5 + 1), Initial value: 0xFFFF.
 *
 * @param data Byte buffer.
 * @param len Buffer length in bytes.
 * @param init_crc Initial CRC accumulator (typically 0xFFFF).
 * @return Computed 16-bit CRC checksum.
 */
uint16_t axi_spi_crc16(const uint8_t *data, size_t len, uint16_t init_crc);

/**
 * @brief Parse and validate a raw serialized SPI packet buffer.
 *
 * Validates preamble (0xAA, 0x55), parses header fields, checks buffer
 * bounds, and calculates CRC-16-CCITT checksum.
 *
 * @param raw_buf Raw byte buffer containing serialized packet.
 * @param raw_len Total bytes in raw_buf.
 * @param[out] payload_out Destination buffer for extracted payload.
 * @param max_payload_len Capacity of payload_out buffer.
 * @param[out] frame_out Pointer to structured frame result.
 * @return 0 on success and valid CRC,
 *        -1 if packet length exceeds max_payload_len,
 *        -2 if preamble invalid,
 *        -3 if CRC check failed,
 *        -4 if buffer too small for header.
 */
int axi_spi_parse_packet(const uint8_t *raw_buf,
                         size_t raw_len,
                         uint8_t *payload_out,
                         size_t max_payload_len,
                         spi_frame_t *frame_out);

/**
 * @brief Drain a complete incoming SPI frame directly from the AXI Quad SPI FIFO.
 *
 * Polls the hardware FIFO with a timeout, aligns to preamble, extracts
 * length and payload, and performs CRC-16 validation.
 *
 * @param base_addr AXI Quad SPI base address.
 * @param[out] payload_buf Destination buffer for payload.
 * @param max_payload_len Buffer capacity.
 * @param[out] frame_out Structured packet metadata.
 * @param max_poll_cycles Timeout counter limit.
 * @return 0 on success and CRC verified, negative on error or timeout.
 */
int axi_spi_drain_frame(uintptr_t base_addr,
                        uint8_t *payload_buf,
                        size_t max_payload_len,
                        spi_frame_t *frame_out,
                        uint32_t max_poll_cycles);

#ifdef __cplusplus
}
#endif

#endif /* AXI_SPI_RECEIVER_H */
