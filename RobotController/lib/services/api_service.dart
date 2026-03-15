import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'pid_storage_service.dart';

class ApiService extends ChangeNotifier {
  static final ApiService _instance = ApiService._internal();
  static const _defaultServerHost = String.fromEnvironment(
    'BALANCE_ROBOT_HOST',
    defaultValue: '10.235.155.125',
  );
  static const _defaultServerPort = int.fromEnvironment(
    'BALANCE_ROBOT_API_PORT',
    defaultValue: 8080,
  );
  static const _tokenKey = 'jwt_token';
  static const _serverHostKey = 'server_host';
  static const _serverPortKey = 'api_port';

  factory ApiService() => _instance;
  ApiService._internal();

  String _serverHost = _defaultServerHost;
  int _serverPort = _defaultServerPort;
  String? _token;
  String? _lastError;

  String get serverHost => _serverHost;
  int get serverPort => _serverPort;
  String get baseUrl => 'http://$_serverHost:$_serverPort/api';
  String? get token => _token;
  String? get lastError => _lastError;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _serverHost = prefs.getString(_serverHostKey) ?? _defaultServerHost;
    _serverPort = prefs.getInt(_serverPortKey) ?? _defaultServerPort;
    notifyListeners();
  }

  bool get isAuthenticated => _token != null;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<void> updateServerConfig(String input) async {
    final uri = _normalizeServerInput(input);
    final prefs = await SharedPreferences.getInstance();
    _serverHost = uri.host;
    _serverPort = uri.port == 0 ? _defaultServerPort : uri.port;
    await prefs.setString(_serverHostKey, _serverHost);
    await prefs.setInt(_serverPortKey, _serverPort);
    notifyListeners();
  }

  // --- Auth API ---

  Future<bool> login(String username, String password) async {
    _lastError = null;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        await _persistAuth(response.body);
        return true;
      }
      _lastError = _extractErrorMessage(response, 'Login failed');
      return false;
    } catch (e) {
      _lastError = 'Cannot reach $baseUrl\n$e';
      debugPrint('Login error: $e');
      return false;
    }
  }

  Future<bool> registerUser(String email, String username, String password) async {
    _lastError = null;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'username': username,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        await _persistAuth(response.body);
        return true;
      }
      _lastError = _extractErrorMessage(response, 'Registration failed');
      return false;
    } catch (e) {
      _lastError = 'Cannot reach $baseUrl\n$e';
      debugPrint('Register error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    notifyListeners();
  }

  // --- Device API ---

  Future<List<dynamic>> getDevices() async {
    if (!isAuthenticated) return [];
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/devices'),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
      return [];
    } catch (e) {
      debugPrint('Get devices error: $e');
      return [];
    }
  }

  Future<bool> registerDevice(String deviceId, String name) async {
    if (!isAuthenticated) return false;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/devices'),
        headers: _headers,
        body: jsonEncode({
          'deviceId': deviceId,
          'name': name,
          'status': 'OFFLINE'
        }),
      ).timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Register device error: $e');
      return false;
    }
  }

  // --- PID Sync API ---

  Future<PidValues?> getDevicePid(String deviceId) async {
    if (!isAuthenticated) {
      _lastError = 'Not authenticated';
      return null;
    }

    _lastError = null;
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/devices/$deviceId/pid'),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return PidValues.fromJson(data);
      }
      if (response.statusCode == 204) {
        return null;
      }

      _lastError = _extractErrorMessage(response, 'Failed to load PID');
      return null;
    } catch (e) {
      _lastError = 'Cannot reach $baseUrl\n$e';
      debugPrint('Get device PID error: $e');
      return null;
    }
  }

  Future<bool> saveDevicePid(String deviceId, PidValues values) async {
    if (!isAuthenticated) {
      _lastError = 'Not authenticated';
      return false;
    }

    _lastError = null;
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/devices/$deviceId/pid'),
        headers: _headers,
        body: jsonEncode(values.toJson()),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return true;
      }

      _lastError = _extractErrorMessage(response, 'Failed to save PID');
      return false;
    } catch (e) {
      _lastError = 'Cannot reach $baseUrl\n$e';
      debugPrint('Save device PID error: $e');
      return false;
    }
  }

  Future<void> _persistAuth(String body) async {
    final data = jsonDecode(body) as Map<String, dynamic>;
    _token = data['token'] as String?;
    if (_token == null || _token!.isEmpty) {
      throw const FormatException('Missing token in auth response');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    notifyListeners();
  }

  String _extractErrorMessage(http.Response response, String fallback) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        final error = data['error'];
        if (error is String && error.isNotEmpty) {
          final details = data['details'];
          if (details is Map && details.isNotEmpty) {
            final summary = details.entries
                .map((entry) => '${entry.key}: ${entry.value}')
                .join(', ');
            return '$error ($summary)';
          }
          return error;
        }
      }
    } catch (_) {
      if (response.body.trim().isNotEmpty) {
        return response.body.trim();
      }
    }
    return '$fallback (${response.statusCode})';
  }

  Uri _normalizeServerInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Server host is required');
    }

    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.parse(withScheme);
    final host = uri.host.isNotEmpty ? uri.host : uri.path;
    if (host.isEmpty) {
      throw const FormatException('Server host is invalid');
    }

    return Uri(
      scheme: 'http',
      host: host,
      port: uri.hasPort ? uri.port : _defaultServerPort,
    );
  }
}
