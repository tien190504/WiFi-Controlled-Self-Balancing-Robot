import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Hexagonal button for the right-side mode navigation menu.
class HexagonButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const HexagonButton({
    super.key,
    required this.label,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _HexPainter(label: label, isActive: isActive),
        ),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  final String label;
  final bool isActive;

  _HexPainter({required this.label, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = min(size.width, size.height) / 2 - 6;

    // Build hex path (flat-top)
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (60 * i - 30) * pi / 180;
      final px = cx + radius * cos(angle);
      final py = cy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();

    // Fill
    canvas.drawPath(
      path,
      Paint()
        ..color = isActive
            ? AppColors.primaryAccent.withValues(alpha: 0.2)
            : AppColors.surface,
    );

    // Glow (active only)
    if (isActive) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = AppColors.primaryAccent.withValues(alpha: 0.15),
      );
    }

    // Stroke
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = isActive
            ? AppColors.primaryAccent
            : AppColors.primaryAccent.withValues(alpha: 0.4),
    );

    // Label
    final style = TextStyle(
      color: isActive ? AppColors.primaryAccent : Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final tp = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _HexPainter old) =>
      old.isActive != isActive || old.label != label;
}
