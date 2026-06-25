import 'package:flutter/material.dart';

import '../theme.dart';

class Sidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Drawer(
      width: 280,
      backgroundColor: colorScheme.surface,
      elevation: 8,
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(22, 32, 22, 28),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(appRadius),
                  ),
                  child: Text(
                    'L',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  "LZCAS",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                const SizedBox(height: 8),
                _buildNavItem(context, Icons.dashboard_rounded, "Dashboard", 0),
                _buildNavItem(
                  context,
                  Icons.inventory_2_rounded,
                  "Inventory",
                  1,
                ),
                _buildNavItem(context, Icons.people_alt_rounded, "Members", 2),
                _buildNavItem(
                  context,
                  Icons.card_giftcard_rounded,
                  "Transactions",
                  3,
                ),
              ],
            ),
          ),
          Divider(
            color: colorScheme.onSurface.withAlpha((0.1 * 255).round()),
            indent: 20,
            endIndent: 20,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _buildNavItem(
              context,
              Icons.settings_rounded,
              "Settings",
              4,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    IconData icon,
    String label,
    int index,
  ) {
    final bool selected = selectedIndex == index;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onItemSelected(index);
      },
      borderRadius: BorderRadius.circular(12),
      hoverColor: const Color(0xFF6C63FF).withAlpha((0.05 * 255).round()),
      splashColor: const Color(0xFF6C63FF).withAlpha((0.1 * 255).round()),
      highlightColor: const Color(0xFF6C63FF).withAlpha((0.1 * 255).round()),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6C63FF).withAlpha(18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected
                  ? const Color(0xFF6C63FF)
                  : colorScheme.onSurface.withAlpha((0.5 * 255).round()),
              size: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? const Color(0xFF6C63FF)
                      : colorScheme.onSurface.withAlpha((0.8 * 255).round()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
