# Balance Robot — Hệ thống Điều khiển & Giám sát Robot Tự Cân Bằng qua Wi-Fi

`Balance Robot` là dự án IoT toàn diện cho phép giám sát và điều khiển thời gian thực robot hai bánh tự cân bằng. Hệ thống bao gồm **ứng dụng di động Flutter**, **Backend Spring Boot**, **MQTT Broker (Eclipse Mosquitto)**, **Firmware ESP32 (ESP-IDF)** và cơ sở dữ liệu **PostgreSQL** để lưu trữ người dùng, thiết bị, dữ liệu telemetry và thông số bộ điều khiển PID.

Hệ thống được thiết kế để cung cấp:
- Đăng ký và đăng nhập tài khoản người dùng (xác thực JWT).
- Quản lý danh sách robot theo từng tài khoản.
- Cập nhật trạng thái và góc nghiêng của robot theo thời gian thực qua giao thức MQTT.
- Điều khiển robot từ ứng dụng di động với nhiều chế độ điều khiển.
- Lưu trữ và đồng bộ thông số bộ điều khiển PID theo từng `deviceId`.

---

## Các thành phần chính

### 1. Ứng dụng Di động (`RobotController` — Flutter)
Giao diện điều khiển và giám sát trung tâm dành cho người dùng:
- Đăng ký, đăng nhập và chọn robot từ danh sách thiết bị đã đăng ký.
- Kết nối trực tiếp MQTT để nhận thông số trạng thái thời gian thực.
- Điều khiển di chuyển qua các chế độ: cần điều khiển ảo (rocker), nút bấm (button) và cảm biến nghiêng (gravity).
- Tinh chỉnh thông số PID trực tiếp trên ứng dụng và tự động đồng bộ với Backend theo từng robot.

### 2. Backend (`backend/` — Spring Boot)
Xử lý nghiệp vụ trung tâm, bảo mật và lưu trữ dữ liệu:
- Cung cấp các API xác thực người dùng dựa trên JWT.
- Quản lý thiết bị theo từng tài khoản người dùng.
- Lưu trữ hồ sơ cấu hình PID và API đồng bộ thông số PID đang hoạt động theo `deviceId`.
- Lắng nghe bản tin MQTT để cập nhật trạng thái hiện diện của thiết bị và lưu lịch sử telemetry, sự kiện hoạt động vào PostgreSQL.

### 3. MQTT Broker (`Eclipse Mosquitto`)
Đóng vai trò kênh truyền thông độ trễ thấp giữa robot, backend và ứng dụng di động:
- Truyền dòng dữ liệu telemetry từ robot lên backend và ứng dụng di động.
- Gửi lệnh điều khiển di chuyển từ ứng dụng xuống robot.
- Phát thông số PID mới tới đúng topic của từng thiết bị.

### 4. Firmware (`Iot_robot` — ESP32 DevKit V1)
Chương trình nhúng viết trên ESP-IDF chịu trách nhiệm:
- Kết nối mạng Wi-Fi và giao thức MQTT.
- Đọc dữ liệu cảm biến quán tính **MPU6050** kết hợp bộ lọc bù (**Complementary Filter**) để ước lượng góc nghiêng chính xác.
- Thực thi vòng lặp điều khiển **PID góc nghiêng** giữ robot tự cân bằng.
- Xuất xung điều khiển hai động cơ qua mạch driver **A4988**.
- Gửi định kỳ bản tin telemetry, heartbeat và sự kiện thiết bị lên MQTT.

---

## Công nghệ sử dụng

- **Backend:** Java 22, Spring Boot 3.3.6, Spring Security + JWT, Spring Data JPA, PostgreSQL, Swagger / OpenAPI
- **Ứng dụng Di động:** Flutter, Dart, HTTP client, MQTT client, SharedPreferences, Google Fonts
- **Firmware & Phần cứng:** ESP-IDF, ESP32 DevKit V1, cảm biến IMU MPU6050, driver động cơ A4988
- **Hạ tầng & Đóng gói:** Docker, Docker Compose, Eclipse Mosquitto

---

## Luồng hoạt động tổng quan

1. Người dùng đăng nhập trên ứng dụng Flutter.
2. Ứng dụng gọi REST API tới Backend để xác thực và lấy danh sách thiết bị.
3. Ứng dụng kết nối tới MQTT Broker để nhận trạng thái robot theo thời gian thực.
4. Mạch ESP32 liên tục gửi dữ liệu góc nghiêng, heartbeat và sự kiện qua MQTT.
5. Backend lắng nghe các bản tin MQTT, cập nhật trạng thái online của robot và lưu trữ bản ghi telemetry đầy đủ từ topic `robot/state/full/{deviceId}`.
6. Khi người dùng điều chỉnh thông số PID trên ứng dụng, cấu hình được tự động lưu về Backend theo `deviceId`.
7. Khi nhấn `SEND`, ứng dụng phát thông số PID hiện tại lên các MQTT topic tương ứng để robot áp dụng ngay lập tức.

---

## Cấu trúc thư mục

```text
WiFi-Controlled-Self-Balancing-Robot/
├── backend/                # Backend Spring Boot + Docker Compose + cấu hình Mosquitto
├── Iot_robot/              # Firmware ESP32 DevKit V1 (ESP-IDF)
├── RobotController/        # Ứng dụng di động Flutter
├── TESTING_GUIDE.md        # Hướng dẫn kiểm thử hệ thống chi tiết
└── README.md
```

---

## Danh sách API & MQTT Topic chính

### REST APIs (8 Endpoints)
- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/devices`
- `POST /api/devices`
- `GET /api/devices/{deviceId}/pid`
- `PUT /api/devices/{deviceId}/pid`
- `GET /api/telemetry/{deviceId}/latest`
- `GET /api/events/{deviceId}`

### MQTT Topics (9 Topics)
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

## Hướng dẫn chạy nhanh

### 1. Khởi chạy Backend & MQTT Broker bằng Docker
```bash
cd backend
docker compose up --build -d
```

### 2. Khởi chạy ứng dụng Flutter
```bash
cd RobotController
flutter pub get
flutter run
```
*(Khi chạy trên điện thoại vật lý, nhập `Server IP / Host` là địa chỉ IP LAN của máy đang chạy backend; nếu dùng máy ảo Android Emulator, có thể dùng `10.0.2.2`.)*

### 3. Biên dịch & nạp Firmware ESP32
```bash
cd Iot_robot
idf.py set-target esp32
idf.py menuconfig
idf.py build flash monitor
```

---

## Tài liệu liên quan & Ghi chú kỹ thuật

- Xem hướng dẫn kiểm thử chi tiết tại: [TESTING_GUIDE.md](./TESTING_GUIDE.md)
- Backend đóng vai trò nguồn dữ liệu chuẩn (source of truth) cho thông số PID khi có kết nối mạng; ứng dụng di động vẫn duy trì bộ nhớ đệm cục bộ (local cache) để không mất cấu hình khi mạng gián đoạn tạm thời.
- Topic `robot/state/full/{deviceId}` được Backend sử dụng để lưu trữ đầy đủ lịch sử bản ghi telemetry vào PostgreSQL.
- Thông số `speed PID` đã được đồng bộ xuyên suốt giữa Backend và ứng dụng di động để sẵn sàng mở rộng, dù phiên bản phần cứng ESP32 v1 hiện tại chưa sử dụng vòng PID tốc độ do chưa lắp encoder.
