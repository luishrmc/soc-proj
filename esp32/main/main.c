/**
 * @file main.c
 * @brief ESP32 Autonomous SPI Master Injector for Cora Z7-10 SoC Benchmark.
 *
 * Implements single pushbutton-driven test execution and dual-channel RGB LED visual telemetry,
 * allowing full test operation without an active serial connection from the PC.
 *
 * Pinout:
 *   - VSPI SCLK: GPIO 18  -> Cora Z7 J7.3 (G20)
 *   - VSPI MOSI: GPIO 23  -> Cora Z7 J7.4 (T10)
 *   - VSPI MISO: GPIO 19  -> Cora Z7 J7.1 (V15)
 *   - VSPI CS0:  GPIO 5   -> Cora Z7 J7.5 (F16)
 *   - BTN_TRIGGER: GPIO 32 (Active-Low, connected to GND with internal pull-up)
 *   - LED_GREEN:   GPIO 21 (RGB Green: Heartbeat / Busy / Success)
 *   - LED_RED:     GPIO 22 (RGB Red: Critical Alert / Error)
 *   - LED_READY:   GPIO 2  (Onboard Blue LED mirror)
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
 * @brief Execute full benchmark suite sequentially across SPI.
 */
static void execute_burst_full_suite(uint32_t burst_id) {
    ESP_LOGI(TAG, "==================================================");
    ESP_LOGI(TAG, ">>> Triggering Full Benchmark Suite (Burst #%lu)", (unsigned long)burst_id);
    ESP_LOGI(TAG, "==================================================");

    ui_controller_set_state(UI_STATE_BUSY);

    int64_t t_start = esp_timer_get_time();
    esp_err_t ret = ESP_OK;

    /* Step 1: 64B Redundant (RLE) */
    esp_err_t err = execute_tx_64b_rle(burst_id);
    if (err != ESP_OK) ret = err;
    vTaskDelay(pdMS_TO_TICKS(30));

    /* Step 2: 1KB Pseudo-Random (LZ4) */
    err = execute_tx_1kb_lz4(burst_id);
    if (err != ESP_OK) ret = err;
    vTaskDelay(pdMS_TO_TICKS(30));

    /* Step 3: 64KB Telemetry (AES-128-CTR) */
    err = execute_tx_64kb_aes(burst_id);
    if (err != ESP_OK) ret = err;
    vTaskDelay(pdMS_TO_TICKS(30));

    /* Step 4: 64KB Telemetry (ChaCha20) */
    err = execute_tx_64kb_chacha(burst_id);
    if (err != ESP_OK) ret = err;

    int64_t t_end = esp_timer_get_time();

    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "==================================================");
        ESP_LOGI(TAG, "[BURST #%lu] Full Suite Completed Successfully! Total Latency: %lld us",
                 (unsigned long)burst_id, (t_end - t_start));
        ESP_LOGI(TAG, "==================================================");
        ui_controller_set_state(UI_STATE_SUCCESS);
    } else {
        ESP_LOGE(TAG, "==================================================");
        ESP_LOGE(TAG, "[BURST #%lu] Full Suite Encountered Errors! Code: %s",
                 (unsigned long)burst_id, esp_err_to_name(ret));
        ESP_LOGE(TAG, "==================================================");
        ui_controller_set_state(UI_STATE_ERROR);
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

    ESP_LOGI(TAG, "Minimalist Autonomous Orchestrator Ready.");
    ESP_LOGI(TAG, "  -> Press BTN_TRIGGER (GPIO 32) to inject Full Benchmark Suite");

    ui_event_t ev;

    while (1) {
        /* Wait up to 10 seconds for user button press */
        if (xQueueReceive(s_ui_event_queue, &ev, pdMS_TO_TICKS(10000)) == pdTRUE) {
            if (ev.type == UI_EVENT_TRIGGER_PRESSED) {
                burst_counter++;
                execute_burst_full_suite(burst_counter);
            }
        } else {
            /* Periodic Standby Log on Serial (if connected) */
            ESP_LOGI(TAG, "[STANDBY] System Ready (Waiting for GPIO 32 trigger) | State: %s",
                     ui_state_to_name(ui_controller_get_state()));
        }
    }
}

void app_main(void) {
    ESP_LOGI(TAG, "======================================================");
    ESP_LOGI(TAG, "  Digilent Cora Z7-10 SoC Benchmark: ESP32 SPI Injector  ");
    ESP_LOGI(TAG, "  Toolchain: ESP-IDF v6.1 / FreeRTOS SMP Dual Core     ");
    ESP_LOGI(TAG, "  Minimalist UI (Single BTN GPIO 32 + RGB LED 21/22)    ");
    ESP_LOGI(TAG, "======================================================");

    /* 1. Initialize UI Controller (Button GPIO 32 & LEDs GPIO 21/22) */
    esp_err_t ret = ui_controller_init(&s_ui_event_queue);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Fatal: Failed to initialize UI controller: %s", esp_err_to_name(ret));
        return;
    }

    /* 2. Initialize SPI Master bus at 25 MHz with default Cora Z7 J7 pinout */
    ret = spi_injector_init(
        SPI_INJECTOR_DEFAULT_SCLK_PIN,
        SPI_INJECTOR_DEFAULT_MOSI_PIN,
        SPI_INJECTOR_DEFAULT_MISO_PIN,
        SPI_INJECTOR_DEFAULT_CS_PIN,
        SPI_SPEED_25MHZ
    );

    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Fatal: Failed to initialize SPI injector driver: %s", esp_err_to_name(ret));
        ui_controller_set_state(UI_STATE_ERROR);
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
        ui_controller_set_state(UI_STATE_ERROR);
    }
}
