#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "driver/gpio.h"
#include "esp_err.h"

typedef struct {
    gpio_num_t left_step_pin;
    gpio_num_t left_dir_pin;
    gpio_num_t right_step_pin;
    gpio_num_t right_dir_pin;
    gpio_num_t enable_pin;
    uint32_t min_frequency_hz;
    uint32_t max_frequency_hz;
    bool invert_left_direction;
    bool invert_right_direction;
} motor_driver_config_t;

esp_err_t motor_driver_init(const motor_driver_config_t *config);
void motor_driver_set_output(float left_norm, float right_norm);
void motor_driver_stop(void);
