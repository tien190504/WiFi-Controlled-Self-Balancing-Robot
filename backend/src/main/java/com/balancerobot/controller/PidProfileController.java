package com.balancerobot.controller;

import com.balancerobot.dto.PidProfileDto;
import com.balancerobot.service.PidProfileService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/pid-profiles")
@RequiredArgsConstructor
public class PidProfileController {

    private final PidProfileService service;

    @GetMapping
    public ResponseEntity<List<PidProfileDto.Response>> getAll(Authentication auth) {
        return ResponseEntity.ok(service.getAll(getUserId(auth)));
    }

    @GetMapping("/active")
    public ResponseEntity<PidProfileDto.Response> getActive(Authentication auth) {
        PidProfileDto.Response active = service.getActive(getUserId(auth));
        return active != null ? ResponseEntity.ok(active) : ResponseEntity.noContent().build();
    }

    @PostMapping
    public ResponseEntity<PidProfileDto.Response> create(
            Authentication auth, @Valid @RequestBody PidProfileDto.Request req) {
        return ResponseEntity.ok(service.create(getUserId(auth), req));
    }

    @PutMapping("/{id}")
    public ResponseEntity<PidProfileDto.Response> update(
            Authentication auth, @PathVariable Long id,
            @Valid @RequestBody PidProfileDto.Request req) {
        return ResponseEntity.ok(service.update(getUserId(auth), id, req));
    }

    @PutMapping("/{id}/activate")
    public ResponseEntity<PidProfileDto.Response> activate(
            Authentication auth, @PathVariable Long id) {
        return ResponseEntity.ok(service.activate(getUserId(auth), id));
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
