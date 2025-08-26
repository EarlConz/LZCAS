import 'package:flutter/material.dart';

class InventorySearchBar extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;

  const InventorySearchBar({super.key, required this.onSearchChanged});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextField(
        decoration: InputDecoration(
          hintText: "Search items...",
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
        ),
        onChanged: onSearchChanged,
      ),
    );
  }
}
