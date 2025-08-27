import 'package:flutter/material.dart';

class InventoryActionButton extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onUpdated;

  const InventoryActionButton({
    super.key,
    required this.item,
    required this.onUpdated,
  });

  void _editStock(BuildContext context) {
    final TextEditingController controller =
        TextEditingController(text: item["stock"].toString());

    showDialog(
      context: context,
      builder: (context) {
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
              onPressed: () => Navigator.pop(context), // ❌ Cancel
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final input = controller.text.trim();

                if (int.tryParse(input) == null) {
                  // ⚠️ Not a number → Show popup
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Numbers only")),
                  );
                } else {
                  // ✅ Update stock
                  item["stock"] = int.parse(input);
                  item["lastUpdated"] =
                      "${DateTime.now().toLocal()}".split('.')[0];

                  // 🔹 Call parent refresh
                  onUpdated();

                  Navigator.pop(context);
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'edit') {
          _editStock(context);
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