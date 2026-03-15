package com.balancerobot.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "pid_profiles")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PidProfile {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "device_id")
    private Device device;

    @Column(nullable = false, length = 100)
    private String name;

    @Column(name = "angle_p")
    @Builder.Default
    private Double angleP = 15.0;
    @Column(name = "angle_i")
    @Builder.Default
    private Double angleI = 0.5;
    @Column(name = "angle_d")
    @Builder.Default
    private Double angleD = 8.0;
    @Column(name = "speed_p")
    @Builder.Default
    private Double speedP = 10.0;
    @Column(name = "speed_i")
    @Builder.Default
    private Double speedI = 0.3;
    @Column(name = "speed_d")
    @Builder.Default
    private Double speedD = 5.0;

    @Column(name = "is_active")
    @Builder.Default
    private Boolean isActive = false;

    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @PrePersist
    void prePersist() {
        createdAt = LocalDateTime.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = LocalDateTime.now();
    }
}
