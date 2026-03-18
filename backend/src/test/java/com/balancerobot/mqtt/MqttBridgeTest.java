package com.balancerobot.mqtt;

import com.balancerobot.entity.Device;
import com.balancerobot.entity.DeviceEvent;
import com.balancerobot.entity.User;
import com.balancerobot.repository.DeviceEventRepository;
import com.balancerobot.repository.DeviceRepository;
import com.balancerobot.service.MqttPublishService;
import com.balancerobot.service.TelemetryService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.eclipse.paho.client.mqttv3.MqttMessage;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class MqttBridgeTest {

    @Mock
    private DeviceRepository deviceRepo;

    @Mock
    private DeviceEventRepository eventRepo;

    @Mock
    private TelemetryService telemetryService;

    @Mock
    private MqttPublishService publishService;

    private MqttBridge bridge;

    @BeforeEach
    void setUp() {
        bridge = new MqttBridge(deviceRepo, eventRepo, telemetryService, publishService, new ObjectMapper());
        ReflectionTestUtils.setField(bridge, "stateAngleTopic", "robot/state/angle");
        ReflectionTestUtils.setField(bridge, "stateSensorsTopic", "robot/state/sensors");
        ReflectionTestUtils.setField(bridge, "stateSpeedTopic", "robot/state/speed");
        ReflectionTestUtils.setField(bridge, "stateFullTopic", "robot/state/full");
        ReflectionTestUtils.setField(bridge, "heartbeatTopic", "robot/heartbeat");
        ReflectionTestUtils.setField(bridge, "deviceEventTopic", "robot/event");
    }

    @Test
    void messageArrivedPersistsFullTelemetryAndMarksDeviceOnline() throws Exception {
        Device device = device("ROBOT_01", "OFFLINE", LocalDateTime.now().minusMinutes(5));
        when(deviceRepo.findByDeviceId("ROBOT_01")).thenReturn(Optional.of(device));

        bridge.messageArrived(
                "robot/state/full/ROBOT_01",
                new MqttMessage("{\"deviceId\":\"ROBOT_01\",\"angle\":2.5,\"speed\":44.0,\"x\":-0.8,\"y\":2.5,\"z\":0.0}".getBytes()));

        verify(telemetryService).saveTelemetry(device, 2.5, 44.0, -0.8, 2.5, 0.0);
        verify(deviceRepo).save(device);
        verify(eventRepo).save(argThat(event ->
                "CONNECTED".equals(event.getEventType()) &&
                        "Device came online".equals(event.getDescription())));
    }

    @Test
    void messageArrivedPersistsRobotEventWithoutCreatingConnectedEventWhenAlreadyOnline() throws Exception {
        Device device = device("ROBOT_01", "ONLINE", LocalDateTime.now());
        when(deviceRepo.findByDeviceId("ROBOT_01")).thenReturn(Optional.of(device));

        bridge.messageArrived(
                "robot/event/ROBOT_01",
                new MqttMessage("{\"deviceId\":\"ROBOT_01\",\"eventType\":\"FALL_DETECTED\",\"description\":\"Pitch exceeded safety limit\"}".getBytes()));

        verify(eventRepo).save(argThat(event ->
                "FALL_DETECTED".equals(event.getEventType()) &&
                        "Pitch exceeded safety limit".equals(event.getDescription())));
        verify(deviceRepo).save(device);
    }

    @Test
    void checkDeviceHeartbeatsMarksStaleDevicesOffline() {
        Device stale = device("ROBOT_01", "ONLINE", LocalDateTime.now().minusMinutes(3));
        when(deviceRepo.findAll()).thenReturn(List.of(stale));

        bridge.checkDeviceHeartbeats();

        verify(deviceRepo).save(argThat(device ->
                "OFFLINE".equals(device.getStatus()) &&
                        "ROBOT_01".equals(device.getDeviceId())));
        verify(eventRepo).save(argThat(event ->
                "DISCONNECTED".equals(event.getEventType()) &&
                        "No heartbeat for 2+ minutes".equals(event.getDescription())));
    }

    private Device device(String deviceId, String status, LocalDateTime lastSeen) {
        return Device.builder()
                .id(1L)
                .deviceId(deviceId)
                .name(deviceId)
                .status(status)
                .lastSeen(lastSeen)
                .owner(User.builder()
                        .id(99L)
                        .username("tester")
                        .email("tester@example.com")
                        .passwordHash("hash")
                        .build())
                .build();
    }
}
