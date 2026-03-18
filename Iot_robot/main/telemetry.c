#include "telemetry.h"

#include <stdbool.h>

#include "cJSON.h"

static esp_err_t publish_json(esp_mqtt_client_handle_t client, const char *topic, cJSON *json)
{
    if (client == NULL || topic == NULL || json == NULL) {
        cJSON_Delete(json);
        return ESP_ERR_INVALID_ARG;
    }

    char *payload = cJSON_PrintUnformatted(json);
    cJSON_Delete(json);
    if (payload == NULL) {
        return ESP_ERR_NO_MEM;
    }

    const int msg_id = esp_mqtt_client_publish(client, topic, payload, 0, 0, false);
    cJSON_free(payload);
    return (msg_id >= 0) ? ESP_OK : ESP_FAIL;
}

static cJSON *create_base_payload(const char *device_id)
{
    cJSON *json = cJSON_CreateObject();
    if (json == NULL) {
        return NULL;
    }

    if (!cJSON_AddStringToObject(json, "deviceId", device_id)) {
        cJSON_Delete(json);
        return NULL;
    }

    return json;
}

esp_err_t telemetry_publish_state_angle(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    float angle_deg)
{
    cJSON *json = create_base_payload(device_id);
    if (json == NULL) {
        return ESP_ERR_NO_MEM;
    }
    cJSON_AddNumberToObject(json, "angle", angle_deg);
    return publish_json(client, topic, json);
}

esp_err_t telemetry_publish_state_speed(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    float speed_percent)
{
    cJSON *json = create_base_payload(device_id);
    if (json == NULL) {
        return ESP_ERR_NO_MEM;
    }
    cJSON_AddNumberToObject(json, "speed", speed_percent);
    return publish_json(client, topic, json);
}

esp_err_t telemetry_publish_state_sensors(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    float roll_deg,
    float pitch_deg,
    float z_value)
{
    cJSON *json = create_base_payload(device_id);
    if (json == NULL) {
        return ESP_ERR_NO_MEM;
    }
    cJSON_AddNumberToObject(json, "x", roll_deg);
    cJSON_AddNumberToObject(json, "y", pitch_deg);
    cJSON_AddNumberToObject(json, "z", z_value);
    return publish_json(client, topic, json);
}

esp_err_t telemetry_publish_state_full(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    float angle_deg,
    float speed_percent,
    float roll_deg,
    float pitch_deg,
    float z_value)
{
    cJSON *json = create_base_payload(device_id);
    if (json == NULL) {
        return ESP_ERR_NO_MEM;
    }
    cJSON_AddNumberToObject(json, "angle", angle_deg);
    cJSON_AddNumberToObject(json, "speed", speed_percent);
    cJSON_AddNumberToObject(json, "x", roll_deg);
    cJSON_AddNumberToObject(json, "y", pitch_deg);
    cJSON_AddNumberToObject(json, "z", z_value);
    return publish_json(client, topic, json);
}

esp_err_t telemetry_publish_heartbeat(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    int wifi_rssi)
{
    cJSON *json = create_base_payload(device_id);
    if (json == NULL) {
        return ESP_ERR_NO_MEM;
    }
    cJSON_AddStringToObject(json, "status", "ONLINE");
    cJSON_AddNumberToObject(json, "wifiRssi", wifi_rssi);
    return publish_json(client, topic, json);
}

esp_err_t telemetry_publish_event(
    esp_mqtt_client_handle_t client,
    const char *topic,
    const char *device_id,
    const robot_event_message_t *event)
{
    if (event == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    cJSON *json = create_base_payload(device_id);
    if (json == NULL) {
        return ESP_ERR_NO_MEM;
    }
    cJSON_AddStringToObject(json, "eventType", event->event_type);
    cJSON_AddStringToObject(json, "description", event->description);
    return publish_json(client, topic, json);
}
