import 'package:flutter/material.dart';

class OutOfStockCard extends StatelessWidget {
  const OutOfStockCard({super.key});

  final int outOfStockCount = 15;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);

    return Card(
      color: Color(0xFFFFEBEE),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.redAccent, width: 1.5)),
      borderOnForeground: true,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.remove_shopping_cart, color: Color(0xFFE57373)),
                SizedBox(width: 8),
                Text(
                  "Out of Stock Items",
                  style: TextStyle(
                    color: Color(0xFFE57373),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              "Count of items currently out of stock",
              style: TextStyle(color: Color(0xFFE57373)),
            ),
            const SizedBox(height: 10),
            Text(
              "$outOfStockCount", // replace with dynamic value later
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