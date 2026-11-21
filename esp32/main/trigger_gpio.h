/**
 * @file trigger_gpio.h
 * @brief Falling-edge GPIO 32 hardware trigger driver for Cora Z7 PMOD JA1.
 *
 * Configures GPIO 32 with an internal pull-up and a falling-edge ISR
 * (GPIO_INTR_NEGEDGE) that notifies the SPI TX task via xTaskNotifyFromISR()
 * while enforcing a configurable lockout window against pulse bounce.
 */

#ifndef TRIGGER_GPIO_H
#define TRIGGER_GPIO_H

#include <stdint.h>
#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Dedicated hardware trigger input pin (Cora Z7 PMOD JA1 active-low pulse). */
#define TRIGGER_GPIO_PIN 32

/**
 * @brief Initialize GPIO 32 falling-edge interrupt and bind target FreeRTOS task.
 *
 * Uses zero dynamic allocation. Safe to call after RTOS scheduler start from
 * the SPI TX task (passing xTaskGetCurrentTaskHandle()).
 *
 * @param target_task FreeRTOS task handle notified on accepted falling edge
 * @param lockout_ms  Minimum elapsed time (ms) between accepted trigger edges
 * @return esp_err_t  ESP_OK on success, error code otherwise
 */
esp_err_t trigger_gpio_init(TaskHandle_t target_task, uint32_t lockout_ms);

/**
 * @brief Return total number of accepted GPIO 32 falling-edge triggers.
 *
 * @return uint32_t Accepted trigger count since initialization
 */
uint32_t trigger_gpio_get_count(void);

/**
 * @brief Read current logic level of GPIO 32 (1 = idle high, 0 = active low).
 *
 * @return int Current GPIO 32 input level (0 or 1)
 */
int trigger_gpio_get_level(void);

/**
 * @brief Detach the GPIO 32 ISR handler and disable interrupts on the pin.
 */
void trigger_gpio_deinit(void);

#ifdef __cplusplus
}
#endif

#endif /* TRIGGER_GPIO_H */
