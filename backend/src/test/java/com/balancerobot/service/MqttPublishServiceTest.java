package com.balancerobot.service;

import com.balancerobot.entity.Device;
import com.balancerobot.entity.PidProfile;
import com.balancerobot.entity.User;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.eclipse.paho.client.mqttv3.MqttClient;
import org.eclipse.paho.client.mqttv3.MqttMessage;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class MqttPublishServiceTest {

    @Mock
    private MqttClient mqttClient;

    private MqttPublishService service;

    @BeforeEach
    void setUp() {
        service = new MqttPublishService(new ObjectMapper());
        ReflectionTestUtils.setField(service, "pidAngleTopic", "robot/pid/angle");
        ReflectionTestUtils.setField(service, "pidSpeedTopic", "robot/pid/speed");
        service.setMqttClient(mqttClient);
    }

    @Test
    void publishPidProfileAppendsDeviceIdWhenProfileHasDevice() throws Exception {
        User owner = User.builder()
                .id(10L)
                .username("user10")
                .email("user10@test.dev")
                .passwordHash("hash")
                .build();
        Device device = Device.builder()
                .id(1L)
                .deviceId("ROBOT_01")
                .owner(owner)
                .build();
        PidProfile profile = PidProfile.builder()
                .id(5L)
                .user(owner)
                .device(device)
                .name("Auto Sync - ROBOT_01")
                .angleP(15.0)
                .angleI(0.5)
                .angleD(8.0)
                .speedP(10.0)
                .speedI(0.3)
                .speedD(5.0)
                .build();

        when(mqttClient.isConnected()).thenReturn(true);

        service.publishPidProfile(profile);

        verify(mqttClient).publish(eq("robot/pid/angle/ROBOT_01"), any(MqttMessage.class));
        verify(mqttClient).publish(eq("robot/pid/speed/ROBOT_01"), any(MqttMessage.class));
    }
}
