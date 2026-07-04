// lib/widgets/member_sidebar.dart
// Sidebar navigation for the Member Dashboard.
// Reseller-only items are hidden for basic members.

import 'package:flutter/material.dart';
import '../utils/fonts.dart';
import '../theme.dart';

class MemberSidebar extends StatelessWidget {
  final int selectedIndex;
  final bool isReseller;
  final ValueChanged<int> onItemSelected;
  final VoidCallback? onLogout;

  const MemberSidebar({
    super.key,
    required this.selectedIndex,
    required this.isReseller,
    required this.onItemSelected,
    this.onLogout,
  });

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
          // Brand
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
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

          // Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _SidebarTile(
                  icon: Icons.dashboard_rounded,
                  label: 'Overview',
                  index: 0,
                  selectedIndex: selectedIndex,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () => onItemSelected(0),
                ),
                _SidebarTile(
                  icon: Icons.receipt_long_rounded,
                  label: 'My Purchases',
                  index: 1,
                  selectedIndex: selectedIndex,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () => onItemSelected(1),
                ),
                // Reseller-only items
                if (isReseller) ...[
                  const SizedBox(height: 12),
                  Divider(
                    color: isDark
                        ? StockpileColors.darkDivider
                        : StockpileColors.divider,
                    indent: 12,
                    endIndent: 12,
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      'RESELLER',
                      style: StockpileFonts.satoshi(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                    ),
                  ),
                  _SidebarTile(
                    icon: Icons.swap_horiz_rounded,
                    label: 'My Borrows',
                    index: 2,
                    selectedIndex: selectedIndex,
                    activeBg: activeBg,
                    isDark: isDark,
                    onTap: () => onItemSelected(2),
                  ),
                  _SidebarTile(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Earnings',
                    index: 3,
                    selectedIndex: selectedIndex,
                    activeBg: activeBg,
                    isDark: isDark,
                    onTap: () => onItemSelected(3),
                  ),
                  _SidebarTile(
                    icon: Icons.leaderboard_rounded,
                    label: 'Rankings',
                    index: 4,
                    selectedIndex: selectedIndex,
                    activeBg: activeBg,
                    isDark: isDark,
                    onTap: () => onItemSelected(4),
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    color: isDark
                        ? StockpileColors.darkDivider
                        : StockpileColors.divider,
                    indent: 12,
                    endIndent: 12,
                  ),
                ],
                const SizedBox(height: 4),
                _SidebarTile(
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  index: isReseller ? 5 : 2,
                  selectedIndex: selectedIndex,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () => onItemSelected(isReseller ? 5 : 2),
                ),
              ],
            ),
          ),

          // Bottom divider + logout
          Divider(
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
            indent: 16,
            endIndent: 16,
          ),
          ListTile(
            leading: Icon(
              Icons.logout_rounded,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
            title: Text(
              'Sign Out',
              style: StockpileFonts.satoshi(
                fontSize: 14,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              onLogout?.call();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int selectedIndex;
  final Color activeBg;
  final bool isDark;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.activeBg,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedIndex == index;
    final textColor = isSelected
        ? StockpileColors.primary900
        : isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final bg = isSelected ? activeBg : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: textColor),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: textColor,
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
