import 'package:flutter/material.dart';
import '../widgets/infocard.dart';
import '../widgets/transactionstable.dart';

class TransactionPage extends StatefulWidget {
  const TransactionPage({super.key});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(child: TransactionsTable()),
            Container(
              margin: const EdgeInsets.all(8.0),
              width: 280,
              child: InfoCard(
                title: "REWARDS",
                icon: Icons.card_giftcard_rounded,
                contentColor: colorScheme.secondary,
                backgroundColor: colorScheme.secondary.withAlpha(
                  (0.1 * 255).round(),
                ),
                contentWidget: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "1,000 pts :   ₱500",
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                    Text(
                      "2,000 pts :   ₱1,000",
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                    Text(
                      "5,000 pts :   ₱2,500",
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                    Text(
                      "10,000 pts : ₱5,000",
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                    Text(
                      "20,000 pts : ₱10,000",
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
