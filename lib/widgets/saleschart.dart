import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class SalesChart extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> salesData;
  final double maxYOffset;
  final Color barColor;

  const SalesChart({
    super.key,
    required this.title,
    required this.salesData,
    required this.maxYOffset,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    // Sort sales descending (highest on left)
    salesData.sort((a, b) => (b["sales"] as int).compareTo(a["sales"] as int));

    final theme = Theme.of(context);

    return Card(
      color: theme.cardTheme.color, // Use theme's card color
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SizedBox(
              height: 210,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY:
                      (salesData.isNotEmpty
                              ? (salesData.first["sales"] as int) + maxYOffset
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
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          if (index < 0 || index >= salesData.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              salesData[index]["product"] as String,
                              style: theme
                                  .textTheme
                                  .bodySmall, // Use theme's text style
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barGroups: salesData.asMap().entries.map((entry) {
                    final index = entry.key;
                    final sales = entry.value["sales"] as int;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: sales.toDouble(),
                          color: barColor,
                          width: 20,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
