/**
 * @file spi_injector_master.h
 * @brief High-speed SPI Master driver for ESP32 synthetic data injection
 *        into Digilent Cora Z7-10 (Zynq-7010).
 *
 * Implements the deterministic TelemetryFrame data contract and bus configuration
 * for bring-up over flying jumper wires.
 */

#ifndef SPI_INJECTOR_MASTER_H
#define SPI_INJECTOR_MASTER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "esp_err.h"
#include "spi_frame.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Default Hardware Pin Mapping (ESP32 -> Cora Z7 Dedicated SPI Header J7)   */
/* ========================================================================= */
/* Cora Z7 FPGA Pins: SCLK=H15 (J7.3), MOSI=T12 (J7.4), MISO=W15 (J7.1), CS_N=F16 (J7.5) */
#define SPI_INJECTOR_DEFAULT_SCLK_PIN  18  /* VSPI SCK  -> Cora Z7 H15 (J7.3) */
#define SPI_INJECTOR_DEFAULT_MOSI_PIN  23  /* VSPI MOSI -> Cora Z7 T12 (J7.4) */
#define SPI_INJECTOR_DEFAULT_MISO_PIN  19  /* VSPI MISO -> Cora Z7 W15 (J7.1) */
#define SPI_INJECTOR_DEFAULT_CS_PIN    5   /* VSPI CS0  -> Cora Z7 F16 (J7.5) */

/* Standard Bus Frequencies for Bring-Up */
#define SPI_SPEED_1MHZ                 1000000   /* 1.0 MHz conservative bring-up speed */
#define SPI_SPEED_2MHZ                 2000000   /* 2.0 MHz standard bring-up speed */
#define SPI_SPEED_10MHZ                10000000  /* 10.0 MHz production speed */
#define SPI_SPEED_25MHZ                25000000  /* 25.0 MHz maximum speed */

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
 * @param clock_speed_hz SPI clock speed in Hz (e.g. 1000000 or 2000000)
 * @return esp_err_t ESP_OK on success, error code otherwise
 */
esp_err_t spi_injector_init(int sclk_pin, int mosi_pin, int miso_pin, int cs_pin, int clock_speed_hz);

/**
 * @brief Build a valid TelemetryFrame with incremental payload and computed CRC-16.
 *
 * @param frame Pointer to frame struct to populate
 * @param pkt_type Packet type (0x01: Echo, 0x02: Telemetry)
 * @param seq_id Monotonic sequence counter
 * @param payload Optional payload buffer (if NULL, generates 0x00, 0x01, ..., 0xN)
 * @param len Length in bytes (must be <= SPI_BRINGUP_PAYLOAD_LEN)
 */
void spi_injector_build_frame(TelemetryFrame *frame, uint8_t pkt_type, uint16_t seq_id, const uint8_t *payload, uint16_t len);

/**
 * @brief Execute a synchronous full-duplex transfer of a TelemetryFrame.
 *
 * Transmits tx_frame while simultaneously reading the response into rx_ack_frame.
 *
 * @param tx_frame Pointer to outgoing frame
 * @param rx_ack_frame Pointer to buffer receiving ACK/response frame (can be NULL)
 * @return esp_err_t ESP_OK on successful bus transfer, error code otherwise
 */
esp_err_t spi_injector_transfer_frame(const TelemetryFrame *tx_frame, TelemetryFrame *rx_ack_frame);

/**
 * @brief Validate an incoming ACK response frame from Cora Z7 slave.
 *
 * @param ack_frame Pointer to received frame
 * @param expected_seq_id Expected sequence ID matching the transmitted packet
 * @return bool true if preamble, pkt_type (0x81), seq_id, EOF, and CRC are valid
 */
bool spi_injector_validate_ack(const TelemetryFrame *ack_frame, uint16_t expected_seq_id);

/**
 * @brief De-initialize the SPI bus and free associated device/DMA resources.
 */
void spi_injector_deinit(void);

#ifdef __cplusplus
}
#endif

#endif /* SPI_INJECTOR_MASTER_H */
