import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/widgets/infocard.dart';
import '/widgets/saleschart.dart';
import 'package:lzcas/db/db.dart';

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

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final items = await repository.fetchItems();
    final sales = await repository.fetchSales();

    // product counts
    totalProducts = items.length;
    lowStockItems = items.where((i) => i.stock < 50 && i.stock > 0).length;
    outOfStockItems = items.where((i) => i.stock <= 0).length;

    // compute weekly/monthly top sales by product name
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

    // sort descending
    weekly.sort((a, b) => (b['sales'] as int).compareTo(a['sales'] as int));
    monthly.sort((a, b) => (b['sales'] as int).compareTo(a['sales'] as int));

    setState(() {});
  }

  @override
Widget build(BuildContext context) {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile)
              Column(
                children: [
                  _buildCard("Total Products", totalProducts.toString(), "Total number of products in inventory", Icons.inventory_2_rounded, const Color(0xFF4CAF50)),
                  const SizedBox(height: 16),
                  _buildCard("Low Stock Items", lowStockItems.toString(), "Number of items that are running low", Icons.warning_amber_rounded, const Color(0xFFFFB74D)),
                  const SizedBox(height: 16),
                  _buildCard("Out of Stock Items", outOfStockItems.toString(), "Count of items currently out of stock", Icons.remove_shopping_cart_rounded, const Color(0xFFE57373)),
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: _buildCard("Total Products", totalProducts.toString(), "Total number of products in inventory", Icons.inventory_2_rounded, const Color(0xFF4CAF50))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildCard("Low Stock Items", lowStockItems.toString(), "Number of items that are running low", Icons.warning_amber_rounded, const Color(0xFFFFB74D))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildCard("Out of Stock Items", outOfStockItems.toString(), "Count of items currently out of stock", Icons.remove_shopping_cart_rounded, const Color(0xFFE57373))),
                ],
              ),
            
            const SizedBox(height: 24),

            if (isMobile)
              Column(
                children: [
                  _buildWeeklyChart(context),
                  const SizedBox(height: 16),
                  _buildMonthlyChart(context),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildWeeklyChart(context)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMonthlyChart(context)),
                ],
              ),
          ],
        );
      },
    ),
  );
}

Widget _buildCard(String title, String value, String description, IconData icon, Color color) {
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
    title: "Top Sales This Month (${DateFormat.MMMM().format(DateTime.now())})",
    salesData: monthly,
    maxYOffset: 50,
    barColor: Theme.of(context).colorScheme.primary,
  );
}

}