package com.balancerobot.dto;

import lombok.*;

public class DeviceDto {

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    public static class RegisterRequest {
        private String deviceId;
        private String name;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class Response {
        private Long id;
        private String deviceId;
        private String name;
        private String status;
        private String lastSeen;
        private String createdAt;
    }
}
