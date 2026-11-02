/**
 * @file main.c
 * @brief ESP32 Autonomous SPI Master Injector for Cora Z7-10 SoC Benchmark.
 *
 * Implements deterministic telemetry transmission, sequence tracking, and
 * full-duplex ACK validation over SPI Mode 0 with the Digilent Cora Z7.
 *
 * Pinout:
 *   - VSPI SCLK: GPIO 18  -> Cora Z7 Header J7 Pin 3 (H15)
 *   - VSPI MOSI: GPIO 23  -> Cora Z7 Header J7 Pin 4 (T12)
 *   - VSPI MISO: GPIO 19  -> Cora Z7 Header J7 Pin 1 (W15)
 *   - VSPI CS0:  GPIO 5   -> Cora Z7 Header J7 Pin 5 (F16)
 *   - BTN_TRIGGER: GPIO 32 (Trigger Input from Cora Z7 PMOD JA1 Pin Y18)
 *   - LED_GREEN:   GPIO 21 (RGB Green: Heartbeat / Success ACK)
 *   - LED_RED:     GPIO 22 (RGB Red: Critical Alert / Error)
 *   - LED_READY:   GPIO 2  (Onboard Blue LED mirror)
 */

#include <stdio.h>
#include <string.h>
#include <arpa/inet.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "spi_injector_master.h"
#include "ui_controller.h"

static const char *TAG = "ESP32_MASTER";

/* Static Global Frames */
static TelemetryFrame s_tx_frame;
static TelemetryFrame s_rx_ack_frame;

/* Metrics Counters */
static uint32_t s_total_sent = 0;
static uint32_t s_acks_received = 0;
static uint32_t s_ack_errors = 0;

static void spi_master_task(void *pvParameters) {
    (void)pvParameters;

    ESP_LOGI(TAG, "Starting deterministic SPI Master transmission loop...");
    vTaskDelay(pdMS_TO_TICKS(1000));

    uint16_t seq_id = 0;

    while (1) {
        /* Assemble test frame with incremental payload */
        spi_injector_build_frame(&s_tx_frame,
                                 SPI_PKT_TYPE_LOOPBACK,
                                 seq_id,
                                 NULL, /* Generates incremental pattern 0x00, 0x01, ... */
                                 SPI_BRINGUP_PAYLOAD_LEN);

        int64_t t_start = esp_timer_get_time();
        esp_err_t err = spi_injector_transfer_frame(&s_tx_frame, &s_rx_ack_frame);
        int64_t t_end = esp_timer_get_time();

        s_total_sent++;

        if (err == ESP_OK) {
            bool ack_ok = spi_injector_validate_ack(&s_rx_ack_frame, seq_id);
            if (ack_ok) {
                s_acks_received++;
                ui_controller_set_state(UI_STATE_SUCCESS);
                ESP_LOGI(TAG, "[TX #%u] SENT %u B | CRC: 0x%04X | ACK RECEIVED (Echo Seq: %u, Latency: %lld us) [ACKs: %lu/%lu]",
                         seq_id,
                         (unsigned int)TELEMETRY_FRAME_TOTAL_SIZE,
                         ntohs(s_tx_frame.crc16),
                         ntohs(s_rx_ack_frame.seq_id),
                         (t_end - t_start),
                         (unsigned long)s_acks_received,
                         (unsigned long)s_total_sent);
            } else {
                /* On initial transfer, slave may have preloaded IDLE/dummy bytes */
                if (s_total_sent > 1) {
                    s_ack_errors++;
                    ui_controller_set_state(UI_STATE_ERROR);
                }
                ESP_LOGI(TAG, "[TX #%u] SENT %u B | CRC: 0x%04X | Slave RX: PktType=0x%02X Seq=%u CRC=0x%04X [Total: %lu]",
                         seq_id,
                         (unsigned int)TELEMETRY_FRAME_TOTAL_SIZE,
                         ntohs(s_tx_frame.crc16),
                         s_rx_ack_frame.pkt_type,
                         ntohs(s_rx_ack_frame.seq_id),
                         ntohs(s_rx_ack_frame.crc16),
                         (unsigned long)s_total_sent);
            }
        } else {
            s_ack_errors++;
            ui_controller_set_state(UI_STATE_ERROR);
            ESP_LOGE(TAG, "[TX #%u] Bus Transfer Failed: %s", seq_id, esp_err_to_name(err));
        }

        seq_id++;

        /* Transmit periodically every 500 ms */
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

void app_main(void) {
    ESP_LOGI(TAG, "============================================================");
    ESP_LOGI(TAG, "  ESP32-WROOM: SPI Master Telemetry Transmitter Initializing  ");
    ESP_LOGI(TAG, "  Bus: VSPI (SCK=18, MOSI=23, MISO=19, CS=5) Mode 0 @ 2 MHz  ");
    ESP_LOGI(TAG, "============================================================");

    /* Initialize UI Controller (RGB status LEDs and Trigger Button) */
    ui_controller_init(NULL);
    ui_controller_set_state(UI_STATE_IDLE);

    /* Initialize SPI Master at conservative 2.0 MHz bring-up frequency */
    esp_err_t err = spi_injector_init(SPI_INJECTOR_DEFAULT_SCLK_PIN,
                                      SPI_INJECTOR_DEFAULT_MOSI_PIN,
                                      SPI_INJECTOR_DEFAULT_MISO_PIN,
                                      SPI_INJECTOR_DEFAULT_CS_PIN,
                                      SPI_SPEED_2MHZ);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize SPI Master: %s", esp_err_to_name(err));
        ui_controller_set_state(UI_STATE_ERROR);
        return;
    }

    /* Create background transmission FreeRTOS task */
    xTaskCreatePinnedToCore(spi_master_task, "spi_master_task", 4096, NULL, 5, NULL, 1);
}
