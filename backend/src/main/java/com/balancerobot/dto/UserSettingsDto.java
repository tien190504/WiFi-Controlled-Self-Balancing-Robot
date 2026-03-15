package com.balancerobot.dto;

import lombok.*;

public class UserSettingsDto {

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class Response {
        private String preferredMode;
        private Double gravitySensitivity;
        private String mqttBrokerUrl;
        private Integer mqttPort;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    public static class UpdateRequest {
        private String preferredMode;
        private Double gravitySensitivity;
        private String mqttBrokerUrl;
        private Integer mqttPort;
    }
}
