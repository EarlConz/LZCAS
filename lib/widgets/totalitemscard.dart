import 'package:flutter/material.dart';

class TotalItemsCard extends StatelessWidget {
  const TotalItemsCard({super.key});

  final int totalItemCount = 120;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);

    return Card(
      color: Color(0xFFE8F5E9),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.greenAccent, width: 1.5)),
      borderOnForeground: true,
      clipBehavior: Clip.none,
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.inventory_2, color: Color(0xFF4CAF50)),
                SizedBox(width: 8),
                Text(
                  "Total Products",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              "Total number of products in inventory",
              style: TextStyle(color: Color(0xFF4CAF50)),
            ),
            const SizedBox(height: 10),
            Text(
              "$totalItemCount", // replace with dynamic value later
              style: const TextStyle(
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