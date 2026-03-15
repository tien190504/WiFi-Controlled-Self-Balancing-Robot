# 📋 HƯỚNG DẪN TEST TOÀN DIỆN - Balance Robot

Tài liệu này cung cấp hướng dẫn đầy đủ từ bước khởi động Backend, MQTT Broker, đến cách kiểm tra tích hợp với Android App. 

Tài liệu đã được cập nhật dựa trên các bản vá lỗi mới nhất về Docker Healthcheck và tương thích thư viện.

---

## 1. Yêu Cầu Hệ Thống

| Thành phần | Yêu cầu |
|---|---|
| **Docker** | Docker Desktop đang chạy (dùng cho DB, MQTT, API) |
| **Java** | JDK 22+ (nếu muốn chạy code API ngoài Docker) |
| **Flutter** | Flutter SDK 3.x (dùng cho RobotController App) |
| **Android** | Android Studio + Máy ảo (Emulator) hoặc điện thoại thật |
| **Mạng** | PC và điện thoại phải kết nối **cùng một mạng LAN/WiFi** |

---

## 2. Khởi Động Hệ Thống (Môi trường Docker)

Hệ thống được thiết kế tối ưu với Docker Compose, bao gồm 3 container: 
- `balance_robot_db` (Postgres 16)
- `balance_robot_mqtt` (Mosquitto 2.0)
- `balance_robot_api` (Spring Boot 3.3.6)

### 2.1. Build và chạy toàn bộ kiến trúc

Mở terminal tại thư mục gốc backend:
```bash
cd d:\Balance_robot\backend
docker compose down -v  # (Tùy chọn) Xóa container và dữ liệu cũ nếu muốn làm sạch
docker compose up --build -d
```

### 2.2. Kiểm tra các Container

Chạy lệnh để đảm bảo tất cả các service đã lên và ở trạng thái **healthy / Up**:
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```
**Kết quả mong đợi:** 
Cả 3 container đều `Up (healthy)`. Container API phải kết nối thành công và không bị vòng lặp restart.

### 2.3. Cách xem Logs khi gặp sự cố

```bash
# Xem logs của API (Spring Boot):
docker logs balance_robot_api -f

# Xem logs của MQTT Broker:
docker logs balance_robot_mqtt -f

# Xem logs của Database:
docker logs balance_robot_db -f
```

---

## 3. Test Các Thành Phần Độc Lập

### 3.1. Test MQTT Broker
Broker lắng nghe tại port `1883`. Healthcheck được thực hiện bằng tool `mosquitto_pub` có sẵn trong container.

**Mở Terminal 1 (Subscribe để theo dõi robot telemetry)**
```bash
docker exec -it balance_robot_mqtt mosquitto_sub -t "robot/state/angle/#" -v
```

**Mở Terminal 2 (Publish dữ liệu góc nghiêng giả lập)**
```bash
docker exec -it balance_robot_mqtt mosquitto_pub -t "robot/state/angle/ROBOT_01" -m '{"angle": 12.5, "deviceId": "ROBOT_01"}' -q 0
```
**Kết quả:** Terminal 1 sẽ ngay lập tức in ra dòng message vừa publish. Log của `balance_robot_api` cũng sẽ bắt được message này nếu API bridge hoạt động đúng.

### 3.1b. Cấu trúc các MQTT Topics để test Telemetry

Theo code của Backend `MqttBridge.java`, hệ thống hiện tại hỗ trợ bắt các topics và bóc tách dữ liệu theo chuẩn sau:

> **Lưu ý:** Device ID (`ROBOT_01`) có thể được lấy từ **đuôi của topic** OR bên trong chuỗi **JSON payload**. Bạn có thể test một trong các dạng bên dưới.

**1. Gửi trạng thái góc nghiêng (Angle)**
- Topic: `robot/state/angle/ROBOT_01`
- Payload (JSON):
  ```json
  {"angle": 12.5, "deviceId": "ROBOT_01"}
  ```

**2. Gửi trạng thái tốc độ (Speed)**
- Topic: `robot/state/speed/ROBOT_01`
- Payload (JSON):
  ```json
  {"speed": 5.2, "deviceId": "ROBOT_01"}
  ```

**3. Gửi trạng thái cảm biến (Sensors - Gia tốc/Gyro)**
- Topic: `robot/state/sensors/ROBOT_01`
- Payload (JSON):
  ```json
  {"x": 1.05, "y": 0.02, "z": 9.81, "deviceId": "ROBOT_01"}
  ```

**4. Heartbeat (Giữ thiết bị "ONLINE")**
- Cứ mỗi 60s, Backend sẽ quét và tắt trạng thái những thiết bị không gửi tín hiệu quá 2 phút. Gửi topic này để giữ thiết bị luôn Online.
- Topic: `robot/heartbeat/ROBOT_01`
- Payload (JSON):
  ```json
  {"deviceId": "ROBOT_01", "status": "ok"}
  ```

---

### 3.2. Test REST API (bằng Swagger UI)

API cung cấp giao diện Swagger UI để test trực quan.

1. Truy cập: **http://localhost:8080/swagger-ui.html**
2. **Kiểm tra luồng Đăng ký & Đăng nhập:**
   - Sử dụng API `POST /api/auth/register` để tạo tài khoản.
   - Sử dụng API `POST /api/auth/login` để lấy `JWT_TOKEN`.
   - Copy token, nhấn nút **Authorize** ở góc trên cùng bên phải Swagger, điền `Bearer <JWT_TOKEN>`.
3. **Kiểm tra luồng Device:**
   - Dùng `POST /api/devices` để đăng ký 1 thiết bị mới (VD: `deviceId`: "ROBOT_01").
   - Dùng `GET /api/devices` để lấy danh sách.

---

## 4. Test Ứng Dụng Android (RobotController)

### 4.1. Cấu hình IP quan trọng

Vì App chạy trên thiết bị (hoặc máy ảo) riêng biệt, bạn **KHÔNG THỂ DÙNG `localhost`**. Bạn phải chỉnh sửa code Flutter trỏ về IP của máy tính (PC) đang chạy Docker backend.

1. Lấy địa chỉ IP của PC mạng LAN: 
   - Mở CMD trên Windows, gõ `ipconfig`.
   - Tìm dòng `IPv4 Address` (Ví dụ: `192.168.1.5`).

2. Cập nhật URL trong code Flutter:
   - Sửa `lib/services/api_service.dart`: 
     `String baseUrl = 'http://192.168.1.5:8080/api';`
   - Sửa `lib/services/mqtt_service.dart`: 
     `String brokerUrl = '192.168.1.5';`

*(Lưu ý: Nếu test bằng thư viện Emulator của Android Studio, bạn có thể dùng IP Loopback đặc biệt là `10.0.2.2`).*

### 4.2. Khởi chạy và Test luồng E2E (End-to-End)

1. Mở terminal tại thư mục Flutter:
   ```bash
   cd d:\Balance_robot\RobotController
   flutter pub get
   flutter run
   ```
2. **App:** Thực hiện nút `Register` -> Điền Email/Password -> `Đăng ký`.
3. **App:** Thực hiện `Login` -> Trở về màn hình chính.
4. **App:** Vào màn hình quản lý Device -> Bấm dấu `+` nhập "ROBOT_01".
5. **App:** Chọn thiết bị con quay, bật kết nối MQTT.
6. **Docker (PC):** Gửi tọa độ MQTT mô phỏng:
   ```bash
   docker exec -it balance_robot_mqtt mosquitto_pub -t "robot/state/angle/ROBOT_01" -m '{"angle": -5.5}'
   ```
7. **Xác nhận:** App ngay lập tức nhảy giá trị thông số hoặc gauge trên màn hình lái thay đổi tương ứng. Tương tự với speed hoặc sensor.

---

## 5. Xử Lý Sự Cố Thường Gặp (Troubleshooting)

Qua quá trình debug và phát triển, những vấn đề sau đã được khắc phục nhưng có thể xuất hiện lại nếu cấu hình sai:

| Hiện Tượng Lỗi | Nguyên Nhân (Root Cause) & Cách Xử Lý |
|---|---|
| **Container API cứ loop restart liên tục (Exit Code 1), không lên được** | API báo lỗi `ClassNotFoundException: LiteWebJarsResourceResolver`. Đây là do phiên bản `springdoc-openapi` bị lệch. Dự án dùng Spring Boot 3.3.6, bạn phải đảm bảo trong `pom.xml` version `springdoc-openapi-starter-webmvc-ui` đang ở `2.6.0` thay vì `2.7.0`. |
| **API không start vì "Waiting for MQTT healthcheck" mãi mãi** | Image `eclipse-mosquitto` chuẩn alpine không chứa lệnh `nc`. Đảm bảo file `docker-compose.yml` tại phần `mqtt` healthcheck sử dụng câu lệnh command là: `mosquitto_pub -h localhost -p 1883 -t healthcheck -m ping -q 0` thay cho `nc`. |
| **App Android báo Connection Refused hoặc Timeout** | App đang cố gọi API vào IP sai. Hãy chắc chắn bạn đã đổi `baseUrl` từ `localhost` thành IPv4 của laptop như hướng dẫn ở bước 4.1. |
| **Broker MQTT báo ngắt kết nối khi App gửi tin nhắn** | Kiểm tra file cấu hình `mosquitto/mosquitto.conf`. Đảm bảo hai thiết lập bắt buộc được giữ lại: `listener 1883 0.0.0.0` và `allow_anonymous true`. |

---
*Chúc bạn test hệ thống thành công. Nếu cần thay đổi kiến trúc nội tại backend, vui lòng cập nhật lại tài liệu này!*
