import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../theme.dart';

class SalesChart extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> salesData;
  final double maxYOffset;
  final Color barColor;
  final bool showTitle;

  const SalesChart({
    super.key,
    required this.title,
    required this.salesData,
    required this.maxYOffset,
    required this.barColor,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 750;

    // Sort sales descending (highest on left)
    salesData.sort((a, b) => (b["sales"] as int).compareTo(a["sales"] as int));

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      color: colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(appRadius),
        ),
        padding: EdgeInsets.fromLTRB(
          isMobile ? 12 : 16,
          isMobile ? 10 : 14,
          isMobile ? 12 : 16,
          isMobile ? 8 : 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTitle) ...[
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 14),
            ],
            SizedBox(
              height: isMobile ? 180 : 220,
              child: salesData.isEmpty
                  ? Center(
                      child: Text(
                        'No sales data yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY:
                            (salesData.isNotEmpty
                                    ? (salesData.first["sales"] as int) +
                                          maxYOffset
                                    : 100)
                                .toDouble(),
                        barTouchData: BarTouchData(enabled: true),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: isMobile ? 38 : 44,
                              getTitlesWidget: (value, meta) {
                                int index = value.toInt();
                                if (index < 0 || index >= salesData.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: SizedBox(
                                    width: isMobile ? 50 : 76,
                                    child: Text(
                                      salesData[index]["product"] as String,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontSize: isMobile ? 10 : null,
                                          ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: theme.dividerColor.withValues(alpha: 0.55),
                            strokeWidth: 1,
                          ),
                        ),
                        barGroups: salesData.asMap().entries.map((entry) {
                          final index = entry.key;
                          final sales = entry.value["sales"] as int;
                          return BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: sales.toDouble(),
                                color: barColor,
                                width: isMobile ? 12 : 18,
                                borderRadius: BorderRadius.circular(5),
                                backDrawRodData: BackgroundBarChartRodData(
                                  show: true,
                                  toY:
                                      (salesData.first["sales"] as int) +
                                      maxYOffset,
                                  color: colorScheme.surfaceContainerHighest,
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
