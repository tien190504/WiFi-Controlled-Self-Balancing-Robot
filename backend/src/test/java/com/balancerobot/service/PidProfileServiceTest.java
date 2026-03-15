package com.balancerobot.service;

import com.balancerobot.dto.PidProfileDto;
import com.balancerobot.entity.Device;
import com.balancerobot.entity.PidProfile;
import com.balancerobot.entity.User;
import com.balancerobot.repository.DeviceRepository;
import com.balancerobot.repository.PidProfileRepository;
import com.balancerobot.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class PidProfileServiceTest {

    @Mock
    private PidProfileRepository profileRepo;

    @Mock
    private UserRepository userRepo;

    @Mock
    private DeviceRepository deviceRepo;

    @Mock
    private MqttPublishService mqttPublishService;

    @InjectMocks
    private PidProfileService service;

    @Test
    void upsertDevicePidCreatesNewActiveProfileForOwnedDevice() {
        User owner = user(10L);
        Device device = device(1L, "ROBOT_01", owner);

        when(deviceRepo.findByDeviceIdAndOwnerId("ROBOT_01", 10L)).thenReturn(Optional.of(device));
        when(profileRepo.findByUserIdAndDeviceIdAndIsActiveTrue(10L, 1L)).thenReturn(Optional.empty());
        when(profileRepo.save(any(PidProfile.class))).thenAnswer(invocation -> {
            PidProfile saved = invocation.getArgument(0);
            saved.setId(99L);
            return saved;
        });

        PidProfileDto.DeviceSyncResponse response = service.upsertDevicePid(
                10L,
                "ROBOT_01",
                new PidProfileDto.DeviceSyncRequest(15.0, 0.6, 8.5, 10.0, 0.3, 5.0));

        assertThat(response.getId()).isEqualTo(99L);
        assertThat(response.getDeviceId()).isEqualTo("ROBOT_01");
        assertThat(response.getAngleI()).isEqualTo(0.6);
        verify(profileRepo).save(argThat(profile ->
                profile.getDevice() == device
                        && Boolean.TRUE.equals(profile.getIsActive())
                        && "Auto Sync - ROBOT_01".equals(profile.getName())));
    }

    @Test
    void upsertDevicePidUpdatesExistingActiveProfileWithoutCreatingDuplicate() {
        User owner = user(10L);
        Device device = device(1L, "ROBOT_01", owner);
        PidProfile existing = PidProfile.builder()
                .id(44L)
                .user(owner)
                .device(device)
                .name("Auto Sync - ROBOT_01")
                .isActive(true)
                .angleP(10.0)
                .angleI(0.2)
                .angleD(5.0)
                .speedP(8.0)
                .speedI(0.1)
                .speedD(3.0)
                .build();

        when(deviceRepo.findByDeviceIdAndOwnerId("ROBOT_01", 10L)).thenReturn(Optional.of(device));
        when(profileRepo.findByUserIdAndDeviceIdAndIsActiveTrue(10L, 1L)).thenReturn(Optional.of(existing));
        when(profileRepo.save(existing)).thenReturn(existing);

        PidProfileDto.DeviceSyncResponse response = service.upsertDevicePid(
                10L,
                "ROBOT_01",
                new PidProfileDto.DeviceSyncRequest(20.0, 0.9, 9.5, 12.0, 0.4, 6.0));

        assertThat(response.getId()).isEqualTo(44L);
        assertThat(existing.getAngleP()).isEqualTo(20.0);
        assertThat(existing.getSpeedD()).isEqualTo(6.0);
        verify(profileRepo, times(1)).save(existing);
    }

    @Test
    void activateOnlyDeactivatesProfilesInSameDeviceScope() {
        User owner = user(10L);
        Device device1 = device(1L, "ROBOT_01", owner);
        Device device2 = device(2L, "ROBOT_02", owner);
        PidProfile currentScope = PidProfile.builder()
                .id(50L)
                .user(owner)
                .device(device1)
                .isActive(true)
                .build();
        PidProfile selected = PidProfile.builder()
                .id(60L)
                .user(owner)
                .device(device1)
                .isActive(false)
                .build();

        when(profileRepo.findById(60L)).thenReturn(Optional.of(selected));
        when(profileRepo.findByUserIdAndDeviceIdAndIsActiveTrue(10L, 1L)).thenReturn(Optional.of(currentScope));
        when(profileRepo.save(any(PidProfile.class))).thenAnswer(invocation -> invocation.getArgument(0));

        service.activate(10L, 60L);

        verify(profileRepo).findByUserIdAndDeviceIdAndIsActiveTrue(10L, 1L);
        verify(profileRepo, never()).findByUserIdAndDeviceIdAndIsActiveTrue(10L, 2L);
        verify(profileRepo, never()).findByUserIdAndDeviceIsNullAndIsActiveTrue(10L);
        verify(mqttPublishService).publishPidProfile(selected);
        assertThat(selected.getIsActive()).isTrue();
        assertThat(currentScope.getIsActive()).isFalse();
    }

    private User user(Long id) {
        return User.builder()
                .id(id)
                .username("user" + id)
                .email("user" + id + "@test.dev")
                .passwordHash("hash")
                .build();
    }

    private Device device(Long id, String deviceId, User owner) {
        return Device.builder()
                .id(id)
                .deviceId(deviceId)
                .name(deviceId)
                .owner(owner)
                .build();
    }
}
