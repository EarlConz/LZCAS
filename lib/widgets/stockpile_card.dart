import 'package:flutter/material.dart';
import '../theme.dart';

/// The app's standard content card: flat surface, 16px radius, hairline
/// border, responsive padding. Use this instead of hand-rolling the same
/// Container decoration so all cards stay in one visual language.
class StockpileCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const StockpileCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.sizeOf(context).width < 750;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      padding: padding ?? EdgeInsets.all(isMobile ? 14 : 20),
      child: child,
    );
  }
}
