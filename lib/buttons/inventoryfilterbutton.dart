import 'package:flutter/material.dart';

class InventoryFilterButton extends StatelessWidget {
  final String? selectedStatus;
  final String? selectedCategory;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;

  const InventoryFilterButton({
    super.key,
    required this.selectedStatus,
    required this.selectedCategory,
    required this.onStatusChanged,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.filter_list),
      onSelected: (value) {
        if (value.startsWith("status:")) {
          onStatusChanged(value.replaceFirst("status:", ""));
        } else if (value.startsWith("category:")) {
          onCategoryChanged(value.replaceFirst("category:", ""));
        } else if (value == "clear") {
          onStatusChanged(null);
          onCategoryChanged(null);
        }
      },
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem(
          enabled: false,
          child: Text("Filter by Status"),
        ),
        const PopupMenuItem(
          value: "status:Good",
          child: Text("Good"),
        ),
        const PopupMenuItem(
          value: "status:Low Stock",
          child: Text("Low Stock"),
        ),
        const PopupMenuItem(
          value: "status:Out of Stock",
          child: Text("Out of Stock"),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          enabled: false,
          child: Text("Filter by Category"),
        ),
        const PopupMenuItem(
          value: "category:Powder",
          child: Text("Powder"),
        ),
        const PopupMenuItem(
          value: "category:Oil",
          child: Text("Oil"),
        ),
        const PopupMenuItem(
          value: "category:Tablet/Capsules",
          child: Text("Tablet/Capsules"),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: "clear",
          child: Text("Clear Filters"),
        ),
      ],
    );
  }
}