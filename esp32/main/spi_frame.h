/**
 * @file spi_frame.h
 * @brief Binary Frame Contract for ESP32 (Master) <-> Cora Z7 (Slave) SPI Link.
 *
 * Defines the packed binary data contract and CRC-16 CCITT verification logic
 * shared by both firmware codebases.
 */

#ifndef SPI_FRAME_H
#define SPI_FRAME_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Endianness Conversion Macros for Bare-Metal & Network Serialization */
#ifndef htons
#define htons(x) ((uint16_t)((((uint16_t)(x) & 0x00FFU) << 8) | (((uint16_t)(x) & 0xFF00U) >> 8)))
#endif
#ifndef ntohs
#define ntohs(x) htons(x)
#endif
#ifndef htonl
#define htonl(x) ((uint32_t)((((uint32_t)(x) & 0x000000FFU) << 24) | \
                             (((uint32_t)(x) & 0x0000FF00U) << 8)  | \
                             (((uint32_t)(x) & 0x00FF0000U) >> 8)  | \
                             (((uint32_t)(x) & 0xFF000000U) >> 24)))
#endif
#ifndef ntohl
#define ntohl(x) htonl(x)
#endif

/* Magic Frame Delimiters */
#define SPI_FRAME_PREAMBLE       0xA5U
#define SPI_FRAME_EOF_DELIM      0x5AU

/* Packet Types */
#define SPI_PKT_TYPE_LOOPBACK    0x01U  /* Echo / Loopback Request */
#define SPI_PKT_TYPE_TELEMETRY   0x02U  /* Telemetry Ingestion Request */
#define SPI_PKT_TYPE_ACK         0x81U  /* Immediate Acknowledgement / Echo Response */

/* Default Bring-Up Payload Size */
#define SPI_BRINGUP_PAYLOAD_LEN  64U

/**
 * @brief Packed Telemetry / Command Frame Layout (73 Bytes total)
 */
typedef struct __attribute__((packed)) {
    uint8_t  preamble;                         /* [0]    Fixed magic byte (0xA5) */
    uint8_t  pkt_type;                         /* [1]    0x01: Echo, 0x02: Telem, 0x81: ACK */
    uint16_t seq_id;                           /* [2..3] Packet sequence counter (Big-Endian) */
    uint16_t payload_len;                      /* [4..5] Payload length in bytes (Big-Endian) */
    uint8_t  payload[SPI_BRINGUP_PAYLOAD_LEN]; /* [6..69] Incremental test pattern */
    uint16_t crc16;                            /* [70..71] CRC-16-CCITT over [0..69] (Big-Endian) */
    uint8_t  eof_delim;                        /* [72]   Fixed end-of-frame delimiter (0x5A) */
} TelemetryFrame;

#define TELEMETRY_FRAME_TOTAL_SIZE sizeof(TelemetryFrame)
#define TELEMETRY_FRAME_CRC_OFFSET offsetof(TelemetryFrame, crc16)

/**
 * @brief Standard CRC-16-CCITT (Polynomial 0x1021, Initial Value 0xFFFF).
 *        Bit-exact calculation verified against CCITT test vector ("123456789" -> 0x29B1).
 *
 * @param data Pointer to input data buffer
 * @param len  Length in bytes
 * @return uint16_t Computed 16-bit CRC checksum
 */
static inline uint16_t compute_crc16_ccitt(const uint8_t *data, size_t len) {
    uint16_t crc = 0xFFFFU;
    for (size_t i = 0; i < len; i++) {
        crc ^= (uint16_t)((uint16_t)data[i] << 8);
        for (int b = 0; b < 8; b++) {
            if (crc & 0x8000U) {
                crc = (crc << 1) ^ 0x1021U;
            } else {
                crc = crc << 1;
            }
        }
    }
    return crc;
}

#ifdef __cplusplus
}
#endif

#endif /* SPI_FRAME_H */
