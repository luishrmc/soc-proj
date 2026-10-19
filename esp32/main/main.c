/**
 * @file main.c
 * @brief ESP32 Autonomous SPI Master Injector for Cora Z7-10 SoC Benchmark.
 *
 * Implements autonomous pushbutton-driven test execution and multi-LED status telemetry,
 * allowing full test operation without an active serial connection from the PC.
 *
 * Pinout:
 *   - VSPI SCLK: GPIO 18  -> Cora Z7 G20 (SCLK)
 *   - VSPI MOSI: GPIO 23  -> Cora Z7 T10 (MOSI)
 *   - VSPI MISO: GPIO 19  -> Cora Z7 V15 (MISO)
 *   - VSPI CS0:  GPIO 5   -> Cora Z7 F16 (CS#)
 *   - BTN_TRIGGER: GPIO 4 (active low, internal pull-up)
 *   - BTN_SELECT:  GPIO 16 (active low, internal pull-up)
 *   - LED_READY:   GPIO 2 (Heartbeat 1Hz, Blue onboard)
 *   - LED_TX:      GPIO 21 (TX Active / Busy)
 *   - LED_STATUS:  GPIO 22 (Profile Blink Code / Error)
 */

#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_system.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "spi_injector_master.h"
#include "ui_controller.h"

static const char *TAG = "ESP32_INJECTOR";

/* Static Pre-Allocated Test Buffers (Zero Dynamic Allocation in Hot Loop) */
static uint8_t s_buf_64b[64];
static uint8_t s_buf_1kb[1024];
static uint8_t s_buf_64kb[65536];

static QueueHandle_t s_ui_event_queue = NULL;

/**
 * @brief Generate deterministic pseudo-random sequence using 32-bit Xorshift LFSR.
 */
static void generate_pseudorandom(uint8_t *buf, size_t len, uint32_t seed) {
    uint32_t state = (seed != 0) ? seed : 0x12345678U;
    for (size_t i = 0; i < len; i++) {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        buf[i] = (uint8_t)(state & 0xFFU);
    }
}

/**
 * @brief Generate synthetic telemetry records (ASCII records with sequence/temp/press).
 */
static void generate_telemetry(uint8_t *buf, size_t len) {
    size_t offset = 0;
    uint32_t seq = 0;

    while (offset < len) {
        char record[128];
        int written = snprintf(record, sizeof(record),
                               "SEQ=%06lu;TEMP=%02d.%02d;PRESS=%04lu;STATUS=OK\n",
                               (unsigned long)seq,
                               (int)(20 + (seq % 15)), (int)(seq % 100),
                               (unsigned long)(101325 + (seq % 500)));
        seq++;
        if (written <= 0) break;

        size_t to_copy = (size_t)written;
        if (offset + to_copy > len) {
            to_copy = len - offset;
        }
        memcpy(&buf[offset], record, to_copy);
        offset += to_copy;
    }
}

/**
 * @brief Execute a single transmission of 64B High-Redundancy block (RLE).
 */
static esp_err_t execute_tx_64b_rle(uint32_t burst_id) {
    uint8_t flags = SPI_FLAG_COMPRESS_EN | SPI_FLAG_COMP_ALGO_RLE;
    int64_t t0 = esp_timer_get_time();
    esp_err_t err = spi_injector_send_packet(SPI_TYPE_REDUNDANT, flags, s_buf_64b, sizeof(s_buf_64b));
    int64_t t1 = esp_timer_get_time();

    if (err == ESP_OK) {
        ESP_LOGI(TAG, "[BURST #%lu][TX 64B] RLE Packet Sent | Latency: %lld us",
                 (unsigned long)burst_id, (t1 - t0));
    } else {
        ESP_LOGE(TAG, "[BURST #%lu][TX 64B] Failed: %s", (unsigned long)burst_id, esp_err_to_name(err));
    }
    return err;
}

/**
 * @brief Execute a single transmission of 1KB Pseudo-Random block (LZ4).
 */
static esp_err_t execute_tx_1kb_lz4(uint32_t burst_id) {
    uint8_t flags = SPI_FLAG_COMPRESS_EN | SPI_FLAG_COMP_ALGO_LZ4;
    int64_t t0 = esp_timer_get_time();
    esp_err_t err = spi_injector_send_packet(SPI_TYPE_RANDOM, flags, s_buf_1kb, sizeof(s_buf_1kb));
    int64_t t1 = esp_timer_get_time();

    if (err == ESP_OK) {
        float mbps = (1024.0f * 8.0f) / (float)(t1 - t0);
        ESP_LOGI(TAG, "[BURST #%lu][TX 1KB] LZ4 Packet Sent | Latency: %lld us | Throughput: %.2f Mbps",
                 (unsigned long)burst_id, (t1 - t0), mbps);
    } else {
        ESP_LOGE(TAG, "[BURST #%lu][TX 1KB] Failed: %s", (unsigned long)burst_id, esp_err_to_name(err));
    }
    return err;
}

/**
 * @brief Execute a single transmission of 64KB Telemetry block (AES-128-CTR).
 */
static esp_err_t execute_tx_64kb_aes(uint32_t burst_id) {
    uint8_t flags = SPI_FLAG_ENCRYPT_EN | SPI_FLAG_CRYPTO_ALGO_AES_CTR;
    int64_t t0 = esp_timer_get_time();
    esp_err_t err = spi_injector_send_packet(SPI_TYPE_TELEMETRY, flags, s_buf_64kb, sizeof(s_buf_64kb));
    int64_t t1 = esp_timer_get_time();

    if (err == ESP_OK) {
        float mbps = (65536.0f * 8.0f) / (float)(t1 - t0);
        ESP_LOGI(TAG, "[BURST #%lu][TX 64KB] AES-CTR Packet Sent | Latency: %lld us | Throughput: %.2f Mbps",
                 (unsigned long)burst_id, (t1 - t0), mbps);
    } else {
        ESP_LOGE(TAG, "[BURST #%lu][TX 64KB] Failed: %s", (unsigned long)burst_id, esp_err_to_name(err));
    }
    return err;
}

/**
 * @brief Execute a single transmission of 64KB Telemetry block (ChaCha20).
 */
static esp_err_t execute_tx_64kb_chacha(uint32_t burst_id) {
    uint8_t flags = SPI_FLAG_ENCRYPT_EN | SPI_FLAG_CRYPTO_ALGO_CHACHA20;
    int64_t t0 = esp_timer_get_time();
    esp_err_t err = spi_injector_send_packet(SPI_TYPE_TELEMETRY, flags, s_buf_64kb, sizeof(s_buf_64kb));
    int64_t t1 = esp_timer_get_time();

    if (err == ESP_OK) {
        float mbps = (65536.0f * 8.0f) / (float)(t1 - t0);
        ESP_LOGI(TAG, "[BURST #%lu][TX 64KB] ChaCha20 Packet Sent | Latency: %lld us | Throughput: %.2f Mbps",
                 (unsigned long)burst_id, (t1 - t0), mbps);
    } else {
        ESP_LOGE(TAG, "[BURST #%lu][TX 64KB] Failed: %s", (unsigned long)burst_id, esp_err_to_name(err));
    }
    return err;
}

/**
 * @brief Dispatch active benchmark burst based on selected UI profile.
 */
static void dispatch_active_burst(uint32_t burst_id) {
    ui_test_profile_t profile = ui_get_active_profile();

    ESP_LOGI(TAG, "==================================================");
    ESP_LOGI(TAG, ">>> Triggering Burst #%lu: Profile [%d] %s",
             (unsigned long)burst_id, profile, ui_profile_to_name(profile));
    ESP_LOGI(TAG, "==================================================");

    ui_set_tx_busy(true);

    esp_err_t ret = ESP_OK;

    switch (profile) {
        case UI_PROFILE_64B_RLE:
            ret = execute_tx_64b_rle(burst_id);
            break;

        case UI_PROFILE_1KB_LZ4:
            ret = execute_tx_1kb_lz4(burst_id);
            break;

        case UI_PROFILE_64KB_AES:
            ret = execute_tx_64kb_aes(burst_id);
            break;

        case UI_PROFILE_64KB_CHACHA:
            ret = execute_tx_64kb_chacha(burst_id);
            break;

        case UI_PROFILE_FULL_SUITE:
            ret |= execute_tx_64b_rle(burst_id);
            vTaskDelay(pdMS_TO_TICKS(30));
            ret |= execute_tx_1kb_lz4(burst_id);
            vTaskDelay(pdMS_TO_TICKS(30));
            ret |= execute_tx_64kb_aes(burst_id);
            vTaskDelay(pdMS_TO_TICKS(30));
            ret |= execute_tx_64kb_chacha(burst_id);
            break;

        default:
            ESP_LOGW(TAG, "Unknown profile ID %d", profile);
            break;
    }

    ui_set_tx_busy(false);

    if (ret != ESP_OK) {
        ui_set_error(true);
    } else {
        ui_set_error(false);
    }
}

/**
 * @brief Perform comprehensive hardware and algorithmic self-test on startup.
 */
static esp_err_t run_onboard_selftest(void) {
    ESP_LOGI(TAG, "==================================================");
    ESP_LOGI(TAG, "  ESP32 On-Board Self-Test & Diagnostic Routine   ");
    ESP_LOGI(TAG, "==================================================");

    /* 1. UI GPIO and LED Chaser Self-Test */
    esp_err_t err = ui_controller_selftest();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "[SELFTEST] UI Controller test failed!");
        return err;
    }
    ESP_LOGI(TAG, "[SELFTEST] UI Controller: PASS");

    /* 2. Buffer initialization and CRC-16 Verification */
    ESP_LOGI(TAG, "[SELFTEST] Initializing static test buffers...");
    memset(s_buf_64b, 'A', sizeof(s_buf_64b));
    generate_pseudorandom(s_buf_1kb, sizeof(s_buf_1kb), 0xA5A55A5AU);
    generate_telemetry(s_buf_64kb, sizeof(s_buf_64kb));

    uint16_t crc_64b = spi_injector_crc16(s_buf_64b, sizeof(s_buf_64b));
    uint16_t crc_1kb = spi_injector_crc16(s_buf_1kb, sizeof(s_buf_1kb));
    uint16_t crc_64kb = spi_injector_crc16(s_buf_64kb, sizeof(s_buf_64kb));

    ESP_LOGI(TAG, "[SELFTEST] Computed CRC-16 (64B Redundant):   0x%04X", crc_64b);
    ESP_LOGI(TAG, "[SELFTEST] Computed CRC-16 (1KB PseudoRandom): 0x%04X", crc_1kb);
    ESP_LOGI(TAG, "[SELFTEST] Computed CRC-16 (64KB Telemetry):   0x%04X", crc_64kb);

    if (crc_64b != 0 && crc_1kb != 0 && crc_64kb != 0) {
        ESP_LOGI(TAG, "[SELFTEST] CRC-16 Computation: PASS");
    } else {
        ESP_LOGE(TAG, "[SELFTEST] CRC-16 Computation Failed (unexpected zero)!");
        return ESP_FAIL;
    }

    /* 3. Dry-Run SPI Transmission Test */
    ESP_LOGI(TAG, "[SELFTEST] Testing dry-run SPI transmission (DMA Mode)...");
    err = execute_tx_64b_rle(0);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "[SELFTEST] SPI Dry-Run Transmission: PASS");
    } else {
        ESP_LOGE(TAG, "[SELFTEST] SPI Dry-Run Transmission: FAIL (%s)", esp_err_to_name(err));
        return err;
    }

    ESP_LOGI(TAG, "==================================================");
    ESP_LOGI(TAG, "  ALL ON-BOARD SELF-TESTS PASSED (READY FOR USE)  ");
    ESP_LOGI(TAG, "==================================================");

    return ESP_OK;
}

/**
 * @brief Main application task receiving UI events and orchestrating injections.
 */
static void app_orchestrator_task(void *pvParameters) {
    (void)pvParameters;

    uint32_t burst_counter = 0;

    /* Execute On-Board Self-Test at boot */
    run_onboard_selftest();

    ESP_LOGI(TAG, "Autonomous Orchestrator Ready. Waiting for Pushbutton Events...");
    ESP_LOGI(TAG, "  -> Press BTN_SELECT  (GPIO 16) to change benchmark profile");
    ESP_LOGI(TAG, "  -> Press BTN_TRIGGER (GPIO 4)  to inject synthetic burst");

    ui_event_t ev;

    while (1) {
        /* Wait up to 10 seconds for user button press */
        if (xQueueReceive(s_ui_event_queue, &ev, pdMS_TO_TICKS(10000)) == pdTRUE) {
            if (ev.type == UI_EVENT_SELECT_PRESSED) {
                ui_test_profile_t new_prof = ui_cycle_profile();
                ESP_LOGI(TAG, "[UI ACTION] Mode Changed: [%d] %s",
                         new_prof, ui_profile_to_name(new_prof));
            } else if (ev.type == UI_EVENT_TRIGGER_PRESSED) {
                burst_counter++;
                dispatch_active_burst(burst_counter);
            }
        } else {
            /* Periodic Heartbeat Log on Serial (if connected) */
            ESP_LOGI(TAG, "[STANDBY] System Ready | Active Profile: [%d] %s",
                     ui_get_active_profile(), ui_profile_to_name(ui_get_active_profile()));
        }
    }
}

void app_main(void) {
    ESP_LOGI(TAG, "======================================================");
    ESP_LOGI(TAG, "  Digilent Cora Z7-10 SoC Benchmark: ESP32 SPI Injector  ");
    ESP_LOGI(TAG, "  Toolchain: ESP-IDF v6.1 / FreeRTOS SMP Dual Core     ");
    ESP_LOGI(TAG, "  Autonomous UI & On-Board Telemetry Enabled           ");
    ESP_LOGI(TAG, "======================================================");

    /* 1. Initialize UI Controller (Buttons & LEDs) */
    esp_err_t ret = ui_controller_init(&s_ui_event_queue);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Fatal: Failed to initialize UI controller: %s", esp_err_to_name(ret));
        return;
    }

    /* 2. Initialize SPI Master bus at 25 MHz with default Cora Z7 J1 pinout */
    ret = spi_injector_init(
        SPI_INJECTOR_DEFAULT_SCLK_PIN,
        SPI_INJECTOR_DEFAULT_MOSI_PIN,
        SPI_INJECTOR_DEFAULT_MISO_PIN,
        SPI_INJECTOR_DEFAULT_CS_PIN,
        SPI_SPEED_25MHZ
    );

    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Fatal: Failed to initialize SPI injector driver: %s", esp_err_to_name(ret));
        ui_set_error(true);
        return;
    }

    /* 3. Spawn Orchestrator Task on Core 1 (leaving Core 0 for UI debounce) */
    BaseType_t task_ret = xTaskCreatePinnedToCore(
        app_orchestrator_task,
        "app_orchestrator",
        16384,
        NULL,
        5,
        NULL,
        1
    );

    if (task_ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create orchestrator task.");
        ui_set_error(true);
    }
}
