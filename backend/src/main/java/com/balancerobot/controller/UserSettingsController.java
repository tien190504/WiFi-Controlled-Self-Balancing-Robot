package com.balancerobot.controller;

import com.balancerobot.dto.UserSettingsDto;
import com.balancerobot.entity.UserSettings;
import com.balancerobot.repository.UserSettingsRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/settings")
@RequiredArgsConstructor
public class UserSettingsController {

    private final UserSettingsRepository settingsRepo;

    @GetMapping
    public ResponseEntity<UserSettingsDto.Response> get(Authentication auth) {
        Long userId = (Long) auth.getPrincipal();
        UserSettings settings = settingsRepo.findByUserId(userId)
                .orElseThrow(() -> new IllegalArgumentException("Settings not found"));
        return ResponseEntity.ok(toResponse(settings));
    }

    @PutMapping
    public ResponseEntity<UserSettingsDto.Response> update(
            Authentication auth, @RequestBody UserSettingsDto.UpdateRequest req) {
        Long userId = (Long) auth.getPrincipal();
        UserSettings settings = settingsRepo.findByUserId(userId)
                .orElseThrow(() -> new IllegalArgumentException("Settings not found"));

        if (req.getPreferredMode() != null)
            settings.setPreferredMode(req.getPreferredMode());
        if (req.getGravitySensitivity() != null)
            settings.setGravitySensitivity(req.getGravitySensitivity());
        if (req.getMqttBrokerUrl() != null)
            settings.setMqttBrokerUrl(req.getMqttBrokerUrl());
        if (req.getMqttPort() != null)
            settings.setMqttPort(req.getMqttPort());

        return ResponseEntity.ok(toResponse(settingsRepo.save(settings)));
    }

    private UserSettingsDto.Response toResponse(UserSettings s) {
        return UserSettingsDto.Response.builder()
                .preferredMode(s.getPreferredMode())
                .gravitySensitivity(s.getGravitySensitivity())
                .mqttBrokerUrl(s.getMqttBrokerUrl())
                .mqttPort(s.getMqttPort())
                .build();
    }
}
