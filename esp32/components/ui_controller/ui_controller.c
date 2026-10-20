/**
 * @file ui_controller.c
 * @brief Minimalist Autonomous UI Controller implementation for ESP32.
 */

#include "ui_controller.h"
#include <stdio.h>
#include <string.h>
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/task.h"

static const char *TAG = "UI_CTRL";

/* State Names */
static const char *s_state_names[] = {
    [UI_STATE_IDLE]    = "IDLE (Heartbeat)",
    [UI_STATE_BUSY]    = "BUSY (Burst Transmitting)",
    [UI_STATE_SUCCESS] = "SUCCESS (Suite Completed)",
    [UI_STATE_ERROR]   = "ERROR (Alert/Failure)",
};

/* Internal State */
static QueueHandle_t s_event_queue = NULL;
static volatile ui_state_t s_ui_state = UI_STATE_IDLE;

/* Debounce state counters */
static uint8_t s_btn_trig_counter = 0;
static bool s_btn_trig_latched = false;

/* Timing Constants (Tick = 20ms) */
#define UI_TICK_MS             20
#define UI_HEARTBEAT_PERIOD    (1000 / UI_TICK_MS) /* 50 ticks = 1000 ms */
#define UI_HEARTBEAT_PULSE     (60 / UI_TICK_MS)   /* 3 ticks = 60 ms */
#define UI_FAST_BLINK_TICKS    (100 / UI_TICK_MS)  /* 5 ticks = 100 ms */

/* Helper for LED polarity */
static inline void set_led_output(gpio_num_t pin, bool on) {
#if UI_LED_ACTIVE_LEVEL == 1
    gpio_set_level(pin, on ? 1 : 0);
#else
    gpio_set_level(pin, on ? 0 : 1);
#endif
}

static void ui_fsm_task(void *pvParameters) {
    (void)pvParameters;

    uint16_t idle_tick_counter = 0;
    uint8_t success_pulses = 0;
    uint8_t success_timer = 0;
    bool success_led_state = false;
    uint8_t err_timer = 0;
    bool err_led_state = false;

    ESP_LOGI(TAG, "UI FSM task running (period = %d ms, BTN=GPIO %d, GRN=GPIO %d, RED=GPIO %d)",
             UI_TICK_MS, UI_GPIO_BTN_TRIGGER, UI_GPIO_LED_GREEN, UI_GPIO_LED_RED);

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(UI_TICK_MS));

        /* ------------------------------------------------------------------ */
        /* 1. Pushbutton Debouncing & Event Posting (GPIO 32, Active-Low)     */
        /* ------------------------------------------------------------------ */
        int raw_trig = gpio_get_level((gpio_num_t)UI_GPIO_BTN_TRIGGER);

        if (raw_trig == 0) {
            /* Button pressed (GND connected) */
            if (s_btn_trig_counter < 3) {
                s_btn_trig_counter++;
            }
            if (s_btn_trig_counter >= 2 && !s_btn_trig_latched) {
                s_btn_trig_latched = true;
                ui_event_t ev = {
                    .type = UI_EVENT_TRIGGER_PRESSED,
                    .timestamp_ms = (uint32_t)(esp_timer_get_time() / 1000)
                };
                ESP_LOGI(TAG, "[BUTTON] TRIGGER Pressed -> Dispatched Full Suite Event");
                if (s_event_queue != NULL) {
                    xQueueSend(s_event_queue, &ev, 0);
                }
            }
        } else {
            /* Button released */
            s_btn_trig_counter = 0;
            s_btn_trig_latched = false;
        }

        /* ------------------------------------------------------------------ */
        /* 2. Visual Telemetry FSM                                            */
        /* ------------------------------------------------------------------ */
        switch (s_ui_state) {
            case UI_STATE_IDLE:
                /* Red is OFF */
                set_led_output((gpio_num_t)UI_GPIO_LED_RED, false);

                /* Green Heartbeat (1 Hz short pulse) */
                idle_tick_counter++;
                if (idle_tick_counter >= UI_HEARTBEAT_PERIOD) {
                    idle_tick_counter = 0;
                }
                if (idle_tick_counter < UI_HEARTBEAT_PULSE) {
                    set_led_output((gpio_num_t)UI_GPIO_LED_GREEN, true);
                    gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, 1);
                } else {
                    set_led_output((gpio_num_t)UI_GPIO_LED_GREEN, false);
                    gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, 0);
                }

                /* Reset temporary states */
                success_pulses = 0;
                success_timer = 0;
                err_timer = 0;
                break;

            case UI_STATE_BUSY:
                /* Red is OFF */
                set_led_output((gpio_num_t)UI_GPIO_LED_RED, false);
                /* Green is Solid ON during active transmission */
                set_led_output((gpio_num_t)UI_GPIO_LED_GREEN, true);
                gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, 1);

                idle_tick_counter = 0;
                success_pulses = 0;
                break;

            case UI_STATE_SUCCESS:
                /* Red is OFF */
                set_led_output((gpio_num_t)UI_GPIO_LED_RED, false);

                /* Green rapid 3 blinks (80ms ON, 80ms OFF) */
                success_timer++;
                if (success_timer >= 4) { /* 4 ticks * 20ms = 80ms */
                    success_timer = 0;
                    success_led_state = !success_led_state;
                    set_led_output((gpio_num_t)UI_GPIO_LED_GREEN, success_led_state);
                    gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, success_led_state ? 1 : 0);

                    if (!success_led_state) {
                        success_pulses++;
                        if (success_pulses >= 3) {
                            /* Blinks finished; return to IDLE */
                            s_ui_state = UI_STATE_IDLE;
                            idle_tick_counter = 0;
                        }
                    }
                }
                break;

            case UI_STATE_ERROR:
                /* Green is OFF */
                set_led_output((gpio_num_t)UI_GPIO_LED_GREEN, false);
                gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, 0);

                /* Red 5 Hz rapid blink (100ms ON, 100ms OFF) */
                err_timer++;
                if (err_timer >= UI_FAST_BLINK_TICKS) {
                    err_timer = 0;
                    err_led_state = !err_led_state;
                    set_led_output((gpio_num_t)UI_GPIO_LED_RED, err_led_state);
                }
                break;
        }
    }
}

esp_err_t ui_controller_init(QueueHandle_t *out_queue) {
    ESP_LOGI(TAG, "Initializing Minimalist UI Controller...");

    /* 1. Configure Output LEDs */
    gpio_config_t io_conf_led = {
        .pin_bit_mask = (1ULL << UI_GPIO_LED_GREEN) |
                        (1ULL << UI_GPIO_LED_RED)   |
                        (1ULL << UI_GPIO_LED_READY),
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

    /* Set default LED levels (OFF) */
    set_led_output((gpio_num_t)UI_GPIO_LED_GREEN, false);
    set_led_output((gpio_num_t)UI_GPIO_LED_RED, false);
    gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, 0);

    /* 2. Configure Input Pushbutton (GPIO 32, Pull-Up, Active-Low) */
    gpio_config_t io_conf_btn = {
        .pin_bit_mask = (1ULL << UI_GPIO_BTN_TRIGGER),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    err = gpio_config(&io_conf_btn);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure Button GPIO: %s", esp_err_to_name(err));
        return err;
    }

    /* 3. Create Event Queue (depth 4) */
    s_event_queue = xQueueCreate(4, sizeof(ui_event_t));
    if (s_event_queue == NULL) {
        ESP_LOGE(TAG, "Failed to allocate UI event queue");
        return ESP_ERR_NO_MEM;
    }
    if (out_queue != NULL) {
        *out_queue = s_event_queue;
    }

    /* 4. Launch UI FSM Task on Core 0 */
    BaseType_t ret = xTaskCreatePinnedToCore(
        ui_fsm_task,
        "ui_fsm_task",
        3072,
        NULL,
        4,
        NULL,
        0
    );

    if (ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create UI FSM task");
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "UI Controller initialized:");
    ESP_LOGI(TAG, "  BTN_TRIGGER: GPIO %d (Full Suite Trigger)", UI_GPIO_BTN_TRIGGER);
    ESP_LOGI(TAG, "  LED_GREEN:   GPIO %d (Heartbeat/Busy/Success)", UI_GPIO_LED_GREEN);
    ESP_LOGI(TAG, "  LED_RED:     GPIO %d (Alert/Error)", UI_GPIO_LED_RED);
    ESP_LOGI(TAG, "  LED_READY:   GPIO %d (Onboard Blue mirror)", UI_GPIO_LED_READY);

    return ESP_OK;
}

void ui_controller_set_state(ui_state_t state) {
    if (state <= UI_STATE_ERROR) {
        s_ui_state = state;
        ESP_LOGI(TAG, "[UI STATE] Changed to: %s", s_state_names[state]);
    }
}

ui_state_t ui_controller_get_state(void) {
    return s_ui_state;
}

const char *ui_state_to_name(ui_state_t state) {
    if (state <= UI_STATE_ERROR) {
        return s_state_names[state];
    }
    return "UNKNOWN";
}

esp_err_t ui_controller_selftest(void) {
    ESP_LOGI(TAG, "==================================================");
    ESP_LOGI(TAG, "  UI Controller Hardware Self-Test (Minimalist)   ");
    ESP_LOGI(TAG, "==================================================");

    /* 1. Cycle LEDs in sequence */
    ESP_LOGI(TAG, "[LED TEST] Testing LED_GREEN (GPIO %d)...", UI_GPIO_LED_GREEN);
    set_led_output((gpio_num_t)UI_GPIO_LED_GREEN, true);
    vTaskDelay(pdMS_TO_TICKS(150));
    set_led_output((gpio_num_t)UI_GPIO_LED_GREEN, false);

    ESP_LOGI(TAG, "[LED TEST] Testing LED_RED (GPIO %d)...", UI_GPIO_LED_RED);
    set_led_output((gpio_num_t)UI_GPIO_LED_RED, true);
    vTaskDelay(pdMS_TO_TICKS(150));
    set_led_output((gpio_num_t)UI_GPIO_LED_RED, false);

    ESP_LOGI(TAG, "[LED TEST] Testing LED_READY Onboard (GPIO %d)...", UI_GPIO_LED_READY);
    gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, 1);
    vTaskDelay(pdMS_TO_TICKS(150));
    gpio_set_level((gpio_num_t)UI_GPIO_LED_READY, 0);

    /* 2. Read Button Default State (Must be HIGH due to pull-up) */
    int trig = gpio_get_level((gpio_num_t)UI_GPIO_BTN_TRIGGER);
    ESP_LOGI(TAG, "[BUTTON TEST] Raw reading (Pull-Up active): TRIGGER (GPIO %d) = %d",
             UI_GPIO_BTN_TRIGGER, trig);

    if (trig == 1) {
        ESP_LOGI(TAG, "[BUTTON TEST] Pull-up verified (PASS: idle high).");
    } else {
        ESP_LOGW(TAG, "[BUTTON TEST] Warning: Button reading LOW at startup (pressed or tied to GND).");
    }

    ESP_LOGI(TAG, "UI Controller Self-Test Completed Successfully.");
    return ESP_OK;
}
