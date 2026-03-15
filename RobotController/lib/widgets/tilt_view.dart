import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Tilt visualizer for Gravity mode.
/// Shows crosshair reticle with a cyan dot indicating phone tilt.
class TiltView extends StatelessWidget {
  final double tiltX; // -1 to 1
  final double tiltY; // -1 to 1

  const TiltView({super.key, this.tiltX = 0, this.tiltY = 0});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TiltPainter(tiltX: tiltX, tiltY: tiltY),
    );
  }
}

class _TiltPainter extends CustomPainter {
  final double tiltX;
  final double tiltY;

  _TiltPainter({required this.tiltX, required this.tiltY});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = min(size.width, size.height) / 2 - 30;

    // Outer reticle
    canvas.drawCircle(
      Offset(cx, cy), radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.gridDivider,
    );

    // Guide rings
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.primaryAccent.withValues(alpha: 0.12);
    canvas.drawCircle(Offset(cx, cy), radius * 0.33, ringPaint);
    canvas.drawCircle(Offset(cx, cy), radius * 0.66, ringPaint);

    // Crosshairs
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.primaryAccent.withValues(alpha: 0.2);
    canvas.drawLine(Offset(cx, cy - radius), Offset(cx, cy + radius), crossPaint);
    canvas.drawLine(Offset(cx - radius, cy), Offset(cx + radius, cy), crossPaint);

    // Deadzone ring
    final deadzonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.tertiaryAccent.withValues(alpha: 0.4);
    canvas.drawCircle(Offset(cx, cy), radius * 0.15, deadzonePaint);

    // Direction arrows
    final arrowStyle = TextStyle(
      color: AppColors.primaryAccent.withValues(alpha: 0.3),
      fontSize: 18,
    );
    final arrowOff = radius + 20;
    _drawText(canvas, '▲', Offset(cx, cy - arrowOff), arrowStyle);
    _drawText(canvas, '▼', Offset(cx, cy + arrowOff), arrowStyle);
    _drawText(canvas, '◄', Offset(cx - arrowOff, cy), arrowStyle);
    _drawText(canvas, '►', Offset(cx + arrowOff, cy), arrowStyle);

    // Tilt dot
    final dotX = cx + tiltX.clamp(-1.0, 1.0) * (radius - 18);
    final dotY = cy + tiltY.clamp(-1.0, 1.0) * (radius - 18);

    canvas.drawCircle(
      Offset(dotX, dotY), 36,
      Paint()..color = AppColors.primaryAccent.withValues(alpha: 0.15),
    );
    canvas.drawCircle(Offset(dotX, dotY), 14, Paint()..color = AppColors.primaryAccent);

    // Label
    _drawText(canvas, 'TILT TO CONTROL', Offset(cx, cy - radius - 18),
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
  bool shouldRepaint(covariant _TiltPainter old) =>
      old.tiltX != tiltX || old.tiltY != tiltY;
}
