import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/widgets/infocard.dart';
import '/widgets/saleschart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lzcas/db/db.dart';
import '../theme.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<Map<String, dynamic>> weekly = [];
  List<Map<String, dynamic>> monthly = [];
  int totalProducts = 0;
  int lowStockItems = 0;
  int outOfStockItems = 0;
  int totalRevenue = 0;
  List<Map<String, dynamic>> topSpenders = const [];
  List<Map<String, dynamic>> salesBreakdown = const [];
  List<Map<String, dynamic>> topPointsMembers = const [];

  static const _topSpenderColors = <Color>[
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Color(0xFFFFB74D),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
  ];

  static const _salesColors = <Color>[
    Color(0xFF26A69A),
    Color(0xFFEF5350),
    Color(0xFFFFCA28),
    Color(0xFF7E57C2),
    Color(0xFF29B6F6),
  ];

  static const _pointsColors = <Color>[
    Color(0xFFFF8A65),
    Color(0xFF4DB6AC),
    Color(0xFFFFD54F),
    Color(0xFF7986CB),
    Color(0xFFA1887F),
  ];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final items = await repository.fetchItems();
    final sales = await repository.fetchSales();
    final members = await repository.fetchMembers();

    totalProducts = items.length;
    lowStockItems = items.where((i) => i.stock < 50 && i.stock > 0).length;
    outOfStockItems = items.where((i) => i.stock <= 0).length;

    totalRevenue = sales.fold(0, (sum, s) => sum + s.price);

    final Map<int, String> memberNames = {};
    for (final m in members) {
      memberNames[m.id] = [
        m.firstName,
        m.lastName,
      ].where((part) => part != null && part.trim().isNotEmpty).join(' ');
      if ((memberNames[m.id]?.trim().isEmpty ?? true)) {
        memberNames[m.id] = 'No name';
      }
    }

    final List<Map<String, dynamic>> pointsRanked = members
        .map(
          (m) => {
            'id': m.id,
            'name': memberNames[m.id] ?? 'No name',
            'points': m.points,
          },
        )
        .toList();
    pointsRanked.sort(
      (a, b) => (b['points'] as int).compareTo(a['points'] as int),
    );
    topPointsMembers = pointsRanked.take(5).toList();

    final Map<int, int> spenderTotals = <int, int>{};
    for (final sale in sales) {
      final buyerId = sale.buyerId;
      if (buyerId != null) {
        spenderTotals[buyerId] = (spenderTotals[buyerId] ?? 0) + sale.price;
      }
    }

    final List<Map<String, dynamic>> ranked = spenderTotals.entries
        .map(
          (e) => {
            'id': e.key,
            'name': memberNames[e.key] ?? 'No name',
            'total': e.value,
          },
        )
        .toList();
    ranked.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
    topSpenders = ranked.take(5).toList();

    final Map<String, int> itemTotals = <String, int>{};
    for (final s in sales) {
      final String itemNameKey = s.itemName;
      if (itemNameKey.trim().isNotEmpty) {
        itemTotals[itemNameKey] = (itemTotals[itemNameKey] ?? 0) + s.price;
      }
    }

    final List<Map<String, dynamic>> itemRanked = itemTotals.entries
        .map((e) => {'item': e.key, 'total': e.value})
        .toList();
    itemRanked.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
    salesBreakdown = itemRanked.take(5).toList();

    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday % 7));
    final monthStart = DateTime(now.year, now.month, 1);

    final Map<String, int> weekAgg = {};
    final Map<String, int> monthAgg = {};

    for (final s in sales) {
      if (s.timestamp.isAfter(weekStart)) {
        weekAgg[s.itemName] = (weekAgg[s.itemName] ?? 0) + s.quantity;
      }
      if (s.timestamp.isAfter(monthStart)) {
        monthAgg[s.itemName] = (monthAgg[s.itemName] ?? 0) + s.quantity;
      }
    }

    weekly = weekAgg.entries
        .map((e) => {"product": e.key, "sales": e.value})
        .toList();
    monthly = monthAgg.entries
        .map((e) => {"product": e.key, "sales": e.value})
        .toList();

    weekly.sort((a, b) => (b['sales'] as int).compareTo(a['sales'] as int));
    monthly.sort((a, b) => (b['sales'] as int).compareTo(a['sales'] as int));

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 750;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(appSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Overview', theme),
          const SizedBox(height: 16),
          if (isMobile)
            Column(
              children: [
                _buildCard(
                  "Total Products",
                  totalProducts.toString(),
                  "Products in inventory",
                  Icons.inventory_2_rounded,
                  const Color(0xFF4CAF50),
                ),
                const SizedBox(height: 14),
                _buildCard(
                  "Low Stock Items",
                  lowStockItems.toString(),
                  "Running low on stock",
                  Icons.warning_amber_rounded,
                  const Color(0xFFFFB74D),
                ),
                const SizedBox(height: 14),
                _buildCard(
                  "Out of Stock Items",
                  outOfStockItems.toString(),
                  "Currently unavailable",
                  Icons.remove_shopping_cart_rounded,
                  const Color(0xFFE57373),
                ),
                const SizedBox(height: 14),
                _buildCard(
                  "Total Revenue",
                  "₱$totalRevenue",
                  "All-time sales revenue",
                  Icons.attach_money_rounded,
                  const Color(0xFF42A5F5),
                ),
              ],
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildCard(
                        "Total Products",
                        totalProducts.toString(),
                        "Products in inventory",
                        Icons.inventory_2_rounded,
                        const Color(0xFF4CAF50),
                      ),
                    ),
                    const SizedBox(width: appSpacing),
                    Expanded(
                      child: _buildCard(
                        "Low Stock Items",
                        lowStockItems.toString(),
                        "Running low on stock",
                        Icons.warning_amber_rounded,
                        const Color(0xFFFFB74D),
                      ),
                    ),
                    const SizedBox(width: appSpacing),
                    Expanded(
                      child: _buildCard(
                        "Out of Stock Items",
                        outOfStockItems.toString(),
                        "Currently unavailable",
                        Icons.remove_shopping_cart_rounded,
                        const Color(0xFFE57373),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildCard(
                  "Total Revenue",
                  "₱$totalRevenue",
                  "All-time sales revenue",
                  Icons.paid_rounded,
                  const Color(0xFF42A5F5),
                ),
              ],
            ),

          const SizedBox(height: 28),

          _buildSectionHeader('Analytics', theme),
          const SizedBox(height: 16),

          if (isMobile)
            Column(
              children: [
                _buildChartCard(
                  title: 'Top Spenders',
                  child: _buildTopSpendersChart(context),
                ),
                const SizedBox(height: 14),
                _buildChartCard(
                  title: 'Sales Breakdown',
                  child: _buildSalesBreakdownChart(context),
                ),
                const SizedBox(height: 14),
                _buildChartCard(
                  title: 'Top Tokens',
                  child: _buildTopPointsChart(context),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildChartCard(
                    title: 'Top Spenders',
                    child: _buildTopSpendersChart(context),
                  ),
                ),
                const SizedBox(width: appSpacing),
                Expanded(
                  child: _buildChartCard(
                    title: 'Sales Breakdown',
                    child: _buildSalesBreakdownChart(context),
                  ),
                ),
                const SizedBox(width: appSpacing),
                Expanded(
                  child: _buildChartCard(
                    title: 'Top Tokens',
                    child: _buildTopPointsChart(context),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 28),

          _buildSectionHeader('Trends', theme),
          const SizedBox(height: 16),

          if (isMobile)
            Column(
              children: [
                _buildChartCard(
                  title: 'Top Sales This Week',
                  child: _buildWeeklyChart(context),
                ),
                const SizedBox(height: 14),
                _buildChartCard(
                  title:
                      'Top Sales This Month (${DateFormat.MMMM().format(DateTime.now())})',
                  child: _buildMonthlyChart(context),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildChartCard(
                    title: 'Top Sales This Week',
                    child: _buildWeeklyChart(context),
                  ),
                ),
                const SizedBox(width: appSpacing),
                Expanded(
                  child: _buildChartCard(
                    title:
                        'Top Sales This Month (${DateFormat.MMMM().format(DateTime.now())})',
                    child: _buildMonthlyChart(context),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard(
    String title,
    String value,
    String description,
    IconData icon,
    Color color,
  ) {
    return InfoCard(
      title: title,
      value: value,
      description: description,
      icon: icon,
      contentColor: color,
    );
  }

  Widget _buildChartCard({required String title, required Widget child}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(appRadius),
        border: Border.all(color: theme.dividerColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(appRadius),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyChart(BuildContext context) {
    return SalesChart(
      title: 'Top Sales This Week',
      salesData: weekly,
      maxYOffset: 20,
      barColor: Theme.of(context).colorScheme.primary,
      showTitle: false,
    );
  }

  Widget _buildMonthlyChart(BuildContext context) {
    return SalesChart(
      title:
          'Top Sales This Month (${DateFormat.MMMM().format(DateTime.now())})',
      salesData: monthly,
      maxYOffset: 50,
      barColor: Theme.of(context).colorScheme.primary,
      showTitle: false,
    );
  }

  Widget _buildTopPointsChart(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 750;

    final data = topPointsMembers;
    final maxValue = data.isEmpty
        ? 100
        : data.fold<int>(
            0,
            (max, e) => max > (e['points'] as int) ? max : (e['points'] as int),
          );

    final barGroups = List.generate(data.length, (index) {
      final entry = data[index];
      final value = entry['points'] as int;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: value.toDouble(),
            color: _pointsColors[index % _pointsColors.length],
            width: isMobile ? 18 : 28,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      );
    });

    return SizedBox(
      height: isMobile ? 200 : 240,
      child: data.isEmpty
          ? Center(
              child: Text(
                'No points data yet',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxValue + 15).toDouble(),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => colorScheme.primary,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final label = data[group.x]['name'] ?? '';
                      final points = (rod.toY).toInt();
                      return BarTooltipItem(
                        '$label\n',
                        theme.textTheme.bodySmall ?? const TextStyle(),
                        children: [
                          TextSpan(
                            text: '$points pts',
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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
                      reservedSize: isMobile ? 40 : 52,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= data.length) {
                          return const SizedBox.shrink();
                        }
                        final label = data[index]['name'] ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SizedBox(
                            width: isMobile ? 50 : 80,
                            child: Text(
                              label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
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
                    color: theme.dividerColor.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                ),
                barGroups: barGroups,
              ),
            ),
    );
  }

  Widget _buildTopSpendersChart(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 750;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final total = topSpenders.fold<int>(
      0,
      (sum, e) => sum + (e['total'] as int? ?? 0),
    );

    List<PieChartSectionData> sections = const <PieChartSectionData>[];
    if (topSpenders.isNotEmpty && total > 0) {
      sections = topSpenders.asMap().entries.map((entry) {
        final int index = entry.key;
        final Map<String, dynamic> data = entry.value;
        final int value = data['total'] as int;
        final Color color = _topSpenderColors[index % _topSpenderColors.length];
        final double fraction = value / total;

        return PieChartSectionData(
          color: color,
          value: fraction,
          title: '${(fraction * 100).toStringAsFixed(1)}%',
          radius: isMobile ? 50 : 80,
          titleStyle: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: isMobile ? 10 : 13,
          ),
        );
      }).toList();
    }

    return _buildPieContent(
      context,
      isMobile: isMobile,
      sections: sections,
      legendItems: List<Widget>.generate(topSpenders.length, (int i) {
        final Color color = _topSpenderColors[i % _topSpenderColors.length];
        return _buildPieLegendRow(
          context,
          color: color,
          label: topSpenders[i]['name'] ?? '',
          onSurface: colorScheme.onSurface,
        );
      }),
      emptyText: 'No spending data yet',
      emptyColor: colorScheme.onSurfaceVariant,
      pieTouchData: PieTouchData(
        enabled: true,
        touchCallback: (event, response) {
          final index = response?.touchedSection?.touchedSectionIndex;
          if (index == null || index >= topSpenders.length) {
            return;
          }
        },
      ),
    );
  }

  Widget _buildSalesBreakdownChart(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 750;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final total = salesBreakdown.fold<int>(
      0,
      (sum, e) => sum + (e['total'] as int? ?? 0),
    );

    List<PieChartSectionData> sections = const <PieChartSectionData>[];
    if (salesBreakdown.isNotEmpty && total > 0) {
      sections = salesBreakdown.asMap().entries.map((entry) {
        final int index = entry.key;
        final Map<String, dynamic> data = entry.value;
        final int value = data['total'] as int;
        final Color color = _salesColors[index % _salesColors.length];
        final double fraction = value / total;

        return PieChartSectionData(
          color: color,
          value: fraction,
          title: '${(fraction * 100).toStringAsFixed(1)}%',
          radius: isMobile ? 50 : 80,
          titleStyle: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: isMobile ? 10 : 13,
          ),
        );
      }).toList();
    }

    return _buildPieContent(
      context,
      isMobile: isMobile,
      sections: sections,
      legendItems: List<Widget>.generate(salesBreakdown.length, (int i) {
        final Color color = _salesColors[i % _salesColors.length];
        return _buildPieLegendRow(
          context,
          color: color,
          label: salesBreakdown[i]['item'] ?? '',
          onSurface: colorScheme.onSurface,
        );
      }),
      emptyText: 'No sales data yet',
      emptyColor: colorScheme.onSurfaceVariant,
    );
  }

  Widget _buildPieContent(
    BuildContext context, {
    required bool isMobile,
    required List<PieChartSectionData> sections,
    required List<Widget> legendItems,
    required String emptyText,
    required Color emptyColor,
    PieTouchData? pieTouchData,
  }) {
    final theme = Theme.of(context);

    return SizedBox(
      height: isMobile ? 220 : 240,
      child: legendItems.isEmpty
          ? Center(
              child: Text(
                emptyText,
                style: theme.textTheme.bodyMedium?.copyWith(color: emptyColor),
              ),
            )
          : isMobile
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 120,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 25,
                      sections: sections,
                      pieTouchData:
                          pieTouchData ?? PieTouchData(enabled: false),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: legendItems,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 4,
                      centerSpaceRadius: 50,
                      sections: sections,
                      pieTouchData:
                          pieTouchData ?? PieTouchData(enabled: false),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: legendItems,
                ),
              ],
            ),
    );
  }

  Widget _buildPieLegendRow(
    BuildContext context, {
    required Color color,
    required String label,
    required Color onSurface,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 70,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 10,
                color: onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
