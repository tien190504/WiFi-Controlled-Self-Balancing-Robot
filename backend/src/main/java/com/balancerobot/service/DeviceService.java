package com.balancerobot.service;

import com.balancerobot.dto.DeviceDto;
import com.balancerobot.entity.Device;
import com.balancerobot.entity.User;
import com.balancerobot.repository.DeviceRepository;
import com.balancerobot.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class DeviceService {

    private final DeviceRepository deviceRepo;
    private final UserRepository userRepo;

    @Transactional
    public DeviceDto.Response register(Long userId, DeviceDto.RegisterRequest req) {
        User user = userRepo.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found"));

        if (deviceRepo.existsByDeviceId(req.getDeviceId())) {
            throw new IllegalArgumentException("Device ID already registered");
        }

        Device device = Device.builder()
                .deviceId(req.getDeviceId())
                .name(req.getName())
                .secretKey(UUID.randomUUID().toString())
                .owner(user)
                .build();
        return toResponse(deviceRepo.save(device));
    }

    public List<DeviceDto.Response> getAll(Long userId) {
        return deviceRepo.findByOwnerId(userId).stream()
                .map(this::toResponse).toList();
    }

    public DeviceDto.Response getStatus(Long userId, Long deviceId) {
        Device device = deviceRepo.findById(deviceId)
                .filter(d -> d.getOwner().getId().equals(userId))
                .orElseThrow(() -> new IllegalArgumentException("Device not found"));
        return toResponse(device);
    }

    @Transactional
    public void delete(Long userId, Long deviceId) {
        Device device = deviceRepo.findById(deviceId)
                .filter(d -> d.getOwner().getId().equals(userId))
                .orElseThrow(() -> new IllegalArgumentException("Device not found"));
        deviceRepo.delete(device);
    }

    private DeviceDto.Response toResponse(Device d) {
        return DeviceDto.Response.builder()
                .id(d.getId())
                .deviceId(d.getDeviceId())
                .name(d.getName())
                .status(d.getStatus())
                .lastSeen(d.getLastSeen() != null ? d.getLastSeen().toString() : null)
                .createdAt(d.getCreatedAt() != null ? d.getCreatedAt().toString() : null)
                .build();
    }
}
