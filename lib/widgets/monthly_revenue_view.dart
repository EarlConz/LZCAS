import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../utils/fonts.dart';
import 'stockpile_card.dart';

/// Full monthly revenue breakdown — bar chart + data table.
///
/// Expects [data] entries with keys: `month` (YYYY-MM), `revenue` (int),
/// `transactions` (int).
class MonthlyRevenueView extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final String currencySymbol;

  const MonthlyRevenueView({
    super.key,
    required this.data,
    this.currencySymbol = '₱',
  });

  static const _monthAbbr = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _label(String yyyymm) {
    final parts = yyyymm.split('-');
    if (parts.length != 2) return yyyymm;
    final m = int.tryParse(parts[1]) ?? 1;
    final y = parts[0].length == 4 ? parts[0].substring(2) : parts[0];
    return "${_monthAbbr[m.clamp(1, 12)]} '$y";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final w = MediaQuery.sizeOf(context).width;
    final isMobile = w < 750;

    // Build enriched rows (computed once)
    final rows = <Map<String, dynamic>>[];
    for (int i = 0; i < data.length; i++) {
      final e = data[i];
      final rev = (e['revenue'] as int?) ?? 0;
      final txn = (e['transactions'] as int?) ?? 0;
      final avg = txn > 0 ? rev / txn : 0.0;
      double? change;
      if (i > 0) {
        final prevRev = (data[i - 1]['revenue'] as int?) ?? 0;
        if (prevRev > 0) {
          change = ((rev - prevRev) / prevRev * 100);
        }
      }
      rows.add({
        'month': e['month'] as String,
        'revenue': rev,
        'transactions': txn,
        'avgTicket': avg,
        'change': change,
      });
    }

    return StockpileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Text(
            'Monthly Revenue History',
            style: StockpileFonts.satoshi(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          const SizedBox(height: 20),

          // ── Bar Chart ────────────────────────────────────────────────
          // On mobile the chart becomes horizontally scrollable so 12
          // months don't get squashed into a narrow viewport.
          if (isMobile && data.isNotEmpty)
            SizedBox(
              height: 200,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  // ~55px per bar group ensures readable spacing
                  width: (rows.length * 55.0).clamp(300, double.infinity),
                  child: _buildChart(isDark, false, rows),
                ),
              ),
            )
          else
            SizedBox(
              height: isMobile ? 200 : 220,
              child: data.isEmpty
                  ? Center(
                      child: Text(
                        'No revenue data yet',
                        style: StockpileFonts.satoshi(
                          fontSize: 14,
                          color: isDark
                              ? StockpileColors.darkTextMuted
                              : StockpileColors.mutedText,
                        ),
                      ),
                    )
                  : _buildChart(isDark, false, rows),
            ),

          const SizedBox(height: 20),

          // ── Data Table ───────────────────────────────────────────────
          _buildTable(isDark, isMobile, rows),
        ],
      ),
    );
  }

  // ── Bar Chart ──────────────────────────────────────────────────────────

  Widget _buildChart(
    bool isDark,
    bool isMobile,
    List<Map<String, dynamic>> rows,
  ) {
    final maxRev = rows
        .map((r) => (r['revenue'] as int).toDouble())
        .reduce((a, b) => a > b ? a : b);
    final maxY = maxRev > 0 ? maxRev * 1.25 : 100.0;
    final barWidth = isMobile ? 18.0 : 24.0;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final idx = group.x;
              if (idx < 0 || idx >= rows.length) return null;
              final rev = rows[idx]['revenue'] as int;
              return BarTooltipItem(
                '${rows[idx]['month']}\n$currencySymbol${NumberFormat('#,###').format(rev)}',
                StockpileFonts.satoshi(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= rows.length) {
                  return const SizedBox.shrink();
                }
                final rev = rows[idx]['revenue'] as int;
                return Text(
                  rev > 0
                      ? '$currencySymbol${_compact(rev)}'
                      : '',
                  style: StockpileFonts.satoshi(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? StockpileColors.darkTextMuted
                        : StockpileColors.mutedText,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= rows.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _label(rows[idx]['month'] as String),
                    style: StockpileFonts.satoshi(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? StockpileColors.darkTextBody
                          : StockpileColors.bodyText,
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
          getDrawingHorizontalLine: (v) => FlLine(
            color: (isDark
                    ? StockpileColors.darkDivider
                    : StockpileColors.divider)
                .withAlpha((0.4 * 255).round()),
            strokeWidth: 1,
          ),
        ),
        barGroups: rows.asMap().entries.map((e) {
          final rev = (e.value['revenue'] as int).toDouble();
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: rev,
                color: StockpileColors.primary900,
                width: barWidth,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Data Table ──────────────────────────────────────────────────────────

  Widget _buildTable(
    bool isDark,
    bool isMobile,
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final fmt = NumberFormat('#,###');

    // Header
    final headerStyle = StockpileFonts.satoshi(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: isDark
          ? StockpileColors.darkTextMuted
          : StockpileColors.mutedText,
      letterSpacing: 0.5,
    );

    final cellStyle = StockpileFonts.satoshi(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: isDark
          ? StockpileColors.darkTextPrimary
          : StockpileColors.darkText,
    );

    final mutedStyle = StockpileFonts.satoshi(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: isDark
          ? StockpileColors.darkTextBody
          : StockpileColors.bodyText,
    );

    final changePos = StockpileFonts.satoshi(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: StockpileColors.success,
    );
    final changeNeg = StockpileFonts.satoshi(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: StockpileColors.danger,
    );

    return Column(
      children: [
        // ── Table Header ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              Expanded(
                flex: isMobile ? 3 : 2,
                child: Text('Month', style: headerStyle),
              ),
              Expanded(
                flex: isMobile ? 3 : 2,
                child: Text('Revenue', style: headerStyle),
              ),
              if (!isMobile) ...[
                Expanded(
                  flex: 2,
                  child: Text('Transactions', style: headerStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Avg Ticket', style: headerStyle),
                ),
              ],
              Expanded(
                flex: isMobile ? 2 : 2,
                child: Text(
                  isMobile ? '±%' : 'vs Prev',
                  style: headerStyle,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // ── Table Rows ────────────────────────────────────────────────
        ...rows.map((r) {
          final rev = r['revenue'] as int;
          final txn = r['transactions'] as int;
          final avg = (r['avgTicket'] as double);
          final change = r['change'] as double?;

          final bg = isDark
              ? StockpileColors.darkInputBg.withAlpha(120)
              : StockpileColors.tableHead;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: isMobile ? 3 : 2,
                    child: Text(
                      _label(r['month'] as String),
                      style: cellStyle,
                    ),
                  ),
                  Expanded(
                    flex: isMobile ? 3 : 2,
                    child: Text(
                      '$currencySymbol${fmt.format(rev)}',
                      style: cellStyle,
                    ),
                  ),
                  if (!isMobile) ...[
                    Expanded(
                      flex: 2,
                      child: Text(
                        fmt.format(txn),
                        style: mutedStyle,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '$currencySymbol${fmt.format(avg.round())}',
                        style: mutedStyle,
                      ),
                    ),
                  ],
                  Expanded(
                    flex: isMobile ? 2 : 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: change == null
                          ? Text('\u2014', style: mutedStyle)
                          : Text(
                              '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                              style: change >= 0 ? changePos : changeNeg,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Compact number format: 1200 → "1.2k", 1500000 → "1.5M".
  static String _compact(int val) {
    if (val >= 1000000) {
      return '${(val / 1000000).toStringAsFixed(1)}M';
    }
    if (val >= 1000) {
      return '${(val / 1000).toStringAsFixed(1)}k';
    }
    return val.toString();
  }
}
