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

    return Drawer(
      width: 250,
      backgroundColor: colorScheme.surface,
      elevation: 16, 
      child: Column(
        children: <Widget>[
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _buildNavItem(context, Icons.dashboard_rounded, "Dashboard", 0),
                _buildNavItem(context, Icons.inventory_2_rounded, "Inventory", 1),
                _buildNavItem(context, Icons.people_alt_rounded, "Members", 2),
                _buildNavItem(context, Icons.card_giftcard_rounded, "Transactions", 3),
              ],
            ),
          ),
          Divider(
            color: colorScheme.onSurface.withAlpha((0.1 * 255).round()),
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
      hoverColor: colorScheme.primary.withAlpha((0.05 * 255).round()),
      splashColor: colorScheme.primary.withAlpha((0.1 * 255).round()),
      highlightColor: colorScheme.primary.withAlpha((0.1 * 255).round()),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withAlpha((0.1 * 255).round())
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurface.withAlpha((0.6 * 255).round()),
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected
                      ? colorScheme.primary
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