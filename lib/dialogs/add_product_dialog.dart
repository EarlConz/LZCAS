import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../db/db.dart';
import '../services/config_service.dart';

class AddProductDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onProductAdded;

  const AddProductDialog({super.key, required this.onProductAdded});

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final nameController = TextEditingController();
  final stockController = TextEditingController();
  String? _selectedCategory;
  List<Category> _categories = [];

  final _nameKey = GlobalKey<FormFieldState>();
  final _stockKey = GlobalKey<FormFieldState>();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await repository.fetchProductCategories();
    if (!mounted) return;
    setState(() => _categories = cats);
  }

  @override
  void dispose() {
    nameController.dispose();
    stockController.dispose();
    super.dispose();
  }

  bool _validateAll() {
    bool valid = true;
    if (nameController.text.trim().isEmpty) {
      _nameKey.currentState?.validate();
      valid = false;
    }
    if (_selectedCategory == null) return false;
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
                autovalidateMode: AutovalidateMode.onUserInteraction,
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
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _categories
                    .map(
                      (c) =>
                          DropdownMenuItem(value: c.name, child: Text(c.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
                validator: (v) => v == null ? 'Required' : null,
              ),

              const SizedBox(height: 24),
              // ── Inventory section ─────────────────────────
              _sectionLabel('Inventory', theme, colorScheme),
              const SizedBox(height: 12),
              TextFormField(
                key: _stockKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
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
        // OverflowBar spaces the buttons horizontally when they fit and
        // stacks them with a gap when they don't (narrow/mobile) — a bare
        // SizedBox spacer left them overlapping once stacked.
        OverflowBar(
          spacing: 12,
          overflowSpacing: 8,
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Product'),
            ),
          ],
        ),
      ],
    );
  }

  void _submit() {
    if (!_validateAll()) return;
    final name = nameController.text.trim();
    final category = _selectedCategory ?? '';
    final stock = int.tryParse(stockController.text) ?? 0;
    widget.onProductAdded({
      'name': name,
      'category': category,
      'stock': stock,
      'lastUpdated': DateTime.now(),
      'status': stock <= 0
          ? 'Out of Stock'
          : (stock < context.read<ConfigService>().lowStockThreshold
                ? 'Low Stock'
                : 'Good'),
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
