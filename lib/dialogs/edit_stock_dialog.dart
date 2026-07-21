// ...existing code...
import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth_state.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';

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
  late final TextEditingController nameController;
  late final TextEditingController addStockController;
  late final TextEditingController reduceStockController;
  late final TextEditingController reasonController;
  List<String> categories = [];
  String? selectedCategory;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(
      text: widget.item["name"] as String? ?? '',
    );
    addStockController = TextEditingController();
    reduceStockController = TextEditingController();
    reasonController = TextEditingController();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      // Categories come from the Settings-managed category list, not from
      // whatever categories existing products happen to use.
      final cats = await repository.fetchProductCategories();
      final set = <String>{
        for (final c in cats)
          if (c.name.trim().isNotEmpty) c.name.trim(),
      };
      final existing = (widget.item['category'] as String?)?.trim();
      // Keep the product's current category selectable even if it was
      // later removed from Settings, so editing never silently drops it.
      if (existing != null && existing.isNotEmpty) set.add(existing);
      final list = set.toList()..sort();
      if (!mounted) return;
      setState(() {
        categories = list;
        selectedCategory = (existing != null && existing.isNotEmpty)
            ? existing
            : null;
      });
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load categories: $e');
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    addStockController.dispose();
    reduceStockController.dispose();
    reasonController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final addAmount = int.tryParse(addStockController.text.trim()) ?? 0;
    final reduceAmount = int.tryParse(reduceStockController.text.trim()) ?? 0;
    final reason = reasonController.text.trim();

    if (addAmount == 0 && reduceAmount == 0) {
      BotToast.showText(text: 'No stock change requested');
      return;
    }

    if (addAmount > 0 && reduceAmount > 0) {
      BotToast.showText(
        text: 'Choose either Add Stock or Reduce Stock, not both',
      );
      return;
    }

    if (reduceAmount > 0 && reason.isEmpty) {
      BotToast.showText(text: 'A reason is required for stock reduction');
      return;
    }

    final newName = nameController.text.trim();
    final newCategory = selectedCategory?.trim();

    final id = widget.item['id'] as int?;
    final currentStock = widget.item['stock'] as int? ?? 0;

    if (id == null) {
      // in-memory
      widget.item['stock'] = currentStock + addAmount - reduceAmount;
      widget.item['name'] = newName;
      widget.item['category'] = newCategory;
      widget.item['lastUpdated'] = "${DateTime.now().toLocal()}".split('.')[0];
      widget.onUpdated();
      Navigator.pop(context);
      return;
    }

    final row = await repository.getItemById(id);
    if (row == null) {
      if (!mounted) return;
      BotToast.showText(text: 'Item not found');
      return;
    }

    // Update name/category if changed
    if (newName.isNotEmpty && newName != row.name ||
        newCategory != row.category) {
      await repository.updateItem(
        row.copyWith(
          name: newName.isEmpty ? row.name : newName,
          category: newCategory,
        ),
      );
    }

    // Apply stock changes with audit trail
    if (addAmount > 0) {
      final ok = await repository.addStock(
        itemId: id,
        itemName: row.name,
        quantity: addAmount,
      );
      if (!ok) {
        if (!mounted) return;
        BotToast.showText(text: 'Failed to add stock');
        return;
      }
    }

    if (reduceAmount > 0 && currentStock >= reduceAmount) {
      final role = context.read<AuthState>().userRole;
      final needsApproval = role == UserRole.inventory;

      if (needsApproval) {
        await repository.submitPendingRequest(
          itemId: id,
          itemName: row.name,
          requestType: 'reduce_stock',
          quantity: reduceAmount,
          reason: reason,
        );
        if (!mounted) return;
        BotToast.showText(
          text: 'Stock reduction request sent to admin for approval',
        );
      } else {
        final ok = await repository.reduceStock(
          itemId: id,
          itemName: row.name,
          quantity: reduceAmount,
          reason: reason,
        );
        if (!ok) {
          if (!mounted) return;
          BotToast.showText(text: 'Failed to reduce stock');
          return;
        }
      }
    }

    if (!mounted) return;
    widget.onUpdated();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isNarrow = MediaQuery.sizeOf(context).width < 500;
    final currentStock = widget.item['stock'] as int? ?? 0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Row(
        children: [
          Icon(Icons.edit_rounded, color: colorScheme.primary, size: 28),
          const SizedBox(width: 10),
          Text(
            'Edit Product',
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current stock display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text('Current Stock: ', style: theme.textTheme.bodyMedium),
                    Text(
                      '$currentStock',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Product name'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: categories.contains(selectedCategory)
                    ? selectedCategory
                    : null,
                decoration: const InputDecoration(labelText: 'Category'),
                items: categories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => selectedCategory = v),
                hint: const Text('Select category'),
              ),
              const SizedBox(height: 20),

              // --- Add Stock ---
              Text(
                'Add Stock',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: StockpileColors.success,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: addStockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount to add',
                  hintText: 'e.g. 50',
                  prefixIcon: Icon(
                    Icons.add_circle_outline,
                    color: Colors.green,
                  ),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // --- Reduce Stock ---
              Text(
                'Reduce Stock',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: StockpileColors.error500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reduceStockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount to reduce',
                  hintText: 'e.g. 10',
                  prefixIcon: Icon(
                    Icons.remove_circle_outline,
                    color: Colors.red,
                  ),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for reduction',
                  hintText: 'e.g. Damaged, expired, transferred',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
