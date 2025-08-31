import 'package:flutter/material.dart';

class OutOfStockCard extends StatelessWidget {
  const OutOfStockCard({super.key});

  final int outOfStockCount = 15;

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.redAccent, width: 1.5)),
      color: theme.colorScheme.surface,
      surfaceTintColor: theme.colorScheme.surfaceTint,
      shadowColor: theme.colorScheme.shadow,
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