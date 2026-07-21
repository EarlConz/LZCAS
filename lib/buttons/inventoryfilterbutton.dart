import 'package:flutter/material.dart';

/// Filter menu for the inventory table. Offers single-select Status and
/// Category filters with a check-mark on the active choice; selecting an
/// already-active choice toggles it off. A small dot on the icon signals
/// that at least one filter is applied. "Clear Filters" only appears when
/// something is active.
class InventoryFilterButton extends StatelessWidget {
  final String? selectedStatus;
  final String? selectedCategory;
  final List<String> categories;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onClear;

  const InventoryFilterButton({
    super.key,
    required this.selectedStatus,
    required this.selectedCategory,
    required this.categories,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onClear,
  });

  static const _statuses = ['Good', 'Low Stock', 'Out of Stock'];

  @override
  Widget build(BuildContext context) {
    final hasStatus = selectedStatus != null && selectedStatus!.isNotEmpty;
    final hasCategory =
        selectedCategory != null && selectedCategory!.isNotEmpty;
    final hasFilters = hasStatus || hasCategory;

    return PopupMenuButton<String>(
      tooltip: 'Filter',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.filter_list),
          if (hasFilters)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
      onSelected: (value) {
        if (value == 'clear') {
          onClear();
        } else if (value.startsWith('status:')) {
          final s = value.substring('status:'.length);
          onStatusChanged(selectedStatus == s ? null : s);
        } else if (value.startsWith('category:')) {
          final c = value.substring('category:'.length);
          onCategoryChanged(selectedCategory == c ? null : c);
        }
      },
      itemBuilder: (BuildContext context) => [
        _sectionHeader('Filter by Status'),
        for (final s in _statuses)
          CheckedPopupMenuItem(
            value: 'status:$s',
            checked: selectedStatus == s,
            child: Text(s),
          ),
        if (categories.isNotEmpty) ...[
          const PopupMenuDivider(),
          _sectionHeader('Filter by Category'),
          for (final c in categories)
            CheckedPopupMenuItem(
              value: 'category:$c',
              checked: selectedCategory == c,
              child: Text(c),
            ),
        ],
        if (hasFilters) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'clear', child: Text('Clear Filters')),
        ],
      ],
    );
  }

  PopupMenuItem<String> _sectionHeader(String text) => PopupMenuItem<String>(
    enabled: false,
    height: 32,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    ),
  );
}
