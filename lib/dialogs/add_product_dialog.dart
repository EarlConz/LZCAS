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
  final stockController = TextEditingController();
  final pointsController = TextEditingController();

  final _nameKey = GlobalKey<FormFieldState>();
  final _categoryKey = GlobalKey<FormFieldState>();
  final _stockKey = GlobalKey<FormFieldState>();
  final _pointsKey = GlobalKey<FormFieldState>();

  @override
  void dispose() {
    nameController.dispose();
    categoryController.dispose();
    stockController.dispose();
    pointsController.dispose();
    super.dispose();
  }

  bool _validateAll() {
    bool valid = true;
    if (nameController.text.trim().isEmpty) {
      _nameKey.currentState?.validate();
      valid = false;
    }
    if (categoryController.text.trim().isEmpty) {
      _categoryKey.currentState?.validate();
      valid = false;
    }
    if (stockController.text.trim().isEmpty) {
      _stockKey.currentState?.validate();
      valid = false;
    }
    if (pointsController.text.trim().isEmpty) {
      _pointsKey.currentState?.validate();
      valid = false;
    }
    return valid;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isNarrow = MediaQuery.sizeOf(context).width < 500;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.inventory_2_rounded, color: colorScheme.primary, size: 28),
          const SizedBox(width: 10),
          Text(
            'Add Product',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: isNarrow ? double.maxFinite : 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Product details section ───────────────────
              _sectionLabel('Product details', theme, colorScheme),
              const SizedBox(height: 10),
              TextFormField(
                key: _nameKey,
                controller: nameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'Product Name',
                  hintText: 'e.g. T-Shirt',
                  prefixIcon: const Icon(Icons.label_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: _categoryKey,
                controller: categoryController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'Category',
                  hintText: 'e.g. Apparel',
                  prefixIcon: const Icon(Icons.category_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                textInputAction: TextInputAction.next,
              ),

              const SizedBox(height: 20),
              // ── Inventory section ─────────────────────────
              _sectionLabel('Inventory', theme, colorScheme),
              const SizedBox(height: 10),
              TextFormField(
                key: _stockKey,
                controller: stockController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'Initial Stock',
                  hintText: '0',
                  prefixIcon: const Icon(Icons.inventory_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: _pointsKey,
                controller: pointsController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'Points per item',
                  hintText: '0',
                  prefixIcon: const Icon(Icons.stars_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Product'),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  void _submit() {
    if (!_validateAll()) return;

    final name = nameController.text.trim();
    final category = categoryController.text.trim();
    final stock = int.tryParse(stockController.text) ?? 0;
    final points = int.tryParse(pointsController.text) ?? 0;

    widget.onProductAdded({
      'name': name,
      'category': category,
      'stock': stock,
      'points': points,
      'lastUpdated': DateTime.now(),
      'status': stock <= 0
          ? 'Out of Stock'
          : (stock < 50 ? 'Low Stock' : 'Good'),
    });
    Navigator.pop(context);
  }

  Widget _sectionLabel(String text, ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            color: colorScheme.outline.withValues(alpha: 0.3),
            endIndent: 4,
          ),
        ),
      ],
    );
  }
}
