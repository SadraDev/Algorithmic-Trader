import 'dart:math';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final bool showGradient;

  const SparklinePainter({
    required this.data,
    this.lineColor = AppColors.green,
    this.showGradient = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final double minVal = data.reduce(min);
    final double maxVal = data.reduce(max);
    final double range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final Path path = Path();
    final double stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final double x = i * stepX;
      final double normalizedY = (data[i] - minVal) / range;
      final double y = size.height - (normalizedY * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    if (showGradient) {
      final Path fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();

      final Paint fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.35),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

      canvas.drawPath(fillPath, fillPaint);
    }

    final Paint strokePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.lineColor != lineColor;
  }
}
