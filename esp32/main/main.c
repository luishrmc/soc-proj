/**
 * @file main.c
 * @brief ESP32 High-Speed SPI Master Synthetic Data Injector for Zynq-7010 SoC.
 *
 * Transmits synthetic benchmark blocks (64 B, 1 KB, 64 KB) across SPI at up to
 * 25 MHz to validate PL-only and Hybrid compression/encryption pipelines.
 */

#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "spi_injector_master.h"

static const char *TAG = "MAIN_APP";

/* Static Test Buffers */
static uint8_t s_buf_64b[64];
static uint8_t s_buf_1kb[1024];
static uint8_t s_buf_64kb[65536];

/**
 * @brief Generate a deterministic pseudo-random sequence using a 32-bit LFSR/Xorshift.
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
 * @brief Generate synthetic telemetry records (mixed ASCII and numerical data).
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
 * @brief Task executing periodic synthetic benchmark injections.
 */
static void injector_task(void *pvParameters) {
    (void)pvParameters;

    ESP_LOGI(TAG, "Preparing synthetic benchmark buffers...");

    /* 1. 64 B High-Redundancy Buffer (e.g. repeated 'A's) */
    memset(s_buf_64b, 'A', sizeof(s_buf_64b));

    /* 2. 1 KB Pseudo-Random Buffer */
    generate_pseudorandom(s_buf_1kb, sizeof(s_buf_1kb), 0xA5A55A5AU);

    /* 3. 64 KB Telemetry Buffer */
    generate_telemetry(s_buf_64kb, sizeof(s_buf_64kb));

    ESP_LOGI(TAG, "Buffers initialized. Beginning SPI injection loop...");

    uint32_t iteration = 0;

    while (1) {
        iteration++;
        ESP_LOGI(TAG, "==================================================");
        ESP_LOGI(TAG, ">>> SPI Benchmark Cycle #%lu Started", (unsigned long)iteration);
        ESP_LOGI(TAG, "==================================================");

        /* ------------------------------------------------------------------ */
        /* Pattern 1: 64 B Redundant Block -> RLE Compression                */
        /* ------------------------------------------------------------------ */
        uint8_t flags_rle = SPI_FLAG_COMPRESS_EN | SPI_FLAG_COMP_ALGO_RLE;
        int64_t t0 = esp_timer_get_time();
        esp_err_t err = spi_injector_send_packet(SPI_TYPE_REDUNDANT, flags_rle, s_buf_64b, sizeof(s_buf_64b));
        int64_t t1 = esp_timer_get_time();

        if (err == ESP_OK) {
            ESP_LOGI(TAG, "[TX 64B] RLE Block Sent. Latency: %lld us", (t1 - t0));
        } else {
            ESP_LOGE(TAG, "[TX 64B] Failed: %s", esp_err_to_name(err));
        }
        vTaskDelay(pdMS_TO_TICKS(50));

        /* ------------------------------------------------------------------ */
        /* Pattern 2: 1 KB Pseudo-Random Block -> LZ4 Compression            */
        /* ------------------------------------------------------------------ */
        uint8_t flags_lz4 = SPI_FLAG_COMPRESS_EN | SPI_FLAG_COMP_ALGO_LZ4;
        t0 = esp_timer_get_time();
        err = spi_injector_send_packet(SPI_TYPE_RANDOM, flags_lz4, s_buf_1kb, sizeof(s_buf_1kb));
        t1 = esp_timer_get_time();

        if (err == ESP_OK) {
            float throughput_mbps = (1024.0f * 8.0f) / (float)(t1 - t0);
            ESP_LOGI(TAG, "[TX 1KB] LZ4 Block Sent. Latency: %lld us (%.2f Mbps)", (t1 - t0), throughput_mbps);
        } else {
            ESP_LOGE(TAG, "[TX 1KB] Failed: %s", esp_err_to_name(err));
        }
        vTaskDelay(pdMS_TO_TICKS(50));

        /* ------------------------------------------------------------------ */
        /* Pattern 3: 64 KB Telemetry Block -> AES-128-CTR                   */
        /* ------------------------------------------------------------------ */
        uint8_t flags_aes = SPI_FLAG_ENCRYPT_EN | SPI_FLAG_CRYPTO_ALGO_AES_CTR;
        t0 = esp_timer_get_time();
        err = spi_injector_send_packet(SPI_TYPE_TELEMETRY, flags_aes, s_buf_64kb, sizeof(s_buf_64kb));
        t1 = esp_timer_get_time();

        if (err == ESP_OK) {
            float throughput_mbps = (65536.0f * 8.0f) / (float)(t1 - t0);
            ESP_LOGI(TAG, "[TX 64KB] AES-CTR Block Sent. Latency: %lld us (%.2f Mbps)", (t1 - t0), throughput_mbps);
        } else {
            ESP_LOGE(TAG, "[TX 64KB] Failed: %s", esp_err_to_name(err));
        }
        vTaskDelay(pdMS_TO_TICKS(50));

        /* ------------------------------------------------------------------ */
        /* Pattern 4: 64 KB Telemetry Block -> ChaCha20                      */
        /* ------------------------------------------------------------------ */
        uint8_t flags_chacha = SPI_FLAG_ENCRYPT_EN | SPI_FLAG_CRYPTO_ALGO_CHACHA20;
        t0 = esp_timer_get_time();
        err = spi_injector_send_packet(SPI_TYPE_TELEMETRY, flags_chacha, s_buf_64kb, sizeof(s_buf_64kb));
        t1 = esp_timer_get_time();

        if (err == ESP_OK) {
            float throughput_mbps = (65536.0f * 8.0f) / (float)(t1 - t0);
            ESP_LOGI(TAG, "[TX 64KB] ChaCha20 Block Sent. Latency: %lld us (%.2f Mbps)", (t1 - t0), throughput_mbps);
        } else {
            ESP_LOGE(TAG, "[TX 64KB] Failed: %s", esp_err_to_name(err));
        }

        /* Wait 1 second before next cycle */
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

void app_main(void) {
    ESP_LOGI(TAG, "======================================================");
    ESP_LOGI(TAG, "  Digilent Cora Z7-10 SoC Benchmark: ESP32 SPI Injector  ");
    ESP_LOGI(TAG, "  Toolchain: ESP-IDF v6.1 / FreeRTOS SMP Dual Core     ");
    ESP_LOGI(TAG, "======================================================");

    /* Initialize SPI Master bus at 25 MHz with default Cora Z7 J1 pinout */
    esp_err_t ret = spi_injector_init(
        SPI_INJECTOR_DEFAULT_SCLK_PIN,
        SPI_INJECTOR_DEFAULT_MOSI_PIN,
        SPI_INJECTOR_DEFAULT_MISO_PIN,
        SPI_INJECTOR_DEFAULT_CS_PIN,
        SPI_SPEED_25MHZ
    );

    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Fatal: Failed to initialize SPI injector driver: %s", esp_err_to_name(ret));
        return;
    }

    /* Spawn injector FreeRTOS task on Core 1 */
    BaseType_t task_ret = xTaskCreatePinnedToCore(
        injector_task,
        "spi_injector",
        16384,
        NULL,
        5,
        NULL,
        1
    );

    if (task_ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create injector task.");
    }
}
