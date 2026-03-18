package com.balancerobot.mqtt;

import com.balancerobot.entity.Device;
import com.balancerobot.entity.DeviceEvent;
import com.balancerobot.repository.DeviceEventRepository;
import com.balancerobot.repository.DeviceRepository;
import com.balancerobot.service.MqttPublishService;
import com.balancerobot.service.TelemetryService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.eclipse.paho.client.mqttv3.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.Optional;

@Component
@Slf4j
@RequiredArgsConstructor
public class MqttBridge implements MqttCallback {

    private final DeviceRepository deviceRepo;
    private final DeviceEventRepository eventRepo;
    private final TelemetryService telemetryService;
    private final MqttPublishService publishService;
    private final ObjectMapper objectMapper;

    @Value("${mqtt.broker.url}")
    private String brokerUrl;

    @Value("${mqtt.client.id}")
    private String clientId;

    @Value("${mqtt.topics.state-angle}")
    private String stateAngleTopic;

    @Value("${mqtt.topics.state-sensors}")
    private String stateSensorsTopic;

    @Value("${mqtt.topics.state-speed}")
    private String stateSpeedTopic;

    @Value("${mqtt.topics.state-full}")
    private String stateFullTopic;

    @Value("${mqtt.topics.heartbeat}")
    private String heartbeatTopic;

    @Value("${mqtt.topics.device-event}")
    private String deviceEventTopic;

    private MqttClient client;
    private static final int MAX_RETRY = 5;
    private static final long RETRY_DELAY_MS = 3000;

    /**
     * Use ApplicationReadyEvent instead of @PostConstruct to ensure
     * all beans and the application context are fully initialized,
     * and add retry logic for broker connectivity.
     */
    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady() {
        connectWithRetry();
    }

    private void connectWithRetry() {
        for (int attempt = 1; attempt <= MAX_RETRY; attempt++) {
            try {
                doConnect();
                if (client != null && client.isConnected()) {
                    log.info("MQTT Bridge connected to {} on attempt {}", brokerUrl, attempt);
                    return;
                }
            } catch (Exception e) {
                log.warn("MQTT connect attempt {}/{} failed: {}", attempt, MAX_RETRY, e.getMessage());
            }

            if (attempt < MAX_RETRY) {
                try {
                    Thread.sleep(RETRY_DELAY_MS * attempt); // exponential-ish backoff
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    return;
                }
            }
        }
        log.error("MQTT Bridge failed to connect after {} attempts. Will retry via scheduled task.", MAX_RETRY);
    }

    private void doConnect() throws MqttException {
        if (client != null && client.isConnected()) {
            return; // Already connected
        }

        client = new MqttClient(brokerUrl, clientId + "_" + System.currentTimeMillis());
        MqttConnectOptions opts = new MqttConnectOptions();
        opts.setAutomaticReconnect(true);
        opts.setCleanSession(true);
        opts.setConnectionTimeout(10);

        client.setCallback(this);
        client.connect(opts);

        client.subscribe(stateAngleTopic + "/#", 0);
        client.subscribe(stateSensorsTopic + "/#", 0);
        client.subscribe(stateSpeedTopic + "/#", 0);
        client.subscribe(stateFullTopic + "/#", 0);
        client.subscribe(heartbeatTopic + "/#", 0);
        client.subscribe(deviceEventTopic + "/#", 0);

        // Provide client to publish service
        publishService.setMqttClient(client);
    }

    @PreDestroy
    public void disconnect() {
        try {
            if (client != null && client.isConnected()) {
                client.disconnect();
            }
        } catch (Exception e) {
            log.error("Error disconnecting MQTT: {}", e.getMessage());
        }
    }

    @Override
    public void connectionLost(Throwable cause) {
        log.warn("MQTT connection lost: {}. Will attempt reconnection via scheduled task.", cause.getMessage());
    }

    @Override
    public void messageArrived(String topic, MqttMessage message) {
        try {
            String payload = new String(message.getPayload());
            JsonNode json = payload.isBlank() ? objectMapper.createObjectNode() : objectMapper.readTree(payload);

            String deviceIdStr = extractDeviceId(topic, json);
            if (deviceIdStr == null || deviceIdStr.isBlank())
                return;

            Optional<Device> deviceOpt = deviceRepo.findByDeviceId(deviceIdStr);
            if (deviceOpt.isEmpty())
                return;

            Device device = deviceOpt.get();
            refreshDevicePresence(device);

            if (topicMatches(topic, stateFullTopic)) {
                Double angle = getDouble(json, "angle");
                Double speed = getDouble(json, "speed");
                Double x = getDouble(json, "x");
                Double y = getDouble(json, "y");
                Double z = getDouble(json, "z");
                telemetryService.saveTelemetry(device, angle, speed, x, y, z);
            } else if (topicMatches(topic, deviceEventTopic)) {
                persistDeviceEvent(device, json);
            } else if (topicMatches(topic, heartbeatTopic)) {
                log.debug("Heartbeat from {}", deviceIdStr);
            }

        } catch (Exception e) {
            log.error("Error processing MQTT message on {}: {}", topic, e.getMessage());
        }
    }

    @Override
    public void deliveryComplete(IMqttDeliveryToken token) {
        // No-op for QoS 0
    }

    /**
     * Every 30 seconds, check if MQTT is disconnected and try to reconnect.
     */
    @Scheduled(fixedRate = 30000)
    public void ensureMqttConnected() {
        if (client == null || !client.isConnected()) {
            log.info("MQTT not connected, attempting reconnection...");
            try {
                doConnect();
                if (client != null && client.isConnected()) {
                    log.info("MQTT reconnected successfully to {}", brokerUrl);
                }
            } catch (Exception e) {
                log.warn("MQTT reconnection failed: {}", e.getMessage());
            }
        }
    }

    /**
     * Every 60 seconds, mark devices with no heartbeat for >2 minutes as OFFLINE.
     */
    @Scheduled(fixedRate = 60000)
    public void checkDeviceHeartbeats() {
        LocalDateTime cutoff = LocalDateTime.now().minusMinutes(2);
        deviceRepo.findAll().stream()
                .filter(d -> "ONLINE".equals(d.getStatus()))
                .filter(d -> d.getLastSeen() != null && d.getLastSeen().isBefore(cutoff))
                .forEach(d -> {
                    d.setStatus("OFFLINE");
                    deviceRepo.save(d);
                    eventRepo.save(DeviceEvent.builder()
                            .device(d).eventType("DISCONNECTED")
                            .description("No heartbeat for 2+ minutes").build());
                    log.info("Device {} marked OFFLINE", d.getDeviceId());
                });
    }

    /**
     * Daily cleanup: remove telemetry data older than 30 days.
     */
    @Scheduled(cron = "0 0 3 * * *") // 3:00 AM daily
    public void cleanupOldTelemetry() {
        telemetryService.cleanupOld(30);
        log.info("Cleaned up telemetry data older than 30 days");
    }

    private String extractDeviceId(String topic, JsonNode json) {
        if (json.has("deviceId")) {
            return json.get("deviceId").asText();
        }
        String[] parts = topic.split("/");
        if (parts.length >= 3) {
            return parts[parts.length - 1];
        }
        return null;
    }

    private Double getDouble(JsonNode json, String field) {
        return json.has(field) ? json.get(field).asDouble() : null;
    }

    private String getText(JsonNode json, String field) {
        return json.has(field) ? json.get(field).asText() : null;
    }

    private boolean topicMatches(String topic, String baseTopic) {
        return topic.equals(baseTopic) || topic.startsWith(baseTopic + "/");
    }

    private void refreshDevicePresence(Device device) {
        device.setLastSeen(LocalDateTime.now());
        if (!"ONLINE".equals(device.getStatus())) {
            device.setStatus("ONLINE");
            eventRepo.save(DeviceEvent.builder()
                    .device(device)
                    .eventType("CONNECTED")
                    .description("Device came online")
                    .build());
        }
        deviceRepo.save(device);
    }

    private void persistDeviceEvent(Device device, JsonNode json) {
        String eventType = getText(json, "eventType");
        if (eventType == null || eventType.isBlank()) {
            return;
        }

        String description = getText(json, "description");
        eventRepo.save(DeviceEvent.builder()
                .device(device)
                .eventType(eventType)
                .description(description)
                .build());
    }
}
