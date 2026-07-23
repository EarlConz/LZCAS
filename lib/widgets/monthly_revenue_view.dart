import 'dart:math' as math;

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

  /// The current (still in-progress) month key, e.g. "2026-07".
  static String get _currentMonthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
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
          const SizedBox(height: 2),
          Text(
            'Products + packages, last ${rows.length} months',
            style: StockpileFonts.satoshi(
              fontSize: 12,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),

          // ── Summary strip ───────────────────────────────────────────
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSummary(isDark, isMobile, rows),
          ],
          const SizedBox(height: 20),

          // ── Bar Chart ────────────────────────────────────────────────
          // On mobile the plot scrolls horizontally so 12 months aren't
          // squashed, but the Y-axis is PINNED (a twin axis-only chart) so
          // the scale stays visible while scrolling.
          if (isMobile && data.isNotEmpty)
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 48,
                    child: _buildChart(isDark, true, rows, axisOnly: true),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        // ~55px per bar group ensures readable spacing
                        width: (rows.length * 55.0).clamp(300, double.infinity),
                        child: _buildChart(
                          isDark,
                          true,
                          rows,
                          showLeftAxis: false,
                        ),
                      ),
                    ),
                  ),
                ],
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

          const SizedBox(height: 16),

          // ── Data Table (collapsed by default) ────────────────────────
          if (rows.isNotEmpty)
            _CollapsibleTable(
              isDark: isDark,
              rowCount: rows.length,
              table: _buildTable(isDark, isMobile, rows),
            ),
        ],
      ),
    );
  }

  // ── Summary strip ───────────────────────────────────────────────────────

  Widget _buildSummary(
    bool isDark,
    bool isMobile,
    List<Map<String, dynamic>> rows,
  ) {
    final fmt = NumberFormat('#,###');
    final total = rows.fold<int>(0, (s, r) => s + (r['revenue'] as int));
    final avg = rows.isEmpty ? 0 : (total / rows.length).round();
    final best = rows.reduce(
      (a, b) => (a['revenue'] as int) >= (b['revenue'] as int) ? a : b,
    );
    final bestRev = best['revenue'] as int;

    final labelColor = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final valueColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final divColor =
        (isDark ? StockpileColors.darkDivider : StockpileColors.divider)
            .withAlpha((0.6 * 255).round());

    Widget stat(String label, String value, String? sub) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: StockpileFonts.satoshi(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: StockpileFonts.satoshi(
                fontSize: isMobile ? 15 : 17,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub,
              style: StockpileFonts.satoshi(fontSize: 11, color: labelColor),
            ),
          ],
        ],
      ),
    );

    Widget sep() => Container(
      width: 1,
      height: 36,
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 14),
      color: divColor,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        stat('TOTAL', '$currencySymbol${fmt.format(total)}', null),
        sep(),
        stat('AVG / MO', '$currencySymbol${fmt.format(avg)}', null),
        sep(),
        stat(
          'BEST MONTH',
          '$currencySymbol${fmt.format(bestRev)}',
          bestRev > 0 ? _label(best['month'] as String) : '—',
        ),
      ],
    );
  }

  // ── Bar Chart ──────────────────────────────────────────────────────────

  /// Builds the bar chart. [showLeftAxis] draws the Y-axis scale;
  /// [axisOnly] renders ONLY the axis + gridlines (no bars, no month
  /// labels) — used as a pinned Y-axis beside the scrollable mobile plot,
  /// so its plot geometry (maxY, reserved sizes) must match the real chart.
  Widget _buildChart(
    bool isDark,
    bool isMobile,
    List<Map<String, dynamic>> rows, {
    bool showLeftAxis = true,
    bool axisOnly = false,
  }) {
    final maxRev = rows
        .map((r) => (r['revenue'] as int).toDouble())
        .reduce((a, b) => a > b ? a : b);
    final maxY = maxRev > 0 ? maxRev * 1.25 : 100.0;
    final interval = _niceInterval(maxY);
    final barWidth = isMobile ? 18.0 : 24.0;
    final gridColor =
        (isDark ? StockpileColors.darkDivider : StockpileColors.divider)
            .withAlpha((0.4 * 255).round());

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: !axisOnly,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final idx = group.x;
              if (idx < 0 || idx >= rows.length) return null;
              final rev = rows[idx]['revenue'] as int;
              final isCurrent = rows[idx]['month'] == _currentMonthKey;
              return BarTooltipItem(
                '${rows[idx]['month']}${isCurrent ? '  (so far)' : ''}\n$currencySymbol${NumberFormat('#,###').format(rev)}',
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
          // Y-axis scale so bar magnitudes are readable at a glance.
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: showLeftAxis,
              reservedSize: 44,
              interval: interval,
              getTitlesWidget: (v, _) {
                // Skip the 0 baseline and anything at/above the top padding.
                if (v <= 0 || v > maxY - interval * 0.5) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    '$currencySymbol${_compact(v.round())}',
                    textAlign: TextAlign.right,
                    style: StockpileFonts.satoshi(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          // Kept shown (blank on the axis-only twin) so both charts reserve
          // the same 30px and their plot areas align pixel-for-pixel.
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) {
                if (axisOnly) return const SizedBox.shrink();
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
          horizontalInterval: interval,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: gridColor, strokeWidth: 1),
        ),
        barGroups: axisOnly
            ? const []
            : rows.asMap().entries.map((e) {
                final rev = (e.value['revenue'] as int).toDouble();
                // The current month is still in progress — render it as a
                // translucent, outlined bar so it doesn't read as a finished
                // (and misleadingly lower) month.
                final isCurrent = e.value['month'] == _currentMonthKey;
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: rev,
                      color: isCurrent
                          ? StockpileColors.primary900.withAlpha(70)
                          : StockpileColors.primary900,
                      borderSide: isCurrent
                          ? const BorderSide(
                              color: StockpileColors.primary900,
                              width: 1.5,
                            )
                          : BorderSide.none,
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

  /// A "nice" gridline interval (~4 lines) rounded to 1/2/5 × 10ⁿ so the
  /// Y-axis labels are round numbers.
  static double _niceInterval(double maxY) {
    if (maxY <= 0) return 1;
    final raw = maxY / 4;
    final magnitude = math
        .pow(10, (math.log(raw) / math.ln10).floor())
        .toDouble();
    final norm = raw / magnitude;
    final double step;
    if (norm < 1.5) {
      step = 1;
    } else if (norm < 3) {
      step = 2;
    } else if (norm < 7) {
      step = 5;
    } else {
      step = 10;
    }
    final result = step * magnitude;
    return result <= 0 ? 1 : result;
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
          final isCurrent = r['month'] == _currentMonthKey;

          final bg = isCurrent
              ? StockpileColors.primary900.withAlpha(isDark ? 40 : 22)
              : (isDark
                    ? StockpileColors.darkInputBg.withAlpha(120)
                    : StockpileColors.tableHead);

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
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            _label(r['month'] as String),
                            style: cellStyle,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: StockpileColors.primary900.withAlpha(
                                isDark ? 60 : 34,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'NOW',
                              style: StockpileFonts.satoshi(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: StockpileColors.primary900,
                              ),
                            ),
                          ),
                        ],
                      ],
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

  /// Compact number format: 1200 → "1.2k", 50000 → "50k", 1.5e6 → "1.5M".
  static String _compact(int val) {
    String trim(double v) {
      final s = v.toStringAsFixed(1);
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }

    if (val >= 1000000) return '${trim(val / 1000000)}M';
    if (val >= 1000) return '${trim(val / 1000)}k';
    return val.toString();
  }
}

/// A "View monthly breakdown" toggle that reveals the detailed table.
/// The full table is long (up to 12 rows); the chart + summary strip give
/// the overview, so the table is collapsed by default.
class _CollapsibleTable extends StatefulWidget {
  final bool isDark;
  final int rowCount;
  final Widget table;

  const _CollapsibleTable({
    required this.isDark,
    required this.rowCount,
    required this.table,
  });

  @override
  State<_CollapsibleTable> createState() => _CollapsibleTableState();
}

class _CollapsibleTableState extends State<_CollapsibleTable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final accent = StockpileColors.primary900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20,
                  color: accent,
                ),
                const SizedBox(width: 4),
                Text(
                  _open
                      ? 'Hide monthly breakdown'
                      : 'View monthly breakdown (${widget.rowCount} months)',
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _open
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: widget.table,
          ),
        ),
      ],
    );
  }
}
