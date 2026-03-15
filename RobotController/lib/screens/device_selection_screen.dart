import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/mqtt_service.dart';
import 'login_screen.dart';
import 'main_screen.dart';

class DeviceSelectionScreen extends StatefulWidget {
  const DeviceSelectionScreen({super.key});

  @override
  State<DeviceSelectionScreen> createState() => _DeviceSelectionScreenState();
}

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> {
  final _api = ApiService();
  final _deviceIdController = TextEditingController();
  final _deviceNameController = TextEditingController();

  List<dynamic> _devices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
  }

  Future<void> _fetchDevices() async {
    setState(() => _isLoading = true);
    final devices = await _api.getDevices();
    setState(() {
      _devices = devices;
      _isLoading = false;
    });
  }

  void _showAddDeviceDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add New Device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _deviceIdController,
              decoration: const InputDecoration(labelText: 'Device ID (e.g., ROBOT_01)'),
            ),
            TextField(
              controller: _deviceNameController,
              decoration: const InputDecoration(labelText: 'Device Name (e.g., Balance Bot 1)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(dialogContext);
              final messenger = ScaffoldMessenger.of(context);
              final success = await _api.registerDevice(
                _deviceIdController.text.trim(),
                _deviceNameController.text.trim(),
              );
              if (!mounted) return;

              navigator.pop();
              if (success) {
                _fetchDevices();
              } else {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Failed to add device')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _selectDevice(String deviceId) {
    // 1. Give deviceId to MQTT Service
    final mqtt = MqttService();
    mqtt.setDeviceId(deviceId);

    // 2. Navigate to MainScreen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  void _logout() async {
    await _api.logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a Robot'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchDevices,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDeviceDialog,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? const Center(child: Text('No devices found. Add one!'))
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final isOnline = device['status'] == 'ONLINE';
                    return ListTile(
                      leading: Icon(
                        Icons.smart_toy,
                        color: isOnline ? Colors.green : Colors.grey,
                        size: 32,
                      ),
                      title: Text(device['name'] ?? device['deviceId']),
                      subtitle: Text('ID: ${device['deviceId']}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _selectDevice(device['deviceId']),
                    );
                  },
                ),
    );
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }
}
