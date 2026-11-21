/**
 * @file trigger_gpio.c
 * @brief ISR-driven falling-edge hardware trigger on GPIO 32 with lockout.
 */

#include "trigger_gpio.h"
#include "driver/gpio.h"
#include "esp_attr.h"
#include "esp_log.h"
#include "esp_timer.h"

static const char *TAG = "TRIGGER_GPIO";

static TaskHandle_t s_target_task = NULL;
static int64_t s_lockout_us = 0;
static volatile int64_t s_last_trigger_us = -1;
static volatile uint32_t s_trigger_count = 0;
static bool s_initialized = false;

static void IRAM_ATTR trigger_gpio_isr_handler(void *arg) {
    (void)arg;

    int64_t now_us = esp_timer_get_time();
    int64_t last_us = s_last_trigger_us;

    if ((last_us < 0) || ((now_us - last_us) >= s_lockout_us)) {
        s_last_trigger_us = now_us;
        uint32_t next_count = s_trigger_count + 1U;
        s_trigger_count = next_count;

        TaskHandle_t task = s_target_task;
        if (task != NULL) {
            BaseType_t higher_prio_woken = pdFALSE;
            xTaskNotifyFromISR(task, 0U, eIncrement, &higher_prio_woken);
            portYIELD_FROM_ISR(higher_prio_woken);
        }
    }
}

esp_err_t trigger_gpio_init(TaskHandle_t target_task, uint32_t lockout_ms) {
    if (target_task == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    if (s_initialized) {
        ESP_LOGW(TAG, "GPIO %d trigger already initialized.", TRIGGER_GPIO_PIN);
        return ESP_OK;
    }

    s_target_task = target_task;
    s_lockout_us = (int64_t)lockout_ms * 1000LL;
    s_last_trigger_us = -1;
    s_trigger_count = 0;

    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << TRIGGER_GPIO_PIN),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };

    esp_err_t err = gpio_config(&io_conf);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "gpio_config failed: %s", esp_err_to_name(err));
        return err;
    }

    err = gpio_install_isr_service(0);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "gpio_install_isr_service failed: %s", esp_err_to_name(err));
        return err;
    }

    err = gpio_isr_handler_add((gpio_num_t)TRIGGER_GPIO_PIN, trigger_gpio_isr_handler, NULL);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "gpio_isr_handler_add failed: %s", esp_err_to_name(err));
        return err;
    }

    err = gpio_set_intr_type((gpio_num_t)TRIGGER_GPIO_PIN, GPIO_INTR_NEGEDGE);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "gpio_set_intr_type failed: %s", esp_err_to_name(err));
        gpio_isr_handler_remove((gpio_num_t)TRIGGER_GPIO_PIN);
        return err;
    }

    s_initialized = true;
    ESP_LOGI(TAG, "Armed GPIO %d (NEGEDGE, internal pull-up, lockout=%lu ms, level=%d)",
             TRIGGER_GPIO_PIN,
             (unsigned long)lockout_ms,
             gpio_get_level((gpio_num_t)TRIGGER_GPIO_PIN));
    return ESP_OK;
}

uint32_t trigger_gpio_get_count(void) {
    return s_trigger_count;
}

int trigger_gpio_get_level(void) {
    return gpio_get_level((gpio_num_t)TRIGGER_GPIO_PIN);
}

void trigger_gpio_deinit(void) {
    if (!s_initialized) {
        return;
    }
    gpio_intr_disable((gpio_num_t)TRIGGER_GPIO_PIN);
    gpio_isr_handler_remove((gpio_num_t)TRIGGER_GPIO_PIN);
    s_target_task = NULL;
    s_initialized = false;
}
