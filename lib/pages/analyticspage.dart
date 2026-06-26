import 'package:flutter/material.dart';
import '../utils/fonts.dart';
import '../theme.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 64,
            color: isDark
                ? StockpileColors.darkTextMuted
                : StockpileColors.mutedText,
          ),
          const SizedBox(height: 16),
          Text(
            'Analytics',
            style: StockpileFonts.satoshi(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Advanced analytics coming soon.',
            style: StockpileFonts.satoshi(
              fontSize: 16,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}
