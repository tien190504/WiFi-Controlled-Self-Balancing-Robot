import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Semi-circular gauge with gradient arc and animated needle.
class GaugeView extends StatefulWidget {
  final String label;
  final String unit;
  final double minValue;
  final double maxValue;
  final double value;

  const GaugeView({
    super.key,
    this.label = 'ANGLE',
    this.unit = '°',
    this.minValue = -45,
    this.maxValue = 45,
    this.value = 0,
  });

  @override
  State<GaugeView> createState() => _GaugeViewState();
}

class _GaugeViewState extends State<GaugeView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _currentValue = widget.value;
    _animation = Tween<double>(begin: _currentValue, end: _currentValue)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(GaugeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animation = Tween<double>(begin: _currentValue, end: widget.value)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut))
        ..addListener(() {
          setState(() => _currentValue = _animation.value);
        });
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GaugePainter(
        value: _currentValue,
        minValue: widget.minValue,
        maxValue: widget.maxValue,
        label: widget.label,
        unit: widget.unit,
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final double minValue;
  final double maxValue;
  final String label;
  final String unit;

  _GaugePainter({
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.label,
    required this.unit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.65;
    final radius = min(size.width, size.height) * 0.38;

    final arcRect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // Arc background
    canvas.drawArc(
      arcRect, pi, pi, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = AppColors.primaryAccent.withValues(alpha: 0.15)
        ..strokeCap = StrokeCap.round,
    );

    // Gradient arc
    final normalized = ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [AppColors.primaryAccent, AppColors.secondaryAccent],
      ).createShader(arcRect);
    canvas.drawArc(arcRect, pi, pi * normalized, false, arcPaint);

    // Tick marks
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.3);
    for (int i = 0; i <= 10; i++) {
      final angle = pi + (i / 10) * pi;
      final inner = radius - 18;
      final outer = radius + 6;
      canvas.drawLine(
        Offset(cx + inner * cos(angle), cy + inner * sin(angle)),
        Offset(cx + outer * cos(angle), cy + outer * sin(angle)),
        tickPaint,
      );
    }

    // Needle
    final needleAngle = pi + normalized * pi;
    final needleLen = radius - 25;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + needleLen * cos(needleAngle), cy + needleLen * sin(needleAngle)),
      Paint()
        ..strokeWidth = 3
        ..color = Colors.white
        ..strokeCap = StrokeCap.round,
    );

    // Center dot
    canvas.drawCircle(Offset(cx, cy), 7, Paint()..color = AppColors.primaryAccent);

    // Value text
    final valueText = '${value.toStringAsFixed(1)}$unit';
    _drawText(canvas, valueText, Offset(cx, cy + 30),
        const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold));

    // Label
    _drawText(canvas, label, Offset(cx, cy + 52),
        TextStyle(color: AppColors.textSecondary, fontSize: 13));
  }

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.label != label;
}
