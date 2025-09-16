import 'package:flutter/material.dart';

class AddProductDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onProductAdded;

  const AddProductDialog({super.key, required this.onProductAdded});

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final nameController = TextEditingController();
  final categoryController = TextEditingController();
  final stockController = TextEditingController(text: '0');

  @override
  void dispose() {
    nameController.dispose();
    categoryController.dispose();
    stockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Product'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Product Name'),
            ),
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            TextField(
              controller: stockController,
              decoration: const InputDecoration(labelText: 'Stock'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final name = nameController.text.trim();
            if (name.isEmpty) return;
            final category = categoryController.text.trim();
            final stock = int.tryParse(stockController.text) ?? 0;
            widget.onProductAdded({
              'name': name,
              'category': category,
              'stock': stock,
              'lastUpdated': '${DateTime.now().toLocal()}'.split('.')[0],
              'status': stock <= 0 ? 'Out of Stock' : (stock < 50 ? 'Low Stock' : 'Good'),
            });
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product added')));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
