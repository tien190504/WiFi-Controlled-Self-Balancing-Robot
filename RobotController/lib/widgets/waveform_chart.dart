import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Real-time waveform chart.
/// Ring buffer of up to 300 data points, drawn as a scrolling red line.
class WaveformChart extends StatelessWidget {
  final List<double> dataPoints;
  final double yRange;
  final bool isPaused;

  const WaveformChart({
    super.key,
    required this.dataPoints,
    this.yRange = 30,
    this.isPaused = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WaveformPainter(dataPoints: dataPoints, yRange: yRange),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> dataPoints;
  final double yRange;
  static const int maxPoints = 300;

  _WaveformPainter({required this.dataPoints, required this.yRange});

  @override
  void paint(Canvas canvas, Size size) {
    const marginLeft = 65.0;
    const marginRight = 15.0;
    const marginTop = 40.0;
    const marginBottom = 40.0;

    final chartW = size.width - marginLeft - marginRight;
    final chartH = size.height - marginTop - marginBottom;
    final chartLeft = marginLeft;
    final chartTop = marginTop;
    final chartRight = chartLeft + chartW;
    final chartBottom = chartTop + chartH;

    // Border
    canvas.drawRect(
      Rect.fromLTRB(chartLeft, chartTop, chartRight, chartBottom),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.gridDivider,
    );

    // Horizontal grid + Y labels
    const hLines = 6;
    for (int i = 0; i <= hLines; i++) {
      final y = chartTop + (chartH / hLines) * i;
      canvas.drawLine(
        Offset(chartLeft, y),
        Offset(chartRight, y),
        Paint()
          ..strokeWidth = 0.5
          ..color = AppColors.gridDivider,
      );
      final val = yRange - (2 * yRange / hLines) * i;
      _drawText(
        canvas,
        '${val.toStringAsFixed(0)}°',
        Offset(chartLeft - 8, y),
        TextStyle(color: AppColors.textSecondary, fontSize: 11),
        align: TextAlign.right,
      );
    }

    // Vertical grid
    const vLines = 10;
    for (int i = 0; i <= vLines; i++) {
      final x = chartLeft + (chartW / vLines) * i;
      canvas.drawLine(
        Offset(x, chartTop),
        Offset(x, chartBottom),
        Paint()
          ..strokeWidth = 0.5
          ..color = AppColors.gridDivider,
      );
    }

    // Target line (y = 0)
    final zeroY = chartTop + chartH / 2;
    final dashPaint = Paint()
      ..strokeWidth = 1.5
      ..color = AppColors.tertiaryAccent;
    _drawDashedLine(
      canvas,
      Offset(chartLeft, zeroY),
      Offset(chartRight, zeroY),
      dashPaint,
    );

    // X-axis label
    _drawText(
      canvas,
      'Time (s)',
      Offset(chartLeft + chartW / 2, chartBottom + 28),
      TextStyle(color: AppColors.textSecondary, fontSize: 12),
    );

    // Y-axis label
    canvas.save();
    canvas.translate(14, chartTop + chartH / 2);
    canvas.rotate(-pi / 2);
    _drawText(
      canvas,
      'Angle (°)',
      Offset.zero,
      TextStyle(color: AppColors.textSecondary, fontSize: 12),
    );
    canvas.restore();

    // Waveform
    if (dataPoints.length > 1) {
      final path = Path();
      final stepX = chartW / (maxPoints - 1);

      for (int i = 0; i < dataPoints.length; i++) {
        final x = chartLeft + i * stepX;
        final normalized = (dataPoints[i] + yRange) / (2 * yRange);
        final y = chartBottom - normalized.clamp(0.0, 1.0) * chartH;

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = AppColors.danger
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Legend
    final legendX = chartLeft + 12;
    final legendY = chartTop + 18.0;
    canvas.drawCircle(
      Offset(legendX, legendY - 4),
      5,
      Paint()..color = AppColors.danger,
    );
    _drawText(
      canvas,
      'Angle',
      Offset(legendX + 12, legendY),
      const TextStyle(color: Colors.white, fontSize: 12),
      align: TextAlign.left,
    );

    canvas.drawCircle(
      Offset(legendX + 80, legendY - 4),
      5,
      Paint()..color = AppColors.tertiaryAccent,
    );
    _drawText(
      canvas,
      'Target',
      Offset(legendX + 92, legendY),
      const TextStyle(color: Colors.white, fontSize: 12),
      align: TextAlign.left,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLen = 10.0;
    const gapLen = 5.0;
    var x = start.dx;
    while (x < end.dx) {
      canvas.drawLine(
        Offset(x, start.dy),
        Offset(min(x + dashLen, end.dx), start.dy),
        paint,
      );
      x += dashLen + gapLen;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset pos,
    TextStyle style, {
    TextAlign align = TextAlign.center,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    double dx;
    if (align == TextAlign.right) {
      dx = pos.dx - tp.width;
    } else if (align == TextAlign.left) {
      dx = pos.dx;
    } else {
      dx = pos.dx - tp.width / 2;
    }
    tp.paint(canvas, Offset(dx, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => true;
}
