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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row with Summary Cards
          Row(
            children: [
              Expanded(
                child: InfoCard(
                  title: "Total Products",
                  value: totalProducts.toString(),
                  description: "Total number of products in inventory",
                  icon: Icons.inventory_2_rounded,
                  contentColor: const Color(0xFF4CAF50),
                  backgroundColor: const Color(0xFFE8F5E9),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: InfoCard(
                  title: "Low Stock Items",
                  value: lowStockItems.toString(),
                  description: "Number of items that are running low",
                  icon: Icons.warning_amber_rounded,
                  contentColor: const Color(0xFFFFB74D),
                  backgroundColor: const Color(0xFFFFF3E0),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: InfoCard(
                  title: "Out of Stock Items",
                  value: outOfStockItems.toString(),
                  description: "Count of items currently out of stock",
                  icon: Icons.remove_shopping_cart_rounded,
                  contentColor: const Color(0xFFE57373),
                  backgroundColor: const Color(0xFFFFEBEE),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Weekly Sales Section
          SalesChart(
            title: "Top Sales This Week",
            salesData: weekly,
            maxYOffset: 20,
            barColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 10),

          // Monthly Sales Section
          SalesChart(
            title:
                "Top Sales This Month (${DateFormat.MMMM().format(DateTime.now())})",
            salesData: monthly,
            maxYOffset: 50,
            barColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
