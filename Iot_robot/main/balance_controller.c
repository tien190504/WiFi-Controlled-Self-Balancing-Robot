#include "balance_controller.h"

#include <math.h>
#include <string.h>

static float clampf(float value, float min_value, float max_value)
{
    if (value < min_value) {
        return min_value;
    }
    if (value > max_value) {
        return max_value;
    }
    return value;
}

void balance_controller_init(
    balance_controller_t *controller,
    const balance_controller_config_t *config,
    const robot_pid_gains_t *initial_angle_pid,
    const robot_pid_gains_t *initial_speed_pid)
{
    memset(controller, 0, sizeof(*controller));
    controller->config = *config;
    controller->angle_pid = *initial_angle_pid;
    controller->speed_pid_reserved = *initial_speed_pid;
    controller->armed = true;
}

void balance_controller_set_angle_pid(balance_controller_t *controller, const robot_pid_gains_t *pid)
{
    controller->angle_pid = *pid;
    controller->integral = 0.0f;
    controller->previous_error = 0.0f;
}

void balance_controller_set_speed_pid(balance_controller_t *controller, const robot_pid_gains_t *pid)
{
    controller->speed_pid_reserved = *pid;
}

void balance_controller_reset(balance_controller_t *controller)
{
    controller->integral = 0.0f;
    controller->previous_error = 0.0f;
    controller->rearm_started_us = 0;
}

void balance_controller_update(
    balance_controller_t *controller,
    const balance_controller_input_t *input,
    robot_motor_output_t *output)
{
    memset(output, 0, sizeof(*output));

    const float pitch = input->pitch_deg;
    const float drive_command = input->command_fresh ? clampf(input->drive_command, -1.0f, 1.0f) : 0.0f;
    const float turn_command = input->command_fresh ? clampf(input->turn_command, -1.0f, 1.0f) : 0.0f;

    if (fabsf(pitch) >= controller->config.max_tilt_deg) {
        if (!controller->fall_latched) {
            controller->fall_latched = true;
            controller->armed = false;
            controller->rearm_started_us = 0;
            controller->integral = 0.0f;
            controller->previous_error = 0.0f;
            output->fall_detected_now = true;
        }
    }

    if (controller->fall_latched) {
        if (fabsf(pitch) <= controller->config.rearm_tilt_deg) {
            if (controller->rearm_started_us == 0) {
                controller->rearm_started_us = input->now_us;
            } else if ((input->now_us - controller->rearm_started_us) >= ((int64_t)controller->config.rearm_hold_ms * 1000LL)) {
                controller->fall_latched = false;
                controller->armed = true;
                controller->rearm_started_us = 0;
                controller->integral = 0.0f;
                controller->previous_error = 0.0f;
                output->rearmed_now = true;
            }
        } else {
            controller->rearm_started_us = 0;
        }
    }

    if (!controller->armed || controller->fall_latched) {
        output->armed = false;
        output->fall_detected = controller->fall_latched;
        return;
    }

    const float target_angle_deg = drive_command * controller->config.max_target_angle_deg;
    const float error = target_angle_deg - pitch;
    const float dt_s = input->dt_s > 0.0f ? input->dt_s : 0.005f;

    const float integral_limit = controller->angle_pid.i > 0.001f
        ? controller->config.output_limit / controller->angle_pid.i
        : controller->config.output_limit;
    controller->integral = clampf(
        controller->integral + (error * dt_s),
        -integral_limit,
        integral_limit);

    const float derivative = (error - controller->previous_error) / dt_s;
    controller->previous_error = error;

    const float base_output =
        (controller->angle_pid.p * error) +
        (controller->angle_pid.i * controller->integral) +
        (controller->angle_pid.d * derivative);
    const float normalized_output = clampf(base_output / controller->config.output_limit, -1.0f, 1.0f);
    const float turn_bias = turn_command * controller->config.max_turn_bias;

    output->left_norm = clampf(normalized_output - turn_bias, -1.0f, 1.0f);
    output->right_norm = clampf(normalized_output + turn_bias, -1.0f, 1.0f);
    output->target_angle_deg = target_angle_deg;
    output->speed_percent = fmaxf(fabsf(output->left_norm), fabsf(output->right_norm)) * 100.0f;
    output->armed = true;
    output->fall_detected = false;
}
