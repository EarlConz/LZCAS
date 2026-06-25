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

  final _nameKey = GlobalKey<FormFieldState>();
  final _categoryKey = GlobalKey<FormFieldState>();
  final _stockKey = GlobalKey<FormFieldState>();

  @override
  void dispose() {
    nameController.dispose();
    categoryController.dispose();
    stockController.dispose();
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
    return valid;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isNarrow = MediaQuery.sizeOf(context).width < 500;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Row(
        children: [
          Icon(Icons.inventory_2_rounded, color: colorScheme.primary, size: 30),
          const SizedBox(width: 12),
          Text(
            'Add Product',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: isNarrow ? double.maxFinite : 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Product details section ───────────────────
              _sectionLabel('Product details', theme, colorScheme),
              const SizedBox(height: 12),
              TextFormField(
                key: _nameKey,
                controller: nameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'Product Name',
                  hintText: 'e.g. T-Shirt',
                  prefixIcon: const Icon(Icons.label_outline),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: _categoryKey,
                controller: categoryController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'Category',
                  hintText: 'e.g. Apparel',
                  prefixIcon: const Icon(Icons.category_outlined),
                ),
                textInputAction: TextInputAction.next,
              ),

              const SizedBox(height: 24),
              // ── Inventory section ─────────────────────────
              _sectionLabel('Inventory', theme, colorScheme),
              const SizedBox(height: 12),
              TextFormField(
                key: _stockKey,
                controller: stockController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'Initial Stock',
                  hintText: '0',
                  prefixIcon: const Icon(Icons.inventory_outlined),
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add Product'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_validateAll()) return;

    final name = nameController.text.trim();
    final category = categoryController.text.trim();
    final stock = int.tryParse(stockController.text) ?? 0;
    widget.onProductAdded({
      'name': name,
      'category': category,
      'stock': stock,
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
          style: theme.textTheme.titleSmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(width: 10),
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
