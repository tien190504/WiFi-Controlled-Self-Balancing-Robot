import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/mqtt_service.dart';
import '../widgets/dpad_view.dart';
import '../widgets/gauge_view.dart';

/// Button control mode: D-Pad left, gauges + sensor data center.
class ButtonScreen extends StatelessWidget {
  const ButtonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MqttService(),
      builder: (context, _) {
        final mqtt = MqttService();
        return Row(
          children: [
            // Left: D-Pad
            Expanded(
              flex: 42,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DPadView(
                  onDPadPress: (direction, pressed) {
                    double speed = 0, turn = 0;
                    if (pressed) {
                      switch (direction) {
                        case DPadDirection.up:
                          speed = 1.0;
                          break;
                        case DPadDirection.down:
                          speed = -1.0;
                          break;
                        case DPadDirection.left:
                          turn = -1.0;
                          break;
                        case DPadDirection.right:
                          turn = 1.0;
                          break;
                        case DPadDirection.none:
                          break;
                      }
                    }
                    mqtt.publish(mqtt.topicControlMove, {
                      'speed': speed,
                      'turn': turn,
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
