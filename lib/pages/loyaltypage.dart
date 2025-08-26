import 'package:flutter/material.dart';

class LoyaltyPage extends StatelessWidget {
  const LoyaltyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        "Loyalty Points Page",
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}