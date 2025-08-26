import 'package:flutter/material.dart';

class InventoryActionButton extends StatelessWidget {
  final VoidCallback onEditStock;

  const InventoryActionButton({
    super.key,
    required this.onEditStock,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'edit') {
          onEditStock();
        }
      },
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Text("Edit Stock"),
        ),
      ],
    );
  }
}