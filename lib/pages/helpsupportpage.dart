import 'package:flutter/material.dart';
import '../utils/fonts.dart';
import '../theme.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.help_outline_rounded,
            size: 64,
            color: isDark
                ? StockpileColors.darkTextMuted
                : StockpileColors.mutedText,
          ),
          const SizedBox(height: 16),
          Text(
            'Help & Support',
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
            'Contact us at support@lzcas.app',
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
