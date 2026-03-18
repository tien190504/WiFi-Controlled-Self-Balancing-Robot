#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "mqtt_client.h"

typedef struct {
    float p;
    float i;
    float d;
} robot_pid_gains_t;

typedef struct {
    float pitch_deg;
    float roll_deg;
    float accel_x_g;
    float accel_y_g;
    float accel_z_g;
    float gyro_x_dps;
    float gyro_y_dps;
    float gyro_z_dps;
} robot_imu_state_t;

typedef struct {
    float speed;
    float turn;
    int64_t updated_at_us;
} robot_command_t;

typedef struct {
    float left_norm;
    float right_norm;
    float target_angle_deg;
    float speed_percent;
    bool armed;
    bool fall_detected;
    bool fall_detected_now;
    bool rearmed_now;
} robot_motor_output_t;

typedef struct {
    char control_move[96];
    char pid_angle[96];
    char pid_speed[96];
    char state_angle[96];
    char state_speed[96];
    char state_sensors[96];
    char state_full[96];
    char heartbeat[96];
    char event[96];
} robot_topics_t;

typedef struct {
    char event_type[32];
    char description[128];
} robot_event_message_t;

typedef struct {
    SemaphoreHandle_t lock;
    esp_mqtt_client_handle_t mqtt_client;
    robot_topics_t topics;
    robot_pid_gains_t angle_pid;
    robot_pid_gains_t speed_pid;
    robot_command_t command;
    robot_imu_state_t imu;
    float control_angle_deg;
    float target_angle_deg;
    float speed_percent;
    float left_output;
    float right_output;
    bool wifi_connected;
    bool mqtt_connected;
    bool imu_ready;
    bool controller_armed;
    bool fall_detected;
    int wifi_rssi;
} robot_app_state_t;
