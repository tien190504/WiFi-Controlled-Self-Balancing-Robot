import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton MQTT service using ChangeNotifier for state management.
class MqttService extends ChangeNotifier {
  static final MqttService _instance = MqttService._internal();
  static const _defaultBrokerHost = String.fromEnvironment(
    'BALANCE_ROBOT_HOST',
    defaultValue: '10.235.155.125',
  );
  static const _defaultBrokerPort = int.fromEnvironment(
    'BALANCE_ROBOT_MQTT_PORT',
    defaultValue: 1883,
  );
  static const _brokerHostKey = 'server_host';
  static const _brokerPortKey = 'mqtt_port';

  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? _client;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _lastError;

  String brokerUrl = _defaultBrokerHost;
  int port = _defaultBrokerPort;
  String? _deviceId;

  String? get deviceId => _deviceId;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    brokerUrl = prefs.getString(_brokerHostKey) ?? _defaultBrokerHost;
    port = prefs.getInt(_brokerPortKey) ?? _defaultBrokerPort;
    notifyListeners();
  }

  Future<void> updateBrokerConfig(String hostInput, {int? nextPort}) async {
    final host = _normalizeHost(hostInput);
    final prefs = await SharedPreferences.getInstance();
    brokerUrl = host;
    port = nextPort ?? port;
    await prefs.setString(_brokerHostKey, brokerUrl);
    await prefs.setInt(_brokerPortKey, port);
    notifyListeners();
  }

  void setDeviceId(String id) {
    _deviceId = id;
    notifyListeners();
  }

  // State data from robot
  double angle = 0;
  double speed = 0;
  double sensorX = 0;
  double sensorY = 0;
  double sensorZ = 0;

  // Waveform buffer
  final List<double> waveformData = [];
  static const int maxWaveformPoints = 300;

  // Action Topics (Published by app)
  String get topicControlMove => 'robot/control/move/$_deviceId';
  String get topicPidAngle => 'robot/pid/angle/$_deviceId';
  String get topicPidSpeed => 'robot/pid/speed/$_deviceId';
  
  // State Topics (Subscribed by app)
  String get topicStateAngle => 'robot/state/angle/$_deviceId';
  String get topicStateSensors => 'robot/state/sensors/$_deviceId';
  String get topicStateSpeed => 'robot/state/speed/$_deviceId';

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get lastError => _lastError;

  /// Connect to broker with a 5-second timeout.
  /// Returns error message or null on success.
  Future<String?> connect() async {
    if (_isConnected) return null;
    if (_isConnecting) return 'Already connecting...';

    _isConnecting = true;
    _lastError = null;
    notifyListeners();

    final clientId = 'RobotController_${DateTime.now().millisecondsSinceEpoch}';
    _client = MqttServerClient(brokerUrl, clientId)
      ..port = port
      ..keepAlivePeriod = 20
      ..connectTimeoutPeriod = 5000 // 5 second timeout
      ..autoReconnect = false // Do NOT auto-reconnect
      ..onDisconnected = _onDisconnected
      ..onConnected = _onConnected
      ..logging(on: false);

    _client!.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    try {
      await _client!.connect().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _client?.disconnect();
          throw TimeoutException('Connection timed out after 5 seconds');
        },
      );
    } catch (e) {
      debugPrint('MQTT connect error: $e');
      _isConnected = false;
      _isConnecting = false;
      _lastError = e.toString();
      _client = null;
      notifyListeners();
      return 'Cannot connect to $brokerUrl:$port\n${e.toString().replaceAll('Exception: ', '')}';
    }

    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      _isConnected = true;
      _isConnecting = false;
      _lastError = null;
      _subscribeAll();
      _client!.updates?.listen(_onMessage);
      notifyListeners();
      return null;
    } else {
      _isConnected = false;
      _isConnecting = false;
      final reason = _client?.connectionStatus?.returnCode?.toString() ?? 'Unknown';
      _lastError = 'Connection refused: $reason';
      _client = null;
      notifyListeners();
      return _lastError;
    }
  }

  void disconnect() {
    _client?.disconnect();
    _client = null;
    _isConnected = false;
    _isConnecting = false;
    notifyListeners();
  }

  void _onConnected() {
    _isConnected = true;
    _isConnecting = false;
    notifyListeners();
  }

  void _onDisconnected() {
    _isConnected = false;
    _isConnecting = false;
    notifyListeners();
  }

  void _subscribeAll() {
    if (_deviceId == null) return;
    _client?.subscribe(topicStateAngle, MqttQos.atMostOnce);
    _client?.subscribe(topicStateSensors, MqttQos.atMostOnce);
    _client?.subscribe(topicStateSpeed, MqttQos.atMostOnce);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      final payload = MqttPublishPayload.bytesToStringAsString(
          (msg.payload as MqttPublishMessage).payload.message);
      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        if (msg.topic == topicStateAngle) {
          angle = (json['angle'] as num?)?.toDouble() ?? 0;
          waveformData.add(angle.clamp(-30.0, 30.0));
          if (waveformData.length > maxWaveformPoints) {
            waveformData.removeAt(0);
          }
        } else if (msg.topic == topicStateSpeed) {
          speed = (json['speed'] as num?)?.toDouble() ?? 0;
        } else if (msg.topic == topicStateSensors) {
          sensorX = (json['x'] as num?)?.toDouble() ?? 0;
          sensorY = (json['y'] as num?)?.toDouble() ?? 0;
          sensorZ = (json['z'] as num?)?.toDouble() ?? 0;
        }
        notifyListeners();
      } catch (e) {
        debugPrint('MQTT parse error: $e');
      }
    }
  }

  void publish(String topic, Map<String, dynamic> data) {
    if (!_isConnected || _client == null) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(data));
    _client!.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
  }

  void clearWaveform() {
    waveformData.clear();
    notifyListeners();
  }

  String _normalizeHost(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Broker host is required');
    }

    final withScheme = trimmed.contains('://') ? trimmed : 'mqtt://$trimmed';
    final uri = Uri.parse(withScheme);
    final host = uri.host.isNotEmpty ? uri.host : uri.path;
    if (host.isEmpty) {
      throw const FormatException('Broker host is invalid');
    }
    return host;
  }
}
