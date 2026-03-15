package com.balancerobot.service;

import com.balancerobot.dto.TelemetryDto;
import com.balancerobot.entity.Device;
import com.balancerobot.entity.TelemetryData;
import com.balancerobot.repository.DeviceEventRepository;
import com.balancerobot.repository.DeviceRepository;
import com.balancerobot.repository.TelemetryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class TelemetryService {

    private final TelemetryRepository telemetryRepo;
    private final DeviceRepository deviceRepo;
    private final DeviceEventRepository eventRepo;

    public List<TelemetryDto.Response> query(String deviceIdStr, LocalDateTime from, LocalDateTime to, int limit) {
        Device device = deviceRepo.findByDeviceId(deviceIdStr)
                .orElseThrow(() -> new IllegalArgumentException("Device not found"));

        List<TelemetryData> data;
        if (from != null && to != null) {
            data = telemetryRepo.findByDeviceIdAndRecordedAtBetweenOrderByRecordedAtDesc(
                    device.getId(), from, to);
        } else {
            data = telemetryRepo.findByDeviceIdOrderByRecordedAtDesc(
                    device.getId(), PageRequest.of(0, limit));
        }
        return data.stream().map(this::toResponse).toList();
    }

    public TelemetryDto.Response getLatest(String deviceIdStr) {
        Device device = deviceRepo.findByDeviceId(deviceIdStr)
                .orElseThrow(() -> new IllegalArgumentException("Device not found"));
        return telemetryRepo.findFirstByDeviceIdOrderByRecordedAtDesc(device.getId())
                .map(this::toResponse).orElse(null);
    }

    public List<TelemetryDto.EventResponse> getEvents(String deviceIdStr, int limit) {
        Device device = deviceRepo.findByDeviceId(deviceIdStr)
                .orElseThrow(() -> new IllegalArgumentException("Device not found"));
        return eventRepo.findByDeviceIdOrderByOccurredAtDesc(device.getId(), PageRequest.of(0, limit))
                .stream()
                .map(e -> TelemetryDto.EventResponse.builder()
                        .eventType(e.getEventType())
                        .description(e.getDescription())
                        .occurredAt(e.getOccurredAt().toString())
                        .build())
                .toList();
    }

    @Transactional
    public void saveTelemetry(Device device, Double angle, Double speed,
            Double sensorX, Double sensorY, Double sensorZ) {
        TelemetryData data = TelemetryData.builder()
                .device(device)
                .angle(angle).speed(speed)
                .sensorX(sensorX).sensorY(sensorY).sensorZ(sensorZ)
                .recordedAt(LocalDateTime.now())
                .build();
        telemetryRepo.save(data);
    }

    @Transactional
    public void cleanupOld(int daysToKeep) {
        telemetryRepo.deleteByRecordedAtBefore(LocalDateTime.now().minusDays(daysToKeep));
    }

    private TelemetryDto.Response toResponse(TelemetryData d) {
        return TelemetryDto.Response.builder()
                .angle(d.getAngle()).speed(d.getSpeed())
                .sensorX(d.getSensorX()).sensorY(d.getSensorY()).sensorZ(d.getSensorZ())
                .recordedAt(d.getRecordedAt().toString())
                .build();
    }
}
