import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Live scrolling trace of one scalar channel.
///
/// Autoscales to the window's own maximum rather than a fixed ceiling: the
/// interesting range at rest (0–0.1 g of hand tremor) and the interesting
/// range during an impact (0–20 g) differ by two orders of magnitude, and a
/// fixed axis renders one of them as a flat line. [floorMax] stops the scale
/// collapsing onto sensor noise when the device is perfectly still.
class TracePainter extends CustomPainter {
  TracePainter({
    required this.samples,
    required this.color,
    this.floorMax = 0.25,
  });

  final List<double> samples;
  final Color color;
  final double floorMax;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (samples.length < 2) return;

    var maxValue = floorMax;
    for (final s in samples) {
      if (s > maxValue) maxValue = s;
    }

    final dx = size.width / (samples.length - 1);
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final y = size.height - (samples[i] / maxValue).clamp(0.0, 1.0) * size.height;
      final x = i * dx;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    final scaleLabel = TextPainter(
      text: TextSpan(
        text: maxValue.toStringAsFixed(2),
        style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    scaleLabel.paint(canvas, const Offset(2, 1));
  }

  @override
  bool shouldRepaint(TracePainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.color != color;
}
