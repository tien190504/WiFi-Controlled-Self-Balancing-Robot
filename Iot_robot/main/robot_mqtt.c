#include "robot_mqtt.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_event.h"
#include "esp_idf_version.h"
#include "esp_log.h"

static const char *TAG = "robot_mqtt";

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

static void handle_control_message(robot_mqtt_client_t *client, cJSON *json)
{
    cJSON *speed = cJSON_GetObjectItemCaseSensitive(json, "speed");
    cJSON *turn = cJSON_GetObjectItemCaseSensitive(json, "turn");
    if (!cJSON_IsNumber(speed) || !cJSON_IsNumber(turn) || client->config.command_callback == NULL) {
        return;
    }

    client->config.command_callback(
        clampf((float)speed->valuedouble, -1.0f, 1.0f),
        clampf((float)turn->valuedouble, -1.0f, 1.0f),
        client->config.context);
}

static void handle_pid_message(robot_mqtt_client_t *client, cJSON *json, bool angle_pid)
{
    if (client->config.pid_callback == NULL) {
        return;
    }

    cJSON *p = cJSON_GetObjectItemCaseSensitive(json, "P");
    cJSON *i = cJSON_GetObjectItemCaseSensitive(json, "I");
    cJSON *d = cJSON_GetObjectItemCaseSensitive(json, "D");
    if (!cJSON_IsNumber(p) || !cJSON_IsNumber(i) || !cJSON_IsNumber(d)) {
        return;
    }

    robot_pid_gains_t gains = {
        .p = (float)p->valuedouble,
        .i = (float)i->valuedouble,
        .d = (float)d->valuedouble,
    };
    client->config.pid_callback(angle_pid, &gains, client->config.context);
}

static void mqtt_event_handler(void *handler_args, esp_event_base_t base, int32_t event_id, void *event_data)
{
    (void)base;
    robot_mqtt_client_t *client = (robot_mqtt_client_t *)handler_args;
    esp_mqtt_event_handle_t event = event_data;

    switch ((esp_mqtt_event_id_t)event_id) {
    case MQTT_EVENT_CONNECTED:
        client->connected = true;
        esp_mqtt_client_subscribe(client->client, client->config.topics->control_move, 0);
        esp_mqtt_client_subscribe(client->client, client->config.topics->pid_angle, 0);
        esp_mqtt_client_subscribe(client->client, client->config.topics->pid_speed, 0);
        if (client->config.connection_callback != NULL) {
            client->config.connection_callback(true, client->config.context);
        }
        ESP_LOGI(TAG, "MQTT connected");
        break;

    case MQTT_EVENT_DISCONNECTED:
        client->connected = false;
        if (client->config.connection_callback != NULL) {
            client->config.connection_callback(false, client->config.context);
        }
        ESP_LOGW(TAG, "MQTT disconnected");
        break;

    case MQTT_EVENT_DATA: {
        char *topic = calloc((size_t)event->topic_len + 1U, sizeof(char));
        char *payload = calloc((size_t)event->data_len + 1U, sizeof(char));
        if (topic == NULL || payload == NULL) {
            free(topic);
            free(payload);
            return;
        }

        memcpy(topic, event->topic, (size_t)event->topic_len);
        memcpy(payload, event->data, (size_t)event->data_len);

        cJSON *json = cJSON_Parse(payload);
        if (json != NULL) {
            if (strcmp(topic, client->config.topics->control_move) == 0) {
                handle_control_message(client, json);
            } else if (strcmp(topic, client->config.topics->pid_angle) == 0) {
                handle_pid_message(client, json, true);
            } else if (strcmp(topic, client->config.topics->pid_speed) == 0) {
                handle_pid_message(client, json, false);
            }
            cJSON_Delete(json);
        }

        free(topic);
        free(payload);
        break;
    }

    case MQTT_EVENT_ERROR:
        ESP_LOGW(TAG, "MQTT error event received");
        break;

    default:
        break;
    }
}

esp_err_t robot_mqtt_init(robot_mqtt_client_t *client, const robot_mqtt_config_t *config)
{
    if (client == NULL || config == NULL || config->host == NULL || config->topics == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    memset(client, 0, sizeof(*client));
    client->config = *config;
    snprintf(client->broker_uri, sizeof(client->broker_uri), "mqtt://%s:%u", config->host, config->port);
    return ESP_OK;
}

esp_err_t robot_mqtt_start(robot_mqtt_client_t *client)
{
    if (client == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    if (client->client != NULL) {
        return ESP_OK;
    }

    esp_mqtt_client_config_t mqtt_config = { 0 };
#if ESP_IDF_VERSION_MAJOR >= 5
    mqtt_config.broker.address.uri = client->broker_uri;
    mqtt_config.session.keepalive = 30;
    mqtt_config.network.reconnect_timeout_ms = 5000;
#else
    mqtt_config.uri = client->broker_uri;
    mqtt_config.keepalive = 30;
#endif

    client->client = esp_mqtt_client_init(&mqtt_config);
    if (client->client == NULL) {
        return ESP_ERR_NO_MEM;
    }

    ESP_ERROR_CHECK(esp_mqtt_client_register_event(
        client->client,
        ESP_EVENT_ANY_ID,
        mqtt_event_handler,
        client));

    return esp_mqtt_client_start(client->client);
}

void robot_mqtt_stop(robot_mqtt_client_t *client)
{
    if (client == NULL || client->client == NULL) {
        return;
    }

    esp_mqtt_client_stop(client->client);
    esp_mqtt_client_destroy(client->client);
    client->client = NULL;
    client->connected = false;
}

bool robot_mqtt_is_connected(const robot_mqtt_client_t *client)
{
    return client != NULL && client->connected;
}

esp_mqtt_client_handle_t robot_mqtt_handle(const robot_mqtt_client_t *client)
{
    return client != NULL ? client->client : NULL;
}
