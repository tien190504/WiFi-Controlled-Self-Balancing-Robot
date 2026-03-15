import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/mqtt_service.dart';
import '../services/pid_storage_service.dart';

/// PID Adjustment screen with Angle and Speed PID panels.
class PidScreen extends StatefulWidget {
  const PidScreen({super.key});

  @override
  State<PidScreen> createState() => _PidScreenState();
}

class _PidScreenState extends State<PidScreen> with WidgetsBindingObserver {
  final _api = ApiService();
  final _storage = PidStorageService();

  double _angleP = PidValues.defaults.angleP;
  double _angleI = PidValues.defaults.angleI;
  double _angleD = PidValues.defaults.angleD;
  double _speedP = PidValues.defaults.speedP;
  double _speedI = PidValues.defaults.speedI;
  double _speedD = PidValues.defaults.speedD;

  late final TextEditingController _anglePCtrl;
  late final TextEditingController _angleICtrl;
  late final TextEditingController _angleDCtrl;
  late final TextEditingController _speedPCtrl;
  late final TextEditingController _speedICtrl;
  late final TextEditingController _speedDCtrl;

  Timer? _saveDebounce;
  PidValues? _queuedRemoteValues;
  Future<void> _remoteSyncFuture = Future.value();
  bool _remoteSyncRunning = false;
  bool _hasSavedLocalValue = false;
  bool _hasMeaningfulPidState = false;
  bool _isDisposed = false;
  String _syncStatus = '';

  String? get _deviceId => MqttService().deviceId;
  bool get _canSyncRemotely => _deviceId != null && _api.isAuthenticated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _anglePCtrl = TextEditingController(text: _formatValue(_angleP));
    _angleICtrl = TextEditingController(text: _formatValue(_angleI));
    _angleDCtrl = TextEditingController(text: _formatValue(_angleD));
    _speedPCtrl = TextEditingController(text: _formatValue(_speedP));
    _speedICtrl = TextEditingController(text: _formatValue(_speedI));
    _speedDCtrl = TextEditingController(text: _formatValue(_speedD));
    unawaited(_initializePidValues());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _saveDebounce?.cancel();
      unawaited(_flushPendingChanges());
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounce?.cancel();
    unawaited(_flushPendingChanges());
    _anglePCtrl.dispose();
    _angleICtrl.dispose();
    _angleDCtrl.dispose();
    _speedPCtrl.dispose();
    _speedICtrl.dispose();
    _speedDCtrl.dispose();
    super.dispose();
  }

  Future<void> _initializePidValues() async {
    PidValues? localValues;
    _hasSavedLocalValue = await _storage.hasSavedValuesForDevice(_deviceId);
    _hasMeaningfulPidState = _hasSavedLocalValue;

    if (_hasSavedLocalValue) {
      localValues = await _storage.loadForDevice(_deviceId);
      if (_isDisposed || !mounted) return;
      setState(() {
        _applyValues(localValues!);
      });
    }

    if (!_canSyncRemotely) {
      if (_hasSavedLocalValue) {
        _setSyncStatus('Saved locally / backend unavailable');
      }
      return;
    }

    final remoteValues = await _api.getDevicePid(_deviceId!);
    if (_isDisposed || !mounted) return;

    if (remoteValues != null) {
      await _storeLocal(remoteValues);
      _hasMeaningfulPidState = true;
      if (_isDisposed || !mounted) return;
      setState(() {
        _applyValues(remoteValues);
        _syncStatus = 'Saved';
      });
      return;
    }

    if (_api.lastError != null) {
      if (_hasSavedLocalValue) {
        _setSyncStatus('Saved locally / backend unavailable');
      }
      return;
    }

    if (_hasSavedLocalValue && localValues != null) {
      await _persistSnapshot(localValues);
    }
  }

  Future<void> _storeLocal(PidValues values) async {
    await _storage.saveForDevice(_deviceId, values);
    _hasSavedLocalValue = true;
  }

  Future<void> _persistSnapshot(PidValues snapshot, {bool force = false}) async {
    if (force) {
      _hasMeaningfulPidState = true;
    }
    if (!force && !_hasMeaningfulPidState) {
      return;
    }

    await _storeLocal(snapshot);

    if (!_canSyncRemotely) {
      _setSyncStatus('Saved locally / backend unavailable');
      return;
    }

    await _queueRemoteSync(snapshot);
  }

  Future<void> _queueRemoteSync(PidValues values) {
    _queuedRemoteValues = values;
    if (_remoteSyncRunning) {
      return _remoteSyncFuture;
    }

    _remoteSyncFuture = _runRemoteSyncLoop();
    return _remoteSyncFuture;
  }

  Future<void> _runRemoteSyncLoop() async {
    _remoteSyncRunning = true;
    try {
      while (_queuedRemoteValues != null) {
        final snapshot = _queuedRemoteValues!;
        _queuedRemoteValues = null;
        _setSyncStatus('Syncing...');

        final success = await _api.saveDevicePid(_deviceId!, snapshot);
        if (success) {
          _setSyncStatus('Saved');
        } else {
          _setSyncStatus('Saved locally / backend unavailable');
        }
      }
    } finally {
      _remoteSyncRunning = false;
    }
  }

  Future<void> _flushPendingChanges({bool force = false}) async {
    _saveDebounce?.cancel();
    await _persistSnapshot(_currentValues, force: force);
    await _remoteSyncFuture;
  }

  void _schedulePersist() {
    final snapshot = _currentValues;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persistSnapshot(snapshot));
    });
  }

  void _applyValues(PidValues values) {
    _angleP = values.angleP;
    _angleI = values.angleI;
    _angleD = values.angleD;
    _speedP = values.speedP;
    _speedI = values.speedI;
    _speedD = values.speedD;
    _syncControllers();
  }

  void _syncControllers() {
    _anglePCtrl.text = _formatValue(_angleP);
    _angleICtrl.text = _formatValue(_angleI);
    _angleDCtrl.text = _formatValue(_angleD);
    _speedPCtrl.text = _formatValue(_speedP);
    _speedICtrl.text = _formatValue(_speedI);
    _speedDCtrl.text = _formatValue(_speedD);
  }

  void _updatePidValue(VoidCallback update) {
    _hasMeaningfulPidState = true;
    setState(update);
    _schedulePersist();
  }

  PidValues get _currentValues => PidValues(
    angleP: _angleP,
    angleI: _angleI,
    angleD: _angleD,
    speedP: _speedP,
    speedI: _speedI,
    speedD: _speedD,
  );

  String _formatValue(double value) => value.toStringAsFixed(1);

  void _setSyncStatus(String status) {
    if (_isDisposed || !mounted || _syncStatus == status) return;
    setState(() {
      _syncStatus = status;
    });
  }

  void _resetDefaults() {
    final defaults = PidValues.defaults;
    _hasMeaningfulPidState = true;
    setState(() {
      _applyValues(defaults);
    });
    unawaited(_persistSnapshot(defaults, force: true));
  }

  void _sendAnglePID() {
    unawaited(_sendAnglePidInternal());
  }

  Future<void> _sendAnglePidInternal() async {
    await _flushPendingChanges(force: true);

    final mqtt = MqttService();
    if (mqtt.deviceId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No device selected')),
      );
      return;
    }

    mqtt.publish(mqtt.topicPidAngle, {
      'P': _angleP,
      'I': _angleI,
      'D': _angleD,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Angle PID sent'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _sendSpeedPID() {
    unawaited(_sendSpeedPidInternal());
  }

  Future<void> _sendSpeedPidInternal() async {
    await _flushPendingChanges(force: true);

    final mqtt = MqttService();
    if (mqtt.deviceId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No device selected')),
      );
      return;
    }

    mqtt.publish(mqtt.topicPidSpeed, {
      'P': _speedP,
      'I': _speedI,
      'D': _speedD,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Speed PID sent'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Widget _buildSliderRow(
    String label,
    double value,
    double max,
    TextEditingController ctrl,
    void Function(double) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: 0,
              max: max,
              onChanged: (v) {
                onChanged(v);
                ctrl.text = _formatValue(v);
              },
            ),
          ),
          SizedBox(
            width: 55,
            height: 32,
            child: TextField(
              controller: ctrl,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: const InputDecoration(
                filled: true,
                fillColor: AppColors.background,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
              ),
              onChanged: (text) {
                final v = double.tryParse(text);
                if (v != null) {
                  onChanged(v.clamp(0, max));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPIDPanel(
    String title,
    double p,
    double i,
    double d,
    TextEditingController pCtrl,
    TextEditingController iCtrl,
    TextEditingController dCtrl,
    void Function(double) onP,
    void Function(double) onI,
    void Function(double) onD,
    VoidCallback onSend,
  ) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.title().copyWith(fontSize: 16)),
            const SizedBox(height: 8),
            _buildSliderRow('P', p, 50, pCtrl, onP),
            _buildSliderRow('I', i, 10, iCtrl, onI),
            _buildSliderRow('D', d, 30, dCtrl, onD),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton(
                onPressed: onSend,
                child: const Text('SEND', style: TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncBadge() {
    if (_syncStatus.isEmpty) {
      return const SizedBox.shrink();
    }

    final bool isSaved = _syncStatus == 'Saved';
    final bool isSyncing = _syncStatus == 'Syncing...';
    final Color borderColor = isSaved
        ? AppColors.success
        : isSyncing
        ? AppColors.secondaryAccent
        : AppColors.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(999),
        color: AppColors.background,
      ),
      child: Text(
        _syncStatus,
        style: TextStyle(
          color: borderColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('PID TUNING', style: AppTextStyles.title()),
              const SizedBox(width: 12),
              _buildSyncBadge(),
              const Spacer(),
              OutlinedButton(
                onPressed: _resetDefaults,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.gridDivider),
                ),
                child: const Text(
                  'RESET DEFAULT',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              _buildPIDPanel(
                'ANGLE PID',
                _angleP,
                _angleI,
                _angleD,
                _anglePCtrl,
                _angleICtrl,
                _angleDCtrl,
                (v) => _updatePidValue(() => _angleP = v),
                (v) => _updatePidValue(() => _angleI = v),
                (v) => _updatePidValue(() => _angleD = v),
                _sendAnglePID,
              ),
              _buildPIDPanel(
                'SPEED PID',
                _speedP,
                _speedI,
                _speedD,
                _speedPCtrl,
                _speedICtrl,
                _speedDCtrl,
                (v) => _updatePidValue(() => _speedP = v),
                (v) => _updatePidValue(() => _speedI = v),
                (v) => _updatePidValue(() => _speedD = v),
                _sendSpeedPID,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
