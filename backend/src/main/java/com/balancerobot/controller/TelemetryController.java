package com.balancerobot.controller;

import com.balancerobot.dto.TelemetryDto;
import com.balancerobot.service.TelemetryService;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class TelemetryController {

    private final TelemetryService service;

    @GetMapping("/telemetry/{deviceId}")
    public ResponseEntity<List<TelemetryDto.Response>> query(
            @PathVariable String deviceId,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime to,
            @RequestParam(defaultValue = "100") int limit) {
        return ResponseEntity.ok(service.query(deviceId, from, to, limit));
    }

    @GetMapping("/telemetry/{deviceId}/latest")
    public ResponseEntity<TelemetryDto.Response> getLatest(@PathVariable String deviceId) {
        TelemetryDto.Response latest = service.getLatest(deviceId);
        return latest != null ? ResponseEntity.ok(latest) : ResponseEntity.noContent().build();
    }

    @GetMapping("/events/{deviceId}")
    public ResponseEntity<List<TelemetryDto.EventResponse>> getEvents(
            @PathVariable String deviceId,
            @RequestParam(defaultValue = "50") int limit) {
        return ResponseEntity.ok(service.getEvents(deviceId, limit));
    }
}
