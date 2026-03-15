import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../theme/app_theme.dart';
import '../services/mqtt_service.dart';
import '../widgets/tilt_view.dart';
import '../widgets/gauge_view.dart';

/// Gravity (tilt) control mode using accelerometer.
class GravityScreen extends StatefulWidget {
  const GravityScreen({super.key});

  @override
  State<GravityScreen> createState() => _GravityScreenState();
}

class _GravityScreenState extends State<GravityScreen> {
  StreamSubscription? _accelSub;
  double _tiltX = 0, _tiltY = 0;
  double _pitch = 0, _roll = 0, _yaw = 0;
  double _sensitivity = 1.5;
  static const double _maxTiltAngle = 45;
  static const double _deadzone = 0.1;

  @override
  void initState() {
    super.initState();
    _accelSub = accelerometerEventStream().listen((event) {
      _roll = event.x;
      _pitch = event.y;
      _yaw = event.z;

      var normTurn = (_roll / _maxTiltAngle * _sensitivity).clamp(-1.0, 1.0);
      var normSpeed = (_pitch / _maxTiltAngle * _sensitivity).clamp(-1.0, 1.0);

      if (normTurn.abs() < _deadzone) normTurn = 0;
      if (normSpeed.abs() < _deadzone) normSpeed = 0;

      setState(() {
        _tiltX = normTurn;
        _tiltY = -normSpeed;
      });

      final mqtt = MqttService();
      mqtt.publish(mqtt.topicControlMove, {
        'speed': (normSpeed * 100).roundToDouble() / 100,
        'turn': (normTurn * 100).roundToDouble() / 100,
      });
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    final mqtt = MqttService();
    mqtt.publish(mqtt.topicControlMove, {'speed': 0.0, 'turn': 0.0});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MqttService(),
      builder: (context, _) {
        final mqtt = MqttService();
        return Row(
          children: [
            // Left: Tilt visualizer
            Expanded(
              flex: 42,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TiltView(tiltX: _tiltX, tiltY: _tiltY),
              ),
            ),
            // Center: Data + sensitivity
            Expanded(
              flex: 58,
              child: Column(
                children: [
                  // Gauges
                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: GaugeView(
                              label: 'ANGLE',
                              unit: '°',
                              minValue: -45,
                              maxValue: 45,
                              value: mqtt.angle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: GaugeView(
                              label: 'SPEED',
                              unit: '%',
                              minValue: 0,
                              maxValue: 100,
                              value: mqtt.speed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Gyroscope data
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Pitch: ${_pitch.toStringAsFixed(1)}°',
                            style: AppTextStyles.dataValue(),
                          ),
                          Text(
                            'Roll: ${_roll.toStringAsFixed(1)}°',
                            style: AppTextStyles.dataValue(),
                          ),
                          Text(
                            'Yaw: ${_yaw.toStringAsFixed(1)}°',
                            style: AppTextStyles.dataValue(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Sensitivity slider
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Sensitivity: ${_sensitivity.toStringAsFixed(1)}×',
                            style: AppTextStyles.caption(),
                          ),
                          Slider(
                            value: _sensitivity,
                            min: 0.5,
                            max: 3.0,
                            divisions: 25,
                            onChanged: (v) => setState(() => _sensitivity = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Connection
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: Text(
                        mqtt.isConnected ? '● CONNECTED' : '● DISCONNECTED',
                        style: TextStyle(
                          color: mqtt.isConnected
                              ? AppColors.success
                              : AppColors.danger,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
