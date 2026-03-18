# Balance Robot

## Overview

`Balance Robot` is a real-time monitoring and control project for a self-balancing robot.
The system includes a Flutter mobile app, a Spring Boot backend, an MQTT broker, an ESP32 firmware project, and PostgreSQL for storing users, devices, telemetry, and PID settings.

The project is designed to provide:

- user registration and login
- robot management per account
- real-time robot status updates through MQTT
- mobile-based robot control with multiple control modes
- PID persistence and synchronization per `deviceId`

---

## Main Components

### 1. Mobile App `RobotController`

The Flutter app is the main control interface for the user.

Key features:

- user registration and login
- robot selection from registered devices
- direct MQTT connection for real-time robot monitoring
- robot control through rocker, button, and gravity modes
- PID tuning with backend synchronization per robot

### 2. Backend `Spring Boot`

The backend handles business logic, security, and data persistence.

Key responsibilities:

- JWT-based authentication APIs
- device management per user
- PID profile storage
- active PID synchronization APIs per `deviceId`
- telemetry and device event processing

### 3. MQTT Broker

Mosquitto is used to exchange real-time data between the robot, backend, and mobile app.

Main MQTT flows:

- telemetry from robot to backend and mobile
- control commands from app to robot
- PID parameters published to the correct topic for each robot

### 4. Firmware `Iot_robot`

The ESP32 DevKit V1 firmware is responsible for:

- Wi-Fi + MQTT connectivity
- MPU6050 reading with a complementary filter
- self-balancing control loop using angle PID
- A4988 motor driver output for both motors
- telemetry, heartbeat, and device event publishing

### 5. PostgreSQL

The database stores:

- users
- devices
- PID profiles
- telemetry
- robot activity events

---

## Tech Stack

### Backend

- Java 22
- Spring Boot 3.3.6
- Spring Security + JWT
- Spring Data JPA
- PostgreSQL
- Swagger / OpenAPI

### Mobile App

- Flutter
- Dart
- HTTP client
- MQTT client
- SharedPreferences
- Google Fonts

### Firmware

- ESP-IDF
- ESP32 DevKit V1
- MPU6050
- A4988

### Infrastructure

- Docker
- Docker Compose
- Eclipse Mosquitto

---

## High-Level Architecture

1. The user logs in from the Flutter app.
2. The app calls REST APIs for authentication and device data.
3. The app connects to MQTT to receive real-time robot status.
4. The ESP32 publishes state, heartbeat, and events via MQTT.
5. The backend listens to MQTT messages, updates device presence, and stores complete telemetry from `robot/state/full/{deviceId}`.
6. When the user changes PID values, the app autosaves them to the backend by `deviceId`.
7. When the user presses `SEND`, the app publishes the current PID values to the MQTT topics for that robot.

---

## Project Structure

```text
Balance_robot/
|-- backend/                # Spring Boot backend + Docker Compose
|-- Iot_robot/              # ESP32 DevKit V1 firmware (ESP-IDF)
|-- RobotController/        # Flutter mobile application
|-- TESTING_GUIDE.md        # System testing guide
|-- README.md
```

---

## Highlights

- JWT-based authentication
- robot management per user account
- real-time MQTT communication
- telemetry persistence through `robot/state/full/{deviceId}`
- multiple robot control modes
- PID tuning with backend sync per robot
- local cache fallback when the backend is temporarily unavailable

---

## Quick Start

### 1. Run the backend with Docker

```bash
cd d:\Balance_robot\backend
docker compose up --build -d
```

### 2. Run the Flutter app

```bash
cd d:\Balance_robot\RobotController
flutter pub get
flutter run
```

### 3. Build and flash the firmware

```bash
cd d:\Balance_robot\Iot_robot
idf.py set-target esp32
idf.py menuconfig
idf.py build flash monitor
```

### 4. Configure the server address

When running the app on a physical phone, enter `Server IP / Host` as the LAN IP address of the machine running the backend.
If you use an Android emulator, you can use `10.0.2.2`.

---

## Important APIs and Topics

### REST APIs

- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/devices`
- `POST /api/devices`
- `GET /api/devices/{deviceId}/pid`
- `PUT /api/devices/{deviceId}/pid`
- `GET /api/telemetry/{deviceId}/latest`
- `GET /api/events/{deviceId}`

### MQTT Topics

- `robot/state/angle/{deviceId}`
- `robot/state/speed/{deviceId}`
- `robot/state/sensors/{deviceId}`
- `robot/state/full/{deviceId}`
- `robot/heartbeat/{deviceId}`
- `robot/event/{deviceId}`
- `robot/control/move/{deviceId}`
- `robot/pid/angle/{deviceId}`
- `robot/pid/speed/{deviceId}`

---

## Related Documents

- [TESTING_GUIDE.md](./TESTING_GUIDE.md)

---

## Notes

- The backend is the source of truth for PID values when it is reachable.
- The app still keeps a local cache to avoid losing settings during temporary network issues.
- `robot/state/full/{deviceId}` is the backend persistence topic for complete telemetry records.
- `speed PID` is still synchronized through backend and mobile for compatibility, but the ESP32 v1 firmware does not use it in the control loop because the current hardware setup has no encoder.
- The project is suitable for IoT demos, balancing-control research, or as a base for a small autonomous robot platform.
