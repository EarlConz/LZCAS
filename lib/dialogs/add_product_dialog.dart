// lib/dialogs/add_product_dialog.dart
//
// Add Product, from the "Staff Modals Redesign" canvas: name, category and
// starting stock. A dialog on desktop, a full screen on a phone
// (widgets/modal_kit.dart). The caller does the insert (onProductAdded);
// stock above 0 is logged there as a stock-in movement.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_state.dart';
import '../db/db.dart';
import '../services/config_service.dart';
import '../services/poster_service.dart' show PreparedPoster;
import '../theme.dart';
import '../utils/fonts.dart';
import '../widgets/modal_kit.dart';
import '../widgets/poster_picker_field.dart';

class AddProductDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onProductAdded;

  const AddProductDialog({super.key, required this.onProductAdded});

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _name = TextEditingController();
  final _stock = TextEditingController(text: '0');
  String? _category;
  List<Category> _categories = [];

  /// A picture to upload once the product exists (v63, admins only).
  PreparedPoster? _photo;

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
    _name.dispose();
    _stock.dispose();
    super.dispose();
  }

  /// Why Add is off, in words; null when it can add.
  String? get _blocker {
    if (_name.text.trim().isEmpty) return 'Enter a product name.';
    if (_category == null) return 'Pick a category.';
    return null;
  }

  void _submit() {
    if (_blocker != null) return;
    final name = _name.text.trim();
    final category = _category!;
    final stock = int.tryParse(_stock.text.trim()) ?? 0;
    final threshold = context.read<ConfigService>().thresholdForCategory(category);
    widget.onProductAdded({
      'name': name,
      'category': category,
      'stock': stock,
      'photo': _photo,
      'lastUpdated': DateTime.now(),
      'status': stock <= 0
          ? 'Out of Stock'
          : (stock < threshold ? 'Low Stock' : 'Good'),
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? StockpileColors.darkTextMuted : const Color(0xFF6E6E7A);
    final threshold = _category == null
        ? null
        : context.read<ConfigService>().thresholdForCategory(_category);
    final blocker = _blocker;

    return AppModal(
      title: 'Add product',
      subtitle: 'It appears in the POS and inventory straight away.',
      leading: const ModalIconTile(Icons.add_rounded),
      maxWidth: 520,
      gap: 18,
      body: [
        LabeledField(
          label: 'Name',
          required: true,
          child: TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'e.g. product name'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        LabeledField(
          label: 'Category',
          required: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _category,
                hint: const Text('Select category'),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(value: c.name, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
              if (threshold != null) ...[
                const SizedBox(height: 6),
                Text(
                  "Shows as Low stock below $threshold, this category's threshold.",
                  style: StockpileFonts.satoshi(fontSize: 12, color: muted),
                ),
              ],
            ],
          ),
        ),
        LabeledField(
          label: 'Starting stock',
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              NumberStepper(
                controller: _stock,
                semanticLabel: 'Starting stock',
                onChanged: (_) => setState(() {}),
              ),
              Text(
                'Leave at 0 to add stock later.\nAnything above 0 is logged as stock in.',
                style: StockpileFonts.satoshi(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
        // Only admins may write to the picture bucket (v63).
        if (context.read<AuthState>().userRole == UserRole.admin)
          PosterPickerField(
            storedPath: null,
            pending: _photo,
            cleared: false,
            enabled: true,
            isDark: dark,
            label: 'Picture for the Marketplace',
            addLabel: 'Add picture',
            emptyLabel: 'No picture: members see its letter instead',
            helper: 'Optional. JPG or PNG, resized for you. A square photo '
                'fits best.',
            maxEdge: 800,
            onPicked: (p) => setState(() => _photo = p),
            onCleared: () => setState(() => _photo = null),
          ),
      ],
      footerNote: Text(
        blocker ?? '',
        style: StockpileFonts.satoshi(fontSize: 12, color: muted),
      ),
      primaryAction: FilledButton(
        onPressed: blocker == null ? _submit : null,
        child: const Text('Add product'),
      ),
    );
  }
}
