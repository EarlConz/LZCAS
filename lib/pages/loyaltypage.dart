import 'package:flutter/material.dart';
import '/widgets/infocard.dart';
import '/buttons/qrscanbutton.dart'; // ✅ import the button

class LoyaltyPage extends StatelessWidget {
  const LoyaltyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 280,
              child: InfoCard(
                title: "REWARDS",
                icon: Icons.card_giftcard_rounded,
                contentColor: colorScheme.secondary,
                backgroundColor: colorScheme.secondary.withOpacity(0.1),
                contentWidget: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("1,000 pts :   ₱500", style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    Text("2,000 pts :   ₱1,000", style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    Text("5,000 pts :   ₱2,500", style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    Text("10,000 pts : ₱5,000", style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    Text("20,000 pts : ₱10,000", style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    const SizedBox(height: 20),
                    const QRScanButton(), // ✅ place the scan button here
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
  }
}