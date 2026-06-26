import 'package:flutter/material.dart';
import '../utils/fonts.dart';
import '../theme.dart';

class StockpileTopBar extends StatelessWidget {
  final String pageTitle;
  final VoidCallback? onMenuTap;
  final bool showMenu;

  const StockpileTopBar({
    super.key,
    required this.pageTitle,
    this.onMenuTap,
    this.showMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.03 * 255).round()),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          // Hamburger (mobile only)
          if (showMenu) ...[
            IconButton(
              icon: Icon(
                Icons.menu_rounded,
                color: isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
              onPressed: onMenuTap,
              tooltip: 'Menu',
            ),
            const SizedBox(width: 12),
          ],

          // Page title
          Text(
            pageTitle,
            style: StockpileFonts.satoshi(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
              height: 1.2,
            ),
          ),

          const Spacer(),

          // Notification bell
          IconButton(
            icon: Badge(
              backgroundColor: StockpileColors.primary900,
              label: const Text(
                '0',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
              child: Icon(
                Icons.notifications_outlined,
                color: isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
            ),
            onPressed: () {
              // TODO: notifications
            },
            tooltip: 'Notifications',
          ),
        ],
      ),
    );
  }
}
