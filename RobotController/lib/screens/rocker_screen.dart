import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/mqtt_service.dart';
import '../widgets/joystick_view.dart';
import '../widgets/gauge_view.dart';

/// Rocker control mode: joystick left, gauges + sensor data center.
class RockerScreen extends StatelessWidget {
  const RockerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MqttService(),
      builder: (context, _) {
        final mqtt = MqttService();
        return Row(
          children: [
            // Left: Joystick
            Expanded(
              flex: 42,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: JoystickView(
                  onMove: (speed, turn) {
                    mqtt.publish(mqtt.topicControlMove, {
                      'speed': (speed * 100).roundToDouble() / 100,
                      'turn': (turn * 100).roundToDouble() / 100,
                    });
                  },
                ),
              ),
            ),
            // Center: Data display
            Expanded(flex: 58, child: _buildDataPanel(mqtt)),
          ],
        );
      },
    );
  }

  Widget _buildDataPanel(MqttService mqtt) {
    return Column(
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
        // Sensor readout
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'X: ${mqtt.sensorX.toStringAsFixed(1)}°',
                  style: AppTextStyles.dataValue(),
                ),
                Text(
                  'Y: ${mqtt.sensorY.toStringAsFixed(1)}°',
                  style: AppTextStyles.dataValue(),
                ),
                Text(
                  'Z: ${mqtt.sensorZ.toStringAsFixed(1)}°',
                  style: AppTextStyles.dataValue(),
                ),
              ],
            ),
          ),
        ),
        // Connection badge
        Expanded(
          flex: 1,
          child: Center(
            child: Text(
              mqtt.isConnected ? '● CONNECTED' : '● DISCONNECTED',
              style: TextStyle(
                color: mqtt.isConnected ? AppColors.success : AppColors.danger,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
