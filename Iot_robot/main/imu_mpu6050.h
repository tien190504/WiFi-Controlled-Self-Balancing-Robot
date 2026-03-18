#pragma once

#include "driver/gpio.h"
#include "driver/i2c.h"
#include "esp_err.h"

typedef struct {
    i2c_port_t port;
    gpio_num_t sda_pin;
    gpio_num_t scl_pin;
    uint32_t clock_speed_hz;
    float complementary_alpha;
} imu_mpu6050_config_t;

typedef struct {
    float pitch_deg;
    float roll_deg;
    float accel_x_g;
    float accel_y_g;
    float accel_z_g;
    float gyro_x_dps;
    float gyro_y_dps;
    float gyro_z_dps;
} imu_mpu6050_sample_t;

esp_err_t imu_mpu6050_init(const imu_mpu6050_config_t *config);
esp_err_t imu_mpu6050_calibrate(uint32_t duration_ms);
esp_err_t imu_mpu6050_update(float dt_seconds, imu_mpu6050_sample_t *sample);
