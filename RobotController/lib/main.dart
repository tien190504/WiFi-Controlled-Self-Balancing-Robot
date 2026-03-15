import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/device_selection_screen.dart';
import 'services/api_service.dart';
import 'services/mqtt_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to landscape
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Immersive fullscreen
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Initialize API service (checks for existing JWT token)
  final api = ApiService();
  await api.init();
  await MqttService().init();

  runApp(RobotControllerApp(isAuthenticated: api.isAuthenticated));
}

class RobotControllerApp extends StatelessWidget {
  final bool isAuthenticated;

  const RobotControllerApp({super.key, required this.isAuthenticated});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Robot Controller',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: isAuthenticated
          ? const DeviceSelectionScreen()
          : const LoginScreen(),
    );
  }
}
