// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:lzcas/db/db.dart';

class EditStockDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onUpdated;

  const EditStockDialog({
    super.key,
    required this.item,
    required this.onUpdated,
  });

  @override
  State<EditStockDialog> createState() => _EditStockDialogState();
}

class _EditStockDialogState extends State<EditStockDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.item["stock"].toString());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Edit Stock"),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: "Enter new stock amount"),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () async {
            final input = controller.text.trim();
            final newStock = int.tryParse(input);

            if (newStock == null) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("Numbers only")));
              return;
            }

            // If item has an id, persist change to the DB; otherwise fall back
            // to updating the provided in-memory map.
            final id = widget.item['id'] as int?;
            if (id == null) {
              widget.item["stock"] = newStock;
              widget.item["lastUpdated"] = "${DateTime.now().toLocal()}".split(
                '.',
              )[0];
              widget.onUpdated();
              Navigator.pop(context);
              return;
            }

            final row = await repository.db.getItemById(id);
            if (row == null) {
              if (!mounted) return;
              final localCtx = context;
              ScaffoldMessenger.of(localCtx).showSnackBar(
                const SnackBar(content: Text("Item not found in DB")),
              );
              return;
            }

            final newStatus = statusFromStock(newStock);
            final updated = row.copyWith(
              stock: newStock,
              lastUpdated: Value(DateTime.now()),
              status: Value(newStatus),
            );

            await repository.updateItem(updated);

            if (!mounted) return;
            widget.onUpdated();
            Navigator.pop(context);
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
