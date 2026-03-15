package com.balancerobot.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "telemetry_data", indexes = {
        @Index(name = "idx_telemetry_device_time", columnList = "device_id,recorded_at")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class TelemetryData {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "device_id", nullable = false)
    private Device device;

    private Double angle;
    private Double speed;

    @Column(name = "sensor_x")
    private Double sensorX;
    @Column(name = "sensor_y")
    private Double sensorY;
    @Column(name = "sensor_z")
    private Double sensorZ;

    @Column(name = "recorded_at", nullable = false)
    private LocalDateTime recordedAt;

    @PrePersist
    void prePersist() {
        if (recordedAt == null)
            recordedAt = LocalDateTime.now();
    }
}
