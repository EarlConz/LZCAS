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
    return AlertDialog(
      title: const Text('Edit Sale'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.sale.itemName),
          const SizedBox(height: 8),
          TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity'),
            controller: TextEditingController(text: _quantity.toString()),
            onChanged: (v) => _quantity = int.tryParse(v) ?? _quantity,
          ),
          const SizedBox(height: 8),
          TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Price'),
            controller: TextEditingController(text: _price.toString()),
            onChanged: (v) => _price = int.tryParse(v) ?? _price,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final updated = widget.sale.copyWith(quantity: _quantity, price: _price);
            Navigator.pop(context, updated);
          },
          child: const Text('Save'),
        )
      ],
    );
  }
}
