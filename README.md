# Balance Robot

## Overview

`Balance Robot` is a real-time monitoring and control project for a self-balancing robot.
The system includes a Flutter mobile app, a Spring Boot backend, an MQTT broker for
real-time messaging, and PostgreSQL for storing users, devices, telemetry, and PID settings.

The project is designed to provide:

- user registration and login
- robot management per account
- real-time robot status updates through MQTT
- mobile-based robot control with multiple control modes
- PID persistence and synchronization per `deviceId` so settings remain available across devices

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

- telemetry from robot to server/app
- control commands from app to robot
- PID parameters published to the correct topic for each robot

### 4. PostgreSQL

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

### Infrastructure

- Docker
- Docker Compose
- Eclipse Mosquitto

---

## High-Level Architecture

Main system flow:

1. The user logs in from the Flutter app.
2. The app calls REST APIs for authentication and device data.
3. The app connects to MQTT to receive real-time robot status.
4. The backend listens to MQTT messages from the robot, updates state, and stores telemetry.
5. When the user changes PID values, the app autosaves them to the backend by `deviceId`.
6. When the user presses `SEND`, the app publishes the current PID values to the MQTT topics for that robot.

---

## Project Structure

```text
Balance_robot/
|-- backend/                # Spring Boot backend + Docker Compose
|-- RobotController/        # Flutter mobile application
|-- TESTING_GUIDE.md        # System testing guide
|-- BAO_CAO_50_PHAN_TRAM.md # Mid-project progress report
```

---

## Highlights

- JWT-based authentication
- robot management per user account
- real-time MQTT communication
- monitoring of angle, speed, and sensor data
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

### 3. Configure the server address

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

### MQTT Topics

- `robot/state/angle/{deviceId}`
- `robot/state/speed/{deviceId}`
- `robot/state/sensors/{deviceId}`
- `robot/heartbeat/{deviceId}`
- `robot/control/move/{deviceId}`
- `robot/pid/angle/{deviceId}`
- `robot/pid/speed/{deviceId}`

---

## Related Documents

- [TESTING_GUIDE.md](./TESTING_GUIDE.md)
- [BAO_CAO_50_PHAN_TRAM.md](./BAO_CAO_50_PHAN_TRAM.md)

---

## Notes

- The backend is the source of truth for PID values when it is reachable.
- The app still keeps a local cache to avoid losing settings during temporary network issues.
- The project is suitable for IoT demos, balancing-control research, or as a base for a small autonomous robot platform.
