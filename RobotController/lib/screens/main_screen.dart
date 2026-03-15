import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/mqtt_service.dart';
import '../services/api_service.dart';
import '../widgets/hexagon_button.dart';
import 'rocker_screen.dart';
import 'button_screen.dart';
import 'gravity_screen.dart';
import 'pid_screen.dart';
import 'waveform_screen.dart';
import 'device_selection_screen.dart';
import 'login_screen.dart';

enum ControlMode { rocker, button, gravity, pid, waveform }

/// Main scaffold with fragment area (left) and hexagonal menu (right).
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  ControlMode _currentMode = ControlMode.rocker;
  final _api = ApiService();

  static const _modeLabels = {
    ControlMode.rocker: 'ROCKER',
    ControlMode.button: 'BUTTON',
    ControlMode.gravity: 'GRAVITY',
    ControlMode.pid: 'PID',
    ControlMode.waveform: 'WAVE',
  };

  void _switchMode(ControlMode mode) {
    if (mode == _currentMode) return;
    HapticFeedback.lightImpact();
    setState(() => _currentMode = mode);
  }

  void _goBack() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DeviceSelectionScreen()),
    );
  }

  Future<void> _logout() async {
    await _api.logout();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Widget _buildScreen() {
    switch (_currentMode) {
      case ControlMode.rocker:
        return const RockerScreen();
      case ControlMode.button:
        return const ButtonScreen();
      case ControlMode.gravity:
        return const GravityScreen();
      case ControlMode.pid:
        return const PidScreen();
      case ControlMode.waveform:
        return const WaveformScreen();
    }
  }

  /// Show broker address dialog and connect.
  Future<void> _showConnectDialog() async {
    final mqtt = MqttService();
    final brokerCtrl = TextEditingController(text: mqtt.brokerUrl);
    final portCtrl = TextEditingController(text: mqtt.port.toString());

    final shouldConnect = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Connect to MQTT Broker',
          style: TextStyle(color: AppColors.primaryAccent, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: brokerCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Broker IP / Hostname',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                hintText: '192.168.4.1',
                hintStyle: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: AppColors.background,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Port',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                hintText: '1883',
                hintStyle: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: AppColors.background,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONNECT'),
          ),
        ],
      ),
    );

    if (shouldConnect != true || !mounted) return;

    final nextPort = int.tryParse(portCtrl.text.trim()) ?? 1883;
    try {
      await mqtt.updateBrokerConfig(
        brokerCtrl.text.trim(),
        nextPort: nextPort,
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message.toString()),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    // Show connecting indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connecting to ${mqtt.brokerUrl}:${mqtt.port}...'),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    // Attempt connection
    final error = await mqtt.connect();

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (error != null) {
      // Connection failed — show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ $error'),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      // Success
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Connected to ${mqtt.brokerUrl}'),
          backgroundColor: AppColors.success.withValues(alpha: 0.8),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left: Screen content (83%)
          Expanded(
            flex: 83,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey(_currentMode),
                child: _buildScreen(),
              ),
            ),
          ),
          // Divider
          Container(width: 1, color: AppColors.gridDivider),
          // Right: Menu (17%)
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.17,
            child: Container(
              color: AppColors.backgroundDark,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  // Mode buttons
                  ...ControlMode.values.map(
                    (mode) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 3,
                        ),
                        child: HexagonButton(
                          label: _modeLabels[mode]!,
                          isActive: _currentMode == mode,
                          onTap: () => _switchMode(mode),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Connect / Disconnect button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    child: ListenableBuilder(
                      listenable: MqttService(),
                      builder: (context, _) {
                        final mqtt = MqttService();
                        return SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: ElevatedButton(
                            onPressed: mqtt.isConnecting
                                ? null // Disable while connecting
                                : () {
                                    if (mqtt.isConnected) {
                                      mqtt.disconnect();
                                    } else {
                                      _showConnectDialog();
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: mqtt.isConnected
                                  ? AppColors.danger
                                  : mqtt.isConnecting
                                  ? AppColors.gridDivider
                                  : AppColors.secondaryAccent,
                            ),
                            child: Text(
                              mqtt.isConnected
                                  ? 'DISCONNECT'
                                  : mqtt.isConnecting
                                  ? 'CONNECTING...'
                                  : 'CONNECT',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Exit button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        onPressed: _goBack,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.secondaryAccent,
                        ),
                        child: const Text(
                          'EXIT',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                  // Logout button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        onPressed: _logout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                        ),
                        child: const Text(
                          'LOGOUT',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
