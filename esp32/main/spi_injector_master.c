/**
 * @file spi_injector_master.c
 * @brief High-speed SPI Master driver for ESP32 synthetic data injection.
 */

#include "spi_injector_master.h"
#include <string.h>
#include "esp_log.h"
#include "esp_heap_caps.h"
#include "driver/spi_master.h"
#include "driver/gpio.h"

static const char *TAG = "SPI_INJECTOR";

static spi_device_handle_t s_spi_dev = NULL;
static bool s_is_initialized = false;

/* CRC-16-CCITT Look-up Table (Polynomial: 0x1021) */
static const uint16_t s_crc16_table[256] = {
    0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50A5, 0x60C6, 0x70E7,
    0x8108, 0x9129, 0xA14A, 0xB16B, 0xC18C, 0xD1AD, 0xE1CE, 0xF1EF,
    0x1231, 0x0210, 0x3273, 0x2252, 0x52B5, 0x4294, 0x72F7, 0x62D6,
    0x9339, 0x8318, 0xB37B, 0xA35A, 0xD3BD, 0xC39C, 0xF3FF, 0xE3DE,
    0x2462, 0x3443, 0x0420, 0x1401, 0x64E6, 0x74C7, 0x44A4, 0x5485,
    0xA56A, 0xB54B, 0x8528, 0x9509, 0xE5EE, 0xF5CF, 0xC5AC, 0xD58D,
    0x3653, 0x2672, 0x1611, 0x0630, 0x76D7, 0x66F6, 0x5695, 0x46B4,
    0xB75B, 0xA77A, 0x9719, 0x8738, 0xF7DF, 0xE7FE, 0xD79D, 0xC7BC,
    0x48C4, 0x58E5, 0x6886, 0x78A7, 0x0840, 0x1861, 0x2802, 0x3823,
    0xC9CC, 0xD9ED, 0xE98E, 0xF9AF, 0x8948, 0x9969, 0xA90A, 0xB92B,
    0x5AF5, 0x4AD4, 0x7AB7, 0x6A96, 0x1A71, 0x0A50, 0x3A33, 0x2A12,
    0xDBFD, 0xCBDC, 0xFBBF, 0xEB9E, 0x9B79, 0x8B58, 0xBB3B, 0xAB1A,
    0x6CA6, 0x7C87, 0x4CE4, 0x5CC5, 0x2C22, 0x3C03, 0x0C60, 0x1C41,
    0xEDAE, 0xFD8F, 0xCDEC, 0xDDCD, 0xAD2A, 0xBD0B, 0x8D68, 0x9D49,
    0x7E97, 0x6EB6, 0x5ED5, 0x4EF4, 0x3E13, 0x2E32, 0x1E51, 0x0E70,
    0xFF9F, 0xEFBE, 0xDFDD, 0xCFFC, 0xBF1B, 0xAF3A, 0x9F59, 0x8F78,
    0x9188, 0x81A9, 0xB1CA, 0xA1EB, 0xD10C, 0xC12D, 0xF14E, 0xE16F,
    0x1080, 0x00A1, 0x30C2, 0x20E3, 0x5004, 0x4025, 0x7046, 0x6067,
    0x83B9, 0x9398, 0xA3FB, 0xB3DA, 0xC33D, 0xD31C, 0xE37F, 0xF35E,
    0x02B1, 0x1290, 0x22F3, 0x32D2, 0x4235, 0x5214, 0x6277, 0x7256,
    0xB5EA, 0xA5CB, 0x95A8, 0x8589, 0xF56E, 0xE54F, 0xD52C, 0xC50D,
    0x34E2, 0x24C3, 0x14A0, 0x0481, 0x7466, 0x6447, 0x5424, 0x4405,
    0xA7DB, 0xB7FA, 0x8799, 0x97B8, 0xE75F, 0xF77E, 0xC71D, 0xD73C,
    0x26D3, 0x36F2, 0x0691, 0x16B0, 0x6657, 0x7676, 0x4615, 0x5634,
    0xD94C, 0xC96D, 0xF90E, 0xE92F, 0x99C8, 0x89E9, 0xB98A, 0xA9AB,
    0x5844, 0x4865, 0x7806, 0x6827, 0x18C0, 0x08E1, 0x3882, 0x28A3,
    0xCB7D, 0xDB5C, 0xEB3F, 0xFB1E, 0x8BF9, 0x9BD8, 0xABBB, 0xBB9A,
    0x4A75, 0x5A54, 0x6A37, 0x7A16, 0x0AF1, 0x1AD0, 0x2AB3, 0x3A92,
    0xFD2E, 0xED0F, 0xDD6C, 0xCD4D, 0xBDAA, 0xAD8B, 0x9DE8, 0x8DC9,
    0x7C26, 0x6C07, 0x5C64, 0x4C45, 0x3CA2, 0x2C83, 0x1CE0, 0x0CC1,
    0xEF1F, 0xFF3E, 0xCF5D, 0xDF7C, 0xAF9B, 0xBFBA, 0x8FD9, 0x9FF8,
    0x6E17, 0x7E36, 0x4E55, 0x5E74, 0x2E93, 0x3EB2, 0x0ED1, 0x1EF0
};

uint16_t spi_injector_crc16(const uint8_t *data, size_t len) {
    uint16_t crc = 0xFFFFU;
    for (size_t i = 0; i < len; i++) {
        uint8_t index = (uint8_t)((crc >> 8) ^ data[i]);
        crc = (uint16_t)((crc << 8) ^ s_crc16_table[index]);
    }
    return crc;
}

esp_err_t spi_injector_init(int sclk_pin, int mosi_pin, int miso_pin, int cs_pin, int clock_speed_hz) {
    if (s_is_initialized) {
        ESP_LOGW(TAG, "SPI injector is already initialized.");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing SPI Master (SCLK=%d, MOSI=%d, MISO=%d, CS=%d, Freq=%d Hz)...",
             sclk_pin, mosi_pin, miso_pin, cs_pin, clock_speed_hz);

    spi_bus_config_t buscfg = {
        .miso_io_num = miso_pin,
        .mosi_io_num = mosi_pin,
        .sclk_io_num = sclk_pin,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = (int)(SPI_MAX_PAYLOAD_SIZE + SPI_HEADER_SIZE + SPI_CRC_SIZE + 64),
    };

    esp_err_t ret = spi_bus_initialize(SPI3_HOST, &buscfg, SPI_DMA_CH_AUTO);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "spi_bus_initialize failed: %s", esp_err_to_name(ret));
        return ret;
    }

    spi_device_interface_config_t devcfg = {
        .clock_speed_hz = clock_speed_hz,
        .mode = 0,                  /* Mode 0: CPOL=0, CPHA=0 */
        .spics_io_num = cs_pin,     /* Hardware CS control */
        .queue_size = 1,
        .flags = 0,
        .pre_cb = NULL,
        .post_cb = NULL,
    };

    ret = spi_bus_add_device(SPI3_HOST, &devcfg, &s_spi_dev);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "spi_bus_add_device failed: %s", esp_err_to_name(ret));
        spi_bus_free(SPI3_HOST);
        return ret;
    }

    s_is_initialized = true;
    ESP_LOGI(TAG, "SPI Master initialized successfully.");
    return ESP_OK;
}

esp_err_t spi_injector_send_packet(uint8_t payload_type, uint8_t flags, const uint8_t *payload, uint32_t length) {
    if (!s_is_initialized || s_spi_dev == NULL) {
        ESP_LOGE(TAG, "Cannot send packet: SPI injector not initialized.");
        return ESP_ERR_INVALID_STATE;
    }

    if (length > SPI_MAX_PAYLOAD_SIZE) {
        ESP_LOGE(TAG, "Payload length %lu exceeds maximum allowed (%lu bytes).",
                 (unsigned long)length, (unsigned long)SPI_MAX_PAYLOAD_SIZE);
        return ESP_ERR_INVALID_SIZE;
    }

    size_t total_frame_len = SPI_HEADER_SIZE + length + SPI_CRC_SIZE;

    /* Allocate DMA-capable memory buffer */
    uint8_t *dma_buf = (uint8_t *)heap_caps_malloc(total_frame_len, MALLOC_CAP_DMA);
    if (dma_buf == NULL) {
        ESP_LOGE(TAG, "Failed to allocate %zu bytes DMA buffer.", total_frame_len);
        return ESP_ERR_NO_MEM;
    }

    /* 1. Header (8 Bytes) */
    dma_buf[0] = SPI_PREAMBLE_BYTE0;
    dma_buf[1] = SPI_PREAMBLE_BYTE1;
    dma_buf[2] = payload_type;
    dma_buf[3] = flags;
    dma_buf[4] = (uint8_t)((length >> 24) & 0xFFU);
    dma_buf[5] = (uint8_t)((length >> 16) & 0xFFU);
    dma_buf[6] = (uint8_t)((length >> 8)  & 0xFFU);
    dma_buf[7] = (uint8_t)(length & 0xFFU);

    /* 2. Payload Data */
    if (length > 0 && payload != NULL) {
        memcpy(&dma_buf[SPI_HEADER_SIZE], payload, length);
    }

    /* 3. CRC-16-CCITT computed over Header + Payload */
    uint16_t crc = spi_injector_crc16(dma_buf, SPI_HEADER_SIZE + length);
    dma_buf[SPI_HEADER_SIZE + length]     = (uint8_t)((crc >> 8) & 0xFFU);
    dma_buf[SPI_HEADER_SIZE + length + 1] = (uint8_t)(crc & 0xFFU);

    /* 4. Transmit via SPI Master */
    spi_transaction_t trans = {
        .length = total_frame_len * 8, /* Transaction length in bits */
        .tx_buffer = dma_buf,
        .rx_buffer = NULL,
    };

    esp_err_t ret = spi_device_transmit(s_spi_dev, &trans);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "spi_device_transmit failed: %s", esp_err_to_name(ret));
    }

    heap_caps_free(dma_buf);
    return ret;
}

void spi_injector_deinit(void) {
    if (s_is_initialized) {
        if (s_spi_dev != NULL) {
            spi_bus_remove_device(s_spi_dev);
            s_spi_dev = NULL;
        }
        spi_bus_free(SPI3_HOST);
        s_is_initialized = false;
        ESP_LOGI(TAG, "SPI injector de-initialized.");
    }
}
