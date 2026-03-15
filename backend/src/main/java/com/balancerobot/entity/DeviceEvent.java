package com.balancerobot.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "device_events", indexes = {
        @Index(name = "idx_events_device_time", columnList = "device_id,occurred_at")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DeviceEvent {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "device_id", nullable = false)
    private Device device;

    @Column(name = "event_type", nullable = false, length = 50)
    private String eventType; // CONNECTED, DISCONNECTED, FALL_DETECTED, ERROR, PID_UPDATED

    @Column(length = 500)
    private String description;

    @Column(name = "occurred_at", nullable = false)
    private LocalDateTime occurredAt;

    @PrePersist
    void prePersist() {
        if (occurredAt == null)
            occurredAt = LocalDateTime.now();
    }
}
