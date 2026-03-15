import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../services/mqtt_service.dart';
import '../widgets/waveform_chart.dart';

/// State Waveform Display screen with real-time chart.
class WaveformScreen extends StatefulWidget {
  const WaveformScreen({super.key});

  @override
  State<WaveformScreen> createState() => _WaveformScreenState();
}

class _WaveformScreenState extends State<WaveformScreen> {
  bool _isPaused = false;

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
  }

  void _clearChart() {
    MqttService().clearWaveform();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chart cleared'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _exportData() async {
    final data = List<double>.from(MqttService().waveformData);
    if (data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export')),
      );
      return;
    }

    try {
      final rows = [
        ['index', 'angle_degrees'],
        ...data.asMap().entries.map((e) => [e.key, e.value.toStringAsFixed(2)]),
      ];
      final csvStr = const ListToCsvConverter().convert(rows);
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final file = File('${dir.path}/robot_waveform_$timestamp.csv');
      await file.writeAsString(csvStr);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported: ${file.path.split('/').last}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Text('REAL-TIME WAVEFORM', style: AppTextStyles.title().copyWith(fontSize: 18)),
              const Spacer(),
              _topButton(_isPaused ? 'RESUME' : 'PAUSE', _togglePause, AppColors.surface),
              const SizedBox(width: 8),
              _topButton('CLEAR', _clearChart, AppColors.surface),
              const SizedBox(width: 8),
              _topButton('EXPORT', _exportData, AppColors.secondaryAccent),
            ],
          ),
        ),
        // Chart
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: ListenableBuilder(
              listenable: MqttService(),
              builder: (context, _) {
                return WaveformChart(
                  dataPoints: MqttService().waveformData,
                  isPaused: _isPaused,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _topButton(String text, VoidCallback onPressed, Color bg) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontSize: 11),
        ),
        child: Text(text),
      ),
    );
  }
}
