# Hướng dẫn kiểm thử dự án Balance Robot

## 1. Mục tiêu

Tài liệu này bao quát kiểm thử cho:

- `backend` Spring Boot + PostgreSQL + MQTT bridge
- `RobotController` Flutter mobile app
- `Iot_robot` firmware ESP32 DevKit V1
- broker MQTT Mosquitto
- luồng tích hợp end-to-end giữa mobile, backend và robot

## 2. Điều kiện tiên quyết

### Phần cứng

- ESP32 DevKit V1
- MPU6050
- 2 driver A4988
- 2 động cơ stepper
- nguồn phù hợp cho ESP32 và motor

### Pin mặc định firmware

- `SDA = GPIO19`
- `SCL = GPIO18`
- `LEFT_STEP = GPIO25`
- `LEFT_DIR = GPIO26`
- `RIGHT_STEP = GPIO32`
- `RIGHT_DIR = GPIO33`
- `ENABLE = GPIO27`

### Phần mềm

- Java 22
- Docker Desktop
- Flutter SDK
- ESP-IDF đã cài và có `IDF_PATH`

## 3. Kiểm thử tự động

### Backend

```powershell
cd D:\Balance_robot\backend
.\mvnw.cmd test
```

Pass khi:

- toàn bộ test pass
- có test cho publish PID
- có test cho ingest `robot/state/full/*`
- có test cho ingest `robot/event/*`
- có test cho timeout heartbeat

### Mobile

```powershell
cd D:\Balance_robot\RobotController
flutter test
```

Pass khi:

- toàn bộ test pass
- app vẫn render flow login mặc định

## 4. Khởi động backend và broker

```powershell
cd D:\Balance_robot\backend
docker compose up --build -d
docker compose ps
```

Pass khi:

- PostgreSQL chạy ở `localhost:5432`
- MQTT chạy ở `localhost:1883`
- API chạy ở `localhost:8080`

## 5. Build và flash firmware ESP32

### Cấu hình build-time

```powershell
cd D:\Balance_robot\Iot_robot
idf.py menuconfig
```

Trong menu `Balance Robot Firmware`, cấu hình:

- `Device ID`
- `Wi-Fi SSID`
- `Wi-Fi password`
- `MQTT broker host`
- `MQTT broker port`

### Build và flash

```powershell
cd D:\Balance_robot\Iot_robot
idf.py set-target esp32
idf.py build
idf.py -p COMx flash monitor
```

Pass khi:

- ESP32 boot không còn menu demo UART cũ
- vào được Wi‑Fi
- kết nối được MQTT
- MPU6050 được init và calibrate

## 6. MQTT contract cần kiểm tra

### Topic command

- `robot/control/move/{deviceId}`
- `robot/pid/angle/{deviceId}`
- `robot/pid/speed/{deviceId}`

### Topic state và event

- `robot/state/angle/{deviceId}`
- `robot/state/speed/{deviceId}`
- `robot/state/sensors/{deviceId}`
- `robot/state/full/{deviceId}`
- `robot/heartbeat/{deviceId}`
- `robot/event/{deviceId}`

### Payload mẫu

```json
{"speed": 0.35, "turn": -0.20}
```

```json
{"P": 15.0, "I": 0.5, "D": 8.0}
```

```json
{"deviceId":"ROBOT_01","angle":1.7}
```

```json
{"deviceId":"ROBOT_01","speed":42.0}
```

```json
{"deviceId":"ROBOT_01","x":-0.4,"y":1.7,"z":0.0}
```

```json
{"deviceId":"ROBOT_01","angle":1.7,"speed":42.0,"x":-0.4,"y":1.7,"z":0.0}
```

```json
{"deviceId":"ROBOT_01","status":"ONLINE","wifiRssi":-55}
```

```json
{"deviceId":"ROBOT_01","eventType":"FALL_DETECTED","description":"Pitch exceeded safety limit"}
```

## 7. Kịch bản kiểm thử chức năng

### 7.1 Auth và đăng ký thiết bị

1. Mở app `RobotController`.
2. Đăng ký tài khoản hoặc đăng nhập.
3. Thêm robot với `deviceId` trùng firmware, ví dụ `ROBOT_01`.

Pass khi:

- backend trả `200`
- robot xuất hiện trong danh sách thiết bị

### 7.2 Kết nối MQTT từ app

1. Chọn robot trong app.
2. Nhấn `CONNECT`.
3. Nhập đúng IP broker và port `1883`.

Pass khi:

- app báo `CONNECTED`
- angle, speed, sensors cập nhật realtime

### 7.3 Telemetry realtime

Kiểm tra:

- gauge `ANGLE` thay đổi theo độ nghiêng thực
- gauge `SPEED` hiển thị dải `0..100`
- màn waveform có dữ liệu liên tục
- backend nhận `robot/state/full/{deviceId}` và lưu record đầy đủ

API kiểm tra:

```powershell
curl -H "Authorization: Bearer <JWT>" http://localhost:8080/api/telemetry/ROBOT_01/latest
curl -H "Authorization: Bearer <JWT>" http://localhost:8080/api/events/ROBOT_01
```

Pass khi:

- `/latest` trả đủ `angle`, `speed`, `sensorX`, `sensorY`, `sensorZ`
- `/events` có `CONNECTED` khi robot lên online

### 7.4 Điều khiển di chuyển

Thực hiện lần lượt:

- `ROCKER`
- `BUTTON`
- `GRAVITY`

Pass khi:

- robot phản hồi đúng hướng tiến, lùi, rẽ
- sau khoảng `500 ms` không có lệnh mới thì trở về neutral command

### 7.5 Angle PID

1. Vào màn `PID`.
2. Chỉnh `ANGLE PID`.
3. Nhấn `SEND`.
4. Reboot ESP32.

Pass khi:

- ESP32 nhận topic `robot/pid/angle/{deviceId}`
- backend lưu event `PID_UPDATED`
- sau reboot, firmware vẫn dùng angle PID mới

### 7.6 Speed PID reserved

1. Chỉnh `SPEED PID`.
2. Nhấn `SEND`.

Pass khi:

- ESP32 parse được topic `robot/pid/speed/{deviceId}`
- hệ thống không lỗi
- hành vi điều khiển không đổi vì bản phần cứng hiện tại không có encoder

### 7.7 Fall detection

1. Nghiêng robot vượt ngưỡng an toàn khoảng `35°`.

Pass khi:

- motor dừng
- robot phát `robot/event/{deviceId}` với `FALL_DETECTED`
- backend lưu event tương ứng

### 7.8 Re-arm

1. Đưa robot về vùng `±10°`.
2. Giữ ổn định ít nhất `1 giây`.

Pass khi:

- control loop re-arm
- robot có thể cân bằng lại

## 8. Kịch bản fault injection

### Mất Wi‑Fi

1. Tắt router hoặc đổi SSID.

Pass khi:

- ESP32 retry kết nối Wi‑Fi
- backend đánh dấu `OFFLINE` nếu quá `2 phút` không có heartbeat

### Mất MQTT broker

```powershell
cd D:\Balance_robot\backend
docker compose stop mqtt
```

Pass khi:

- ESP32 không treo
- app không còn điều khiển được robot
- khi broker lên lại, ESP32 reconnect được

### Lỗi MPU6050

1. Rút dây MPU6050 hoặc tạo lỗi I2C.

Pass khi:

- motor dừng an toàn
- firmware phát `ERROR` khi MQTT còn khả dụng

## 9. Ma trận pass/fail

| Hạng mục | Điều kiện pass |
|---|---|
| Backend unit test | `./mvnw.cmd test` pass |
| Mobile unit test | `flutter test` pass |
| Docker services | `postgres`, `mqtt`, `api` đều healthy |
| ESP32 boot | không còn firmware demo |
| Wi‑Fi | kết nối đúng SSID |
| MQTT subscribe | nhận `control` và `pid` topic |
| MQTT publish | phát đủ `state`, `state/full`, `heartbeat`, `event` |
| Device status | online/offline đúng theo heartbeat |
| Telemetry API | `/latest` trả record đầy đủ |
| Events API | có `CONNECTED`, `DISCONNECTED`, `PID_UPDATED`, `FALL_DETECTED`, `ERROR` |
| Control modes | rocker, button, gravity đều dùng được |
| Safety | quá nghiêng thì motor dừng |
| Persistence | angle PID còn sau reboot |

## 10. Ghi chú

- `speed PID` hiện chỉ được giữ để tương thích dữ liệu giữa app, backend và firmware.
- Với phần cứng hiện tại chưa có encoder, vòng điều khiển trên ESP32 chỉ dùng `angle PID`.
- Nếu bạn có frontend web React ở repo khác, hãy dùng lại cùng các test case API/MQTT trong tài liệu này.
