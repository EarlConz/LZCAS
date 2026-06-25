import 'package:flutter/material.dart';
import '../utils/fonts.dart';
import '../theme.dart';

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? badgeText;
  final Color? badgeColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.badgeText,
    this.badgeColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;

    return Card(
      color: cardColor,
      elevation: 1,
      shadowColor: Colors.black.withAlpha((0.05 * 255).round()),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                        height: 1.3,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 12),

              // Value
              Text(
                value,
                style: StockpileFonts.satoshi(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                  height: 1.2,
                ),
              ),

              // Badge
              if (badgeText != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? StockpileColors.success).withAlpha(
                      (0.12 * 255).round(),
                    ),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    badgeText!,
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: badgeColor ?? StockpileColors.success,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
