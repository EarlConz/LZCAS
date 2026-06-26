import 'package:flutter/material.dart';
import '../utils/fonts.dart';
import '../theme.dart';

class StockpileTopBar extends StatelessWidget {
  final String pageTitle;
  final VoidCallback? onMenuTap;
  final VoidCallback? onAddNewItem;
  final bool showMenu;

  const StockpileTopBar({
    super.key,
    required this.pageTitle,
    this.onMenuTap,
    this.onAddNewItem,
    this.showMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searchBg = isDark
        ? StockpileColors.darkInputBg
        : StockpileColors.inputBg;
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

          const SizedBox(width: 32),

          // Search bar (stretched)
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: searchBg,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: isDark
                        ? StockpileColors.darkTextMuted
                        : StockpileColors.mutedText,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Search...',
                    style: StockpileFonts.satoshi(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

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

          const SizedBox(width: 12),

          // + Add New Item button
          ElevatedButton.icon(
            onPressed: onAddNewItem,
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              'Add New Item',
              style: StockpileFonts.satoshi(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: StockpileColors.charcoal,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(0, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
