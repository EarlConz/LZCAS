import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/widgets/infocard.dart';
import '/widgets/saleschart.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

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
                  value: "120", // Replace with dynamic value later
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
                  value: "8", // Replace with dynamic value later
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
                  value: "15", // Replace with dynamic value later
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
            salesData: [
              {"product": "Product A", "sales": 120},
              {"product": "Product B", "sales": 95},
              {"product": "Product C", "sales": 80},
              {"product": "Product D", "sales": 70},
              {"product": "Product E", "sales": 50},
            ],
            maxYOffset: 20,
            barColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 10),

          // Monthly Sales Section
          SalesChart(
            title: "Top Sales This Month (${DateFormat.MMMM().format(DateTime.now())})",
            salesData: [
              {"product": "Product A", "sales": 400},
              {"product": "Product B", "sales": 350},
              {"product": "Product C", "sales": 300},
              {"product": "Product D", "sales": 250},
              {"product": "Product E", "sales": 200},
            ],
            maxYOffset: 50,
            barColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}