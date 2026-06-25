import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class MiniDonutChart extends StatelessWidget {
  final double percentage; // 0.0 to 1.0
  final double size;
  final Color foregroundColor;
  final Color backgroundColor;

  const MiniDonutChart({
    super.key,
    required this.percentage,
    this.size = 48,
    this.foregroundColor = StockpileColors.primary900,
    this.backgroundColor = const Color(0xFFE8E8EC),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MiniDonutPainter(
          percentage: percentage.clamp(0.0, 1.0),
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
        ),
        child: Center(
          child: Text(
            '${(percentage * 100).round()}%',
            style: TextStyle(
              fontSize: size * 0.22,
              fontWeight: FontWeight.w700,
              color: StockpileColors.darkText,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniDonutPainter extends CustomPainter {
  final double percentage;
  final Color foregroundColor;
  final Color backgroundColor;

  _MiniDonutPainter({
    required this.percentage,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    const strokeWidth = 5.0;

    // Background arc
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi,
      false,
      bgPaint,
    );

    // Foreground arc
    final fgPaint = Paint()
      ..color = foregroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * percentage,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniDonutPainter oldDelegate) {
    return percentage != oldDelegate.percentage ||
        foregroundColor != oldDelegate.foregroundColor;
  }
}
