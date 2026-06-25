import 'package:flutter/material.dart';
import 'package:lzcas/db/db.dart';

class EditSaleDialog extends StatefulWidget {
  final Sale sale;
  const EditSaleDialog({super.key, required this.sale});

  @override
  State<EditSaleDialog> createState() => _EditSaleDialogState();
}

class _EditSaleDialogState extends State<EditSaleDialog> {
  late int _quantity;
  late int _price;

  @override
  void initState() {
    super.initState();
    _quantity = widget.sale.quantity;
    _price = widget.sale.price;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Text(
        'Edit Sale',
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.sale.itemName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity'),
            controller: TextEditingController(text: _quantity.toString()),
            onChanged: (v) => _quantity = int.tryParse(v) ?? _quantity,
          ),
          const SizedBox(height: 16),
          TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Price'),
            controller: TextEditingController(text: _price.toString()),
            onChanged: (v) => _price = int.tryParse(v) ?? _price,
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: () {
            final updated = widget.sale.copyWith(
              quantity: _quantity,
              price: _price,
            );
            Navigator.pop(context, updated);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
