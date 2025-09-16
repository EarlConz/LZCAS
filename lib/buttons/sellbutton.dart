// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' show Value;
import 'package:lzcas/db/db.dart';

class SellButton extends StatefulWidget {
  const SellButton({super.key});

  @override
  State<SellButton> createState() => _SellButtonState();
}

class _SellButtonState extends State<SellButton> {
  List<String> items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();

    // ✅ Clear field when focused (if it's "1")
    _qtyFocusNode.addListener(() {
      if (_qtyFocusNode.hasFocus && _qtyController.text == "1") {
        _qtyController.clear();
      }
    });
  }

  Future<void> _loadItems() async {
    final rows = await repository.fetchItems();
    setState(() {
      items = inventoryItemsFromRows(rows).map((i) => i['name'].toString()).toList();
    });
  }

  String? selectedItem;
  int quantity = 1;
  List<Map<String, dynamic>> cart = [];
  final TextEditingController _qtyController = TextEditingController(text: "1");
  final FocusNode _qtyFocusNode = FocusNode();

  @override
  void dispose() {
    _qtyController.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
  }

  void _showError(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showSellDialog(BuildContext context) {
  // Capture context before async/await usage inside the dialog
  final localContext = context;
  showDialog(
      context: localContext,
      builder: (_) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text("Sell Items"),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🔍 Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: selectedItem,
                      hint: const Text("Select Item"),
                      items: items
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() => selectedItem = value);
                      },
                    ),
                    const SizedBox(height: 16),

                    // 🔢 Quantity Input Box
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Quantity:"),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _qtyController,
                            focusNode: _qtyFocusNode,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              if (value.isEmpty) {
                                setState(() => quantity = 0);
                                return;
                              }

                              final normalized = int.parse(value).toString();
                              setState(() {
                                quantity = int.tryParse(normalized) ?? 1;
                                _qtyController.text = quantity.toString();
                                _qtyController.selection = TextSelection.fromPosition(
                                  TextPosition(offset: _qtyController.text.length),
                                );
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ➕ Add to List
          ElevatedButton.icon(
                      onPressed: () async {
                        if (selectedItem != null) {
                          final itemObj = (await repository.fetchItems())
                .firstWhere((r) => r.name == selectedItem);

              if (!mounted) return;

                          if (itemObj.stock <= 0 || itemObj.stock < quantity) {
                            if (!mounted) return;
                            _showError(dialogContext, "Not enough stock");
                            return;
                          }

                          setState(() {
                            cart.add({
                              "item": selectedItem!,
                              "quantity": quantity,
                              "price": "", // start empty, user will input
                              "priceController":
                                  TextEditingController(), // for each item
                            });
                            selectedItem = null;
                            quantity = 1;
                            _qtyController.text = "1";
                          });
                          }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text("Add to List"),
                    ),

                    const SizedBox(height: 16),

                    // 📝 Cart with price input
                    if (cart.isNotEmpty)
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          itemCount: cart.length,
                          itemBuilder: (context, index) {
                            final entry = cart[index];
                            return Row(
                              children: [
                                // Item name & quantity
                                Expanded(
                                  child: ListTile(
                                    title: Text(entry["item"]),
                                    subtitle: Text("Qty: ${entry["quantity"]}"),
                                  ),
                                ),
                                // 💲 Price input field
                                SizedBox(
                                  width: 100,
                                  child: TextField(
                                    controller: entry["priceController"],
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: "Price",
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) {
                                      entry["price"] = val;
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      cart.removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: cart.isEmpty
                      ? null
                      : () async {
                          for (var entry in cart) {
                            final dbItem = (await repository.fetchItems())
                                .firstWhere((r) => r.name == entry["item"]);
                            final q = entry["quantity"] as int;
                            final newStock = dbItem.stock - q;
                            final newStatus = statusFromStock(newStock);
                            final updated = dbItem.copyWith(
                                stock: newStock,
                                lastUpdated: Value(DateTime.now()),
                                status: Value(newStatus));
                            // use repository helper so listeners are notified
                            await repository.updateItem(updated);
                            // persist sale record
                            final priceStr = (entry["price"] ?? '').toString();
                            final price = int.tryParse(priceStr) ?? 0;
                            await repository.addSale(itemId: dbItem.id, itemName: dbItem.name, quantity: q, price: price);
                          }
                          // reload items first, then close dialog using captured dialogContext
                          await _loadItems();
                          if (!mounted) return;
                          Navigator.pop(dialogContext, cart);
                          cart.clear();
                          // optionally notify a transactions list elsewhere by reloading sales if implemented
                        },
                  child: const Text("Confirm"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.point_of_sale),
      label: const Text("Sell"),
      onPressed: () => _showSellDialog(context),
    );
  }
}