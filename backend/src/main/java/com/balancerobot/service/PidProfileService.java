package com.balancerobot.service;

import com.balancerobot.dto.PidProfileDto;
import com.balancerobot.entity.Device;
import com.balancerobot.entity.PidProfile;
import com.balancerobot.entity.User;
import com.balancerobot.repository.DeviceRepository;
import com.balancerobot.repository.PidProfileRepository;
import com.balancerobot.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
public class PidProfileService {

    private static final String AUTO_SYNC_NAME_PREFIX = "Auto Sync - ";

    private final PidProfileRepository profileRepo;
    private final UserRepository userRepo;
    private final DeviceRepository deviceRepo;
    private final MqttPublishService mqttPublishService;

    public List<PidProfileDto.Response> getAll(Long userId) {
        return profileRepo.findByUserId(userId).stream()
                .map(this::toResponse).toList();
    }

    public PidProfileDto.Response getActive(Long userId) {
        return profileRepo.findByUserIdAndDeviceIsNullAndIsActiveTrue(userId)
                .map(this::toResponse)
                .orElse(null);
    }

    public PidProfileDto.DeviceSyncResponse getDevicePid(Long userId, String deviceIdStr) {
        Device device = resolveOwnedDevice(userId, deviceIdStr);
        return profileRepo.findByUserIdAndDeviceIdAndIsActiveTrue(userId, device.getId())
                .map(this::toDeviceSyncResponse)
                .orElse(null);
    }

    @Transactional
    public PidProfileDto.Response create(Long userId, PidProfileDto.Request req) {
        User user = userRepo.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found"));

        PidProfile profile = PidProfile.builder()
                .user(user)
                .name(req.getName())
                .angleP(req.getAngleP()).angleI(req.getAngleI()).angleD(req.getAngleD())
                .speedP(req.getSpeedP()).speedI(req.getSpeedI()).speedD(req.getSpeedD())
                .build();
        return toResponse(profileRepo.save(profile));
    }

    @Transactional
    public PidProfileDto.Response update(Long userId, Long profileId, PidProfileDto.Request req) {
        PidProfile profile = profileRepo.findById(profileId)
                .filter(p -> p.getUser().getId().equals(userId))
                .orElseThrow(() -> new IllegalArgumentException("Profile not found"));

        profile.setName(req.getName());
        profile.setAngleP(req.getAngleP());
        profile.setAngleI(req.getAngleI());
        profile.setAngleD(req.getAngleD());
        profile.setSpeedP(req.getSpeedP());
        profile.setSpeedI(req.getSpeedI());
        profile.setSpeedD(req.getSpeedD());
        return toResponse(profileRepo.save(profile));
    }

    @Transactional
    public PidProfileDto.DeviceSyncResponse upsertDevicePid(
            Long userId, String deviceIdStr, PidProfileDto.DeviceSyncRequest req) {
        Device device = resolveOwnedDevice(userId, deviceIdStr);

        PidProfile profile = profileRepo.findByUserIdAndDeviceIdAndIsActiveTrue(userId, device.getId())
                .orElseGet(() -> PidProfile.builder()
                        .user(device.getOwner())
                        .device(device)
                        .name(autoSyncName(device))
                        .isActive(true)
                        .build());

        profile.setDevice(device);
        profile.setName(autoSyncName(device));
        profile.setIsActive(true);
        profile.setAngleP(req.getAngleP());
        profile.setAngleI(req.getAngleI());
        profile.setAngleD(req.getAngleD());
        profile.setSpeedP(req.getSpeedP());
        profile.setSpeedI(req.getSpeedI());
        profile.setSpeedD(req.getSpeedD());

        return toDeviceSyncResponse(profileRepo.save(profile));
    }

    @Transactional
    public PidProfileDto.Response activate(Long userId, Long profileId) {
        PidProfile profile = profileRepo.findById(profileId)
                .filter(p -> p.getUser().getId().equals(userId))
                .orElseThrow(() -> new IllegalArgumentException("Profile not found"));

        deactivateScope(userId, profile);
        profile.setIsActive(true);
        profile = profileRepo.save(profile);

        mqttPublishService.publishPidProfile(profile);

        return toResponse(profile);
    }

    @Transactional
    public void delete(Long userId, Long profileId) {
        PidProfile profile = profileRepo.findById(profileId)
                .filter(p -> p.getUser().getId().equals(userId))
                .orElseThrow(() -> new IllegalArgumentException("Profile not found"));
        profileRepo.delete(profile);
    }

    private Device resolveOwnedDevice(Long userId, String deviceIdStr) {
        return deviceRepo.findByDeviceIdAndOwnerId(deviceIdStr, userId)
                .orElseThrow(() -> new IllegalArgumentException("Device not found"));
    }

    private void deactivateScope(Long userId, PidProfile profile) {
        if (profile.getDevice() == null) {
            profileRepo.findByUserIdAndDeviceIsNullAndIsActiveTrue(userId)
                    .ifPresent(current -> {
                        current.setIsActive(false);
                        profileRepo.save(current);
                    });
            return;
        }

        profileRepo.findByUserIdAndDeviceIdAndIsActiveTrue(userId, profile.getDevice().getId())
                .ifPresent(current -> {
                    current.setIsActive(false);
                    profileRepo.save(current);
                });
    }

    private String autoSyncName(Device device) {
        return AUTO_SYNC_NAME_PREFIX + device.getDeviceId();
    }

    private PidProfileDto.Response toResponse(PidProfile p) {
        return PidProfileDto.Response.builder()
                .id(p.getId())
                .name(p.getName())
                .deviceId(p.getDevice() != null ? p.getDevice().getDeviceId() : null)
                .angleP(p.getAngleP()).angleI(p.getAngleI()).angleD(p.getAngleD())
                .speedP(p.getSpeedP()).speedI(p.getSpeedI()).speedD(p.getSpeedD())
                .isActive(p.getIsActive())
                .createdAt(p.getCreatedAt() != null ? p.getCreatedAt().toString() : null)
                .updatedAt(p.getUpdatedAt() != null ? p.getUpdatedAt().toString() : null)
                .build();
    }

    private PidProfileDto.DeviceSyncResponse toDeviceSyncResponse(PidProfile p) {
        return PidProfileDto.DeviceSyncResponse.builder()
                .id(p.getId())
                .deviceId(p.getDevice() != null ? p.getDevice().getDeviceId() : null)
                .angleP(p.getAngleP())
                .angleI(p.getAngleI())
                .angleD(p.getAngleD())
                .speedP(p.getSpeedP())
                .speedI(p.getSpeedI())
                .speedD(p.getSpeedD())
                .updatedAt(p.getUpdatedAt() != null ? p.getUpdatedAt().toString() : null)
                .build();
    }
}
