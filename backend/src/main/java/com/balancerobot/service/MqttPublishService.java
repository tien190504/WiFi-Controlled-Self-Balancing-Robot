package com.balancerobot.service;

import com.balancerobot.entity.PidProfile;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.eclipse.paho.client.mqttv3.MqttClient;
import org.eclipse.paho.client.mqttv3.MqttMessage;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.Map;

@Service
@Slf4j
@RequiredArgsConstructor
public class MqttPublishService {

    private final ObjectMapper objectMapper;

    @Value("${mqtt.topics.pid-angle}")
    private String pidAngleTopic;

    @Value("${mqtt.topics.pid-speed}")
    private String pidSpeedTopic;

    private MqttClient mqttClient;

    public void setMqttClient(MqttClient client) {
        this.mqttClient = client;
    }

    public void publishPidProfile(PidProfile profile) {
        try {
            String angleTopic = topicForProfile(pidAngleTopic, profile);
            String speedTopic = topicForProfile(pidSpeedTopic, profile);

            // Publish angle PID
            String angleJson = objectMapper.writeValueAsString(Map.of(
                    "P", profile.getAngleP(),
                    "I", profile.getAngleI(),
                    "D", profile.getAngleD()));
            publish(angleTopic, angleJson);

            // Publish speed PID
            String speedJson = objectMapper.writeValueAsString(Map.of(
                    "P", profile.getSpeedP(),
                    "I", profile.getSpeedI(),
                    "D", profile.getSpeedD()));
            publish(speedTopic, speedJson);

            log.info("Published PID profile '{}' to robot", profile.getName());
        } catch (Exception e) {
            log.error("Failed to publish PID profile: {}", e.getMessage());
        }
    }

    public void publish(String topic, String payload) {
        if (mqttClient == null || !mqttClient.isConnected()) {
            log.warn("MQTT client not connected, cannot publish to {}. Message will be lost.", topic);
            return;
        }
        try {
            MqttMessage msg = new MqttMessage(payload.getBytes());
            msg.setQos(0);
            mqttClient.publish(topic, msg);
            log.debug("Published to {}: {}", topic, payload);
        } catch (Exception e) {
            log.error("MQTT publish error on {}: {} - {}", topic, e.getClass().getSimpleName(), e.getMessage());
        }
    }

    private String topicForProfile(String baseTopic, PidProfile profile) {
        if (profile.getDevice() == null || profile.getDevice().getDeviceId() == null
                || profile.getDevice().getDeviceId().isBlank()) {
            return baseTopic;
        }
        return baseTopic + "/" + profile.getDevice().getDeviceId();
    }
}
