/**
 * @file ui_controller.h
 * @brief Minimalist Autonomous User Interface (Single Button & RGB LED) for ESP32.
 *
 * Designed for space-constrained breadboards. Uses:
 *  - GPIO 32: Trigger button (Active-Low with internal pull-up to GND)
 *  - GPIO 21: RGB LED Green channel (Activity / Heartbeat / Success)
 *  - GPIO 22: RGB LED Red channel (Alert / Error)
 *  - GPIO 2:  Onboard Blue LED (optional mirror of Green heartbeat)
 *
 * Debouncing is handled in FreeRTOS without dynamic memory allocation.
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
#define UI_GPIO_BTN_TRIGGER     32  /* Pushbutton: Trigger Full Test Suite (Active-Low, internal pull-up) */

#define UI_GPIO_LED_GREEN       21  /* RGB LED Green Channel: Heartbeat / Busy / Success */
#define UI_GPIO_LED_RED         22  /* RGB LED Red Channel: Alert / Critical Error */
#define UI_GPIO_LED_READY       2   /* Onboard Blue LED: Ready Heartbeat mirror */

/* Polarity: 1 for Common Cathode (active HIGH), 0 for Common Anode (active LOW) */
#ifndef UI_LED_ACTIVE_LEVEL
#define UI_LED_ACTIVE_LEVEL     0
#endif

/* ========================================================================= */
/* Visual Telemetry States & Events                                          */
/* ========================================================================= */
typedef enum {
    UI_STATE_IDLE,      /* Green Heartbeat (1 Hz), Red OFF */
    UI_STATE_BUSY,      /* Green Solid ON during burst TX, Red OFF */
    UI_STATE_SUCCESS,   /* Green 3 rapid blinks upon suite completion, Red OFF */
    UI_STATE_ERROR      /* Red 5 Hz rapid blink or Solid ON, Green OFF */
} ui_state_t;

typedef enum {
    UI_EVENT_TRIGGER_PRESSED,
} ui_event_type_t;

typedef struct {
    ui_event_type_t type;
    uint32_t timestamp_ms;
} ui_event_t;

/* ========================================================================= */
/* Public API                                                                */
/* ========================================================================= */

/**
 * @brief Initialize GPIOs for button and LEDs, and launch the FreeRTOS UI FSM task.
 *
 * @param out_queue Pointer to queue handle receiving UI trigger events
 * @return esp_err_t ESP_OK on success
 */
esp_err_t ui_controller_init(QueueHandle_t *out_queue);

/**
 * @brief Set the visual telemetry state (LED color and flashing pattern).
 */
void ui_controller_set_state(ui_state_t state);

/**
 * @brief Get the current visual telemetry state.
 */
ui_state_t ui_controller_get_state(void);

/**
 * @brief Convert state enum to human-readable string.
 */
const char *ui_state_to_name(ui_state_t state);

/**
 * @brief Run a self-test of all UI GPIOs (LED sequence and button read).
 */
esp_err_t ui_controller_selftest(void);

#ifdef __cplusplus
}
#endif

#endif /* UI_CONTROLLER_H */
