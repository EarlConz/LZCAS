import 'package:flutter/material.dart';

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
        decoration: const InputDecoration(
          labelText: "Enter new stock amount",
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () {
            final input = controller.text.trim();

            if (int.tryParse(input) == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Numbers only")),
              );
            } else {
              widget.item["stock"] = int.parse(input);
              widget.item["lastUpdated"] =
                  "${DateTime.now().toLocal()}".split('.')[0];

              widget.onUpdated();

              Navigator.pop(context);
            }
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
