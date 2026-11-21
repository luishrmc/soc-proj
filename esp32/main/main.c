/**
 * @file main.c
 * @brief ESP32 SPI Master Telemetry Injector for Cora Z7-10 SoC Benchmark.
 *
 * Transmits paced bursts of 1035-byte Telemetry Frames (1024-byte payload = 64
 * packed 16-byte Telemetry Records) from a flash-resident Embedded Dataset across
 * Quiescent, Dynamic, and Chaotic Entropy Profiles over VSPI Mode 0.
 *
 * Bursts are initiated by a falling-edge interrupt on GPIO 32 (Cora Z7 PMOD JA1
 * active-low pulse), with optional non-blocking UART debug commands ('t'/'s')
 * and optional Kconfig auto-trigger fallback.
 *
 * Pinout:
 *   - VSPI SCLK: GPIO 18 -> Cora Z7 Header J7 Pin 3 (H15)
 *   - VSPI MOSI: GPIO 23 -> Cora Z7 Header J7 Pin 4 (T12)
 *   - VSPI MISO: GPIO 19 -> Cora Z7 Header J7 Pin 1 (W15)
 *   - VSPI CS0:  GPIO 5  -> Cora Z7 Header J7 Pin 5 (F16)
 *   - TRIGGER:   GPIO 32 <- Cora Z7 PMOD JA1 (Y18, Active-Low pulse, internal pull-up)
 */

#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

#include "sdkconfig.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_timer.h"

#include "spi_injector_master.h"
#include "telemetry_dataset.h"
#include "trigger_gpio.h"

static const char *TAG = "ESP32_MASTER";

/* Static Global Frames (zero dynamic allocation after init) */
static TelemetryFrame s_tx_frame;
static TelemetryFrame s_rx_ack_frame;

/* Transfer Statistics */
static uint32_t s_bursts_completed = 0;
static uint32_t s_total_sent = 0;
static uint32_t s_acks_received = 0;
static uint32_t s_ack_errors = 0;

/**
 * @brief Print boot configuration, Embedded Dataset summary, and trigger status.
 */
static void log_boot_summary(void) {
    ESP_LOGI(TAG, "============================================================");
    ESP_LOGI(TAG, "  ESP32 SPI Master Telemetry Injector (ADR-020 / 1024 B)    ");
    ESP_LOGI(TAG, "============================================================");
    ESP_LOGI(TAG, "VSPI Bus   : SCK=%d MOSI=%d MISO=%d CS=%d Mode 0 @ %d Hz",
             SPI_INJECTOR_DEFAULT_SCLK_PIN,
             SPI_INJECTOR_DEFAULT_MOSI_PIN,
             SPI_INJECTOR_DEFAULT_MISO_PIN,
             SPI_INJECTOR_DEFAULT_CS_PIN,
             CONFIG_ESP32_SPI_CLOCK_HZ);
    ESP_LOGI(TAG, "Dataset    : %u frames (%u/profile: Quiescent, Dynamic, Chaotic)",
             (unsigned int)TELEMETRY_DATASET_FRAME_COUNT,
             (unsigned int)TELEMETRY_FRAMES_PER_PROFILE);
    ESP_LOGI(TAG, "Frame Spec : pkt_type=0x%02X payload=%u B (%u records x %u B) wire=%u B seed=%u",
             (unsigned int)SPI_PKT_TYPE_TELEMETRY,
             (unsigned int)TELEMETRY_PAYLOAD_SIZE,
             (unsigned int)TELEMETRY_RECORDS_PER_FRAME,
             (unsigned int)TELEMETRY_RECORD_SIZE,
             (unsigned int)TELEMETRY_FRAME_TOTAL_SIZE,
             (unsigned int)TELEMETRY_DATASET_SEED);
    ESP_LOGI(TAG, "Pacing     : inter-frame gap=%d ms | GPIO %d lockout=%d ms (level=%d)",
             CONFIG_ESP32_INTER_FRAME_GAP_MS,
             TRIGGER_GPIO_PIN,
             CONFIG_ESP32_TRIGGER_LOCKOUT_MS,
             trigger_gpio_get_level());

#if defined(CONFIG_ESP32_UART_DEBUG_TRIGGER) && CONFIG_ESP32_UART_DEBUG_TRIGGER
    ESP_LOGI(TAG, "UART Debug : enabled (send 't' to trigger burst, 's' for stats)");
#else
    ESP_LOGI(TAG, "UART Debug : disabled");
#endif

#if defined(CONFIG_ESP32_AUTO_TRIGGER_FALLBACK) && CONFIG_ESP32_AUTO_TRIGGER_FALLBACK
    ESP_LOGI(TAG, "Auto-Trig  : enabled (period=%d ms)", CONFIG_ESP32_AUTO_TRIGGER_PERIOD_MS);
#else
    ESP_LOGI(TAG, "Auto-Trig  : disabled (armed for GPIO %d falling-edge trigger)", TRIGGER_GPIO_PIN);
#endif
}

/**
 * @brief Print current Embedded Dataset metadata and runtime transfer counters.
 */
static void log_status_summary(uint16_t next_seq_id) {
    ESP_LOGI(TAG, "[STATS] Dataset: %u frames (%u/profile, seed=%u) | GPIO %d level=%d isr_triggers=%lu",
             (unsigned int)TELEMETRY_DATASET_FRAME_COUNT,
             (unsigned int)TELEMETRY_FRAMES_PER_PROFILE,
             (unsigned int)TELEMETRY_DATASET_SEED,
             TRIGGER_GPIO_PIN,
             trigger_gpio_get_level(),
             (unsigned long)trigger_gpio_get_count());
    ESP_LOGI(TAG, "[STATS] Bursts=%lu | FramesTX=%lu | ACKs=%lu | Errors=%lu | NextSeq=%u",
             (unsigned long)s_bursts_completed,
             (unsigned long)s_total_sent,
             (unsigned long)s_acks_received,
             (unsigned long)s_ack_errors,
             (unsigned int)next_seq_id);
}

#if defined(CONFIG_ESP32_UART_DEBUG_TRIGGER) && CONFIG_ESP32_UART_DEBUG_TRIGGER
/**
 * @brief Configure STDIN_FILENO for non-blocking reads on UART console.
 */
static void configure_stdin_nonblocking(void) {
    int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
    if (flags >= 0) {
        (void)fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
    }
}

/**
 * @brief Poll non-blocking UART stdin for single-character debug commands.
 */
static void poll_uart_debug_cmd(bool *trigger_burst, bool *print_stats) {
    char ch = 0;
    while (read(STDIN_FILENO, &ch, 1) == 1) {
        if (ch == 't' || ch == 'T') {
            *trigger_burst = true;
        } else if (ch == 's' || ch == 'S') {
            *print_stats = true;
        }
    }
}
#endif /* CONFIG_ESP32_UART_DEBUG_TRIGGER */

/**
 * @brief Transmit one full Embedded Dataset burst with monotonic sequence IDs.
 */
static void transmit_dataset_burst(uint16_t *seq_id, const char *trigger_src) {
    ESP_LOGI(TAG, ">>> Burst #%lu started (source=%s, frames=%u, start_seq=%u)",
             (unsigned long)(s_bursts_completed + 1U),
             trigger_src,
             (unsigned int)TELEMETRY_DATASET_FRAME_COUNT,
             (unsigned int)*seq_id);

    for (size_t i = 0; i < TELEMETRY_DATASET_FRAME_COUNT; i++) {
        const telemetry_dataset_entry_t *entry = &g_telemetry_dataset[i];
        uint16_t frame_seq = *seq_id;

        spi_injector_build_frame(&s_tx_frame,
                                 SPI_PKT_TYPE_TELEMETRY,
                                 frame_seq,
                                 entry->payload,
                                 (uint16_t)TELEMETRY_PAYLOAD_SIZE);

        int64_t t_start = esp_timer_get_time();
        esp_err_t err = spi_injector_transfer_frame(&s_tx_frame, &s_rx_ack_frame);
        int64_t t_end = esp_timer_get_time();
        int64_t latency_us = t_end - t_start;

        s_total_sent++;

        if (err == ESP_OK) {
            bool ack_ok = spi_injector_validate_ack(&s_rx_ack_frame, frame_seq);
            if (ack_ok) {
                s_acks_received++;
                ESP_LOGI(TAG,
                         "[%2u/%2u] seq=%u profile=%-9s crc=0x%04X ack=OK   lat=%lld us",
                         (unsigned int)(i + 1U),
                         (unsigned int)TELEMETRY_DATASET_FRAME_COUNT,
                         (unsigned int)frame_seq,
                         telemetry_profile_name(entry->profile),
                         (unsigned int)ntohs(s_tx_frame.crc16),
                         (long long)latency_us);
            } else {
                s_ack_errors++;
                ESP_LOGW(TAG,
                         "[%2u/%2u] seq=%u profile=%-9s crc=0x%04X ack=NONE (rx_type=0x%02X rx_seq=%u) lat=%lld us",
                         (unsigned int)(i + 1U),
                         (unsigned int)TELEMETRY_DATASET_FRAME_COUNT,
                         (unsigned int)frame_seq,
                         telemetry_profile_name(entry->profile),
                         (unsigned int)ntohs(s_tx_frame.crc16),
                         (unsigned int)s_rx_ack_frame.pkt_type,
                         (unsigned int)ntohs(s_rx_ack_frame.seq_id),
                         (long long)latency_us);
            }
        } else {
            s_ack_errors++;
            ESP_LOGE(TAG,
                     "[%2u/%2u] seq=%u profile=%-9s TX failed: %s",
                     (unsigned int)(i + 1U),
                     (unsigned int)TELEMETRY_DATASET_FRAME_COUNT,
                     (unsigned int)frame_seq,
                     telemetry_profile_name(entry->profile),
                     esp_err_to_name(err));
        }

        (*seq_id)++;

#if CONFIG_ESP32_INTER_FRAME_GAP_MS > 0
        if ((i + 1U) < TELEMETRY_DATASET_FRAME_COUNT) {
            vTaskDelay(pdMS_TO_TICKS(CONFIG_ESP32_INTER_FRAME_GAP_MS));
        }
#endif
    }

    s_bursts_completed++;
    ESP_LOGI(TAG, "<<< Burst #%lu complete (next_seq=%u, total_acks=%lu/%lu)",
             (unsigned long)s_bursts_completed,
             (unsigned int)*seq_id,
             (unsigned long)s_acks_received,
             (unsigned long)s_total_sent);
}

static void spi_master_task(void *pvParameters) {
    (void)pvParameters;

    esp_err_t err = trigger_gpio_init(xTaskGetCurrentTaskHandle(),
                                      (uint32_t)CONFIG_ESP32_TRIGGER_LOCKOUT_MS);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize GPIO %d trigger: %s",
                 TRIGGER_GPIO_PIN, esp_err_to_name(err));
        spi_injector_deinit();
        vTaskDelete(NULL);
        return;
    }

#if defined(CONFIG_ESP32_UART_DEBUG_TRIGGER) && CONFIG_ESP32_UART_DEBUG_TRIGGER
    configure_stdin_nonblocking();
#endif

    log_boot_summary();

    uint16_t seq_id = 0;

#if defined(CONFIG_ESP32_UART_DEBUG_TRIGGER) && CONFIG_ESP32_UART_DEBUG_TRIGGER
    const TickType_t wait_ticks = pdMS_TO_TICKS(50);
#elif defined(CONFIG_ESP32_AUTO_TRIGGER_FALLBACK) && CONFIG_ESP32_AUTO_TRIGGER_FALLBACK
    const TickType_t wait_ticks = pdMS_TO_TICKS(CONFIG_ESP32_AUTO_TRIGGER_PERIOD_MS);
#else
    const TickType_t wait_ticks = portMAX_DELAY;
#endif

#if defined(CONFIG_ESP32_AUTO_TRIGGER_FALLBACK) && CONFIG_ESP32_AUTO_TRIGGER_FALLBACK
    int64_t last_auto_us = esp_timer_get_time();
    const int64_t auto_period_us = (int64_t)CONFIG_ESP32_AUTO_TRIGGER_PERIOD_MS * 1000LL;
#endif

    while (1) {
        uint32_t notified = ulTaskNotifyTake(pdTRUE, wait_ticks);
        bool uart_trigger = false;
        bool print_stats = false;

#if defined(CONFIG_ESP32_UART_DEBUG_TRIGGER) && CONFIG_ESP32_UART_DEBUG_TRIGGER
        poll_uart_debug_cmd(&uart_trigger, &print_stats);
        if (print_stats) {
            log_status_summary(seq_id);
        }
#endif

        if (notified > 0U) {
            transmit_dataset_burst(&seq_id, "GPIO32");
        } else if (uart_trigger) {
            transmit_dataset_burst(&seq_id, "UART");
        } else {
#if defined(CONFIG_ESP32_AUTO_TRIGGER_FALLBACK) && CONFIG_ESP32_AUTO_TRIGGER_FALLBACK
            int64_t now_us = esp_timer_get_time();
            if ((now_us - last_auto_us) >= auto_period_us) {
                transmit_dataset_burst(&seq_id, "AUTO_FALLBACK");
            } else {
                continue;
            }
#else
            continue;
#endif
        }
#if defined(CONFIG_ESP32_AUTO_TRIGGER_FALLBACK) && CONFIG_ESP32_AUTO_TRIGGER_FALLBACK
        last_auto_us = esp_timer_get_time();
#endif
    }
}

void app_main(void) {
    esp_err_t err = spi_injector_init(SPI_INJECTOR_DEFAULT_SCLK_PIN,
                                      SPI_INJECTOR_DEFAULT_MOSI_PIN,
                                      SPI_INJECTOR_DEFAULT_MISO_PIN,
                                      SPI_INJECTOR_DEFAULT_CS_PIN,
                                      CONFIG_ESP32_SPI_CLOCK_HZ);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize SPI Master: %s", esp_err_to_name(err));
        return;
    }

    BaseType_t created = xTaskCreatePinnedToCore(
        spi_master_task,
        "spi_master_task",
        4096,
        NULL,
        5,
        NULL,
        1);
    if (created != pdPASS) {
        ESP_LOGE(TAG, "Failed to create spi_master_task");
    }
}
