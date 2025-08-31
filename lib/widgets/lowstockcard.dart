import 'package:flutter/material.dart';

class LowStockCard extends StatelessWidget {
  const LowStockCard({super.key});

  final int lowStockCount = 8;

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.orangeAccent, width: 1.5)),       
      color: theme.colorScheme.surface,
      surfaceTintColor: theme.colorScheme.surfaceTint,
      shadowColor: theme.colorScheme.shadow,
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
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  "Low Stock Items",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              "Number of items that are running low",
              style: TextStyle(color: Colors.black54),
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