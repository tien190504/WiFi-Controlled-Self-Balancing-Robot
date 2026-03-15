import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Virtual joystick widget for Rocker mode.
/// Provides normalized speed [-1, 1] and turn [-1, 1] via callback.
class JoystickView extends StatefulWidget {
  final void Function(double speed, double turn)? onMove;

  const JoystickView({super.key, this.onMove});

  @override
  State<JoystickView> createState() => _JoystickViewState();
}

class _JoystickViewState extends State<JoystickView> {
  Offset _thumbOffset = Offset.zero;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth, constraints.maxHeight);
        final center = Offset(size / 2, size / 2);
        final outerRadius = size / 2 - 30;
        final thumbRadius = outerRadius * 0.18;

        return GestureDetector(
          onPanStart: (details) {
            _isDragging = true;
            _updateThumb(details.localPosition, center, outerRadius, thumbRadius);
          },
          onPanUpdate: (details) {
            if (_isDragging) {
              _updateThumb(details.localPosition, center, outerRadius, thumbRadius);
            }
          },
          onPanEnd: (_) => _resetThumb(),
          onPanCancel: () => _resetThumb(),
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _JoystickPainter(
                thumbOffset: _thumbOffset,
                outerRadius: outerRadius,
                thumbRadius: thumbRadius,
              ),
            ),
          ),
        );
      },
    );
  }

  void _updateThumb(Offset touch, Offset center, double outerRadius, double thumbRadius) {
    var dx = touch.dx - center.dx;
    var dy = touch.dy - center.dy;
    final dist = sqrt(dx * dx + dy * dy);
    final maxDisp = outerRadius - thumbRadius;

    if (dist > maxDisp) {
      final ratio = maxDisp / dist;
      dx *= ratio;
      dy *= ratio;
    }

    setState(() => _thumbOffset = Offset(dx, dy));

    final speed = (-dy / maxDisp).clamp(-1.0, 1.0);
    final turn = (dx / maxDisp).clamp(-1.0, 1.0);
    widget.onMove?.call(speed, turn);
  }

  void _resetThumb() {
    setState(() {
      _isDragging = false;
      _thumbOffset = Offset.zero;
    });
    widget.onMove?.call(0, 0);
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset thumbOffset;
  final double outerRadius;
  final double thumbRadius;

  _JoystickPainter({
    required this.thumbOffset,
    required this.outerRadius,
    required this.thumbRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Glow
    canvas.drawCircle(
      center, outerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..color = AppColors.primaryAccent.withValues(alpha: 0.23),
    );

    // Outer ring
    canvas.drawCircle(
      center, outerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = AppColors.primaryAccent,
    );

    // Base fill
    canvas.drawCircle(
      center, outerRadius - 6,
      Paint()..color = AppColors.surface80,
    );

    // Guide circles
    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.primaryAccent.withValues(alpha: 0.15);
    canvas.drawCircle(center, outerRadius * 0.33, guidePaint);
    canvas.drawCircle(center, outerRadius * 0.66, guidePaint);

    // Crosshairs
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.primaryAccent.withValues(alpha: 0.12);
    canvas.drawLine(Offset(center.dx, center.dy - outerRadius),
        Offset(center.dx, center.dy + outerRadius), crossPaint);
    canvas.drawLine(Offset(center.dx - outerRadius, center.dy),
        Offset(center.dx + outerRadius, center.dy), crossPaint);

    // Labels
    final labelStyle = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 13,
    );
    _drawText(canvas, 'FWD', Offset(center.dx, center.dy - outerRadius - 18), labelStyle);
    _drawText(canvas, 'BACK', Offset(center.dx, center.dy + outerRadius + 18), labelStyle);
    _drawText(canvas, 'L', Offset(center.dx - outerRadius - 18, center.dy), labelStyle);
    _drawText(canvas, 'R', Offset(center.dx + outerRadius + 18, center.dy), labelStyle);

    // Thumb
    final thumbCenter = center + thumbOffset;
    canvas.drawCircle(
      thumbCenter + const Offset(2, 2), thumbRadius,
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );
    canvas.drawCircle(thumbCenter, thumbRadius, Paint()..color = AppColors.primaryAccent);
    canvas.drawCircle(
      thumbCenter, thumbRadius * 0.55,
      Paint()..color = AppColors.primaryAccent.withValues(alpha: 0.7),
    );
  }

  void _drawText(Canvas canvas, String text, Offset position, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter old) =>
      old.thumbOffset != thumbOffset;
}
