/**
 * @file spi_injector_master.c
 * @brief High-speed SPI Master driver for ESP32 synthetic data injection.
 */

#include "spi_injector_master.h"
#include <string.h>
#include <arpa/inet.h>
#include "esp_log.h"
#include "esp_attr.h"
#include "esp_rom_sys.h"
#include "driver/spi_master.h"
#include "driver/gpio.h"

static const char *TAG = "SPI_MASTER";

static spi_device_handle_t s_spi_dev = NULL;
static bool s_is_initialized = false;

/* Pre-allocated DMA-capable buffers */
static DMA_ATTR uint8_t s_dma_tx_buf[sizeof(TelemetryFrame) + 32];
static DMA_ATTR uint8_t s_dma_rx_buf[sizeof(TelemetryFrame) + 32];

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
        .max_transfer_sz = sizeof(TelemetryFrame) + 64,
    };

    esp_err_t ret = spi_bus_initialize(SPI3_HOST, &buscfg, SPI_DMA_CH_AUTO);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "spi_bus_initialize failed: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Configure CS pin pull-up so it defaults high (inactive) */
    gpio_set_pull_mode((gpio_num_t)cs_pin, GPIO_PULLUP_ONLY);

    spi_device_interface_config_t devcfg = {
        .clock_speed_hz = clock_speed_hz,
        .mode = 0,                  /* Mode 0: CPOL=0, CPHA=0 */
        .spics_io_num = cs_pin,     /* Hardware CS control */
        .queue_size = 4,
        .flags = 0,                 /* Full-duplex simultaneous TX/RX */
        .cs_ena_pretrans = 2,       /* CS active 2 SPI clock cycles before SCK */
        .cs_ena_posttrans = 2,      /* CS active 2 SPI clock cycles after SCK */
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

void spi_injector_build_frame(TelemetryFrame *frame, uint8_t pkt_type, uint16_t seq_id, const uint8_t *payload, uint16_t len) {
    if (frame == NULL) return;

    if (len > SPI_BRINGUP_PAYLOAD_LEN) {
        len = SPI_BRINGUP_PAYLOAD_LEN;
    }

    frame->preamble = SPI_FRAME_PREAMBLE;
    frame->pkt_type = pkt_type;
    frame->seq_id = htons(seq_id);
    frame->payload_len = htons(len);

    if (payload != NULL) {
        memcpy(frame->payload, payload, len);
    } else {
        /* Deterministic incremental pattern: 0x00, 0x01, ..., 0xN */
        for (uint16_t i = 0; i < len; i++) {
            frame->payload[i] = (uint8_t)(i & 0xFFU);
        }
    }

    /* Zero pad any remaining bytes in fixed payload buffer */
    if (len < SPI_BRINGUP_PAYLOAD_LEN) {
        memset(&frame->payload[len], 0, SPI_BRINGUP_PAYLOAD_LEN - len);
    }

    /* Compute CRC-16-CCITT over [preamble ... payload] */
    uint16_t crc = compute_crc16_ccitt((const uint8_t *)frame, TELEMETRY_FRAME_CRC_OFFSET);
    frame->crc16 = htons(crc);
    frame->eof_delim = SPI_FRAME_EOF_DELIM;
}

esp_err_t spi_injector_transfer_frame(const TelemetryFrame *tx_frame, TelemetryFrame *rx_ack_frame) {
    if (!s_is_initialized || s_spi_dev == NULL) {
        ESP_LOGE(TAG, "SPI injector not initialized.");
        return ESP_ERR_INVALID_STATE;
    }
    if (tx_frame == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    memcpy(s_dma_tx_buf, tx_frame, sizeof(TelemetryFrame));
    memset(s_dma_rx_buf, 0, sizeof(TelemetryFrame));

    spi_transaction_t trans = {
        .length = sizeof(TelemetryFrame) * 8, /* Transaction length in bits */
        .tx_buffer = s_dma_tx_buf,
        .rx_buffer = s_dma_rx_buf,
    };

    esp_err_t ret = spi_device_transmit(s_spi_dev, &trans);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "spi_device_transmit failed: %s", esp_err_to_name(ret));
        return ret;
    }

    if (rx_ack_frame != NULL) {
        /* If slave returned an immediate valid ACK during this full-duplex transfer (pipelined) */
        if (s_dma_rx_buf[0] == SPI_FRAME_PREAMBLE && s_dma_rx_buf[1] == SPI_PKT_TYPE_ACK) {
            memcpy(rx_ack_frame, s_dma_rx_buf, sizeof(TelemetryFrame));
            return ESP_OK;
        }

        /* Provide 500 us turnaround for Cora Z7 PS to drain FIFO, verify CRC, and stage ACK in DTR */
        esp_rom_delay_us(500);

        /* Send dummy transaction (73 bytes) to clock the ACK response out of slave TX FIFO */
        memset(s_dma_tx_buf, 0, sizeof(TelemetryFrame));
        memset(s_dma_rx_buf, 0, sizeof(TelemetryFrame));

        spi_transaction_t ack_trans = {
            .length = sizeof(TelemetryFrame) * 8,
            .tx_buffer = s_dma_tx_buf,
            .rx_buffer = s_dma_rx_buf,
        };

        ret = spi_device_transmit(s_spi_dev, &ack_trans);
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "spi_device_transmit (ack read) failed: %s", esp_err_to_name(ret));
            return ret;
        }

        memcpy(rx_ack_frame, s_dma_rx_buf, sizeof(TelemetryFrame));
    }

    return ESP_OK;
}

bool spi_injector_validate_ack(const TelemetryFrame *ack_frame, uint16_t expected_seq_id) {
    if (ack_frame == NULL) return false;

    if (ack_frame->preamble != SPI_FRAME_PREAMBLE) {
        return false;
    }
    if (ack_frame->pkt_type != SPI_PKT_TYPE_ACK) {
        return false;
    }
    if (ntohs(ack_frame->seq_id) != expected_seq_id) {
        return false;
    }
    if (ack_frame->eof_delim != SPI_FRAME_EOF_DELIM) {
        return false;
    }

    uint16_t expected_crc = ntohs(ack_frame->crc16);
    uint16_t computed_crc = compute_crc16_ccitt((const uint8_t *)ack_frame, TELEMETRY_FRAME_CRC_OFFSET);
    return (expected_crc == computed_crc);
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
