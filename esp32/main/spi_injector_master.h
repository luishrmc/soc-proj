/**
 * @file spi_injector_master.h
 * @brief High-speed SPI Master driver for ESP32 synthetic data injection
 *        into Digilent Cora Z7-10 FPGA (Zynq-7010).
 *
 * Implements the frame contract and timing constraints documented in
 * cora7z/app/hw/src/INTERFACES.md (Section 1).
 */

#ifndef SPI_INJECTOR_MASTER_H
#define SPI_INJECTOR_MASTER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Default Hardware Pin Mapping (ESP32 -> Cora Z7-10 Dedicated SPI Header J7) */
/* ========================================================================= */
/* Cora Z7 FPGA Pins: SCLK=G20 (J7.3), MOSI=T10 (J7.4), MISO=V15 (J7.1), CS_N=F16 (J7.5) */
#define SPI_INJECTOR_DEFAULT_SCLK_PIN  18  /* VSPI SCK  -> Cora Z7 G20 */
#define SPI_INJECTOR_DEFAULT_MOSI_PIN  23  /* VSPI MOSI -> Cora Z7 T10 */
#define SPI_INJECTOR_DEFAULT_MISO_PIN  19  /* VSPI MISO -> Cora Z7 V15 */
#define SPI_INJECTOR_DEFAULT_CS_PIN    5   /* VSPI CS0  -> Cora Z7 F16 */

/* Standard Bus Frequencies */
#define SPI_SPEED_1MHZ                 1000000
#define SPI_SPEED_10MHZ                10000000
#define SPI_SPEED_25MHZ                25000000  /* Maximum validated bus speed */

/* ========================================================================= */
/* Protocol Frame Definitions (INTERFACES.md Section 1.3)                    */
/* ========================================================================= */
#define SPI_PREAMBLE_BYTE0             0xAAU
#define SPI_PREAMBLE_BYTE1             0x55U

/* Payload Types */
#define SPI_TYPE_REDUNDANT             0x01U /* High-redundancy (RLE & LZ4 optimal) */
#define SPI_TYPE_RANDOM                0x02U /* Pseudo-random (entropy ~8 bits/byte) */
#define SPI_TYPE_TELEMETRY             0x03U /* Structured telemetry records */

/* Control Flags (1 Byte) */
#define SPI_FLAG_COMPRESS_EN           (1U << 0) /* Bit 0: Enable Compression */
#define SPI_FLAG_ENCRYPT_EN            (1U << 1) /* Bit 1: Enable Encryption */
#define SPI_FLAG_COMP_ALGO_RLE         (0U << 2) /* Bit 2 = 0: RLE Compression */
#define SPI_FLAG_COMP_ALGO_LZ4         (1U << 2) /* Bit 2 = 1: LZ4 Compression */
#define SPI_FLAG_CRYPTO_ALGO_AES_CTR   (0U << 3) /* Bit 3 = 0: AES-128-CTR */
#define SPI_FLAG_CRYPTO_ALGO_CHACHA20  (1U << 3) /* Bit 3 = 1: ChaCha20 */

/* Header & Framing Constants */
#define SPI_HEADER_SIZE                8U  /* Preamble(2) + Type(1) + Flags(1) + Len(4) */
#define SPI_CRC_SIZE                   2U  /* CRC-16-CCITT(2) */
#define SPI_MAX_PAYLOAD_SIZE           65536U

/* ========================================================================= */
/* Public API                                                                */
/* ========================================================================= */

/**
 * @brief Initialize the ESP32 SPI Master controller with DMA and bus parameters.
 *
 * @param sclk_pin SCLK GPIO number
 * @param mosi_pin MOSI GPIO number
 * @param miso_pin MISO GPIO number
 * @param cs_pin CS GPIO number (active low)
 * @param clock_speed_hz SPI clock speed in Hz (e.g. 25000000 for 25 MHz)
 * @return esp_err_t ESP_OK on success, error code otherwise
 */
esp_err_t spi_injector_init(int sclk_pin, int mosi_pin, int miso_pin, int cs_pin, int clock_speed_hz);

/**
 * @brief Pack and transmit a complete structured frame over SPI using DMA.
 *
 * Frame structure:
 *   [0..1] Preamble (0xAA, 0x55)
 *   [2]    Payload Type
 *   [3]    Flags
 *   [4..7] Length (Big-Endian)
 *   [8..8+N-1] Payload Data
 *   [8+N..8+N+1] CRC-16-CCITT (Big-Endian)
 *
 * @param payload_type Type of synthetic data (REDUNDANT, RANDOM, TELEMETRY)
 * @param flags Control flags for FPGA acceleration stages
 * @param payload Pointer to raw data buffer (must be DMA capable / 32-bit aligned)
 * @param length Size of payload in bytes
 * @return esp_err_t ESP_OK on transmission complete, error code otherwise
 */
esp_err_t spi_injector_send_packet(uint8_t payload_type, uint8_t flags, const uint8_t *payload, uint32_t length);

/**
 * @brief Compute CRC-16-CCITT (poly 0x1021, init 0xFFFF).
 *
 * @param data Input data buffer
 * @param len Length in bytes
 * @return uint16_t Computed CRC
 */
uint16_t spi_injector_crc16(const uint8_t *data, size_t len);

/**
 * @brief De-initialize the SPI bus and free associated device/DMA resources.
 */
void spi_injector_deinit(void);

#ifdef __cplusplus
}
#endif

#endif /* SPI_INJECTOR_MASTER_H */
