import 'package:flutter/material.dart';

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

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(1, 0),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          // Logo Section
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40.0),
            child: Text(
              "LZCAS",
              style: theme.textTheme.headlineMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Navigation Section
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _buildNavItem(context, Icons.dashboard_rounded, "Dashboard", 0),
                _buildNavItem(context, Icons.inventory_2_rounded, "Inventory", 1),
                _buildNavItem(context, Icons.people_alt_rounded, "Members", 2),
                _buildNavItem(context, Icons.card_giftcard_rounded, "Loyalty", 3),
              ],
            ),
          ),
          // Bottom section (settings)
          Divider(
            color: colorScheme.onSurface.withOpacity(0.1),
            indent: 20,
            endIndent: 20,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildNavItem(context, Icons.settings_rounded, "Settings", 4),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label, int index) {
    final bool selected = selectedIndex == index;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () => onItemSelected(index),
      borderRadius: BorderRadius.circular(12),
      hoverColor: colorScheme.primary.withOpacity(0.05),
      splashColor: colorScheme.primary.withOpacity(0.1),
      highlightColor: colorScheme.primary.withOpacity(0.1),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.6),
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
