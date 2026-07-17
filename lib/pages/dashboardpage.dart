import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/db/db.dart';
import '../theme.dart';
import '../utils/fonts.dart';
import '../widgets/metric_card.dart';
import '../widgets/mini_bar_chart.dart';
import '../widgets/monthly_revenue_view.dart';
import '../widgets/stockpile_card.dart';
import '../services/config_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _loading = true;
  int monthlyRevenue = 0;
  int previousMonthRevenue = 0;
  int activeOrders = 0;
  int previousMonthOrders = 0;
  int lowStockItems = 0;
  int packageRevenue = 0;
  int packagesSold = 0;
  int previousPackagesSold = 0;
  List<Map<String, dynamic>> categoryRevenue = [];
  List<Map<String, dynamic>> topProducts = [];
  List<double> revenueTrend = [];

  /// Product sales count per month (oldest→newest, 6 entries) — feeds
  /// the Sales This Month mini chart.
  List<double> ordersTrend = [];

  StreamSubscription<String>? _changeSub;
  Timer? _reloadDebounce;

  /// Package series names in fixed display order (top 3 by 6-month
  /// revenue, extras folded into 'Other'). Colors are assigned by this
  /// order and never reshuffled.
  List<String> packageSeries = [];

  /// Per month (oldest→newest, 6 entries):
  /// `{'label': 'Feb', 'revenue': Map<String,int>, 'count': Map<String,int>}`
  List<Map<String, dynamic>> packageMonthly = [];

  /// This month's per-package totals: {'name', 'count', 'revenue'}
  List<Map<String, dynamic>> packageBreakdown = [];
  List<Map<String, dynamic>> monthlyHistory = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
    // Keep metrics fresh: reload (debounced) whenever sales, items,
    // or packages change anywhere in the app.
    _changeSub = repository.changes.listen((e) {
      const relevant = {
        'sale_added',
        'sale_updated',
        'sale_deleted',
        'sale_imported',
        'item_added',
        'item_updated',
        'item_deleted',
        'package_updated',
      };
      if (!relevant.contains(e)) return;
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 400), _loadStats);
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _changeSub?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      await _loadStatsInner();
    } catch (e) {
      debugPrint('[Dashboard] load failed: $e');
    } finally {
      // Never leave the page stuck on the spinner; a failed refresh
      // keeps showing the previous numbers.
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _loadStatsInner() async {
    final now = DateTime.now();
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final threshold = context.read<ConfigService>().lowStockThreshold;

    // ── 1. Main metrics via server-side aggregate query ─────────────
    final stats = await repository.fetchDashboardStats(
      thisMonthStart: thisMonthStart,
      thisMonthEnd: nextMonth,
      lastMonthStart: lastMonthStart,
      lastMonthEnd: thisMonthStart,
      lowStockThreshold: threshold,
    );

    if (!mounted) return;
    monthlyRevenue = stats['monthlyRevenue'] as int;
    activeOrders = stats['activeOrders'] as int;
    previousMonthRevenue = stats['previousMonthRevenue'] as int;
    previousMonthOrders = stats['previousMonthOrders'] as int;
    lowStockItems = stats['lowStockItems'] as int;
    packageRevenue = stats['packageRevenue'] as int? ?? 0;
    packagesSold = stats['packagesSold'] as int? ?? 0;
    previousPackagesSold = stats['previousPackagesSold'] as int? ?? 0;

    // ── 2. This month's sales + items (parallel) ────────────────────
    final results = await Future.wait<dynamic>([
      repository.fetchSalesBetween(thisMonthStart, nextMonth),
      repository
          .fetchItems(), // items table is small; categories are only on items
    ]);
    if (!mounted) return;

    final thisMonthSales = results[0] as List<Sale>;
    final items = results[1] as List<Item>;

    // ── 3. Category revenue breakdown (products only) ───────────────
    final Map<String, int> catRevenue = {};
    for (final s in thisMonthSales) {
      if (s.isPackage) continue; // packages are not products
      final item = items.where((i) => i.id == s.itemId).firstOrNull;
      final cat = item?.category?.isNotEmpty == true
          ? item!.category!
          : 'Uncategorized';
      catRevenue[cat] = (catRevenue[cat] ?? 0) + s.price * s.quantity;
    }
    categoryRevenue =
        catRevenue.entries
            .map((e) => {'category': e.key, 'revenue': e.value})
            .toList()
          ..sort(
            (a, b) => (b['revenue'] as int).compareTo(a['revenue'] as int),
          );

    // ── 4. Top products (this month only, products only) ────────────
    final Map<int, Map<String, dynamic>> productAgg = {};
    for (final s in thisMonthSales) {
      if (s.isPackage) continue; // packages are not products
      productAgg[s.itemId] = {
        'itemId': s.itemId,
        'productName': s.itemName,
        'revenue':
            (productAgg[s.itemId]?['revenue'] ?? 0) + s.price * s.quantity,
        'unitsSold': (productAgg[s.itemId]?['unitsSold'] ?? 0) + s.quantity,
      };
    }
    topProducts = productAgg.values.toList()
      ..sort(
        (a, b) => (b['unitsSold'] as int).compareTo(a['unitsSold'] as int),
      );
    topProducts = topProducts.take(5).toList();

    // ── 4b. This month's package breakdown ──────────────────────────
    final Map<String, Map<String, int>> pkgAgg = {};
    for (final s in thisMonthSales) {
      if (!s.isPackage) continue;
      final name = s.itemName.isNotEmpty ? s.itemName : 'Package';
      final entry = pkgAgg.putIfAbsent(name, () => {'count': 0, 'revenue': 0});
      entry['count'] = entry['count']! + s.quantity;
      entry['revenue'] = entry['revenue']! + s.price * s.quantity;
    }
    packageBreakdown =
        pkgAgg.entries
            .map(
              (e) => {
                'name': e.key,
                'count': e.value['count'],
                'revenue': e.value['revenue'],
              },
            )
            .toList()
          ..sort(
            (a, b) => (b['revenue'] as int).compareTo(a['revenue'] as int),
          );

    // ── 5. Monthly revenue history (single query, client-aggregated)
    monthlyHistory = await repository.fetchMonthlyRevenueHistory(12);

    // ── 6. 6-month trends: product revenue + per-package breakdown ──
    // Months fetched in parallel (current month reuses step 2's rows);
    // product revenue/count feed the mini charts, package sales are
    // aggregated per package name for the panel.
    if (!mounted) return;
    final monthlySales = await Future.wait([
      for (int i = 5; i >= 1; i--)
        repository.fetchSalesBetween(
          DateTime(now.year, now.month - i, 1),
          DateTime(now.year, now.month - i + 1, 1),
        ),
    ]);
    if (!mounted) return;
    monthlySales.add(thisMonthSales);

    revenueTrend = [];
    ordersTrend = [];
    final List<String> monthLabels = [];
    final List<Map<String, int>> monthlyPkgRevenue = [];
    final List<Map<String, int>> monthlyPkgCount = [];
    final Map<String, int> pkgTotals = {};
    for (int m = 0; m < monthlySales.length; m++) {
      final monthStart = DateTime(
        now.year,
        now.month - (monthlySales.length - 1 - m),
        1,
      );
      double productSum = 0;
      double productCount = 0;
      final Map<String, int> mRev = {};
      final Map<String, int> mCnt = {};
      for (final sale in monthlySales[m]) {
        final lineRevenue = sale.price * sale.quantity;
        if (sale.isPackage) {
          final name = sale.itemName.isNotEmpty ? sale.itemName : 'Package';
          mRev[name] = (mRev[name] ?? 0) + lineRevenue;
          mCnt[name] = (mCnt[name] ?? 0) + sale.quantity;
          pkgTotals[name] = (pkgTotals[name] ?? 0) + lineRevenue;
        } else {
          productSum += lineRevenue;
          productCount++;
        }
      }
      revenueTrend.add(productSum);
      ordersTrend.add(productCount);
      monthLabels.add(DateFormat('MMM').format(monthStart));
      monthlyPkgRevenue.add(mRev);
      monthlyPkgCount.add(mCnt);
    }

    // Series order fixed by 6-month revenue; 4th+ packages fold into 'Other'
    final ordered = pkgTotals.keys.toList()
      ..sort((a, b) => pkgTotals[b]!.compareTo(pkgTotals[a]!));
    final topSeries = ordered.take(3).toList();
    packageSeries = [...topSeries, if (ordered.length > 3) 'Other'];
    packageMonthly = List.generate(monthLabels.length, (m) {
      final rev = <String, int>{};
      final cnt = <String, int>{};
      monthlyPkgRevenue[m].forEach((name, v) {
        final key = topSeries.contains(name) ? name : 'Other';
        rev[key] = (rev[key] ?? 0) + v;
      });
      monthlyPkgCount[m].forEach((name, v) {
        final key = topSeries.contains(name) ? name : 'Other';
        cnt[key] = (cnt[key] ?? 0) + v;
      });
      return {'label': monthLabels[m], 'revenue': rev, 'count': cnt};
    });

    if (mounted) setState(() => _loading = false);
  }

  String _fmt(int val) {
    final symbol = context.read<ConfigService>().currencySymbol;
    return NumberFormat.currency(symbol: symbol, decimalDigits: 0).format(val);
  }

  /// Month-over-month change. A zero previous month has no meaningful
  /// percentage — report "New" instead of fake growth.
  String _chg(int cur, int prev) {
    if (prev == 0) return cur > 0 ? 'New' : '0%';
    final c = ((cur - prev) / prev * 100).round();
    return c >= 0 ? '+$c%' : '$c%';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ConfigService>(); // rebuild when settings change
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final w = MediaQuery.sizeOf(context).width;
    final isMobile = w < 750;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final revUp = monthlyRevenue >= previousMonthRevenue;
    final ordUp = activeOrders >= previousMonthOrders;

    final mobilePad = isMobile ? 12.0 : appSpacing;
    return SingleChildScrollView(
      padding: EdgeInsets.all(mobilePad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: section label + month scope + manual refresh
          Row(
            children: [
              _sectionLabel('Overview', isDark),
              const Spacer(),
              Text(
                DateFormat('MMMM yyyy').format(DateTime.now()),
                style: StockpileFonts.satoshi(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? StockpileColors.darkTextMuted
                      : StockpileColors.mutedText,
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: isDark
                      ? StockpileColors.darkTextMuted
                      : StockpileColors.mutedText,
                ),
                onPressed: _loadStats,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMetricRow(isDark, revUp, ordUp, isMobile),
          const SizedBox(height: 32),
          _sectionLabel('Sales', isDark),
          const SizedBox(height: 16),
          if (isMobile) ...[
            _revenueChart(isDark, isMobile),
            const SizedBox(height: 32),
            _buildProductsTableCompact(isDark),
          ] else
            _buildChartAndProductsRow(isDark),
          const SizedBox(height: 32),
          _sectionLabel('Packages', isDark),
          const SizedBox(height: 16),
          _packageSalesPanel(isDark, isMobile),
          const SizedBox(height: 32),
          _sectionLabel('History', isDark),
          const SizedBox(height: 16),
          MonthlyRevenueView(
            data: monthlyHistory,
            currencySymbol: context.read<ConfigService>().currencySymbol,
          ),
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
        title: 'Sales This Month',
        value: activeOrders.toString(),
        badgeText: '${_chg(activeOrders, previousMonthOrders)} This Month',
        badgeColor: ordUp ? StockpileColors.success : StockpileColors.danger,
        trailing: MiniBarChart(
          values: ordersTrend.isEmpty ? [0, 0, 0, 0] : ordersTrend,
        ),
      ),
      MetricCard(
        title: 'Low Stock Items',
        value: lowStockItems.toString(),
        badgeText: lowStockItems > 0 ? 'Needs restocking' : 'All stocked',
        badgeColor: lowStockItems > 0
            ? StockpileColors.danger
            : StockpileColors.success,
        trailing: _iconCapsule(
          lowStockItems > 0
              ? Icons.warning_amber_rounded
              : Icons.check_circle_outline_rounded,
          lowStockItems > 0 ? StockpileColors.danger : StockpileColors.success,
          d,
        ),
      ),
    ];

    if (mobile) {
      return Column(
        children: [
          for (var i = 0; i < metricCards.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            metricCards[i],
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // 4-across needs real width; fall back to a 2×2 grid.
        if (constraints.maxWidth >= 1100) {
          return Row(
            children: [
              for (var i = 0; i < metricCards.length; i++) ...[
                if (i > 0) const SizedBox(width: appSpacing),
                Expanded(child: metricCards[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var r = 0; r < metricCards.length; r += 2) ...[
              if (r > 0) const SizedBox(height: appSpacing),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: metricCards[r]),
                  const SizedBox(width: appSpacing),
                  Expanded(
                    child: r + 1 < metricCards.length
                        ? metricCards[r + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  // ── Empty State ────────────────────────────────────────────────────

  Widget _emptyState(bool d, IconData icon, String title, String hint) {
    final muted = d ? StockpileColors.darkTextMuted : StockpileColors.mutedText;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: muted.withAlpha(140)),
          const SizedBox(height: 10),
          Text(
            title,
            style: StockpileFonts.satoshi(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: d
                  ? StockpileColors.darkTextBody
                  : StockpileColors.bodyText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: StockpileFonts.satoshi(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }

  /// Soft tinted capsule around a metric-card icon.
  Widget _iconCapsule(IconData icon, Color color, bool d) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: color.withAlpha(d ? 36 : 22),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 20, color: color),
  );

  // ── Card Wrapper ────────────────────────────────────────────────────

  Widget _card(bool d, Widget c) => StockpileCard(child: c);

  // â”€â”€ Revenue By Category Chart â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _revenueChart(bool d, bool mobile) {
    final cats = categoryRevenue.take(8).toList();
    final total = categoryRevenue.fold<int>(
      0,
      (s, e) => s + (e['revenue'] as int),
    );
    final barWidth = mobile ? 20.0 : 28.0;

    return _card(
      d,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 24),
          SizedBox(
            height: 240,
            child: cats.isEmpty
                ? _emptyState(
                    d,
                    Icons.bar_chart_rounded,
                    'No revenue yet',
                    'Sales recorded in the POS Terminal will appear here.',
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
                '$cat\n₱${r.toY.toInt()}',
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
              reservedSize: 30,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= cats.length) {
                  return const SizedBox.shrink();
                }
                final name = cats[idx]['category'] as String;
                final displayName = name.length > 10
                    ? '${name.substring(0, 9)}\u2026'
                    : name;
                // Name only — the peso value lives in the tooltip.
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 70,
                    child: Text(
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

  Widget _buildChartAndProductsRow(bool d) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: 3, child: _revenueChart(d, false)),
      const SizedBox(width: 16),
      Expanded(flex: 2, child: _buildProductsTableCompact(d)),
    ],
  );

  Widget _buildProductsTableCompact(bool d) => _card(
    d,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: 12),
        if (topProducts.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: _emptyState(
              d,
              Icons.inventory_2_outlined,
              'No sales yet',
              'Top sellers show up once products are sold.',
            ),
          )
        else
          ...topProducts.take(5).map((p) {
            final i = topProducts.indexOf(p);
            final nm = (p['productName'] as String?) ?? '\u2014';
            final sold = p['unitsSold'] as int;
            return ListTile(
              dense: true,
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  // Top rank gets the brand gold; the rest stay neutral.
                  color: i == 0
                      ? StockpileColors.primary500.withAlpha(d ? 50 : 36)
                      : (d
                            ? StockpileColors.darkInputBg
                            : StockpileColors.inputBg),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: i == 0
                        ? StockpileColors.primary800
                        : (d
                              ? StockpileColors.darkTextMuted
                              : StockpileColors.mutedText),
                  ),
                ),
              ),
              title: Text(
                nm,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: d
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                ),
              ),
              trailing: Text(
                '$sold sold',
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: d
                      ? StockpileColors.darkTextBody
                      : StockpileColors.bodyText,
                ),
              ),
            );
          }),
      ],
    ),
  );

  // ── Package Sales Panel ─────────────────────────────────────────────
  // Packages are not products: they get their own panel instead of a
  // slot in the product metrics. Monthly grouped bars (6 months) per
  // package + this-month breakdown list.

  /// Fixed categorical colors, assigned by [packageSeries] order.
  /// Blue and orange validated for CVD separation and contrast on both
  /// the light (#FFFFFF) and dark (#1A1A2E) card surfaces; the orange
  /// uses a darker step in dark mode to stay in the lightness band.
  /// Gray is reserved for the 'Other' fold.
  List<Color> _packageColors(bool d) => [
    StockpileColors.secondary400,
    d ? const Color(0xFFE65C00) : StockpileColors.primary900,
    d ? StockpileColors.darkTextMuted : StockpileColors.mutedText,
    d ? StockpileColors.darkTextBody : StockpileColors.bodyText,
  ];

  Color _packageColor(bool d, int index) {
    final colors = _packageColors(d);
    return colors[index.clamp(0, colors.length - 1)];
  }

  Widget _packageSalesPanel(bool d, bool mobile) {
    final hasData = packageSeries.isNotEmpty;
    final availedUp = packagesSold >= previousPackagesSold;
    final titleColor = d
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final mutedColor = d
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return _card(
      d,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Package Sales',
                style: StockpileFonts.satoshi(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      (availedUp
                              ? StockpileColors.success
                              : StockpileColors.danger)
                          .withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$packagesSold Availed This Month',
                  style: StockpileFonts.satoshi(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: availedUp
                        ? StockpileColors.success
                        : StockpileColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _fmt(packageRevenue),
            style: StockpileFonts.satoshi(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: titleColor,
            ),
          ),
          Text(
            'Package revenue this month',
            style: StockpileFonts.satoshi(fontSize: 12, color: mutedColor),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: !hasData
                ? _emptyState(
                    d,
                    Icons.card_giftcard_rounded,
                    'No package sales yet',
                    'Packages availed by resellers will chart here.',
                  )
                : _buildPackageBarChart(d, mobile),
          ),
          if (hasData && packageSeries.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (var i = 0; i < packageSeries.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _packageColor(d, i),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        packageSeries[i],
                        style: StockpileFonts.satoshi(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: d
                              ? StockpileColors.darkTextBody
                              : StockpileColors.bodyText,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          if (hasData) ...[
            const SizedBox(height: 16),
            Divider(
              height: 1,
              color: d ? StockpileColors.darkDivider : StockpileColors.divider,
            ),
            const SizedBox(height: 8),
            ..._buildPackageBreakdownRows(d),
          ],
        ],
      ),
    );
  }

  /// This-month totals per package — doubles as the labeled table view
  /// (identity is never color-alone).
  List<Widget> _buildPackageBreakdownRows(bool d) {
    return [
      for (var i = 0; i < packageSeries.length; i++)
        Builder(
          builder: (context) {
            final name = packageSeries[i];
            final row = packageBreakdown.firstWhere(
              (b) => b['name'] == name,
              orElse: () => {'name': name, 'count': 0, 'revenue': 0},
            );
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _packageColor(d, i),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: d
                            ? StockpileColors.darkTextPrimary
                            : StockpileColors.darkText,
                      ),
                    ),
                  ),
                  Text(
                    '${row['count']} availed',
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      color: d
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 90,
                    child: Text(
                      _fmt(row['revenue'] as int),
                      textAlign: TextAlign.right,
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: d
                            ? StockpileColors.darkTextBody
                            : StockpileColors.bodyText,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
    ];
  }

  Widget _buildPackageBarChart(bool d, bool mobile) {
    double maxRev = 0;
    for (final m in packageMonthly) {
      for (final v in (m['revenue'] as Map<String, int>).values) {
        if (v > maxRev) maxRev = v.toDouble();
      }
    }
    if (maxRev <= 0) maxRev = 1;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxRev * 1.25,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, rodIndex) {
              final name = packageSeries[rodIndex];
              final month = packageMonthly[group.x];
              final count = (month['count'] as Map<String, int>)[name] ?? 0;
              return BarTooltipItem(
                '$name\n₱${rod.toY.toInt()} · $count availed',
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
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= packageMonthly.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    packageMonthly[idx]['label'] as String,
                    style: StockpileFonts.satoshi(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: d
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
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
        barGroups: [
          for (var m = 0; m < packageMonthly.length; m++)
            BarChartGroupData(
              x: m,
              barsSpace: 2,
              barRods: [
                for (var i = 0; i < packageSeries.length; i++)
                  BarChartRodData(
                    toY:
                        ((packageMonthly[m]['revenue']
                                    as Map<String, int>)[packageSeries[i]] ??
                                0)
                            .toDouble(),
                    color: _packageColor(d, i),
                    width: mobile ? 8 : 12,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
