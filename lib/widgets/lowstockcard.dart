import 'package:flutter/material.dart';

class LowStockCard extends StatelessWidget {
  const LowStockCard({super.key});

  final int lowStockCount = 8;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);

    return Card(
      color: Color(0xFFFFF3E0),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.orangeAccent, width: 1.5)),       
      borderOnForeground: true,
      clipBehavior: Clip.none,
      margin: EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D)),
                SizedBox(width: 8),
                Text(
                  "Low Stock Items",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFB74D)
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              "Number of items that are running low",
              style: TextStyle(color: Color(0xFFFFB74D)),
            ),
            SizedBox(height: 10),
            Text(
              "$lowStockCount", // you can later replace this with dynamic value
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}