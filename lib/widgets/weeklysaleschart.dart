import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class WeeklySalesChart extends StatelessWidget {
  const WeeklySalesChart({super.key});

  @override
  Widget build(BuildContext context) {
    // 🔹 Example weekly sales data (mock)
    final salesData = [
      {"product": "Product A", "sales": 120},
      {"product": "Product B", "sales": 95},
      {"product": "Product C", "sales": 80},
      {"product": "Product D", "sales": 70},
      {"product": "Product E", "sales": 50},
    ];

    // Sort sales descending (highest on left)
    salesData.sort((a, b) => (b["sales"] as int).compareTo(a["sales"] as int));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Top Sales This Week",
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 250,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (salesData.isNotEmpty
                      ? (salesData.first["sales"] as int) + 20
                      : 100)
                  .toDouble(),
              barTouchData: BarTouchData(enabled: true),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)), // ❌ Remove numbers
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                          style: const TextStyle(fontSize: 12),
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
                      color: Colors.green, // Bars green
                      width: 20,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}