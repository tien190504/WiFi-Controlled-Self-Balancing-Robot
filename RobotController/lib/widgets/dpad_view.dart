import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum DPadDirection { none, up, down, left, right }

/// D-Pad navigation widget for Button mode.
class DPadView extends StatefulWidget {
  final void Function(DPadDirection direction, bool pressed)? onDPadPress;

  const DPadView({super.key, this.onDPadPress});

  @override
  State<DPadView> createState() => _DPadViewState();
}

class _DPadViewState extends State<DPadView> {
  DPadDirection _currentDir = DPadDirection.none;
  Timer? _repeatTimer;

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  DPadDirection _hitTest(Offset local, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final dx = local.dx - cx;
    final dy = local.dy - cy;
    final deadzone = min(size.width, size.height) * 0.08;

    if (dx.abs() < deadzone && dy.abs() < deadzone) return DPadDirection.none;
    if (dx.abs() > dy.abs()) {
      return dx > 0 ? DPadDirection.right : DPadDirection.left;
    } else {
      return dy > 0 ? DPadDirection.down : DPadDirection.up;
    }
  }

  void _onDown(Offset local, Size size) {
    final dir = _hitTest(local, size);
    if (dir != _currentDir) {
      if (_currentDir != DPadDirection.none) {
        widget.onDPadPress?.call(_currentDir, false);
      }
      _currentDir = dir;
      if (dir != DPadDirection.none) {
        widget.onDPadPress?.call(dir, true);
        _repeatTimer?.cancel();
        _repeatTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
          widget.onDPadPress?.call(_currentDir, true);
        });
      }
      setState(() {});
    }
  }

  void _onUp() {
    _repeatTimer?.cancel();
    if (_currentDir != DPadDirection.none) {
      widget.onDPadPress?.call(_currentDir, false);
    }
    setState(() => _currentDir = DPadDirection.none);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanStart: (d) => _onDown(d.localPosition, size),
          onPanUpdate: (d) => _onDown(d.localPosition, size),
          onPanEnd: (_) => _onUp(),
          onPanCancel: () => _onUp(),
          child: CustomPaint(
            size: size,
            painter: _DPadPainter(currentDir: _currentDir),
          ),
        );
      },
    );
  }
}

class _DPadPainter extends CustomPainter {
  final DPadDirection currentDir;

  _DPadPainter({required this.currentDir});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = min(size.width, size.height) / 2 - 20;
    final gap = s * 0.18;
    final arrowW = s * 0.38;
    final arrowL = s * 0.72;

    _drawArrow(canvas, cx, cy, DPadDirection.up,
        [Offset(cx, cy - arrowL), Offset(cx - arrowW, cy - gap), Offset(cx + arrowW, cy - gap)]);
    _drawArrow(canvas, cx, cy, DPadDirection.down,
        [Offset(cx, cy + arrowL), Offset(cx - arrowW, cy + gap), Offset(cx + arrowW, cy + gap)]);
    _drawArrow(canvas, cx, cy, DPadDirection.left,
        [Offset(cx - arrowL, cy), Offset(cx - gap, cy - arrowW), Offset(cx - gap, cy + arrowW)]);
    _drawArrow(canvas, cx, cy, DPadDirection.right,
        [Offset(cx + arrowL, cy), Offset(cx + gap, cy - arrowW), Offset(cx + gap, cy + arrowW)]);

    // Center hub
    canvas.drawCircle(
      Offset(cx, cy), min(size.width, size.height) * 0.06,
      Paint()..color = AppColors.primaryAccent.withValues(alpha: 0.4),
    );

    // Labels
    final style = TextStyle(color: Colors.white, fontSize: 14);
    final labelOff = s * 0.82;
    _drawText(canvas, 'FWD', Offset(cx, cy - labelOff - 5), style);
    _drawText(canvas, 'BACK', Offset(cx, cy + labelOff + 15), style);
    _drawText(canvas, 'L', Offset(cx - labelOff - 5, cy), style);
    _drawText(canvas, 'R', Offset(cx + labelOff + 5, cy), style);
  }

  void _drawArrow(Canvas canvas, double cx, double cy, DPadDirection dir, List<Offset> pts) {
    final path = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..close();

    final pressed = currentDir == dir;
    canvas.drawPath(path, Paint()..color = pressed ? AppColors.primaryAccent : AppColors.surface);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.primaryAccent,
    );
  }

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DPadPainter old) => old.currentDir != currentDir;
}
