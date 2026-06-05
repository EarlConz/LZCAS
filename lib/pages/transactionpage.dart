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

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 750;

    final rewardsLines = [
      '1,000 pts :   PHP 500',
      '2,000 pts :   PHP 1,000',
      '5,000 pts :   PHP 2,500',
      '10,000 pts : PHP 5,000',
      '20,000 pts : PHP 10,000',
    ];

    Widget rewardsContent() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in rewardsLines)
            Text(
              line,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          const SizedBox(height: 12),
        ],
      );
    }

    final Widget rewardsCard = Container(
      margin: const EdgeInsets.all(8.0),
      width: 280,
      child: InfoCard(
        title: "REWARDS",
        icon: Icons.card_giftcard_rounded,
        contentColor: colorScheme.secondary,
        backgroundColor: colorScheme.secondary.withAlpha((0.1 * 255).round()),
        contentWidget: rewardsContent(),
      ),
    );

    final Widget mobileRewardsPanel = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Card(
        margin: EdgeInsets.zero,
        color: colorScheme.secondary.withAlpha((0.1 * 255).round()),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: Icon(
            Icons.card_giftcard_rounded,
            color: colorScheme.secondary,
          ),
          title: Text(
            'Rewards',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.secondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            Align(alignment: Alignment.centerLeft, child: rewardsContent()),
          ],
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: isDesktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: TransactionsTable()),
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, right: 8.0),
                    child: rewardsCard,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  mobileRewardsPanel,
                  const Expanded(child: TransactionsTable()),
                ],
              ),
      ),
    );
  }
}
