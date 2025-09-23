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
  List<String> members = ["Non Member", "Member A", "Member B", "Member C"];
  String? selectedItem;
  String? selectedMember = "Non Member";
  int quantity = 1;
  List<Map<String, dynamic>> cart = [];

  final TextEditingController _qtyController = TextEditingController(text: "1");
  final TextEditingController _memberSearchController = TextEditingController();
  final TextEditingController _itemSearchController = TextEditingController();
  final FocusNode _qtyFocusNode = FocusNode();
  final FocusNode _memberFocusNode = FocusNode();
  final FocusNode _itemFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadItems();

    _qtyFocusNode.addListener(() {
      if (_qtyFocusNode.hasFocus && _qtyController.text == "1") {
        _qtyController.clear();
      }
    });
  }

  Future<void> _loadItems() async {
    final rows = await repository.fetchItems();
    setState(() {
      items = inventoryItemsFromRows(rows)
          .map((i) => i['name'].toString())
          .toList();
    });
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _memberSearchController.dispose();
    _itemSearchController.dispose();
    _qtyFocusNode.dispose();
    _memberFocusNode.dispose();
    _itemFocusNode.dispose();
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
                    // 🔎 Member Search with Dropdown
                    FocusScope(
                      child: Focus(
                        focusNode: _memberFocusNode,
                        child: Column(
                          children: [
                            TextField(
                              controller: _memberSearchController,
                              decoration: const InputDecoration(
                                labelText: "Search Member",
                                hintText:
                                    "Type to search or leave blank for Non Member",
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            if (_memberFocusNode.hasFocus ||
                                _memberSearchController.text.isNotEmpty)
                              Container(
                                constraints:
                                    const BoxConstraints(maxHeight: 200),
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: ListView(
                                  shrinkWrap: true,
                                  children: members
                                      .where((m) {
                                        final query = _memberSearchController
                                            .text
                                            .toLowerCase();
                                        return query.isEmpty ||
                                            m.toLowerCase().contains(query);
                                      })
                                      .map((m) => ListTile(
                                            title: Text(m),
                                            onTap: () {
                                              setState(() {
                                                selectedMember = m;
                                                _memberSearchController.text = m;
                                                _memberFocusNode.unfocus();
                                              });
                                            },
                                          ))
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const Divider(height: 32),

                    // 🔎 Item Search with Dropdown
                    FocusScope(
                      child: Focus(
                        focusNode: _itemFocusNode,
                        child: Column(
                          children: [
                            TextField(
                              controller: _itemSearchController,
                              decoration: const InputDecoration(
                                labelText: "Search Item",
                                hintText: "Type to search item",
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            if (_itemFocusNode.hasFocus ||
                                _itemSearchController.text.isNotEmpty)
                              Container(
                                constraints:
                                    const BoxConstraints(maxHeight: 200),
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: ListView(
                                  shrinkWrap: true,
                                  children: items
                                      .where((i) {
                                        final query = _itemSearchController.text
                                            .toLowerCase();
                                        return query.isEmpty ||
                                            i.toLowerCase().contains(query);
                                      })
                                      .map((i) => ListTile(
                                            title: Text(i),
                                            onTap: () {
                                              setState(() {
                                                selectedItem = i;
                                                _itemSearchController.text = i;
                                                _itemFocusNode.unfocus();
                                              });
                                            },
                                          ))
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 🔢 Quantity
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
                              hintText: "Enter Quantity",
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
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
                                _qtyController.selection =
                                    TextSelection.fromPosition(TextPosition(
                                        offset: _qtyController.text.length));
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
                              "price": "",
                              "priceController": TextEditingController(),
                            });
                            selectedItem = null;
                            _itemSearchController.clear();
                            quantity = 1;
                            _qtyController.text = "1";
                          });
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text("Add to List"),
                    ),

                    const SizedBox(height: 16),

                    // 📝 Cart
                    if (cart.isNotEmpty)
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          itemCount: cart.length,
                          itemBuilder: (context, index) {
                            final entry = cart[index];
                            return Row(
                              children: [
                                Expanded(
                                  child: ListTile(
                                    title: Text(entry["item"]),
                                    subtitle: Text("Qty: ${entry["quantity"]}"),
                                  ),
                                ),
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
                                      hintText: "Enter Price",
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
                          final member = (_memberSearchController.text.isEmpty)
                              ? "Non Member"
                              : _memberSearchController.text;

                          for (var entry in cart) {
                            final dbItem = (await repository.fetchItems())
                                .firstWhere((r) => r.name == entry["item"]);
                            final q = entry["quantity"] as int;
                            final newStock = dbItem.stock - q;
                            final newStatus = statusFromStock(newStock);
                            final updated = dbItem.copyWith(
                              stock: newStock,
                              lastUpdated: Value(DateTime.now()),
                              status: Value(newStatus),
                            );
                            await repository.updateItem(updated);

                            final priceStr = (entry["price"] ?? '').toString();
                            final price = int.tryParse(priceStr) ?? 0;
                            await repository.addSale(
                              itemId: dbItem.id,
                              itemName: dbItem.name,
                              quantity: q,
                              price: price,
                            );
                          }
                          await _loadItems();
                          if (!mounted) return;
                          Navigator.pop(dialogContext, cart);
                          cart.clear();
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
