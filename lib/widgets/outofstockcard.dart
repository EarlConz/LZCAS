import 'package:flutter/material.dart';

class OutOfStockCard extends StatelessWidget {
  const OutOfStockCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.remove_shopping_cart, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  "Out of Stock Items",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              "Count of items currently out of stock",
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            const Text(
              "15", // replace with dynamic value later
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