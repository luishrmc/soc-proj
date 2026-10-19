/**
 * @file ui_controller.h
 * @brief Autonomous User Interface (Pushbuttons & LED Telemetry) for ESP32.
 *
 * Provides button debouncing (FreeRTOS) and LED visual telemetry
 * allowing standalone benchmark control without an active USB-serial connection.
 */

#ifndef UI_CONTROLLER_H
#define UI_CONTROLLER_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Hardware GPIO Pin Assignments                                            */
/* ========================================================================= */
#define UI_GPIO_BTN_TRIGGER     4   /* Pushbutton 1: Start/Trigger (active low, pull-up) */
#define UI_GPIO_BTN_SELECT      16  /* Pushbutton 2: Mode/Select (active low, pull-up) */

#define UI_GPIO_LED_READY       2   /* LED 1: Heartbeat / Ready (Blue On-board) */
#define UI_GPIO_LED_TX          21  /* LED 2: TX Active / Busy */
#define UI_GPIO_LED_STATUS      22  /* LED 3: Profile Blink Code / Error Alert */

/* ========================================================================= */
/* Test Profiles and Event Types                                             */
/* ========================================================================= */
typedef enum {
    UI_PROFILE_64B_RLE = 0,         /* Pattern 1: 64 B Redundant -> RLE */
    UI_PROFILE_1KB_LZ4 = 1,         /* Pattern 2: 1 KB Random -> LZ4 */
    UI_PROFILE_64KB_AES = 2,        /* Pattern 3: 64 KB Telemetry -> AES-128-CTR */
    UI_PROFILE_64KB_CHACHA = 3,     /* Pattern 4: 64 KB Telemetry -> ChaCha20 */
    UI_PROFILE_FULL_SUITE = 4,      /* Pattern 5: All 4 benchmarks sequentially */
    UI_PROFILE_MAX = 5
} ui_test_profile_t;

typedef enum {
    UI_EVENT_TRIGGER_PRESSED,
    UI_EVENT_SELECT_PRESSED
} ui_event_type_t;

typedef struct {
    ui_event_type_t type;
    uint32_t timestamp_ms;
} ui_event_t;

/* ========================================================================= */
/* Public API                                                                */
/* ========================================================================= */

/**
 * @brief Initialize GPIOs for buttons and LEDs, and launch the FreeRTOS UI task.
 *
 * @param out_queue Pointer to queue handle receiving UI events
 * @return esp_err_t ESP_OK on success
 */
esp_err_t ui_controller_init(QueueHandle_t *out_queue);

/**
 * @brief Update the active test profile and adjust the visual blink code.
 */
void ui_set_active_profile(ui_test_profile_t profile);

/**
 * @brief Get the currently active test profile.
 */
ui_test_profile_t ui_get_active_profile(void);

/**
 * @brief Cycle to the next test profile.
 * @return ui_test_profile_t New active profile
 */
ui_test_profile_t ui_cycle_profile(void);

/**
 * @brief Assert or de-assert the TX Active / Busy LED indicator.
 */
void ui_set_tx_busy(bool active);

/**
 * @brief Assert or de-assert the Error alert condition.
 * When true, LED_STATUS remains continuously ON.
 */
void ui_set_error(bool error_active);

/**
 * @brief Convert profile enum to readable descriptive string.
 */
const char *ui_profile_to_name(ui_test_profile_t profile);

/**
 * @brief Run a self-test of all UI GPIOs (LED sequence and button read).
 */
esp_err_t ui_controller_selftest(void);

#ifdef __cplusplus
}
#endif

#endif /* UI_CONTROLLER_H */
