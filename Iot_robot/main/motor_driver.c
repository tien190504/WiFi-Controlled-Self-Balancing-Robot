#include "motor_driver.h"

#include <math.h>
#include <stdbool.h>

#include "driver/ledc.h"
#include "esp_check.h"
#include "esp_log.h"

#define MOTOR_PWM_MODE LEDC_LOW_SPEED_MODE
#define MOTOR_DUTY_RES LEDC_TIMER_10_BIT
#define MOTOR_DUTY_50_PERCENT 512
#define MOTOR_COMMAND_DEADBAND 0.02f

static const char *TAG = "motor_driver";

static motor_driver_config_t s_config;
static bool s_initialized;

static const ledc_timer_t LEFT_TIMER = LEDC_TIMER_0;
static const ledc_timer_t RIGHT_TIMER = LEDC_TIMER_1;
static const ledc_channel_t LEFT_CHANNEL = LEDC_CHANNEL_0;
static const ledc_channel_t RIGHT_CHANNEL = LEDC_CHANNEL_1;

static void configure_motor_channel(ledc_timer_t timer, ledc_channel_t channel, gpio_num_t gpio, uint32_t freq_hz)
{
    ledc_timer_config_t timer_config = {
        .speed_mode = MOTOR_PWM_MODE,
        .duty_resolution = MOTOR_DUTY_RES,
        .timer_num = timer,
        .freq_hz = freq_hz,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer_config));

    ledc_channel_config_t channel_config = {
        .gpio_num = gpio,
        .speed_mode = MOTOR_PWM_MODE,
        .channel = channel,
        .intr_type = LEDC_INTR_DISABLE,
        .timer_sel = timer,
        .duty = 0,
        .hpoint = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&channel_config));
}

static void set_single_motor(float normalized, gpio_num_t dir_pin, ledc_timer_t timer, ledc_channel_t channel)
{
    const float magnitude = fabsf(normalized);
    if (magnitude < MOTOR_COMMAND_DEADBAND) {
        ledc_set_duty(MOTOR_PWM_MODE, channel, 0);
        ledc_update_duty(MOTOR_PWM_MODE, channel);
        return;
    }

    const uint32_t freq = s_config.min_frequency_hz +
        (uint32_t)((s_config.max_frequency_hz - s_config.min_frequency_hz) * fminf(magnitude, 1.0f));
    gpio_set_level(dir_pin, normalized >= 0.0f ? 1 : 0);
    ledc_set_freq(MOTOR_PWM_MODE, timer, freq);
    ledc_set_duty(MOTOR_PWM_MODE, channel, MOTOR_DUTY_50_PERCENT);
    ledc_update_duty(MOTOR_PWM_MODE, channel);
}

esp_err_t motor_driver_init(const motor_driver_config_t *config)
{
    ESP_RETURN_ON_FALSE(config != NULL, ESP_ERR_INVALID_ARG, TAG, "config is required");
    ESP_RETURN_ON_FALSE(config->min_frequency_hz < config->max_frequency_hz, ESP_ERR_INVALID_ARG, TAG, "invalid frequency range");

    s_config = *config;

    const gpio_config_t output_config = {
        .pin_bit_mask = (1ULL << s_config.left_dir_pin) |
                        (1ULL << s_config.right_dir_pin) |
                        (1ULL << s_config.enable_pin),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    ESP_RETURN_ON_ERROR(gpio_config(&output_config), TAG, "gpio config failed");

    configure_motor_channel(LEFT_TIMER, LEFT_CHANNEL, s_config.left_step_pin, s_config.min_frequency_hz);
    configure_motor_channel(RIGHT_TIMER, RIGHT_CHANNEL, s_config.right_step_pin, s_config.min_frequency_hz);

    gpio_set_level(s_config.left_dir_pin, 0);
    gpio_set_level(s_config.right_dir_pin, 0);
    gpio_set_level(s_config.enable_pin, 1);

    s_initialized = true;
    ESP_LOGI(TAG, "Motor driver initialized");
    return ESP_OK;
}

void motor_driver_set_output(float left_norm, float right_norm)
{
    if (!s_initialized) {
        return;
    }

    if (s_config.invert_left_direction) {
        left_norm = -left_norm;
    }
    if (s_config.invert_right_direction) {
        right_norm = -right_norm;
    }

    const bool left_active = fabsf(left_norm) >= MOTOR_COMMAND_DEADBAND;
    const bool right_active = fabsf(right_norm) >= MOTOR_COMMAND_DEADBAND;
    gpio_set_level(s_config.enable_pin, (left_active || right_active) ? 0 : 1);

    set_single_motor(left_norm, s_config.left_dir_pin, LEFT_TIMER, LEFT_CHANNEL);
    set_single_motor(right_norm, s_config.right_dir_pin, RIGHT_TIMER, RIGHT_CHANNEL);
}

void motor_driver_stop(void)
{
    if (!s_initialized) {
        return;
    }

    ledc_set_duty(MOTOR_PWM_MODE, LEFT_CHANNEL, 0);
    ledc_update_duty(MOTOR_PWM_MODE, LEFT_CHANNEL);
    ledc_set_duty(MOTOR_PWM_MODE, RIGHT_CHANNEL, 0);
    ledc_update_duty(MOTOR_PWM_MODE, RIGHT_CHANNEL);
    gpio_set_level(s_config.enable_pin, 1);
}
