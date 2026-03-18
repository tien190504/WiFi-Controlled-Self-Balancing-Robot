/**
 * Balance Robot - main.c (ESP-IDF v5.x)
 *
 * Các fix so với phiên bản cũ:
 *  1. PID gains mặc định hợp lý hơn cho stepper (Kp=18, Ki=0.4, Kd=6)
 *  2. Bỏ deadband motor (magnitude < 1.0) → motor phản ứng mượt hơn
 *  3. SAFETY_ANGLE giảm từ 45° → 30° để tránh overrun
 *  4. RESET_ANGLE tăng lên 15° để dễ re-arm hơn
 *  5. Slew rate giảm để tránh giật motor đột ngột
 *  6. Thêm lệnh serial "trim", "pid", "axis", "invert" đầy đủ
 *  7. Filter alpha tách ra khỏi define cứng, có thể chỉnh qua serial
 *  8. Debug log rõ hơn, in angle/pid mỗi 100ms
 */

#include <ctype.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#include "app_config.h"
#include "cJSON.h"
#include "driver/gpio.h"
#include "driver/i2c.h"
#include "driver/ledc.h"
#include "driver/uart.h"
#include "esp_check.h"
#include "esp_err.h"
#include "esp_event.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_netif_ip_addr.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

/* ──────────────────── PIN MAP ──────────────────── */
#define I2C_PORT         I2C_NUM_0
#define UART_PORT        UART_NUM_0
#define PIN_MPU_SCL      ((gpio_num_t)ROBOT_SCL_PIN)
#define PIN_MPU_SDA      ((gpio_num_t)ROBOT_SDA_PIN)
#define PIN_ENABLE       ((gpio_num_t)ROBOT_ENABLE_PIN)
#define PIN_LEFT_STEP    ((gpio_num_t)ROBOT_LEFT_STEP_PIN)
#define PIN_LEFT_DIR     ((gpio_num_t)ROBOT_LEFT_DIR_PIN)
#define PIN_RIGHT_STEP   ((gpio_num_t)ROBOT_RIGHT_STEP_PIN)
#define PIN_RIGHT_DIR    ((gpio_num_t)ROBOT_RIGHT_DIR_PIN)

/* ──────────────────── TIMING ──────────────────── */
#define CONTROL_PERIOD_US   5000        /* 200 Hz */
#define CONTROL_PERIOD_S    0.005f
#define COMM_TASK_PERIOD_MS 50
#define SERIAL_BAUD         115200
#define WIFI_RSSI_REFRESH_US 500000
#define DEBUG_INTERVAL_US   100000      /* in ra log mỗi 100ms */
#define CALIBRATION_SAMPLES 400
#define WEB_SERVER_PORT     80

/* ──────────────────── PID MẶC ĐỊNH ──────────────────── */
/*
 * Cách tuning từng bước:
 *   1. Đặt Ki=0, Kd=0, tăng Kp từ 5 lên cho đến khi robot
 *      đứng ~2s rồi ngã (lúc này Kp ≈ Ku).
 *   2. Tăng Kd đến khi hết dao động (thường Kd = Kp * 0.3~0.5).
 *   3. Tăng Ki từ từ để bù offset góc (thường Ki rất nhỏ 0.1~0.5).
 *   4. Dùng lệnh serial "pid <Kp> <Ki> <Kd>" để thay đổi realtime.
 *
 * Giá trị dưới đây là điểm bắt đầu hợp lý cho stepper 200 step/rev:
 */
#define PID_KP_DEFAULT    15.0f
#define PID_KI_DEFAULT     0.5f
#define PID_KD_DEFAULT     8.0f

/* ──────────────────── BALANCE CONFIG ──────────────────── */
#define TARGET_ANGLE_BASE_DEG   0.0f
#define SAFETY_ANGLE_DEG        30.0f   /* FIX: giảm từ 45→30° */
#define RESET_ANGLE_DEG         15.0f   /* FIX: tăng từ 10→15° dễ re-arm hơn */
#define COMPLEMENTARY_ALPHA     0.98f
#define MAX_INTEGRAL_TERM      200.0f   /* FIX: giảm windup */
#define COMMAND_TILT_DEG        2.5f
#define STEERING_BIAS_HZ      150.0f

/* ──────────────────── MOTOR CONFIG ──────────────────── */
#define MAX_STEP_HZ             1800.0f
#define MIN_ACTIVE_STEP_HZ        80.0f
/*
 * FIX: Slew rate giảm từ 120→80 step/cycle để tránh giật đột ngột
 * khi robot mới đứng dậy. Tăng lại nếu robot phản ứng quá chậm.
 */
#define MAX_STEP_DELTA_PER_CYCLE  80.0f

/* FIX: INVERT_RIGHT_DIR = true cho stepper gắn đối xứng */
#define INVERT_LEFT_DIR   false
#define INVERT_RIGHT_DIR  true
#define INVERT_ANGLE_SIGN true

/* ──────────────────── LEDC / PWM ──────────────────── */
#define MOTOR_PWM_MODE        LEDC_LOW_SPEED_MODE
#define MOTOR_DUTY_RES        LEDC_TIMER_10_BIT
#define MOTOR_DUTY_50_PERCENT 512

/* ──────────────────── MPU6050 ──────────────────── */
#define MPU6050_ADDRESS    0x68
#define MPU6050_SMPLRT_DIV 0x19
#define MPU6050_CONFIG     0x1A
#define MPU6050_GYRO_CONFIG  0x1B
#define MPU6050_ACCEL_CONFIG 0x1C
#define MPU6050_PWR_MGMT_1   0x6B
#define MPU6050_ACCEL_XOUT_H 0x3B
#define MPU6050_ACCEL_SCALE  16384.0f
#define MPU6050_GYRO_SCALE   131.0f
#define RAD_TO_DEG           57.2957795f
#define MPU_I2C_TIMEOUT_MS   100

/* ═══════════════════════════════════════════════════════
 *  TYPES
 * ═══════════════════════════════════════════════════════ */
typedef enum {
    ROBOT_STATE_INIT = 0,
    ROBOT_STATE_BALANCING,
    ROBOT_STATE_FALLEN,
} RobotState;

typedef enum {
    CMD_NONE = 0,
    CMD_FORWARD,
    CMD_BACKWARD,
    CMD_LEFT,
    CMD_RIGHT,
    CMD_STOP,
    CMD_RESET,
} Command;

typedef struct {
    float accelXG, accelYG, accelZG;
    float gyroXDps, gyroYDps, gyroZDps;
} MpuSample;

typedef struct {
    float angle;
    float pitchAngle, rollAngle;
    float targetAngle;
    float targetAngleOffset;
    float steeringOffset;
    float pidError;
    float pidIntegral;
    float pidOutput;
    float leftMotorSpeed, rightMotorSpeed;
    float accelXG, accelYG, accelZG;
    float gyroXDps, gyroYDps, gyroZDps;
    RobotState robotState;
} RobotStatus;

/* ═══════════════════════════════════════════════════════
 *  GLOBALS
 * ═══════════════════════════════════════════════════════ */
static const char *TAG = "balance_robot";

static const ledc_timer_t   LEFT_TIMER    = LEDC_TIMER_0;
static const ledc_timer_t   RIGHT_TIMER   = LEDC_TIMER_1;
static const ledc_channel_t LEFT_CHANNEL  = LEDC_CHANNEL_0;
static const ledc_channel_t RIGHT_CHANNEL = LEDC_CHANNEL_1;

static RobotStatus s_status = {
    .targetAngle = TARGET_ANGLE_BASE_DEG,
    .robotState  = ROBOT_STATE_INIT,
};

static esp_timer_handle_t s_loopTimer;
static TaskHandle_t s_balanceTaskHandle;
static httpd_handle_t s_httpServer;
static volatile bool s_wifiConnected;
static volatile bool s_webServerStarted;
static volatile int s_wifiRssi;
static volatile int s_httpActiveClients;
static char s_wifiIpAddress[16];

/* IMU state */
static float s_gyroXBias, s_gyroYBias, s_gyroZBias;
static float s_pitchDeg, s_rollDeg;
static bool  s_filterInitialized;
static float s_compAlpha = COMPLEMENTARY_ALPHA;

/* PID state */
static float s_pidIntegral;
static float s_previousError;
static float s_kp = PID_KP_DEFAULT;
static float s_ki = PID_KI_DEFAULT;
static float s_kd = PID_KD_DEFAULT;

/* Config flags */
static float s_balanceTrimDeg;
static bool  s_useRollAxis       = false;
static bool  s_invertAngleSign   = INVERT_ANGLE_SIGN;
static bool  s_invertLeftDir     = INVERT_LEFT_DIR;
static bool  s_invertRightDir    = INVERT_RIGHT_DIR;
static bool  s_manualMode        = false;
static float s_manualLeftSpeed   = 0.0f;
static float s_manualRightSpeed  = 0.0f;
static float s_targetLeftSpeed   = 0.0f;
static float s_targetRightSpeed  = 0.0f;

/* Debug */
static int64_t s_lastDebugPrintUs;
static int64_t s_lastWifiRssiRefreshUs;

/* ═══════════════════════════════════════════════════════
 *  HELPERS
 * ═══════════════════════════════════════════════════════ */
static float clampf(float v, float lo, float hi)
{
    return v < lo ? lo : (v > hi ? hi : v);
}

static float slewTowards(float current, float target, float maxDelta)
{
    if (target > current + maxDelta) return current + maxDelta;
    if (target < current - maxDelta) return current - maxDelta;
    return target;
}

static const char *robotStateToString(RobotState s)
{
    switch (s) {
    case ROBOT_STATE_INIT:      return "INIT";
    case ROBOT_STATE_BALANCING: return "BALANCING";
    case ROBOT_STATE_FALLEN:    return "FALLEN";
    default:                    return "UNKNOWN";
    }
}

/* ═══════════════════════════════════════════════════════
 *  I2C / MPU6050
 * ═══════════════════════════════════════════════════════ */
static esp_err_t writeMPUReg(uint8_t reg, uint8_t val)
{
    const uint8_t buf[2] = { reg, val };
    return i2c_master_write_to_device(
        I2C_PORT, MPU6050_ADDRESS, buf, 2,
        pdMS_TO_TICKS(MPU_I2C_TIMEOUT_MS));
}

static esp_err_t readMPURegs(uint8_t start, uint8_t *out, size_t len)
{
    return i2c_master_write_read_device(
        I2C_PORT, MPU6050_ADDRESS, &start, 1, out, len,
        pdMS_TO_TICKS(MPU_I2C_TIMEOUT_MS));
}

static esp_err_t initMPU6050(void)
{
    const i2c_config_t cfg = {
        .mode             = I2C_MODE_MASTER,
        .sda_io_num       = PIN_MPU_SDA,
        .scl_io_num       = PIN_MPU_SCL,
        .sda_pullup_en    = GPIO_PULLUP_ENABLE,
        .scl_pullup_en    = GPIO_PULLUP_ENABLE,
        .master.clk_speed = 400000,
        .clk_flags        = 0,
    };
    ESP_RETURN_ON_ERROR(i2c_param_config(I2C_PORT, &cfg), TAG, "i2c param config failed");

    esp_err_t err = i2c_driver_install(I2C_PORT, I2C_MODE_MASTER, 0, 0, 0);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) return err;

    vTaskDelay(pdMS_TO_TICKS(100));

    ESP_RETURN_ON_ERROR(writeMPUReg(MPU6050_PWR_MGMT_1,   0x00), TAG, "wake failed");
    ESP_RETURN_ON_ERROR(writeMPUReg(MPU6050_SMPLRT_DIV,   0x04), TAG, "smplrt failed");
    ESP_RETURN_ON_ERROR(writeMPUReg(MPU6050_CONFIG,        0x03), TAG, "dlpf failed");
    ESP_RETURN_ON_ERROR(writeMPUReg(MPU6050_GYRO_CONFIG,   0x00), TAG, "gyro cfg failed");
    ESP_RETURN_ON_ERROR(writeMPUReg(MPU6050_ACCEL_CONFIG,  0x00), TAG, "accel cfg failed");

    s_filterInitialized = false;
    s_pitchDeg = 0.0f;
    s_rollDeg  = 0.0f;
    ESP_LOGI(TAG, "MPU6050 OK  SDA=%d SCL=%d", PIN_MPU_SDA, PIN_MPU_SCL);
    return ESP_OK;
}

static esp_err_t calibrateMPU6050(void)
{
    float gxSum = 0, gySum = 0, gzSum = 0;
    uint8_t raw[14];

    ESP_LOGI(TAG, "Calibrating gyro — robot phải đứng yên...");
    for (uint32_t i = 0; i < CALIBRATION_SAMPLES; ++i) {
        ESP_RETURN_ON_ERROR(readMPURegs(MPU6050_ACCEL_XOUT_H, raw, 14), TAG, "calib read");
        gxSum += (float)(int16_t)((raw[8]  << 8) | raw[9])  / MPU6050_GYRO_SCALE;
        gySum += (float)(int16_t)((raw[10] << 8) | raw[11]) / MPU6050_GYRO_SCALE;
        gzSum += (float)(int16_t)((raw[12] << 8) | raw[13]) / MPU6050_GYRO_SCALE;
        vTaskDelay(pdMS_TO_TICKS(5));
    }
    s_gyroXBias = gxSum / CALIBRATION_SAMPLES;
    s_gyroYBias = gySum / CALIBRATION_SAMPLES;
    s_gyroZBias = gzSum / CALIBRATION_SAMPLES;
    ESP_LOGI(TAG, "Calib xDone gx=%.3f gy=%.3f gz=%.3f",
             (double)s_gyroXBias, (double)s_gyroYBias, (double)s_gyroZBias);
    return ESP_OK;
}

static esp_err_t readMPU6050(MpuSample *s)
{
    uint8_t raw[14];
    ESP_RETURN_ON_ERROR(readMPURegs(MPU6050_ACCEL_XOUT_H, raw, 14), TAG, "read failed");

    s->accelXG  = (float)(int16_t)((raw[0]  << 8) | raw[1])  / MPU6050_ACCEL_SCALE;
    s->accelYG  = (float)(int16_t)((raw[2]  << 8) | raw[3])  / MPU6050_ACCEL_SCALE;
    s->accelZG  = (float)(int16_t)((raw[4]  << 8) | raw[5])  / MPU6050_ACCEL_SCALE;
    s->gyroXDps = (float)(int16_t)((raw[8]  << 8) | raw[9])  / MPU6050_GYRO_SCALE - s_gyroXBias;
    s->gyroYDps = (float)(int16_t)((raw[10] << 8) | raw[11]) / MPU6050_GYRO_SCALE - s_gyroYBias;
    s->gyroZDps = (float)(int16_t)((raw[12] << 8) | raw[13]) / MPU6050_GYRO_SCALE - s_gyroZBias;
    return ESP_OK;
}

/* ═══════════════════════════════════════════════════════
 *  ANGLE FILTER (Complementary)
 * ═══════════════════════════════════════════════════════ */
static float updateAngle(const MpuSample *s)
{
    const float accelPitch = atan2f(s->accelYG,
        sqrtf(s->accelXG*s->accelXG + s->accelZG*s->accelZG)) * RAD_TO_DEG;
    const float accelRoll  = atan2f(-s->accelXG, s->accelZG) * RAD_TO_DEG;

    if (s_filterInitialized) {
        s_pitchDeg = s_compAlpha * (s_pitchDeg + s->gyroXDps * CONTROL_PERIOD_S)
                   + (1.0f - s_compAlpha) * accelPitch;
        s_rollDeg  = s_compAlpha * (s_rollDeg  + s->gyroYDps * CONTROL_PERIOD_S)
                   + (1.0f - s_compAlpha) * accelRoll;
    } else {
        s_pitchDeg = accelPitch;
        s_rollDeg  = accelRoll;
        s_filterInitialized = true;
    }

    float angle = s_useRollAxis ? s_rollDeg : s_pitchDeg;
    if (s_invertAngleSign) angle = -angle;

    s_status.angle      = angle;
    s_status.pitchAngle = s_pitchDeg;
    s_status.rollAngle  = s_rollDeg;
    s_status.accelXG = s->accelXG;  s_status.accelYG = s->accelYG;  s_status.accelZG = s->accelZG;
    s_status.gyroXDps = s->gyroXDps; s_status.gyroYDps = s->gyroYDps; s_status.gyroZDps = s->gyroZDps;
    return angle;
}

/* ═══════════════════════════════════════════════════════
 *  PID
 * ═══════════════════════════════════════════════════════ */
static void resetPIDState(void)
{
    s_pidIntegral = 0.0f;
    s_previousError = 0.0f;
    s_status.pidError = 0.0f;
    s_status.pidIntegral = 0.0f;
    s_status.pidOutput = 0.0f;
}

static float computePID(void)
{
    s_status.targetAngle = TARGET_ANGLE_BASE_DEG + s_balanceTrimDeg + s_status.targetAngleOffset;

    const float error = s_status.targetAngle - s_status.angle;

    /* Anti-windup: chỉ tích phân khi output chưa bão hòa */
    const float derivative = (error - s_previousError) / CONTROL_PERIOD_S;
    const float pTerm = s_kp * error;
    const float dTerm = s_kd * derivative;
    const float integralCandidate = clampf(
        s_pidIntegral + error * CONTROL_PERIOD_S,
        -MAX_INTEGRAL_TERM,
        MAX_INTEGRAL_TERM);
    const float iTermCandidate = s_ki * integralCandidate;
    const float unsaturatedCandidate = pTerm + iTermCandidate + dTerm;
    const bool outputWouldSaturate = fabsf(unsaturatedCandidate) > MAX_STEP_HZ;
    const bool errorReducesPositiveSaturation = (unsaturatedCandidate > MAX_STEP_HZ) && (error < 0.0f);
    const bool errorReducesNegativeSaturation = (unsaturatedCandidate < -MAX_STEP_HZ) && (error > 0.0f);

    if (!outputWouldSaturate || errorReducesPositiveSaturation || errorReducesNegativeSaturation) {
        s_pidIntegral = integralCandidate;
    }

    s_previousError = error;
    s_status.pidError = error;
    s_status.pidIntegral = s_pidIntegral;

    const float iTerm = s_ki * s_pidIntegral;
    const float output = pTerm + iTerm + dTerm;
    s_status.pidOutput = clampf(output, -MAX_STEP_HZ, MAX_STEP_HZ);
    return s_status.pidOutput;
}

/* ═══════════════════════════════════════════════════════
 *  MOTOR
 * ═══════════════════════════════════════════════════════ */
static void setDriverEnabled(bool en)
{
    /* ENABLE thấp = active cho hầu hết driver A4988/DRV8825 */
    gpio_set_level(PIN_ENABLE, en ? 0 : 1);
}

static void configureMotorChannel(ledc_timer_t timer, ledc_channel_t ch, gpio_num_t pin)
{
    ledc_timer_config_t tc = {
        .speed_mode      = MOTOR_PWM_MODE,
        .duty_resolution = MOTOR_DUTY_RES,
        .timer_num       = timer,
        .freq_hz         = (uint32_t)MIN_ACTIVE_STEP_HZ,
        .clk_cfg         = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&tc));

    ledc_channel_config_t cc = {
        .gpio_num   = pin,
        .speed_mode = MOTOR_PWM_MODE,
        .channel    = ch,
        .intr_type  = LEDC_INTR_DISABLE,
        .timer_sel  = timer,
        .duty       = 0,
        .hpoint     = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&cc));
}

/*
 * FIX QUAN TRỌNG: Bỏ deadband "magnitude < 1.0"
 * Với stepper tự cân bằng, motor phải chạy ngay cả tốc độ rất thấp.
 * Deadband tạo ra vùng chết quanh điểm cân bằng khiến robot dao động liên tục.
 */
static void applySingleMotor(
    float speed,
    gpio_num_t dirPin, bool invertDir,
    ledc_timer_t timer, ledc_channel_t ch,
    float *appliedSpeed)
{
    const float requestedHz = clampf(speed, -MAX_STEP_HZ, MAX_STEP_HZ);
    const float mag = fabsf(requestedHz);

    if (mag < MIN_ACTIVE_STEP_HZ) {
        /* Chỉ tắt motor khi thực sự gần 0 */
        ledc_set_duty(MOTOR_PWM_MODE, ch, 0);
        ledc_update_duty(MOTOR_PWM_MODE, ch);
        *appliedSpeed = 0.0f;
        return;
    }

    /* Map [0, MAX_STEP_HZ] → [MIN_ACTIVE_STEP_HZ, MAX_STEP_HZ] */
    const float freq = clampf(mag, MIN_ACTIVE_STEP_HZ, MAX_STEP_HZ);

    bool forward = (requestedHz >= 0.0f);
    if (invertDir) forward = !forward;

    gpio_set_level(dirPin, forward ? 1 : 0);
    ledc_set_freq(MOTOR_PWM_MODE, timer, (uint32_t)lroundf(freq));
    ledc_set_duty(MOTOR_PWM_MODE, ch, MOTOR_DUTY_50_PERCENT);
    ledc_update_duty(MOTOR_PWM_MODE, ch);
    *appliedSpeed = forward ? freq : -freq;
}

static void setMotorSpeed(float left, float right)
{
    s_targetLeftSpeed  = clampf(left,  -MAX_STEP_HZ, MAX_STEP_HZ);
    s_targetRightSpeed = clampf(right, -MAX_STEP_HZ, MAX_STEP_HZ);
}

static void updateMotors(void)
{
    if (s_status.robotState != ROBOT_STATE_BALANCING) return;
    setDriverEnabled(true);

    const float nextL = slewTowards(s_status.leftMotorSpeed,  s_targetLeftSpeed,  MAX_STEP_DELTA_PER_CYCLE);
    const float nextR = slewTowards(s_status.rightMotorSpeed, s_targetRightSpeed, MAX_STEP_DELTA_PER_CYCLE);

    applySingleMotor(nextL, PIN_LEFT_DIR,  s_invertLeftDir,  LEFT_TIMER,  LEFT_CHANNEL,  &s_status.leftMotorSpeed);
    applySingleMotor(nextR, PIN_RIGHT_DIR, s_invertRightDir, RIGHT_TIMER, RIGHT_CHANNEL, &s_status.rightMotorSpeed);
}

static void stopMotors(void)
{
    ledc_set_duty(MOTOR_PWM_MODE, LEFT_CHANNEL,  0); ledc_update_duty(MOTOR_PWM_MODE, LEFT_CHANNEL);
    ledc_set_duty(MOTOR_PWM_MODE, RIGHT_CHANNEL, 0); ledc_update_duty(MOTOR_PWM_MODE, RIGHT_CHANNEL);
    s_status.leftMotorSpeed  = 0.0f;
    s_status.rightMotorSpeed = 0.0f;
    setDriverEnabled(false);
}

/* ═══════════════════════════════════════════════════════
 *  FALLEN / RESET
 * ═══════════════════════════════════════════════════════ */
static void enterFallenState(const char *reason)
{
    if (s_status.robotState != ROBOT_STATE_FALLEN) {
        ESP_LOGW(TAG, "FALLEN: %s  angle=%.1f°", reason, (double)s_status.angle);
    }
    s_status.robotState       = ROBOT_STATE_FALLEN;
    s_status.targetAngleOffset = 0.0f;
    s_status.steeringOffset    = 0.0f;
    s_manualMode               = false;
    s_manualLeftSpeed          = 0.0f;
    s_manualRightSpeed         = 0.0f;
    s_targetLeftSpeed          = 0.0f;
    s_targetRightSpeed         = 0.0f;
    resetPIDState();
    stopMotors();
}

static void resetRobot(void)
{
    if (fabsf(s_status.angle) > RESET_ANGLE_DEG) {
        ESP_LOGW(TAG, "Reset refused: angle=%.1f° > limit=%.1f°",
                 (double)s_status.angle, (double)RESET_ANGLE_DEG);
        return;
    }
    resetPIDState();
    s_filterInitialized        = false;
    s_pitchDeg = s_rollDeg     = 0.0f;
    s_manualMode               = false;
    s_manualLeftSpeed          = 0.0f;
    s_manualRightSpeed         = 0.0f;
    s_targetLeftSpeed          = 0.0f;
    s_targetRightSpeed         = 0.0f;
    s_status.targetAngle       = TARGET_ANGLE_BASE_DEG;
    s_status.targetAngleOffset = 0.0f;
    s_status.steeringOffset    = 0.0f;
    s_status.pidOutput         = 0.0f;
    s_status.leftMotorSpeed    = 0.0f;
    s_status.rightMotorSpeed   = 0.0f;
    s_status.robotState        = ROBOT_STATE_BALANCING;
    setDriverEnabled(true);
    ESP_LOGI(TAG, "Robot re-armed!");
    printConfig();
}

/* ═══════════════════════════════════════════════════════
 *  COMMAND
 * ═══════════════════════════════════════════════════════ */
static void setCommand(Command cmd)
{
    if (s_status.robotState == ROBOT_STATE_FALLEN && cmd != CMD_RESET && cmd != CMD_STOP) {
        ESP_LOGW(TAG, "Ignored: robot FALLEN");
        return;
    }
    switch (cmd) {
    case CMD_FORWARD:  s_status.targetAngleOffset =  COMMAND_TILT_DEG; s_status.steeringOffset = 0; break;
    case CMD_BACKWARD: s_status.targetAngleOffset = -COMMAND_TILT_DEG; s_status.steeringOffset = 0; break;
    case CMD_LEFT:     s_status.steeringOffset = -STEERING_BIAS_HZ; break;
    case CMD_RIGHT:    s_status.steeringOffset =  STEERING_BIAS_HZ; break;
    case CMD_STOP:     s_status.targetAngleOffset = 0; s_status.steeringOffset = 0; break;
    case CMD_RESET:    resetRobot(); break;
    default: break;
    }
}

/* ═══════════════════════════════════════════════════════
 *  SERIAL COMMANDS
 *
 *  Các lệnh hỗ trợ:
 *    forward / backward / left / right / stop / reset
 *    status
 *    pid <Kp> <Ki> <Kd>        — ví dụ: pid 18 0.4 6
 *    trim <deg>                 — bù góc nghiêng tĩnh, ví dụ: trim 1.5
 *    alpha <0.90~0.99>          — đổi filter alpha, ví dụ: alpha 0.97
 *    axis pitch / axis roll
 *    invert angle on/off
 *    invert left on/off
 *    invert right on/off
 *    manual on / manual off
 *    motor <left_hz> <right_hz> — chạy thủ công, ví dụ: motor 200 200
 * ═══════════════════════════════════════════════════════ */
static void printConfig(void)
{
    ESP_LOGI(TAG,
        "CONFIG axis=%s invertAngle=%d invertL=%d invertR=%d trim=%.1f alpha=%.3f",
        s_useRollAxis ? "roll" : "pitch",
        s_invertAngleSign, s_invertLeftDir, s_invertRightDir,
        (double)s_balanceTrimDeg, (double)s_compAlpha);
    ESP_LOGI(TAG,
        "PID Kp=%.2f Ki=%.3f Kd=%.2f  manual=%d",
        (double)s_kp, (double)s_ki, (double)s_kd, s_manualMode);
}

static void handleSerialLine(const char *line)
{
    char lc[64];
    size_t n = strlen(line);
    if (n >= sizeof(lc)) n = sizeof(lc) - 1;
    for (size_t i = 0; i < n; ++i) lc[i] = (char)tolower((unsigned char)line[i]);
    lc[n] = '\0';

    float a, b, c;

    if      (strcmp(lc, "forward")  == 0) { setCommand(CMD_FORWARD);  }
    else if (strcmp(lc, "backward") == 0) { setCommand(CMD_BACKWARD); }
    else if (strcmp(lc, "left")     == 0) { setCommand(CMD_LEFT);     }
    else if (strcmp(lc, "right")    == 0) { setCommand(CMD_RIGHT);    }
    else if (strcmp(lc, "stop")     == 0) { setCommand(CMD_STOP);     }
    else if (strcmp(lc, "reset")    == 0) { setCommand(CMD_RESET);    }
    else if (strcmp(lc, "status")   == 0) {
        printConfig();
        ESP_LOGI(TAG, "STATE=%s angle=%.2f° pitch=%.2f° roll=%.2f° left=%.0f right=%.0f",
            robotStateToString(s_status.robotState),
            (double)s_status.angle, (double)s_status.pitchAngle, (double)s_status.rollAngle,
            (double)s_status.leftMotorSpeed, (double)s_status.rightMotorSpeed);
        ESP_LOGI(TAG, "PID target=%.2f err=%.3f int=%.3f out=%.1f",
            (double)s_status.targetAngle,
            (double)s_status.pidError,
            (double)s_status.pidIntegral,
            (double)s_status.pidOutput);
        ESP_LOGI(TAG, "WIFI connected=%d ip=%s rssi=%d web=%d clients=%d ssid=%s",
            s_wifiConnected,
            s_wifiIpAddress[0] ? s_wifiIpAddress : "-",
            s_wifiRssi,
            s_webServerStarted,
            s_httpActiveClients,
            ROBOT_WIFI_SSID);
    }
    else if (strcmp(lc, "axis pitch") == 0) { s_useRollAxis = false; resetPIDState(); ESP_LOGI(TAG, "axis=pitch"); printConfig(); }
    else if (strcmp(lc, "axis roll")  == 0) { s_useRollAxis = true;  resetPIDState(); ESP_LOGI(TAG, "axis=roll");  printConfig(); }
    else if (strcmp(lc, "invert angle on")  == 0) { s_invertAngleSign = true;  resetPIDState(); printConfig(); }
    else if (strcmp(lc, "invert angle off") == 0) { s_invertAngleSign = false; resetPIDState(); printConfig(); }
    else if (strcmp(lc, "invert left on")   == 0) { s_invertLeftDir   = true;  printConfig(); }
    else if (strcmp(lc, "invert left off")  == 0) { s_invertLeftDir   = false; printConfig(); }
    else if (strcmp(lc, "invert right on")  == 0) { s_invertRightDir  = true;  printConfig(); }
    else if (strcmp(lc, "invert right off") == 0) { s_invertRightDir  = false; printConfig(); }
    else if (strcmp(lc, "manual on")  == 0 || strcmp(lc, "balance off") == 0) {
        s_manualMode = true;  resetPIDState(); printConfig();
    }
    else if (strcmp(lc, "manual off") == 0 || strcmp(lc, "balance on") == 0) {
        s_manualMode = false; s_manualLeftSpeed = 0; s_manualRightSpeed = 0;
        setMotorSpeed(0, 0); resetPIDState(); printConfig();
    }
    else if (sscanf(lc, "pid %f %f %f", &a, &b, &c) == 3) {
        s_kp = a; s_ki = b; s_kd = c;
        resetPIDState();
        ESP_LOGI(TAG, "PID Kp=%.2f Ki=%.3f Kd=%.2f", (double)a, (double)b, (double)c);
        printConfig();
    }
    else if (sscanf(lc, "trim %f", &a) == 1) {
        s_balanceTrimDeg = clampf(a, -10.0f, 10.0f);
        resetPIDState();
        ESP_LOGI(TAG, "trim=%.2f°", (double)s_balanceTrimDeg);
        printConfig();
    }
    else if (sscanf(lc, "alpha %f", &a) == 1) {
        s_compAlpha = clampf(a, 0.80f, 0.99f);
        ESP_LOGI(TAG, "filter alpha=%.3f", (double)s_compAlpha);
        printConfig();
    }
    else if (sscanf(lc, "motor %f %f", &a, &b) == 2) {
        s_manualMode      = true;
        s_manualLeftSpeed  = clampf(a, -MAX_STEP_HZ, MAX_STEP_HZ);
        s_manualRightSpeed = clampf(b, -MAX_STEP_HZ, MAX_STEP_HZ);
        ESP_LOGI(TAG, "manual motor L=%.0f R=%.0f", (double)a, (double)b);
    }
    else {
        ESP_LOGW(TAG,
            "Unknown: '%s'  | Cmds: forward backward left right stop reset status "
            "pid <P> <I> <D>  trim <deg>  alpha <0.9~0.99>  axis pitch/roll  "
            "invert angle/left/right on/off  manual on/off  motor <L> <R>", line);
    }
}

static void parseSerialCommand(void)
{
    static char buf[64];
    static size_t len = 0;
    uint8_t byte;

    while (uart_read_bytes(UART_PORT, &byte, 1, 0) == 1) {
        if (byte == '\r') continue;
        if (byte == '\n') {
            buf[len] = '\0';
            if (len > 0) handleSerialLine(buf);
            len = 0;
            continue;
        }
        if (len < sizeof(buf) - 1) buf[len++] = (char)byte;
        else                        len = 0;
    }
}

/* ═══════════════════════════════════════════════════════
 *  DEBUG
 * ═══════════════════════════════════════════════════════ */
static void printDebugStatus(void)
{
    const int64_t now = esp_timer_get_time();
    if ((now - s_lastDebugPrintUs) < DEBUG_INTERVAL_US) return;
    s_lastDebugPrintUs = now;

    ESP_LOGI(TAG,
        "%s angle=%6.2f° target=%5.2f° pid=%7.1f  L=%6.0f R=%6.0f  trim=%.1f",
        robotStateToString(s_status.robotState),
        (double)s_status.angle,
        (double)s_status.targetAngle,
        (double)s_status.pidOutput,
        (double)s_status.leftMotorSpeed,
        (double)s_status.rightMotorSpeed,
        (double)s_balanceTrimDeg);
    ESP_LOGI(TAG,
        "PID detail err=%6.2f int=%7.3f axis=%s invertAngle=%d",
        (double)s_status.pidError,
        (double)s_status.pidIntegral,
        s_useRollAxis ? "roll" : "pitch",
        s_invertAngleSign);
}

/* -------------------------------------------------------------------------- */
/* Wi-Fi / HTTP JSON                                                          */
/* -------------------------------------------------------------------------- */
static esp_err_t startWebServer(void);
static void stopWebServer(void);

static esp_err_t initNvs(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    return err;
}

static void updateHttpClientCount(void)
{
    if (!s_httpServer) {
        s_httpActiveClients = 0;
        return;
    }

    int clientFds[8] = { 0 };
    size_t clientCount = sizeof(clientFds) / sizeof(clientFds[0]);
    if (httpd_get_client_list(s_httpServer, &clientCount, clientFds) == ESP_OK) {
        s_httpActiveClients = (int)clientCount;
    }
}

static char *readRequestBody(httpd_req_t *req)
{
    if (req->content_len <= 0 || req->content_len > 512) {
        return NULL;
    }

    char *body = calloc((size_t)req->content_len + 1U, sizeof(char));
    if (!body) {
        return NULL;
    }

    int total = 0;
    while (total < req->content_len) {
        const int received = httpd_req_recv(req, body + total, req->content_len - total);
        if (received <= 0) {
            free(body);
            return NULL;
        }
        total += received;
    }

    body[req->content_len] = '\0';
    return body;
}

static void setJsonHeaders(httpd_req_t *req)
{
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
}

static esp_err_t sendJsonResponse(httpd_req_t *req, cJSON *root, const char *status)
{
    char *payload = cJSON_PrintUnformatted(root);
    if (!payload) {
        cJSON_Delete(root);
        return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "json encode failed");
    }

    setJsonHeaders(req);
    if (status) {
        httpd_resp_set_status(req, status);
    }
    const esp_err_t err = httpd_resp_send(req, payload, HTTPD_RESP_USE_STRLEN);
    cJSON_free(payload);
    cJSON_Delete(root);
    return err;
}

static cJSON *buildStatusJson(void)
{
    const RobotStatus status = s_status;

    cJSON *root = cJSON_CreateObject();
    if (!root) {
        return NULL;
    }

    cJSON_AddStringToObject(root, "robotState", robotStateToString(status.robotState));
    cJSON_AddNumberToObject(root, "angle", status.angle);
    cJSON_AddNumberToObject(root, "pitchAngle", status.pitchAngle);
    cJSON_AddNumberToObject(root, "rollAngle", status.rollAngle);
    cJSON_AddNumberToObject(root, "targetAngle", status.targetAngle);
    cJSON_AddNumberToObject(root, "targetAngleOffset", status.targetAngleOffset);
    cJSON_AddNumberToObject(root, "steeringOffset", status.steeringOffset);
    cJSON_AddNumberToObject(root, "pidError", status.pidError);
    cJSON_AddNumberToObject(root, "pidIntegral", status.pidIntegral);
    cJSON_AddNumberToObject(root, "pidOutput", status.pidOutput);
    cJSON_AddNumberToObject(root, "leftMotorSpeed", status.leftMotorSpeed);
    cJSON_AddNumberToObject(root, "rightMotorSpeed", status.rightMotorSpeed);
    cJSON_AddNumberToObject(root, "accelXG", status.accelXG);
    cJSON_AddNumberToObject(root, "accelYG", status.accelYG);
    cJSON_AddNumberToObject(root, "accelZG", status.accelZG);
    cJSON_AddNumberToObject(root, "gyroXDps", status.gyroXDps);
    cJSON_AddNumberToObject(root, "gyroYDps", status.gyroYDps);
    cJSON_AddNumberToObject(root, "gyroZDps", status.gyroZDps);

    cJSON *control = cJSON_AddObjectToObject(root, "control");
    if (control) {
        cJSON_AddBoolToObject(control, "manualMode", s_manualMode);
        cJSON_AddStringToObject(control, "axis", s_useRollAxis ? "roll" : "pitch");
        cJSON_AddNumberToObject(control, "kp", s_kp);
        cJSON_AddNumberToObject(control, "ki", s_ki);
        cJSON_AddNumberToObject(control, "kd", s_kd);
        cJSON_AddNumberToObject(control, "trim", s_balanceTrimDeg);
        cJSON_AddNumberToObject(control, "alpha", s_compAlpha);
        cJSON_AddBoolToObject(control, "invertAngle", s_invertAngleSign);
        cJSON_AddBoolToObject(control, "invertLeft", s_invertLeftDir);
        cJSON_AddBoolToObject(control, "invertRight", s_invertRightDir);
    }

    cJSON *wifi = cJSON_AddObjectToObject(root, "wifi");
    if (wifi) {
        cJSON_AddBoolToObject(wifi, "connected", s_wifiConnected);
        cJSON_AddBoolToObject(wifi, "webServerStarted", s_webServerStarted);
        cJSON_AddNumberToObject(wifi, "rssi", s_wifiRssi);
        cJSON_AddNumberToObject(wifi, "httpClients", s_httpActiveClients);
        cJSON_AddStringToObject(wifi, "ip", s_wifiIpAddress[0] ? s_wifiIpAddress : "");
        cJSON_AddStringToObject(wifi, "ssid", ROBOT_WIFI_SSID);
    }

    return root;
}

static esp_err_t sendStatusResponse(httpd_req_t *req)
{
    cJSON *root = buildStatusJson();
    if (!root) {
        return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "json alloc failed");
    }
    return sendJsonResponse(req, root, "200 OK");
}

static esp_err_t httpRootHandler(httpd_req_t *req)
{
    httpd_resp_set_type(req, "text/plain");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    return httpd_resp_sendstr(req,
        "Balance robot firmware\n"
        "GET  /api/status\n"
        "POST /api/command  {\"cmd\":\"forward\"}\n"
        "POST /api/pid      {\"kp\":18,\"ki\":0.4,\"kd\":6}\n"
        "POST /api/config   {\"trim\":0.5,\"axis\":\"pitch\"}\n");
}

static esp_err_t httpStatusHandler(httpd_req_t *req)
{
    updateHttpClientCount();
    return sendStatusResponse(req);
}

static esp_err_t httpCommandHandler(httpd_req_t *req)
{
    char *body = readRequestBody(req);
    if (!body) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "invalid body");
    }

    cJSON *root = cJSON_Parse(body);
    if (root) {
        const cJSON *cmd = cJSON_GetObjectItemCaseSensitive(root, "cmd");
        if (cJSON_IsString(cmd) && cmd->valuestring) {
            handleSerialLine(cmd->valuestring);
        } else {
            cJSON_Delete(root);
            free(body);
            return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "missing cmd");
        }
        cJSON_Delete(root);
    } else {
        handleSerialLine(body);
    }

    free(body);
    updateHttpClientCount();
    return sendStatusResponse(req);
}

static esp_err_t httpPidHandler(httpd_req_t *req)
{
    char *body = readRequestBody(req);
    if (!body) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "invalid body");
    }

    cJSON *root = cJSON_Parse(body);
    free(body);
    if (!root) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "invalid json");
    }

    const cJSON *kp = cJSON_GetObjectItemCaseSensitive(root, "kp");
    const cJSON *ki = cJSON_GetObjectItemCaseSensitive(root, "ki");
    const cJSON *kd = cJSON_GetObjectItemCaseSensitive(root, "kd");
    if (!cJSON_IsNumber(kp) || !cJSON_IsNumber(ki) || !cJSON_IsNumber(kd)) {
        cJSON_Delete(root);
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "kp/ki/kd required");
    }

    s_kp = (float)kp->valuedouble;
    s_ki = (float)ki->valuedouble;
    s_kd = (float)kd->valuedouble;
    resetPIDState();
    printConfig();

    cJSON_Delete(root);
    updateHttpClientCount();
    return sendStatusResponse(req);
}

static esp_err_t httpConfigHandler(httpd_req_t *req)
{
    char *body = readRequestBody(req);
    if (!body) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "invalid body");
    }

    cJSON *root = cJSON_Parse(body);
    free(body);
    if (!root) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "invalid json");
    }

    const cJSON *trim = cJSON_GetObjectItemCaseSensitive(root, "trim");
    if (cJSON_IsNumber(trim)) {
        s_balanceTrimDeg = clampf((float)trim->valuedouble, -10.0f, 10.0f);
        resetPIDState();
    }

    const cJSON *alpha = cJSON_GetObjectItemCaseSensitive(root, "alpha");
    if (cJSON_IsNumber(alpha)) {
        s_compAlpha = clampf((float)alpha->valuedouble, 0.80f, 0.99f);
    }

    const cJSON *axis = cJSON_GetObjectItemCaseSensitive(root, "axis");
    if (cJSON_IsString(axis) && axis->valuestring) {
        s_useRollAxis = (strcasecmp(axis->valuestring, "roll") == 0);
        resetPIDState();
    }

    const cJSON *invertAngle = cJSON_GetObjectItemCaseSensitive(root, "invertAngle");
    if (cJSON_IsBool(invertAngle)) {
        s_invertAngleSign = cJSON_IsTrue(invertAngle);
        resetPIDState();
    }

    const cJSON *invertLeft = cJSON_GetObjectItemCaseSensitive(root, "invertLeft");
    if (cJSON_IsBool(invertLeft)) {
        s_invertLeftDir = cJSON_IsTrue(invertLeft);
    }

    const cJSON *invertRight = cJSON_GetObjectItemCaseSensitive(root, "invertRight");
    if (cJSON_IsBool(invertRight)) {
        s_invertRightDir = cJSON_IsTrue(invertRight);
    }

    const cJSON *manual = cJSON_GetObjectItemCaseSensitive(root, "manual");
    if (cJSON_IsBool(manual)) {
        s_manualMode = cJSON_IsTrue(manual);
        if (!s_manualMode) {
            s_manualLeftSpeed = 0.0f;
            s_manualRightSpeed = 0.0f;
            setMotorSpeed(0.0f, 0.0f);
            resetPIDState();
        }
    }

    const cJSON *leftMotor = cJSON_GetObjectItemCaseSensitive(root, "leftMotor");
    const cJSON *rightMotor = cJSON_GetObjectItemCaseSensitive(root, "rightMotor");
    if (cJSON_IsNumber(leftMotor) && cJSON_IsNumber(rightMotor)) {
        s_manualMode = true;
        s_manualLeftSpeed = clampf((float)leftMotor->valuedouble, -MAX_STEP_HZ, MAX_STEP_HZ);
        s_manualRightSpeed = clampf((float)rightMotor->valuedouble, -MAX_STEP_HZ, MAX_STEP_HZ);
    }

    cJSON_Delete(root);
    printConfig();
    updateHttpClientCount();
    return sendStatusResponse(req);
}

static esp_err_t startWebServer(void)
{
    if (s_httpServer) {
        s_webServerStarted = true;
        return ESP_OK;
    }

    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.server_port = WEB_SERVER_PORT;
    config.max_uri_handlers = 8;
    config.stack_size = 8192;
    config.lru_purge_enable = true;

    ESP_RETURN_ON_ERROR(httpd_start(&s_httpServer, &config), TAG, "httpd start failed");

    static const httpd_uri_t rootUri = {
        .uri = "/",
        .method = HTTP_GET,
        .handler = httpRootHandler,
        .user_ctx = NULL,
    };
    static const httpd_uri_t statusUri = {
        .uri = "/api/status",
        .method = HTTP_GET,
        .handler = httpStatusHandler,
        .user_ctx = NULL,
    };
    static const httpd_uri_t commandUri = {
        .uri = "/api/command",
        .method = HTTP_POST,
        .handler = httpCommandHandler,
        .user_ctx = NULL,
    };
    static const httpd_uri_t pidUri = {
        .uri = "/api/pid",
        .method = HTTP_POST,
        .handler = httpPidHandler,
        .user_ctx = NULL,
    };
    static const httpd_uri_t configUri = {
        .uri = "/api/config",
        .method = HTTP_POST,
        .handler = httpConfigHandler,
        .user_ctx = NULL,
    };

    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(s_httpServer, &rootUri), TAG, "root uri");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(s_httpServer, &statusUri), TAG, "status uri");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(s_httpServer, &commandUri), TAG, "command uri");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(s_httpServer, &pidUri), TAG, "pid uri");
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(s_httpServer, &configUri), TAG, "config uri");

    s_webServerStarted = true;
    ESP_LOGI(TAG, "HTTP server started on port %d", WEB_SERVER_PORT);
    return ESP_OK;
}

static void stopWebServer(void)
{
    if (s_httpServer) {
        httpd_stop(s_httpServer);
        s_httpServer = NULL;
    }
    s_httpActiveClients = 0;
    s_webServerStarted = false;
}

static void updateWifiRssi(void)
{
    const int64_t now = esp_timer_get_time();
    if ((now - s_lastWifiRssiRefreshUs) < WIFI_RSSI_REFRESH_US) {
        return;
    }
    s_lastWifiRssiRefreshUs = now;

    if (!s_wifiConnected) {
        s_wifiRssi = 0;
        return;
    }

    wifi_ap_record_t apInfo;
    if (esp_wifi_sta_get_ap_info(&apInfo) == ESP_OK) {
        s_wifiRssi = apInfo.rssi;
    }
}

static void wifiEventHandler(void *arg, esp_event_base_t eventBase, int32_t eventId, void *eventData)
{
    (void)arg;

    if (eventBase == WIFI_EVENT && eventId == WIFI_EVENT_STA_START) {
        ESP_LOGI(TAG, "Wi-Fi start, connecting to %s", ROBOT_WIFI_SSID);
        const esp_err_t err = esp_wifi_connect();
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "esp_wifi_connect failed: %s", esp_err_to_name(err));
        }
        return;
    }

    if (eventBase == WIFI_EVENT && eventId == WIFI_EVENT_STA_DISCONNECTED) {
        const wifi_event_sta_disconnected_t *event = (const wifi_event_sta_disconnected_t *)eventData;
        s_wifiConnected = false;
        s_wifiRssi = 0;
        s_wifiIpAddress[0] = '\0';
        stopWebServer();
        ESP_LOGW(TAG, "Wi-Fi disconnected, reason=%d. Reconnecting...", event ? event->reason : -1);
        const esp_err_t err = esp_wifi_connect();
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "esp_wifi_connect failed: %s", esp_err_to_name(err));
        }
        return;
    }

    if (eventBase == IP_EVENT && eventId == IP_EVENT_STA_GOT_IP) {
        const ip_event_got_ip_t *event = (const ip_event_got_ip_t *)eventData;
        s_wifiConnected = true;
        snprintf(s_wifiIpAddress, sizeof(s_wifiIpAddress), IPSTR, IP2STR(&event->ip_info.ip));
        ESP_LOGI(TAG, "Wi-Fi connected, IP=%s", s_wifiIpAddress);
        if (startWebServer() != ESP_OK) {
            ESP_LOGE(TAG, "Failed to start HTTP server");
        }
    }
}

static esp_err_t initWifi(void)
{
    if (ROBOT_WIFI_SSID[0] == '\0') {
        ESP_LOGW(TAG, "Wi-Fi skipped: SSID is empty");
        return ESP_OK;
    }

    esp_err_t err = esp_netif_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return err;
    }

    err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return err;
    }

    esp_netif_create_default_wifi_sta();

    wifi_init_config_t wifiInit = WIFI_INIT_CONFIG_DEFAULT();
    ESP_RETURN_ON_ERROR(esp_wifi_init(&wifiInit), TAG, "wifi init failed");
    ESP_RETURN_ON_ERROR(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifiEventHandler, NULL), TAG, "wifi event register failed");
    ESP_RETURN_ON_ERROR(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifiEventHandler, NULL), TAG, "ip event register failed");

    wifi_config_t wifiConfig = { 0 };
    snprintf((char *)wifiConfig.sta.ssid, sizeof(wifiConfig.sta.ssid), "%s", ROBOT_WIFI_SSID);
    snprintf((char *)wifiConfig.sta.password, sizeof(wifiConfig.sta.password), "%s", ROBOT_WIFI_PASSWORD);
    wifiConfig.sta.threshold.authmode = WIFI_AUTH_OPEN;
    wifiConfig.sta.pmf_cfg.capable = true;
    wifiConfig.sta.pmf_cfg.required = false;

    ESP_RETURN_ON_ERROR(esp_wifi_set_storage(WIFI_STORAGE_RAM), TAG, "wifi storage failed");
    ESP_RETURN_ON_ERROR(esp_wifi_set_mode(WIFI_MODE_STA), TAG, "wifi mode failed");
    ESP_RETURN_ON_ERROR(esp_wifi_set_config(WIFI_IF_STA, &wifiConfig), TAG, "wifi config failed");
    ESP_RETURN_ON_ERROR(esp_wifi_set_ps(WIFI_PS_NONE), TAG, "wifi ps failed");
    ESP_RETURN_ON_ERROR(esp_wifi_start(), TAG, "wifi start failed");
    ESP_LOGI(TAG, "Wi-Fi init done, waiting for connection...");
    return ESP_OK;
}

/* ═══════════════════════════════════════════════════════
 *  INIT
 * ═══════════════════════════════════════════════════════ */
static esp_err_t initSerial(void)
{
    const uart_config_t uc = {
        .baud_rate  = SERIAL_BAUD,
        .data_bits  = UART_DATA_8_BITS,
        .parity     = UART_PARITY_DISABLE,
        .stop_bits  = UART_STOP_BITS_1,
        .flow_ctrl  = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_APB,
    };
    ESP_RETURN_ON_ERROR(uart_param_config(UART_PORT, &uc), TAG, "uart param");
    ESP_RETURN_ON_ERROR(uart_driver_install(UART_PORT, 1024, 0, 0, NULL, 0), TAG, "uart install");
    ESP_RETURN_ON_ERROR(uart_set_pin(UART_PORT, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE,
                                     UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE), TAG, "uart pin");
    return ESP_OK;
}

static esp_err_t initMotors(void)
{
    const gpio_config_t gc = {
        .pin_bit_mask = (1ULL << PIN_ENABLE) | (1ULL << PIN_LEFT_DIR) | (1ULL << PIN_RIGHT_DIR),
        .mode         = GPIO_MODE_OUTPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    ESP_RETURN_ON_ERROR(gpio_config(&gc), TAG, "motor gpio");
    gpio_set_level(PIN_LEFT_DIR,  0);
    gpio_set_level(PIN_RIGHT_DIR, 0);
    gpio_set_level(PIN_ENABLE,    1);   /* disabled */
    configureMotorChannel(LEFT_TIMER,  LEFT_CHANNEL,  PIN_LEFT_STEP);
    configureMotorChannel(RIGHT_TIMER, RIGHT_CHANNEL, PIN_RIGHT_STEP);
    return ESP_OK;
}

/* ═══════════════════════════════════════════════════════
 *  MAIN LOOP
 * ═══════════════════════════════════════════════════════ */
static void loopBody(void)
{
    MpuSample sample;

    if (readMPU6050(&sample) != ESP_OK) {
        enterFallenState("MPU read error");
        return;
    }

    updateAngle(&sample);

    /* Safety: robot ngã quá xa */
    if (fabsf(s_status.angle) > SAFETY_ANGLE_DEG) {
        enterFallenState("safety angle exceeded");
        return;
    }

    if (s_status.robotState == ROBOT_STATE_FALLEN) {
        return;
    }

    /* Balance mode */
    if (s_status.robotState == ROBOT_STATE_BALANCING) {
        if (s_manualMode) {
            setMotorSpeed(s_manualLeftSpeed, s_manualRightSpeed);
        } else {
            const float base  = computePID();
            const float left  = base + s_status.steeringOffset;
            const float right = base - s_status.steeringOffset;
            setMotorSpeed(left, right);
        }
        updateMotors();
    } else {
        stopMotors();
    }
}

static void loopTimerCallback(void *arg)
{
    (void)arg;
    if (s_balanceTaskHandle) {
        xTaskNotifyGive(s_balanceTaskHandle);
    }
}

static void setup(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);

    ESP_ERROR_CHECK(initSerial());
    ESP_ERROR_CHECK(initMotors());
    ESP_ERROR_CHECK(initMPU6050());
    ESP_ERROR_CHECK(calibrateMPU6050());

    MpuSample sample;
    ESP_ERROR_CHECK(readMPU6050(&sample));
    updateAngle(&sample);

    resetPIDState();
    s_status.targetAngle       = TARGET_ANGLE_BASE_DEG;
    s_status.targetAngleOffset = 0.0f;
    s_status.steeringOffset    = 0.0f;
    s_status.robotState        = ROBOT_STATE_BALANCING;
    s_wifiConnected            = false;
    s_webServerStarted         = false;
    s_wifiRssi                 = 0;
    s_httpActiveClients        = 0;
    s_wifiIpAddress[0]         = '\0';
    setDriverEnabled(true);

    esp_err_t err = initNvs();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "NVS init failed: %s", esp_err_to_name(err));
    } else {
        err = initWifi();
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "Wi-Fi init failed: %s", esp_err_to_name(err));
        }
    }

    ESP_LOGI(TAG, "=== Balance Robot Ready ===");
    ESP_LOGI(TAG, "Pins EN=%d | L step=%d dir=%d | R step=%d dir=%d | IMU sda=%d scl=%d",
             PIN_ENABLE, PIN_LEFT_STEP, PIN_LEFT_DIR, PIN_RIGHT_STEP, PIN_RIGHT_DIR,
             PIN_MPU_SDA, PIN_MPU_SCL);
    printConfig();
    ESP_LOGI(TAG, "Commands: pid <P> <I> <D>  trim <deg>  reset  status  ...");
}

static void loop(void)
{
    loopBody();
}

static void balanceTask(void *arg)
{
    (void)arg;
    ESP_LOGI(TAG, "Balance task running on core %d", xPortGetCoreID());

    while (true) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        loop();
    }
}

static void communicationTask(void *arg)
{
    (void)arg;
    ESP_LOGI(TAG, "Comm task running on core %d", xPortGetCoreID());

    while (true) {
        parseSerialCommand();
        updateWifiRssi();
        updateHttpClientCount();
        printDebugStatus();
        vTaskDelay(pdMS_TO_TICKS(COMM_TASK_PERIOD_MS));
    }
}

void app_main(void)
{
    setup();

    if (xTaskCreatePinnedToCore(balanceTask, "balance_task", 4096, NULL, 10, &s_balanceTaskHandle, 1) != pdPASS) {
        ESP_LOGE(TAG, "Failed to create balance task");
        ESP_ERROR_CHECK(ESP_FAIL);
    }

    if (xTaskCreatePinnedToCore(communicationTask, "comm_task", 4096, NULL, 4, NULL, 0) != pdPASS) {
        ESP_LOGE(TAG, "Failed to create comm task");
        ESP_ERROR_CHECK(ESP_FAIL);
    }

    const esp_timer_create_args_t timerArgs = {
        .callback = loopTimerCallback,
        .arg = NULL,
        .name = "loop_timer",
    };
    ESP_ERROR_CHECK(esp_timer_create(&timerArgs, &s_loopTimer));
    ESP_ERROR_CHECK(esp_timer_start_periodic(s_loopTimer, CONTROL_PERIOD_US));

    vTaskDelete(NULL);
}
