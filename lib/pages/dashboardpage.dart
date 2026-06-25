import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lzcas/db/db.dart';
import '../theme.dart';
import '../utils/fonts.dart';
import '../widgets/metric_card.dart';
import '../widgets/mini_bar_chart.dart';
import '../widgets/mini_donut_chart.dart';
import '../widgets/mini_line_chart.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int monthlyRevenue = 0;
  int previousMonthRevenue = 0;
  int activeOrders = 0;
  int previousMonthOrders = 0;
  int lowStockItems = 0;
  List<Map<String, dynamic>> categoryRevenue = [];
  List<Map<String, dynamic>> topProducts = [];
  List<double> revenueTrend = [];
  List<double> lowStockTrend = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final items = await repository.fetchItems();
    final sales = await repository.fetchSales();
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    final lastMonth = DateTime(now.year, now.month - 1, 1);

    monthlyRevenue = sales
        .where(
          (s) =>
              s.timestamp.isAfter(thisMonth.subtract(const Duration(days: 1))),
        )
        .fold(0, (sum, s) => sum + s.price);

    previousMonthRevenue = sales
        .where(
          (s) =>
              s.timestamp.isAfter(
                lastMonth.subtract(const Duration(days: 1)),
              ) &&
              s.timestamp.isBefore(thisMonth),
        )
        .fold(0, (sum, s) => sum + s.price);

    final thisMonthSales = sales
        .where(
          (s) =>
              s.timestamp.isAfter(thisMonth.subtract(const Duration(days: 1))),
        )
        .toList();
    activeOrders = thisMonthSales.length;

    final lastMonthSales = sales
        .where(
          (s) =>
              s.timestamp.isAfter(
                lastMonth.subtract(const Duration(days: 1)),
              ) &&
              s.timestamp.isBefore(thisMonth),
        )
        .toList();
    previousMonthOrders = lastMonthSales.length;

    lowStockItems = items.where((i) => i.stock < 50 && i.stock > 0).length;

    final Map<String, int> catRevenue = {};
    for (final s in sales) {
      final item = items.where((i) => i.id == s.itemId).firstOrNull;
      final cat = item?.category ?? 'Uncategorized';
      catRevenue[cat] = (catRevenue[cat] ?? 0) + s.price;
    }
    categoryRevenue =
        catRevenue.entries
            .map((e) => {'category': e.key, 'revenue': e.value})
            .toList()
          ..sort(
            (a, b) => (b['revenue'] as int).compareTo(a['revenue'] as int),
          );

    final Map<int, Map<String, dynamic>> productAgg = {};
    for (final s in sales) {
      productAgg[s.itemId] = {
        'itemId': s.itemId,
        'productName': s.itemName,
        'revenue': (productAgg[s.itemId]?['revenue'] ?? 0) + s.price,
        'unitsSold': (productAgg[s.itemId]?['unitsSold'] ?? 0) + s.quantity,
      };
    }
    topProducts = productAgg.values.toList()
      ..sort((a, b) => (b['revenue'] as int).compareTo(a['revenue'] as int));
    topProducts = topProducts.take(8).toList();

    revenueTrend = List.generate(6, (i) {
      final monthStart = DateTime(now.year, now.month - i, 1);
      final monthEnd = DateTime(now.year, now.month - i + 1, 1);
      return sales
          .where(
            (s) =>
                s.timestamp.isAfter(
                  monthStart.subtract(const Duration(days: 1)),
                ) &&
                s.timestamp.isBefore(monthEnd),
          )
          .fold<double>(0, (sum, s) => sum + s.price)
          .toDouble();
    }).reversed.toList();

    lowStockTrend = List.generate(6, (_) => lowStockItems.toDouble());

    if (mounted) setState(() {});
  }

  String _fmt(int val) =>
      NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(val);

  String _chg(int cur, int prev) {
    if (prev == 0) return cur > 0 ? '+100%' : '0%';
    final c = ((cur - prev) / prev * 100).round();
    return c >= 0 ? '+$c%' : '$c%';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final w = MediaQuery.sizeOf(context).width;
    final isMobile = w < 750;
    final revUp = monthlyRevenue >= previousMonthRevenue;
    final ordUp = activeOrders >= previousMonthOrders;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(appSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Overview', isDark),
          const SizedBox(height: 16),
          _buildMetricRow(isDark, revUp, ordUp, isMobile),
          const SizedBox(height: 32),
          _revenueChart(isDark, isMobile),
          const SizedBox(height: 32),
          _buildProductsTable(isDark),
        ],
      ),
    );
  }

  // â”€â”€ Section Label â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _sectionLabel(String t, bool d) => Text(
    t,
    style: StockpileFonts.satoshi(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: d ? StockpileColors.darkTextMuted : StockpileColors.mutedText,
      letterSpacing: 1,
    ),
  );

  // â”€â”€ Metric Row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildMetricRow(bool d, bool revUp, bool ordUp, bool mobile) {
    final metricCards = [
      MetricCard(
        title: 'Total Revenue',
        value: _fmt(monthlyRevenue),
        badgeText: '${_chg(monthlyRevenue, previousMonthRevenue)} This Month',
        badgeColor: revUp ? StockpileColors.success : StockpileColors.danger,
        trailing: MiniBarChart(
          values: revenueTrend.isEmpty ? [0, 0, 0, 0] : revenueTrend,
        ),
      ),
      MetricCard(
        title: 'Active Orders',
        value: activeOrders.toString(),
        badgeText: '${_chg(activeOrders, previousMonthOrders)} This Month',
        badgeColor: ordUp ? StockpileColors.success : StockpileColors.danger,
        trailing: MiniDonutChart(
          percentage: activeOrders > 0
              ? activeOrders /
                    (activeOrders + previousMonthOrders).clamp(1, 999999)
              : 0,
        ),
      ),
      MetricCard(
        title: 'Low Stock Items',
        value: lowStockItems.toString(),
        trailing: MiniLineChart(
          values: lowStockTrend.isEmpty ? [0, 0, 0, 0] : lowStockTrend,
        ),
      ),
    ];

    if (mobile) {
      return Column(
        children: [
          metricCards[0],
          const SizedBox(height: 14),
          metricCards[1],
          const SizedBox(height: 14),
          metricCards[2],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: metricCards[0]),
        const SizedBox(width: appSpacing),
        Expanded(child: metricCards[1]),
        const SizedBox(width: appSpacing),
        Expanded(child: metricCards[2]),
      ],
    );
  }

  // â”€â”€ Analytics Row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  // ── Card Wrapper ────────────────────────────────────────────────────

  // â”€â”€ Card Wrapper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _card(bool d, Widget c) => Container(
    decoration: BoxDecoration(
      color: d ? StockpileColors.darkSurface : StockpileColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: d ? StockpileColors.darkDivider : StockpileColors.divider,
      ),
    ),
    padding: const EdgeInsets.all(20),
    child: c,
  );

  // â”€â”€ Revenue By Category Chart â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _revenueChart(bool d, bool mobile) {
    final cats = categoryRevenue.take(8).toList();
    final total = categoryRevenue.fold<int>(0, (s, e) => e['revenue'] as int);
    final barWidth = mobile ? 20.0 : 28.0;

    return _card(
      d,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Revenue By Product Category',
                style: StockpileFonts.satoshi(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: d
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                ),
              ),
              const Spacer(),
              _chip('Income', true),
              const SizedBox(width: 8),
              _chip('Online Sales', false),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 240,
            child: cats.isEmpty
                ? Center(
                    child: Text(
                      'No revenue data yet',
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        color: d
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                    ),
                  )
                : _buildBarChart(d, cats, total, barWidth),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(
    bool d,
    List<Map<String, dynamic>> cats,
    int total,
    double barWidth,
  ) {
    final maxVal = (cats.first['revenue'] as int).toDouble() * 1.3;
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxVal,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, _, r, __) {
              final cat = cats[g.x]['category'] as String;
              return BarTooltipItem(
                '$cat\n\$${r.toY.toInt()}',
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
                if (idx < 0 || idx >= cats.length)
                  return const SizedBox.shrink();
                final val = cats[idx]['revenue'] as int;
                final pct = total > 0 ? (val / total * 100).round() : 0;
                return Text(
                  '$pct%',
                  style: StockpileFonts.satoshi(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: d
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
              reservedSize: 50,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= cats.length)
                  return const SizedBox.shrink();
                final name = cats[idx]['category'] as String;
                final val = cats[idx]['revenue'] as int;
                final displayName = name.length > 10
                    ? '${name.substring(0, 9)}\u2026'
                    : name;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 70,
                    child: Column(
                      children: [
                        Text(
                          displayName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: StockpileFonts.satoshi(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: d
                                ? StockpileColors.darkTextBody
                                : StockpileColors.bodyText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '\$$val',
                          style: StockpileFonts.satoshi(
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            color: d
                                ? StockpileColors.darkTextMuted
                                : StockpileColors.mutedText,
                          ),
                        ),
                      ],
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
            color: (d ? StockpileColors.darkDivider : StockpileColors.divider)
                .withAlpha((0.4 * 255).round()),
            strokeWidth: 1,
          ),
        ),
        barGroups: cats.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: (e.value['revenue'] as int).toDouble(),
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

  Widget _buildProductsTable(bool d) => _card(
    d,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Top Selling Products',
              style: StockpileFonts.satoshi(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: d
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {},
              child: Text(
                'View All',
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: StockpileColors.primary900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        topProducts.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No sales data yet',
                    style: StockpileFonts.satoshi(
                      fontSize: 14,
                      color: d
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                ),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    d ? StockpileColors.darkInputBg : StockpileColors.tableHead,
                  ),
                  dividerThickness: 1,
                  headingTextStyle: StockpileFonts.satoshi(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: d
                        ? StockpileColors.darkTextMuted
                        : StockpileColors.mutedText,
                  ),
                  dataTextStyle: StockpileFonts.satoshi(
                    fontSize: 14,
                    color: d
                        ? StockpileColors.darkTextBody
                        : StockpileColors.bodyText,
                  ),
                  columns: const [
                    DataColumn(label: Text('Rank')),
                    DataColumn(label: Text('Product')),
                    DataColumn(label: Text('Item ID'), numeric: true),
                    DataColumn(label: Text('Revenue'), numeric: true),
                    DataColumn(label: Text('Units Sold'), numeric: true),
                    DataColumn(label: Text('Margin')),
                    DataColumn(label: Text('')),
                  ],
                  rows: topProducts.asMap().entries.map((e) {
                    final i = e.key;
                    final p = e.value;
                    final nm = (p['productName'] as String?) ?? '\u2014';
                    return DataRow(
                      cells: [
                        DataCell(Text('${i + 1}')),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: StockpileColors.primary900.withAlpha(
                                    (0.12 * 255).round(),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  nm.isNotEmpty ? nm[0].toUpperCase() : '?',
                                  style: StockpileFonts.satoshi(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: StockpileColors.primary900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(nm),
                            ],
                          ),
                        ),
                        DataCell(Text('#${p['itemId']}')),
                        DataCell(Text(_fmt(p['revenue'] as int))),
                        DataCell(Text('${p['unitsSold']}')),
                        const DataCell(Text('\u2014')),
                        DataCell(
                          IconButton(
                            icon: Icon(
                              Icons.more_horiz,
                              size: 20,
                              color: d
                                  ? StockpileColors.darkTextMuted
                                  : StockpileColors.mutedText,
                            ),
                            onPressed: () {},
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
      ],
    ),
  );

  // â”€â”€ Filter Chip â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _chip(String l, bool s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: s
          ? StockpileColors.primary900.withAlpha((0.12 * 255).round())
          : Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      border: Border.all(
        color: s
            ? StockpileColors.primary900.withAlpha((0.3 * 255).round())
            : StockpileColors.divider,
      ),
    ),
    child: Text(
      l,
      style: StockpileFonts.satoshi(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: s ? StockpileColors.primary900 : StockpileColors.mutedText,
      ),
    ),
  );
}
