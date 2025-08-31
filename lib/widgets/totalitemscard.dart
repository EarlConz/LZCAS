import 'package:flutter/material.dart';

class TotalItemsCard extends StatelessWidget {
  const TotalItemsCard({super.key});

  final int totalItemCount = 120;

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.greenAccent, width: 1.5)),
      color: theme.colorScheme.surface,
      surfaceTintColor: theme.colorScheme.surfaceTint,
      shadowColor: theme.colorScheme.shadow,
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
                Icon(Icons.inventory_2, color: Colors.green),
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
              style: TextStyle(color: Colors.black54),
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