#pragma once

#include "esp_err.h"
#include "mqtt_client.h"

#include "robot_app.h"

esp_err_t telemetry_publish_state_angle(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    float angle_deg);
esp_err_t telemetry_publish_state_speed(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    float speed_percent);
esp_err_t telemetry_publish_state_sensors(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    float roll_deg,
    float pitch_deg,
    float z_value);
esp_err_t telemetry_publish_state_full(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    float angle_deg,
    float speed_percent,
    float roll_deg,
    float pitch_deg,
    float z_value);
esp_err_t telemetry_publish_heartbeat(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    int wifi_rssi);
esp_err_t telemetry_publish_event(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    const robot_event_message_t *event);
