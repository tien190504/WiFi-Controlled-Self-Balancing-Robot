package com.balancerobot.dto;

import jakarta.validation.constraints.*;
import lombok.*;

public class PidProfileDto {

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Request {
        @NotBlank
        @Size(max = 100)
        private String name;
        @NotNull
        private Double angleP;
        @NotNull
        private Double angleI;
        @NotNull
        private Double angleD;
        @NotNull
        private Double speedP;
        @NotNull
        private Double speedI;
        @NotNull
        private Double speedD;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    public static class DeviceSyncRequest {
        @NotNull
        private Double angleP;
        @NotNull
        private Double angleI;
        @NotNull
        private Double angleD;
        @NotNull
        private Double speedP;
        @NotNull
        private Double speedI;
        @NotNull
        private Double speedD;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class Response {
        private Long id;
        private String name;
        private String deviceId;
        private Double angleP, angleI, angleD;
        private Double speedP, speedI, speedD;
        private Boolean isActive;
        private String createdAt;
        private String updatedAt;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class DeviceSyncResponse {
        private Long id;
        private String deviceId;
        private Double angleP;
        private Double angleI;
        private Double angleD;
        private Double speedP;
        private Double speedI;
        private Double speedD;
        private String updatedAt;
    }
}
