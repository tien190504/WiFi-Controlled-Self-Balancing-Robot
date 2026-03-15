package com.balancerobot.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "user_settings")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserSettings {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", unique = true, nullable = false)
    private User user;

    @Column(name = "preferred_mode", length = 20)
    @Builder.Default
    private String preferredMode = "ROCKER";

    @Column(name = "gravity_sensitivity")
    @Builder.Default
    private Double gravitySensitivity = 1.5;

    @Column(name = "mqtt_broker_url", length = 255)
    @Builder.Default
    private String mqttBrokerUrl = "192.168.4.1";

    @Column(name = "mqtt_port")
    @Builder.Default
    private Integer mqttPort = 1883;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @PrePersist
    @PreUpdate
    void onSave() {
        updatedAt = LocalDateTime.now();
    }
}
