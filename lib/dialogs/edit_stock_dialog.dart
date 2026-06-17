// ...existing code...
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:lzcas/db/db.dart';

class EditProductDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onUpdated;

  const EditProductDialog({
    super.key,
    required this.item,
    required this.onUpdated,
  });

  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<EditProductDialog> {
  late final TextEditingController stockController;
  late final TextEditingController nameController;
  List<String> categories = [];
  String? selectedCategory;

  @override
  void initState() {
    super.initState();
    stockController = TextEditingController(
      text: widget.item["stock"].toString(),
    );
    nameController = TextEditingController(
      text: widget.item["name"] as String? ?? '',
    );
    // load categories from existing items
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final rows = await repository.fetchItems();
      final set = <String>{};
      for (final r in rows) {
        final c = r.category;
        if (c != null && c.trim().isNotEmpty) set.add(c.trim());
      }
      final list = set.toList()..sort();
      if (!mounted) return;
      // Normalize the existing category (trim) and ensure it exists in the loaded list.
      final existing = (widget.item['category'] as String?)?.trim();
      setState(() {
        categories = list;
        if (existing != null &&
            existing.isNotEmpty &&
            list.contains(existing)) {
          selectedCategory = existing;
        } else {
          selectedCategory = list.isNotEmpty ? list.first : null;
        }
      });
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load categories: $e');
    }
  }

  @override
  void dispose() {
    stockController.dispose();
    nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final stockText = stockController.text.trim();
    final newStock = int.tryParse(stockText);
    if (newStock == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Stock must be a number')));
      return;
    }

    final newName = nameController.text.trim();
    final newCategory = selectedCategory?.trim();

    final id = widget.item['id'] as int?;
    if (id == null) {
      // in-memory
      widget.item['stock'] = newStock;
      widget.item['name'] = newName;
      widget.item['category'] = newCategory;
      widget.item['lastUpdated'] = "${DateTime.now().toLocal()}".split('.')[0];
      widget.onUpdated();
      Navigator.pop(context);
      return;
    }

    final row = await repository.db.getItemById(id);
    if (row == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Item not found')));
      return;
    }

    final updated = row.copyWith(
      name: newName.isEmpty ? row.name : newName,
      category: Value(newCategory),
      stock: newStock,
      lastUpdated: Value(DateTime.now()),
      status: Value(statusFromStock(newStock)),
    );

    await repository.updateItem(updated);

    if (!mounted) return;
    widget.onUpdated();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 500;

    return AlertDialog(
      title: const Text('Edit Product'),
      content: SizedBox(
        width: isNarrow ? double.maxFinite : 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Product name'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: categories.contains(selectedCategory)
                          ? selectedCategory
                          : null,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: categories
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => selectedCategory = v),
                      hint: const Text('Select category'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      final result = await showDialog<String>(
                        context: context,
                        builder: (ctx) {
                          final tc = TextEditingController();
                          return AlertDialog(
                            title: const Text('Add category'),
                            content: TextField(
                              controller: tc,
                              decoration: const InputDecoration(
                                labelText: 'Category name',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, tc.text.trim()),
                                child: const Text('Add'),
                              ),
                            ],
                          );
                        },
                      );
                      if (result != null && result.isNotEmpty) {
                        if (!categories.contains(result)) {
                          setState(() {
                            categories = List.from(categories)..add(result);
                            categories.sort();
                            selectedCategory = result;
                          });
                        } else {
                          setState(() => selectedCategory = result);
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: stockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Stock'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
