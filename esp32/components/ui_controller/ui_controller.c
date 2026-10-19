/**
 * @file ui_controller.c
 * @brief Implementation of autonomous UI controller for ESP32 benchmark injector.
 */

#include "ui_controller.h"
#include <stdio.h>
#include <string.h>
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/task.h"

static const char *TAG = "UI_CTRL";

/* Profile Names */
static const char *s_profile_names[UI_PROFILE_MAX] = {
    [UI_PROFILE_64B_RLE]     = "64B High-Redundancy (RLE)",
    [UI_PROFILE_1KB_LZ4]     = "1KB Pseudo-Random (LZ4)",
    [UI_PROFILE_64KB_AES]    = "64KB Telemetry (AES-128-CTR)",
    [UI_PROFILE_64KB_CHACHA] = "64KB Telemetry (ChaCha20)",
    [UI_PROFILE_FULL_SUITE]  = "Full Benchmark Suite (All 4)",
};

/* Internal State */
static QueueHandle_t s_event_queue = NULL;
static volatile ui_test_profile_t s_active_profile = UI_PROFILE_64B_RLE;
static volatile bool s_tx_busy = false;
static volatile bool s_error_active = false;

/* Debounce state counters */
static uint8_t s_btn_trig_counter = 0;
static uint8_t s_btn_sel_counter = 0;
static bool s_btn_trig_latched = false;
static bool s_btn_sel_latched = false;

/* Profile visual telemetry state machine */
#define UI_TICK_MS          20
#define UI_HEARTBEAT_TICKS  (500 / UI_TICK_MS)  /* 500 ms = 25 ticks */
#define UI_BLINK_ON_TICKS   (100 / UI_TICK_MS)  /* 100 ms = 5 ticks */
#define UI_BLINK_OFF_TICKS  (140 / UI_TICK_MS)  /* 140 ms = 7 ticks */
#define UI_PAUSE_TICKS      (1400 / UI_TICK_MS) /* 1400 ms = 70 ticks */

typedef enum {
    LED_FSM_IDLE,
    LED_FSM_PULSE_ON,
    LED_FSM_PULSE_OFF,
    LED_FSM_CYCLE_PAUSE
} led_fsm_state_t;

static led_fsm_state_t s_led_fsm_state = LED_FSM_IDLE;
static uint16_t s_led_fsm_timer = 0;
static uint8_t s_led_pulses_remaining = 0;

static void ui_fsm_task(void *pvParameters) {
    (void)pvParameters;

    uint16_t heartbeat_counter = 0;
    bool heartbeat_state = false;

    ESP_LOGI(TAG, "UI FSM background task started (period = %d ms)", UI_TICK_MS);

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(UI_TICK_MS));

        /* ------------------------------------------------------------------ */
        /* 1. Pushbutton Debouncing & Event Posting                           */
        /* ------------------------------------------------------------------ */
        int raw_trig = gpio_get_level((gpio_num_t)UI_GPIO_BTN_TRIGGER);
        int raw_sel  = gpio_get_level((gpio_num_t)UI_GPIO_BTN_SELECT);

        /* Button 1: Trigger (Active Low) */
        if (raw_trig == 0) {
            if (s_btn_trig_counter < 3) {
                s_btn_trig_counter++;
            }
            if (s_btn_trig_counter >= 2 && !s_btn_trig_latched) {
                s_btn_trig_latched = true;
                ui_event_t ev = {
                    .type = UI_EVENT_TRIGGER_PRESSED,
                    .timestamp_ms = (uint32_t)(esp_timer_get_time() / 1000)
                };
                ESP_LOGI(TAG, "[BUTTON] TRIGGER Pressed -> Dispatched Event");
                if (s_event_queue != NULL) {
                    xQueueSend(s_event_queue, &ev, 0);
                }
            }
        } else {
            s_btn_trig_counter = 0;
            s_btn_trig_latched = false;
        }

        /* Button 2: Select/Mode (Active Low) */
        if (raw_sel == 0) {
            if (s_btn_sel_counter < 3) {
                s_btn_sel_counter++;
            }
            if (s_btn_sel_counter >= 2 && !s_btn_sel_latched) {
                s_btn_sel_latched = true;
                ui_event_t ev = {
                    .type = UI_EVENT_SELECT_PRESSED,
                    .timestamp_ms = (uint32_t)(esp_timer_get_time() / 1000)
                };
                ESP_LOGI(TAG, "[BUTTON] SELECT Pressed -> Dispatched Event");
                if (s_event_queue != NULL) {
                    xQueueSend(s_event_queue, &ev, 0);
                }
            }
        } else {
            s_btn_sel_counter = 0;
            s_btn_sel_latched = false;
        }

        /* ------------------------------------------------------------------ */
        /* 2. LED 1: Heartbeat / Ready (1 Hz)                                 */
        /* ------------------------------------------------------------------ */
        heartbeat_counter++;
        if (heartbeat_counter >= UI_HEARTBEAT_TICKS) {
            heartbeat_counter = 0;
            heartbeat_state = !heartbeat_state;
            gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, heartbeat_state ? 1 : 0);
        }

        /* ------------------------------------------------------------------ */
        /* 3. LED 2: TX Active / Busy                                         */
        /* ------------------------------------------------------------------ */
        gpio_set_level((gpio_num_t)UI_GPIO_LED_TX, s_tx_busy ? 1 : 0);

        /* ------------------------------------------------------------------ */
        /* 4. LED 3: Profile Blink Code / Error Condition                     */
        /* ------------------------------------------------------------------ */
        if (s_error_active) {
            /* Continuous ON for critical error alert */
            gpio_set_level((gpio_num_t)UI_GPIO_LED_STATUS, 1);
            s_led_fsm_state = LED_FSM_IDLE;
        } else {
            switch (s_led_fsm_state) {
                case LED_FSM_IDLE:
                    s_led_pulses_remaining = (uint8_t)(s_active_profile + 1);
                    s_led_fsm_timer = 0;
                    s_led_fsm_state = LED_FSM_PULSE_ON;
                    gpio_set_level((gpio_num_t)UI_GPIO_LED_STATUS, 1);
                    break;

                case LED_FSM_PULSE_ON:
                    s_led_fsm_timer++;
                    if (s_led_fsm_timer >= UI_BLINK_ON_TICKS) {
                        s_led_fsm_timer = 0;
                        gpio_set_level((gpio_num_t)UI_GPIO_LED_STATUS, 0);
                        s_led_pulses_remaining--;
                        s_led_fsm_state = LED_FSM_PULSE_OFF;
                    }
                    break;

                case LED_FSM_PULSE_OFF:
                    s_led_fsm_timer++;
                    if (s_led_fsm_timer >= UI_BLINK_OFF_TICKS) {
                        s_led_fsm_timer = 0;
                        if (s_led_pulses_remaining > 0) {
                            gpio_set_level((gpio_num_t)UI_GPIO_LED_STATUS, 1);
                            s_led_fsm_state = LED_FSM_PULSE_ON;
                        } else {
                            s_led_fsm_state = LED_FSM_CYCLE_PAUSE;
                        }
                    }
                    break;

                case LED_FSM_CYCLE_PAUSE:
                    s_led_fsm_timer++;
                    if (s_led_fsm_timer >= UI_PAUSE_TICKS) {
                        s_led_fsm_timer = 0;
                        s_led_fsm_state = LED_FSM_IDLE;
                    }
                    break;
            }
        }
    }
}

esp_err_t ui_controller_init(QueueHandle_t *out_queue) {
    ESP_LOGI(TAG, "Initializing UI Controller GPIOs...");

    /* 1. Configure Output LEDs */
    gpio_config_t io_conf_led = {
        .pin_bit_mask = (1ULL << UI_GPIO_LED_READY) |
                        (1ULL << UI_GPIO_LED_TX)    |
                        (1ULL << UI_GPIO_LED_STATUS),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t err = gpio_config(&io_conf_led);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure LED GPIOs: %s", esp_err_to_name(err));
        return err;
    }

    /* Set default LED levels */
    gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, 0);
    gpio_set_level((gpio_num_t)UI_GPIO_LED_TX, 0);
    gpio_set_level((gpio_num_t)UI_GPIO_LED_STATUS, 0);

    /* 2. Configure Input Pushbuttons with internal pull-ups */
    gpio_config_t io_conf_btn = {
        .pin_bit_mask = (1ULL << UI_GPIO_BTN_TRIGGER) |
                        (1ULL << UI_GPIO_BTN_SELECT),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    err = gpio_config(&io_conf_btn);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure Button GPIOs: %s", esp_err_to_name(err));
        return err;
    }

    /* 3. Create Event Queue (depth 8) */
    s_event_queue = xQueueCreate(8, sizeof(ui_event_t));
    if (s_event_queue == NULL) {
        ESP_LOGE(TAG, "Failed to allocate UI event queue");
        return ESP_ERR_NO_MEM;
    }
    if (out_queue != NULL) {
        *out_queue = s_event_queue;
    }

    /* 4. Launch UI FSM Task */
    BaseType_t ret = xTaskCreatePinnedToCore(
        ui_fsm_task,
        "ui_fsm_task",
        3072,
        NULL,
        4,
        NULL,
        0   /* Pinned to Core 0 to leave Core 1 dedicated to high-speed SPI */
    );

    if (ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create UI FSM task");
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "UI Controller initialized successfully.");
    ESP_LOGI(TAG, "  BTN_TRIGGER: GPIO %d (Start Burst)", UI_GPIO_BTN_TRIGGER);
    ESP_LOGI(TAG, "  BTN_SELECT:  GPIO %d (Cycle Profile)", UI_GPIO_BTN_SELECT);
    ESP_LOGI(TAG, "  LED_READY:   GPIO %d (Heartbeat 1Hz)", UI_GPIO_LED_READY);
    ESP_LOGI(TAG, "  LED_TX:      GPIO %d (TX Active)", UI_GPIO_LED_TX);
    ESP_LOGI(TAG, "  LED_STATUS:  GPIO %d (Profile Blink Code)", UI_GPIO_LED_STATUS);

    return ESP_OK;
}

void ui_set_active_profile(ui_test_profile_t profile) {
    if (profile < UI_PROFILE_MAX) {
        s_active_profile = profile;
        s_led_fsm_state = LED_FSM_IDLE; /* Restart blink sequence */
        ESP_LOGI(TAG, "[PROFILE] Active Mode: [%d] %s", profile, s_profile_names[profile]);
    }
}

ui_test_profile_t ui_get_active_profile(void) {
    return s_active_profile;
}

ui_test_profile_t ui_cycle_profile(void) {
    ui_test_profile_t next = (s_active_profile + 1) % UI_PROFILE_MAX;
    ui_set_active_profile(next);
    return next;
}

void ui_set_tx_busy(bool active) {
    s_tx_busy = active;
}

void ui_set_error(bool error_active) {
    s_error_active = error_active;
    if (error_active) {
        ESP_LOGE(TAG, "[ALERT] Error condition signaled!");
    }
}

const char *ui_profile_to_name(ui_test_profile_t profile) {
    if (profile < UI_PROFILE_MAX) {
        return s_profile_names[profile];
    }
    return "Unknown Profile";
}

esp_err_t ui_controller_selftest(void) {
    ESP_LOGI(TAG, "==================================================");
    ESP_LOGI(TAG, "  Starting UI Controller Hardware Self-Test       ");
    ESP_LOGI(TAG, "==================================================");

    /* 1. Cycle all LEDs in sequence */
    ESP_LOGI(TAG, "[LED TEST] Testing LED_READY (GPIO %d)...", UI_GPIO_LED_READY);
    gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, 1);
    vTaskDelay(pdMS_TO_TICKS(150));
    gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, 0);

    ESP_LOGI(TAG, "[LED TEST] Testing LED_TX (GPIO %d)...", UI_GPIO_LED_TX);
    gpio_set_level((gpio_num_t)UI_GPIO_LED_TX, 1);
    vTaskDelay(pdMS_TO_TICKS(150));
    gpio_set_level((gpio_num_t)UI_GPIO_LED_TX, 0);

    ESP_LOGI(TAG, "[LED TEST] Testing LED_STATUS (GPIO %d)...", UI_GPIO_LED_STATUS);
    gpio_set_level((gpio_num_t)UI_GPIO_LED_STATUS, 1);
    vTaskDelay(pdMS_TO_TICKS(150));
    gpio_set_level((gpio_num_t)UI_GPIO_LED_STATUS, 0);

    /* 2. Read Button Default States (Must be HIGH due to pull-ups) */
    int trig = gpio_get_level((gpio_num_t)UI_GPIO_BTN_TRIGGER);
    int sel  = gpio_get_level((gpio_num_t)UI_GPIO_BTN_SELECT);

    ESP_LOGI(TAG, "[BUTTON TEST] Raw readings (Pull-Up active): TRIGGER=%d, SELECT=%d", trig, sel);

    if (trig == 1 && sel == 1) {
        ESP_LOGI(TAG, "[BUTTON TEST] Pull-ups verified (PASS: idle high).");
    } else {
        ESP_LOGW(TAG, "[BUTTON TEST] Warning: A button is reading LOW at startup (pressed or pin tied to GND).");
    }

    ESP_LOGI(TAG, "UI Controller Self-Test Completed Successfully.");
    return ESP_OK;
}
