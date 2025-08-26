import 'package:flutter/material.dart';
import '/widgets/monthlysaleschart.dart';
import '/widgets/weeklysaleschart.dart';
import '/widgets/lowstockcard.dart';
import '/widgets/totalitemscard.dart';
import '/widgets/outofstockcard.dart';

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
            children: const [
              Expanded(child: TotalItemsCard()),
              SizedBox(width: 16),
              Expanded(child: LowStockCard()),
              SizedBox(width: 16),
              Expanded(child: OutOfStockCard()),
            ],
          ),
          const SizedBox(height: 20),

          // Weekly Sales Section
          const Card(
            elevation: 3,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: WeeklySalesChart(),
            ),
          ),
          const SizedBox(height: 20),

          // Monthly Sales Section
          const Card(
            elevation: 3,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: MonthlySalesChart(),
            ),
          ),
        ],
      ),
    );
  }
}