import 'package:flutter/material.dart';

class RewardsCard extends StatelessWidget {
  const RewardsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shadowColor: Colors.blueGrey.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 280,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title (Top Left)
              Text(
                "REWARDS",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[800],
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),

              // Rewards List
              const Text(
                "1,000 pts :   ₱500",
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
              const Text(
                "2,000 pts :   ₱1,000",
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
              const Text(
                "5,000 pts :   ₱2,500",
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
              const Text(
                "10,000 pts : ₱5,000",
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
              const Text(
                "20,000 pts : ₱10,000",
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
