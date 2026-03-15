# Báo Cáo Tiến Độ Giai Đoạn 50% - Dự Án Robot Cân Bằng (Balance Robot)

Dưới đây là tổng hợp các chức năng và công việc đã hoàn thành trong giai đoạn đầu (50%) của dự án. Hệ thống đã được định hình kiến trúc lõi, bao gồm Backend (API & MQTT Broker), Cơ sở dữ liệu, và Ứng dụng điều khiển trên thiết bị di động.

---

## 1. Hệ Thống Backend (Java Spring Boot 3.3.6)
Tầng Backend đóng vai trò là bộ não trung tâm, xử lý logic nghiệp vụ, lưu trữ dữ liệu và cầu nối giao tiếp thời gian thực:
- **Xác thực & Phân quyền (Authentication):** 
  - Cung cấp API Đăng ký và Đăng nhập bảo mật với JWT Token (`/api/auth/register`, `/api/auth/login`).
- **Quản lý thiết bị (Device Management):** 
  - Cho phép người dùng đăng ký thiết bị robot của mình (`/api/devices`).
  - Lấy danh sách và quản lý trạng thái của các thiết bị thuộc quyền sở hữu.
- **Quản lý cấu hình điều khiển:** 
  - Thực hiện các thao tác CRUD (Tạo, Đọc, Cập nhật, Xóa) cho các hồ sơ thông số điều khiển (PID Profiles), cho phép lưu và kích hoạt thông số từ xa.
- **Tích hợp giao diện kiểm thử API:** 
  - Tự động sinh tài liệu API bằng OpenAPI/Swagger UI giúp kiểm thử trực quan trên Web (tại cổng `8080/swagger-ui.html`).

## 2. Hệ Thống Giao Tiếp Thời Gian Thực (MQTT Broker)
Ứng dụng sử dụng giao thức siêu nhẹ MQTT để truyền luồng dữ liệu giữa Robot tự hành và Server/App:
- **Khởi tạo và cấu hình Mosquitto Broker (v2.0):** 
  - Lắng nghe trên cổng `1883`, cho phép truy cập và định tuyến các bản tin.
- **Xây dựng MQTT Bridge (trên API BE):** 
  - **Telemetry Sync:** Lắng nghe và bóc tách dữ liệu từ các Topic của robot:
    - Góc nghiêng: `robot/state/angle/{deviceId}`
    - Tốc độ: `robot/state/speed/{deviceId}`
    - Cảm biến linh kiện (Gia tốc/Gyro): `robot/state/sensors/{deviceId}`
  - **Quản lý trạng thái sống trễ (Heartbeat):** Theo dõi tín hiệu `robot/heartbeat/{deviceId}` mỗi 60s để đánh dấu thiết bị đang trực tuyến (ONLINE) hoặc ngắt kết nối.

## 3. Hạ Tầng & Triển Khai (Infrastructure - Docker)
Toàn bộ môi trường hệ thống mạng được đóng gói để triển khai nhanh chóng và đồng bộ:
- Đóng gói (Container hóa) hệ thống thành 3 dịch vụ liên kết chặt chẽ qua Docker Compose:
  1. `balance_robot_db`: Hệ quản trị Cơ sở dữ liệu PostgreSQL 16.
  2. `balance_robot_mqtt`: Máy chủ thông điệp Eclipse Mosquitto.
  3. `balance_robot_api`: Ứng dụng Spring Boot Backend.
- Tích hợp tính năng tự động kiểm tra sức khỏe của dịch vụ (Healthchecks), nhằm tránh lỗi khởi động chéo giữa các service (VD: API đợi MQTT Broker khởi động xong mới chạy).

## 4. Ứng Dụng Di Động - RobotController (Flutter)
Ứng dụng đa nền tảng dành cho SmartPhone đóng vai trò giao diện điều khiển và giám sát trực tiếp cho người dùng:
- **Giao diện người dùng (UI):** 
  - Đã hoàn thiện các luồng màn hình cơ bản: Màn hình Login/Đăng ký người dùng.
  - Màn hình Quản lý Danh sách Thiết bị (Thêm mới thiết bị).
- **Kết nối Dual-Channel (Hai kênh):**
  - **Giao tiếp HTTP:** Kết nối đến RESTful API để xác thực và lấy thông tin cấu hình từ PC/Server.
  - **Giao tiếp MQTT Client:** Đăng ký (Subscribe) trực tiếp vào luồng dữ liệu MQTT để theo dõi biểu đồ/cụm đồng hồ hiển thị các thông số trạng thái vật lý của Robot theo thời gian thực (góc nghiêng, tốc độ).

## 5. Kiểm Thử & Kiểm Soát Lỗi (Testing & Debugging)
- Xây dựng tài liệu **Hướng Dẫn Test Toàn Diện** (`TESTING_GUIDE.md`) cho mọi thành phần.
- Đã khắc phục triệt để các lỗi về tương thích IP thiết bị thật mạng LAN, sửa lỗi crash vòng lặp của container, và xung đột thư viện Springdoc/Docker network.
- Xác nhận luồng E2E (End-to-End) chạy xuyên suốt thành công: *Trạm phát lập trình MQTT gửi dữ liệu góc nghiêng => Backend nhận lệnh phân tích => App Android cập nhật thay đổi tức thì trên màn hình lái.*
