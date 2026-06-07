import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/widgets/infocard.dart';
import '/widgets/saleschart.dart';
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
  int totalPointsIssued = 0;
  int averageTransactionValue = 0;
  int totalActiveMembers = 0;
  String topSpenderName = "N/A";

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
    totalPointsIssued = sales.fold(0, (sum, s) => sum + s.points);

    // Calculate average transaction value
    averageTransactionValue = sales.isEmpty
        ? 0
        : (totalRevenue ~/ sales.length);

    // Count active members (members with at least one sale)
    final Set<int?> activeMemberIds = {};
    for (final sale in sales) {
      if (sale.buyerId != null) {
        activeMemberIds.add(sale.buyerId);
      }
    }
    totalActiveMembers = activeMemberIds.length;

    // Find top spender (member with highest points)
    if (members.isNotEmpty) {
      members.sort((a, b) => b.points.compareTo(a.points));
      final topMember = members.first;
      topSpenderName = [
        topMember.firstName,
        topMember.lastName,
      ].where((part) => part != null && part.trim().isNotEmpty).join(' ');
      if (topSpenderName.isEmpty) topSpenderName = 'No name';
    }

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

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 750;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(appSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile)
            Column(
              children: [
                _buildCard(
                  "Total Products",
                  totalProducts.toString(),
                  "Total number of products in inventory",
                  Icons.inventory_2_rounded,
                  const Color(0xFF4CAF50),
                ),
                const SizedBox(height: appSpacing),
                _buildCard(
                  "Low Stock Items",
                  lowStockItems.toString(),
                  "Number of items that are running low",
                  Icons.warning_amber_rounded,
                  const Color(0xFFFFB74D),
                ),
                const SizedBox(height: appSpacing),
                _buildCard(
                  "Out of Stock Items",
                  outOfStockItems.toString(),
                  "Count of items currently out of stock",
                  Icons.remove_shopping_cart_rounded,
                  const Color(0xFFE57373),
                ),
                const SizedBox(height: appSpacing),
                _buildCard(
                  "Total Revenue",
                  "₱$totalRevenue",
                  "Total money earned from all sales",
                  Icons.attach_money_rounded,
                  const Color(0xFF42A5F5),
                ),
                const SizedBox(height: appSpacing),
                _buildCard(
                  "Total Points",
                  totalPointsIssued.toString(),
                  "Total loyalty points issued to members",
                  Icons.stars_rounded,
                  const Color(0xFFAB47BC),
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
                        "Total number of products in inventory",
                        Icons.inventory_2_rounded,
                        const Color(0xFF4CAF50),
                      ),
                    ),
                    const SizedBox(width: appSpacing),
                    Expanded(
                      child: _buildCard(
                        "Low Stock Items",
                        lowStockItems.toString(),
                        "Number of items that are running low",
                        Icons.warning_amber_rounded,
                        const Color(0xFFFFB74D),
                      ),
                    ),
                    const SizedBox(width: appSpacing),
                    Expanded(
                      child: _buildCard(
                        "Out of Stock Items",
                        outOfStockItems.toString(),
                        "Count of items currently out of stock",
                        Icons.remove_shopping_cart_rounded,
                        const Color(0xFFE57373),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: appSpacing),
                Row(
                  children: [
                    Expanded(
                      child: _buildCard(
                        "Total Revenue",
                        "₱$totalRevenue",
                        "Total money earned from all sales",
                        Icons.paid_rounded,
                        const Color(0xFF42A5F5),
                      ),
                    ),
                    const SizedBox(width: appSpacing),
                    Expanded(
                      child: _buildCard(
                        "Total Points",
                        totalPointsIssued.toString(),
                        "Total loyalty points issued to members",
                        Icons.stars_rounded,
                        const Color(0xFFAB47BC),
                      ),
                    ),
                  ],
                ),
              ],
            ),

          const SizedBox(height: appSpacing),

          if (isMobile)
            Column(
              children: [
                _buildCard(
                  "Avg Transaction",
                  "₱$averageTransactionValue",
                  "Average revenue per transaction",
                  Icons.calculate_rounded,
                  const Color(0xFF66BB6A),
                ),
                const SizedBox(height: appSpacing),
                _buildCard(
                  "Active Members",
                  totalActiveMembers.toString(),
                  "Members who made purchases",
                  Icons.people_rounded,
                  const Color(0xFF29B6F6),
                ),
                const SizedBox(height: appSpacing),
                _buildCard(
                  "Top Spender",
                  topSpenderName,
                  "Member with highest points",
                  Icons.person_pin_rounded,
                  const Color(0xFFEF5350),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildCard(
                    "Avg Transaction",
                    "₱$averageTransactionValue",
                    "Average revenue per transaction",
                    Icons.calculate_rounded,
                    const Color(0xFF66BB6A),
                  ),
                ),
                const SizedBox(width: appSpacing),
                Expanded(
                  child: _buildCard(
                    "Active Members",
                    totalActiveMembers.toString(),
                    "Members who made purchases",
                    Icons.people_rounded,
                    const Color(0xFF29B6F6),
                  ),
                ),
                const SizedBox(width: appSpacing),
                Expanded(
                  child: _buildCard(
                    "Top Spender",
                    topSpenderName,
                    "Member with highest points",
                    Icons.person_pin_rounded,
                    const Color(0xFFEF5350),
                  ),
                ),
              ],
            ),

          const SizedBox(height: appSpacing),

          if (isMobile)
            Column(
              children: [
                _buildWeeklyChart(context),
                const SizedBox(height: appSpacing),
                _buildMonthlyChart(context),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildWeeklyChart(context)),
                const SizedBox(width: appSpacing),
                Expanded(child: _buildMonthlyChart(context)),
              ],
            ),
        ],
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

  Widget _buildWeeklyChart(BuildContext context) {
    return SalesChart(
      title: "Top Sales This Week",
      salesData: weekly,
      maxYOffset: 20,
      barColor: Theme.of(context).colorScheme.primary,
    );
  }

  Widget _buildMonthlyChart(BuildContext context) {
    return SalesChart(
      title:
          "Top Sales This Month (${DateFormat.MMMM().format(DateTime.now())})",
      salesData: monthly,
      maxYOffset: 50,
      barColor: Theme.of(context).colorScheme.primary,
    );
  }
}
