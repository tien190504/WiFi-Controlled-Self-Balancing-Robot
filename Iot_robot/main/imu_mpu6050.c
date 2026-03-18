#include "imu_mpu6050.h"

#include <math.h>
#include <stdbool.h>

#include "esp_check.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define MPU6050_ADDRESS 0x68
#define MPU6050_PWR_MGMT_1 0x6B
#define MPU6050_GYRO_CONFIG 0x1B
#define MPU6050_ACCEL_CONFIG 0x1C
#define MPU6050_ACCEL_XOUT_H 0x3B
#define MPU6050_I2C_TIMEOUT_MS 100
#define MPU6050_ACCEL_SCALE 16384.0f
#define MPU6050_GYRO_SCALE 131.0f
#define RAD_TO_DEG 57.2957795f

static const char *TAG = "imu_mpu6050";

static imu_mpu6050_config_t s_config;
static bool s_initialized;
static float s_pitch_deg;
static float s_roll_deg;
static float s_gyro_x_bias;
static float s_gyro_y_bias;
static float s_gyro_z_bias;

static esp_err_t write_register(uint8_t reg, uint8_t value)
{
    const uint8_t payload[2] = { reg, value };
    return i2c_master_write_to_device(
        s_config.port,
        MPU6050_ADDRESS,
        payload,
        sizeof(payload),
        pdMS_TO_TICKS(MPU6050_I2C_TIMEOUT_MS));
}

static esp_err_t read_registers(uint8_t start_reg, uint8_t *buffer, size_t length)
{
    return i2c_master_write_read_device(
        s_config.port,
        MPU6050_ADDRESS,
        &start_reg,
        sizeof(start_reg),
        buffer,
        length,
        pdMS_TO_TICKS(MPU6050_I2C_TIMEOUT_MS));
}

esp_err_t imu_mpu6050_init(const imu_mpu6050_config_t *config)
{
    ESP_RETURN_ON_FALSE(config != NULL, ESP_ERR_INVALID_ARG, TAG, "config is required");

    s_config = *config;
    s_pitch_deg = 0.0f;
    s_roll_deg = 0.0f;
    s_gyro_x_bias = 0.0f;
    s_gyro_y_bias = 0.0f;
    s_gyro_z_bias = 0.0f;

    i2c_config_t i2c_config = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = s_config.sda_pin,
        .scl_io_num = s_config.scl_pin,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = s_config.clock_speed_hz,
        .clk_flags = 0,
    };

    esp_err_t err = i2c_param_config(s_config.port, &i2c_config);
    if (err != ESP_OK) {
        return err;
    }

    err = i2c_driver_install(s_config.port, i2c_config.mode, 0, 0, 0);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return err;
    }

    ESP_RETURN_ON_ERROR(write_register(MPU6050_PWR_MGMT_1, 0x00), TAG, "failed to wake sensor");
    ESP_RETURN_ON_ERROR(write_register(MPU6050_ACCEL_CONFIG, 0x00), TAG, "failed to config accel");
    ESP_RETURN_ON_ERROR(write_register(MPU6050_GYRO_CONFIG, 0x00), TAG, "failed to config gyro");

    s_initialized = true;
    ESP_LOGI(TAG, "MPU6050 initialized on I2C port %d", s_config.port);
    return ESP_OK;
}

esp_err_t imu_mpu6050_calibrate(uint32_t duration_ms)
{
    ESP_RETURN_ON_FALSE(s_initialized, ESP_ERR_INVALID_STATE, TAG, "sensor not initialized");

    const uint32_t samples = duration_ms / 5U;
    if (samples == 0U) {
        return ESP_ERR_INVALID_ARG;
    }

    float gyro_x_sum = 0.0f;
    float gyro_y_sum = 0.0f;
    float gyro_z_sum = 0.0f;
    uint8_t raw[14];

    for (uint32_t i = 0; i < samples; ++i) {
        ESP_RETURN_ON_ERROR(read_registers(MPU6050_ACCEL_XOUT_H, raw, sizeof(raw)), TAG, "gyro calibration read failed");

        const int16_t gyro_x_raw = (int16_t)((raw[8] << 8) | raw[9]);
        const int16_t gyro_y_raw = (int16_t)((raw[10] << 8) | raw[11]);
        const int16_t gyro_z_raw = (int16_t)((raw[12] << 8) | raw[13]);

        gyro_x_sum += ((float)gyro_x_raw / MPU6050_GYRO_SCALE);
        gyro_y_sum += ((float)gyro_y_raw / MPU6050_GYRO_SCALE);
        gyro_z_sum += ((float)gyro_z_raw / MPU6050_GYRO_SCALE);
        vTaskDelay(pdMS_TO_TICKS(5));
    }

    s_gyro_x_bias = gyro_x_sum / (float)samples;
    s_gyro_y_bias = gyro_y_sum / (float)samples;
    s_gyro_z_bias = gyro_z_sum / (float)samples;

    ESP_LOGI(TAG, "Calibration complete: gx=%.3f gy=%.3f gz=%.3f",
             (double)s_gyro_x_bias,
             (double)s_gyro_y_bias,
             (double)s_gyro_z_bias);
    return ESP_OK;
}

esp_err_t imu_mpu6050_update(float dt_seconds, imu_mpu6050_sample_t *sample)
{
    ESP_RETURN_ON_FALSE(s_initialized, ESP_ERR_INVALID_STATE, TAG, "sensor not initialized");
    ESP_RETURN_ON_FALSE(sample != NULL, ESP_ERR_INVALID_ARG, TAG, "sample is required");
    ESP_RETURN_ON_FALSE(dt_seconds > 0.0f, ESP_ERR_INVALID_ARG, TAG, "dt must be positive");

    uint8_t raw[14];
    ESP_RETURN_ON_ERROR(read_registers(MPU6050_ACCEL_XOUT_H, raw, sizeof(raw)), TAG, "sensor read failed");

    const int16_t accel_x_raw = (int16_t)((raw[0] << 8) | raw[1]);
    const int16_t accel_y_raw = (int16_t)((raw[2] << 8) | raw[3]);
    const int16_t accel_z_raw = (int16_t)((raw[4] << 8) | raw[5]);
    const int16_t gyro_x_raw = (int16_t)((raw[8] << 8) | raw[9]);
    const int16_t gyro_y_raw = (int16_t)((raw[10] << 8) | raw[11]);
    const int16_t gyro_z_raw = (int16_t)((raw[12] << 8) | raw[13]);

    const float accel_x_g = (float)accel_x_raw / MPU6050_ACCEL_SCALE;
    const float accel_y_g = (float)accel_y_raw / MPU6050_ACCEL_SCALE;
    const float accel_z_g = (float)accel_z_raw / MPU6050_ACCEL_SCALE;

    const float gyro_x_dps = ((float)gyro_x_raw / MPU6050_GYRO_SCALE) - s_gyro_x_bias;
    const float gyro_y_dps = ((float)gyro_y_raw / MPU6050_GYRO_SCALE) - s_gyro_y_bias;
    const float gyro_z_dps = ((float)gyro_z_raw / MPU6050_GYRO_SCALE) - s_gyro_z_bias;

    const float accel_pitch_deg = atan2f(accel_y_g, sqrtf((accel_x_g * accel_x_g) + (accel_z_g * accel_z_g))) * RAD_TO_DEG;
    const float accel_roll_deg = atan2f(-accel_x_g, accel_z_g) * RAD_TO_DEG;

    s_pitch_deg = (s_config.complementary_alpha * (s_pitch_deg + (gyro_x_dps * dt_seconds))) +
                  ((1.0f - s_config.complementary_alpha) * accel_pitch_deg);
    s_roll_deg = (s_config.complementary_alpha * (s_roll_deg + (gyro_y_dps * dt_seconds))) +
                 ((1.0f - s_config.complementary_alpha) * accel_roll_deg);

    sample->pitch_deg = s_pitch_deg;
    sample->roll_deg = s_roll_deg;
    sample->accel_x_g = accel_x_g;
    sample->accel_y_g = accel_y_g;
    sample->accel_z_g = accel_z_g;
    sample->gyro_x_dps = gyro_x_dps;
    sample->gyro_y_dps = gyro_y_dps;
    sample->gyro_z_dps = gyro_z_dps;

    return ESP_OK;
}
