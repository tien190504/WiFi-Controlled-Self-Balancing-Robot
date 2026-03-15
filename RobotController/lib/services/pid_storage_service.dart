import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PidValues {
  static const defaults = PidValues(
    angleP: 15.0,
    angleI: 0.5,
    angleD: 8.0,
    speedP: 10.0,
    speedI: 0.3,
    speedD: 5.0,
  );

  final double angleP;
  final double angleI;
  final double angleD;
  final double speedP;
  final double speedI;
  final double speedD;

  const PidValues({
    required this.angleP,
    required this.angleI,
    required this.angleD,
    required this.speedP,
    required this.speedI,
    required this.speedD,
  });

  Map<String, double> toJson() => {
    'angleP': angleP,
    'angleI': angleI,
    'angleD': angleD,
    'speedP': speedP,
    'speedI': speedI,
    'speedD': speedD,
  };

  factory PidValues.fromJson(Map<String, dynamic> json) {
    return PidValues(
      angleP: _asDouble(json['angleP'], defaults.angleP),
      angleI: _asDouble(json['angleI'], defaults.angleI),
      angleD: _asDouble(json['angleD'], defaults.angleD),
      speedP: _asDouble(json['speedP'], defaults.speedP),
      speedI: _asDouble(json['speedI'], defaults.speedI),
      speedD: _asDouble(json['speedD'], defaults.speedD),
    );
  }

  static double _asDouble(dynamic value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }
}

class PidStorageService {
  static final PidStorageService _instance = PidStorageService._internal();
  static const _storagePrefix = 'pid_values_';

  factory PidStorageService() => _instance;
  PidStorageService._internal();

  Future<PidValues> loadForDevice(String? deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(deviceId));
    if (raw == null || raw.isEmpty) {
      return PidValues.defaults;
    }

    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        return PidValues.fromJson(data);
      }
    } catch (_) {
      return PidValues.defaults;
    }

    return PidValues.defaults;
  }

  Future<bool> hasSavedValuesForDevice(String? deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_storageKey(deviceId));
  }

  Future<void> saveForDevice(String? deviceId, PidValues values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey(deviceId), jsonEncode(values.toJson()));
  }

  String _storageKey(String? deviceId) {
    final normalized = (deviceId == null || deviceId.trim().isEmpty)
        ? 'default'
        : deviceId.trim();
    return '$_storagePrefix$normalized';
  }
}
