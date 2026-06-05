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
  final pointsController = TextEditingController(text: '0');

  @override
  void dispose() {
    nameController.dispose();
    categoryController.dispose();
    stockController.dispose();
    pointsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 500;

    return AlertDialog(
      title: const Text('Add Product'),
      content: SizedBox(
        width: isNarrow ? double.maxFinite : 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Product Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: stockController,
                decoration: const InputDecoration(hintText: 'Initial Stock'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pointsController,
                decoration: const InputDecoration(labelText: 'Points per item'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = nameController.text.trim();
            final category = categoryController.text.trim();

            if (name.isEmpty || category.isEmpty) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Validation Error"),
                  content: const Text(
                    "Product Name and Category cannot be empty.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"),
                    ),
                  ],
                ),
              );
              return;
            }

            final stock = int.tryParse(stockController.text) ?? 0;
            final points = int.tryParse(pointsController.text) ?? 0;
            widget.onProductAdded({
              'name': name,
              'category': category,
              'stock': stock,
              'points': points,
              'lastUpdated': '${DateTime.now().toLocal()}'.split('.')[0],
              'status': stock <= 0
                  ? 'Out of Stock'
                  : (stock < 50 ? 'Low Stock' : 'Good'),
            });
            Navigator.pop(context);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
