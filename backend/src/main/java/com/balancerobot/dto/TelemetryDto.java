package com.balancerobot.dto;

import lombok.*;

public class TelemetryDto {

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class Response {
        private Double angle;
        private Double speed;
        private Double sensorX;
        private Double sensorY;
        private Double sensorZ;
        private String recordedAt;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class EventResponse {
        private String eventType;
        private String description;
        private String occurredAt;
    }
}
