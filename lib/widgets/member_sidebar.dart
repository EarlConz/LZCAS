// lib/widgets/member_sidebar.dart
// Sidebar navigation for the Member Dashboard.
// Reseller-only items are hidden for basic members.

import 'package:flutter/material.dart';
import '../config/feature_flags.dart';
import '../utils/fonts.dart';
import 'app_logo.dart';
import '../theme.dart';

class MemberSidebar extends StatelessWidget {
  final int selectedIndex;
  final bool isReseller;

  /// Tab positions, mirroring `_tabs` in member_dashboard.dart: Overview,
  /// [Marketplace, Active Orders], My Purchases, Announcements,
  /// [Earnings], Profile. Optional entries shift everything after them.
  _TabIndex get _ix => _TabIndex(isReseller: isReseller);
  final ValueChanged<int> onItemSelected;
  final VoidCallback? onLogout;

  /// Opens the "Nearest Cashiers" map. Kept separate from [onItemSelected]
  /// because it navigates to a dedicated route rather than switching tabs.
  final VoidCallback? onFindCashiers;

  const MemberSidebar({
    super.key,
    required this.selectedIndex,
    required this.isReseller,
    required this.onItemSelected,
    this.onLogout,
    this.onFindCashiers,
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
                const AppLogo(size: 34, radius: 8),
                const SizedBox(width: 12),
                Text(
                  'GUTVita',
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

          // Navigation Items. The indices are positions in `_tabs` over in
          // member_dashboard.dart, so they are counted here in the same
          // order with the same conditions — never written as literals.
          // (Hiding the delivery tabs with literal indices sent every
          // reseller tile to the wrong page.)
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
                if (enableDeliverySystem) ...[
                  _SidebarTile(
                    icon: Icons.storefront_rounded,
                    label: 'Marketplace',
                    index: _ix.marketplace,
                    selectedIndex: selectedIndex,
                    activeBg: activeBg,
                    isDark: isDark,
                    onTap: () => onItemSelected(_ix.marketplace),
                  ),
                  _SidebarTile(
                    icon: Icons.local_shipping_rounded,
                    label: 'Active Orders',
                    index: _ix.orders,
                    selectedIndex: selectedIndex,
                    activeBg: activeBg,
                    isDark: isDark,
                    onTap: () => onItemSelected(_ix.orders),
                  ),
                ],
                _SidebarTile(
                  icon: Icons.receipt_long_rounded,
                  label: 'My Purchases',
                  index: _ix.purchases,
                  selectedIndex: selectedIndex,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () => onItemSelected(_ix.purchases),
                ),
                _SidebarTile(
                  icon: Icons.campaign_rounded,
                  label: 'Announcements',
                  index: _ix.announcements,
                  selectedIndex: selectedIndex,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () => onItemSelected(_ix.announcements),
                ),
                // Nearest Cashiers opens a dedicated map screen (no tab index).
                _SidebarTile(
                  icon: Icons.near_me_rounded,
                  label: 'Nearest Cashiers',
                  index: -1,
                  selectedIndex: selectedIndex,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () => onFindCashiers?.call(),
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
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Earnings',
                    index: _ix.earnings,
                    selectedIndex: selectedIndex,
                    activeBg: activeBg,
                    isDark: isDark,
                    onTap: () => onItemSelected(_ix.earnings),
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
                  index: _ix.profile,
                  selectedIndex: selectedIndex,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () => onItemSelected(_ix.profile),
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

/// Positions of the member tabs, counted in the same order and under the
/// same conditions as `_tabs` in member_dashboard.dart.
class _TabIndex {
  final bool isReseller;

  const _TabIndex({required this.isReseller});

  static const int _delivery = enableDeliverySystem ? 2 : 0;

  int get overview => 0;
  int get marketplace => 1;
  int get orders => 2;
  int get purchases => 1 + _delivery;
  int get announcements => 2 + _delivery;
  int get earnings => 3 + _delivery;
  int get profile => (isReseller ? 4 : 3) + _delivery;
}
