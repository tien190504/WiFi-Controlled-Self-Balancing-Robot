package com.balancerobot.controller;

import com.balancerobot.dto.DeviceDto;
import com.balancerobot.dto.PidProfileDto;
import com.balancerobot.service.DeviceService;
import com.balancerobot.service.PidProfileService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/devices")
@RequiredArgsConstructor
public class DeviceController {

    private final DeviceService service;
    private final PidProfileService pidProfileService;

    @PostMapping
    public ResponseEntity<DeviceDto.Response> register(
            Authentication auth, @RequestBody DeviceDto.RegisterRequest req) {
        return ResponseEntity.ok(service.register(getUserId(auth), req));
    }

    @GetMapping
    public ResponseEntity<List<DeviceDto.Response>> getAll(Authentication auth) {
        return ResponseEntity.ok(service.getAll(getUserId(auth)));
    }

    @GetMapping("/{id}/status")
    public ResponseEntity<DeviceDto.Response> getStatus(
            Authentication auth, @PathVariable Long id) {
        return ResponseEntity.ok(service.getStatus(getUserId(auth), id));
    }

    @GetMapping("/{deviceId}/pid")
    public ResponseEntity<PidProfileDto.DeviceSyncResponse> getPid(
            Authentication auth, @PathVariable String deviceId) {
        PidProfileDto.DeviceSyncResponse active = pidProfileService.getDevicePid(getUserId(auth), deviceId);
        return active != null ? ResponseEntity.ok(active) : ResponseEntity.noContent().build();
    }

    @PutMapping("/{deviceId}/pid")
    public ResponseEntity<PidProfileDto.DeviceSyncResponse> savePid(
            Authentication auth,
            @PathVariable String deviceId,
            @Valid @RequestBody PidProfileDto.DeviceSyncRequest req) {
        return ResponseEntity.ok(pidProfileService.upsertDevicePid(getUserId(auth), deviceId, req));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(Authentication auth, @PathVariable Long id) {
        service.delete(getUserId(auth), id);
        return ResponseEntity.noContent().build();
    }

    private Long getUserId(Authentication auth) {
        return (Long) auth.getPrincipal();
    }
}
