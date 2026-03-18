#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "mqtt_client.h"

#include "robot_app.h"

typedef void (*robot_mqtt_command_callback_t)(float speed, float turn, void *context);
typedef void (*robot_mqtt_pid_callback_t)(bool angle_pid, const robot_pid_gains_t *pid, void *context);
typedef void (*robot_mqtt_connection_callback_t)(bool connected, void *context);

typedef struct {
    const char *host;
    uint16_t port;
    const robot_topics_t *topics;
    robot_mqtt_command_callback_t command_callback;
    robot_mqtt_pid_callback_t pid_callback;
    robot_mqtt_connection_callback_t connection_callback;
    void *context;
} robot_mqtt_config_t;

typedef struct {
    esp_mqtt_client_handle_t client;
    robot_mqtt_config_t config;
    bool connected;
    char broker_uri[128];
} robot_mqtt_client_t;

esp_err_t robot_mqtt_init(robot_mqtt_client_t *client, const robot_mqtt_config_t *config);
esp_err_t robot_mqtt_start(robot_mqtt_client_t *client);
void robot_mqtt_stop(robot_mqtt_client_t *client);
bool robot_mqtt_is_connected(const robot_mqtt_client_t *client);
esp_mqtt_client_handle_t robot_mqtt_handle(const robot_mqtt_client_t *client);
