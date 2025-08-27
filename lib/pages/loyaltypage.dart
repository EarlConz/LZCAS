import 'package:flutter/material.dart';
import '/widgets/rewardscard.dart';

class LoyaltyPage extends StatelessWidget {
  const LoyaltyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            RewardsCard(), // 🔹 Card on the left
            SizedBox(width: 20),
            Expanded(child: SizedBox()), // placeholder for right section
          ],
        ),
      ),
    );
  }
}