#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "robot_app.h"

typedef struct {
    float max_tilt_deg;
    float rearm_tilt_deg;
    uint32_t rearm_hold_ms;
    float max_target_angle_deg;
    float max_turn_bias;
    float output_limit;
} balance_controller_config_t;

typedef struct {
    float pitch_deg;
    float drive_command;
    float turn_command;
    bool command_fresh;
    float dt_s;
    int64_t now_us;
} balance_controller_input_t;

typedef struct {
    balance_controller_config_t config;
    robot_pid_gains_t angle_pid;
    robot_pid_gains_t speed_pid_reserved;
    float integral;
    float previous_error;
    bool armed;
    bool fall_latched;
    int64_t rearm_started_us;
} balance_controller_t;

void balance_controller_init(
    balance_controller_t *controller,
    const balance_controller_config_t *config,
    const robot_pid_gains_t *initial_angle_pid,
    const robot_pid_gains_t *initial_speed_pid);
void balance_controller_set_angle_pid(balance_controller_t *controller, const robot_pid_gains_t *pid);
void balance_controller_set_speed_pid(balance_controller_t *controller, const robot_pid_gains_t *pid);
void balance_controller_reset(balance_controller_t *controller);
void balance_controller_update(
    balance_controller_t *controller,
    const balance_controller_input_t *input,
    robot_motor_output_t *output);
