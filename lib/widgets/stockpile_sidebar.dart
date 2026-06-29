import 'package:flutter/material.dart';
import '../utils/fonts.dart';
import '../theme.dart';

class StockpileSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const StockpileSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  static const _navItems = <_NavItem>[
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.inventory_2_rounded, 'Inventory'),
    _NavItem(Icons.people_alt_rounded, 'Members'),
    _NavItem(Icons.receipt_long_rounded, 'Transactions'),
    _NavItem(Icons.description_rounded, 'Reports'),
  ];

  static const _bottomItems = <_NavItem>[
    _NavItem(Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final activeBg = isDark
        ? StockpileColors.darkSidebarActive
        : StockpileColors.sidebarActive;

    return Drawer(
      width: 260,
      backgroundColor: surface,
      elevation: 0,
      child: Column(
        children: [
          // â”€â”€ Brand â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: StockpileColors.primary900,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'LZCAS',
                  style: StockpileFonts.satoshi(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? StockpileColors.darkTextPrimary
                        : StockpileColors.darkText,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // â”€â”€ Navigation Items â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                ...List.generate(_navItems.length, (i) {
                  return _SidebarTile(
                    item: _navItems[i],
                    isSelected: selectedIndex == i,
                    activeBg: activeBg,
                    isDark: isDark,
                    onTap: () => onItemSelected(i),
                  );
                }),
                const SizedBox(height: 12),
                Divider(
                  color: isDark
                      ? StockpileColors.darkDivider
                      : StockpileColors.divider,
                  indent: 12,
                  endIndent: 12,
                ),
                const SizedBox(height: 12),
                // Settings â†’ index 5
                _SidebarTile(
                  item: _bottomItems[0],
                  isSelected: selectedIndex == 5,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () => onItemSelected(5),
                ),
              ],
            ),
          ),

          // â”€â”€ User Profile Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? StockpileColors.darkInputBg
                    : StockpileColors.inputBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: StockpileColors.primary900,
                    child: Text(
                      'AL',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Alex',
                          style: StockpileFonts.satoshi(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? StockpileColors.darkTextPrimary
                                : StockpileColors.darkText,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Admin',
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? StockpileColors.darkTextMuted
                                : StockpileColors.mutedText,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.logout_rounded,
                      size: 20,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                    onPressed: () {
                      // TODO: implement logout
                    },
                    tooltip: 'Logout',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€ Sidebar Tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final Color activeBg;
  final bool isDark;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.isSelected,
    required this.activeBg,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = isDark
        ? StockpileColors.primary500
        : StockpileColors.primary900;
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final mutedColor = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 22,
                  color: isSelected ? primaryColor : mutedColor,
                ),
                const SizedBox(width: 14),
                Text(
                  item.label,
                  style: StockpileFonts.satoshi(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? primaryColor : textColor,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€ Nav Item Data Class â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}
