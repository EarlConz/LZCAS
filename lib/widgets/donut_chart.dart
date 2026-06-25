import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/fonts.dart';
import '../theme.dart';

class ChartSegment {
  final String label;
  final double value;
  final Color color;

  const ChartSegment({
    required this.label,
    required this.value,
    required this.color,
  });
}

class DonutChart extends StatelessWidget {
  final List<ChartSegment> segments;
  final double size;
  final String? centerLabel;
  final bool showLegend;

  const DonutChart({
    super.key,
    required this.segments,
    this.size = 200,
    this.centerLabel,
    this.showLegend = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(
              segments: segments,
              backgroundColor: isDark
                  ? StockpileColors.darkInputBg
                  : const Color(0xFFF0F0F4),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    centerLabel ?? _formatTotal(segments),
                    style: StockpileFonts.satoshi(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? StockpileColors.darkTextPrimary
                          : StockpileColors.darkText,
                    ),
                  ),
                  Text(
                    'Total',
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showLegend) ...[
          const SizedBox(height: 20),
          Text(
            'Top 4 Areas',
            style: StockpileFonts.satoshi(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
          const SizedBox(height: 12),
          ...segments.map((seg) {
            final total = segments.fold<double>(0, (s, e) => s + e.value);
            final pct = total > 0 ? (seg.value / total * 100).round() : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: seg.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      seg.label,
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? StockpileColors.darkTextPrimary
                            : StockpileColors.darkText,
                      ),
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _formatCurrency(seg.value),
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? StockpileColors.darkTextPrimary
                          : StockpileColors.darkText,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  String _formatTotal(List<ChartSegment> segs) {
    final total = segs.fold<double>(0, (s, e) => s + e.value);
    if (total >= 1000000) return '\$${(total / 1000000).toStringAsFixed(1)}M';
    if (total >= 1000) return '\$${(total / 1000).toStringAsFixed(1)}K';
    return '\$${total.toInt()}';
  }

  String _formatCurrency(double val) {
    if (val >= 1000000) return '\$${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return '\$${(val / 1000).toStringAsFixed(1)}K';
    return '\$${val.toInt()}';
  }
}

class _DonutPainter extends CustomPainter {
  final List<ChartSegment> segments;
  final Color backgroundColor;

  _DonutPainter({required this.segments, required this.backgroundColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;
    const strokeWidth = 28.0;

    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0 || segments.isEmpty) {
      // Draw empty ring
      final emptyPaint = Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi,
        false,
        emptyPaint,
      );
      return;
    }

    double startAngle = -math.pi / 2;

    for (final seg in segments) {
      final sweepAngle = (seg.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return segments != oldDelegate.segments;
  }
}
