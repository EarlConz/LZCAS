import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' show Value;
import 'package:lzcas/db/db.dart';
import 'package:lzcas/dialogs/receipt_dialog.dart';
import 'package:lzcas/dialogs/qr_scanner_dialog.dart';

class SellButton extends StatefulWidget {
  final bool compact;

  const SellButton({super.key, this.compact = false});

  @override
  State<SellButton> createState() => _SellButtonState();
}

class _SellButtonState extends State<SellButton> {
  List<String> items = [];
  List<Map<String, dynamic>> members = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadMembers();
  }

  Future<void> _loadItems() async {
    final rows = await repository.fetchItems();
    setState(() {
      items = inventoryItemsFromRows(
        rows,
      ).map((i) => i['name'].toString()).toList();
    });
  }

  Future<void> _loadMembers() async {
    final memberRows = await repository.fetchMembers();
    setState(() {
      members = membersFromRows(memberRows);
    });
  }

  void _showSellDialog(BuildContext context) {
    _loadItems();
    _loadMembers();
    showDialog(
      context: context,
      builder: (_) => _SellDialog(
        items: items,
        members: members,
        onSaleConfirmed: _loadItems,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return IconButton.filled(
        tooltip: 'Sell',
        icon: const Icon(Icons.point_of_sale),
        onPressed: () => _showSellDialog(context),
      );
    }

    return ElevatedButton.icon(
      icon: const Icon(Icons.point_of_sale),
      label: const Text('Sell'),
      onPressed: () => _showSellDialog(context),
    );
  }
}

class _SellDialog extends StatefulWidget {
  final List<String> items;
  final List<Map<String, dynamic>> members;
  final VoidCallback onSaleConfirmed;

  const _SellDialog({
    required this.items,
    required this.members,
    required this.onSaleConfirmed,
  });

  @override
  State<_SellDialog> createState() => _SellDialogState();
}

class _SellDialogState extends State<_SellDialog> {
  String? selectedItem;
  int? selectedBuyerId;
  int quantity = 1;
  List<Map<String, dynamic>> cart = [];

  final TextEditingController _qtyController = TextEditingController(text: '1');
  final TextEditingController _itemSearchController = TextEditingController();
  final FocusNode _qtyFocusNode = FocusNode();
  final FocusNode _itemFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _qtyFocusNode.addListener(() {
      if (_qtyFocusNode.hasFocus && _qtyController.text == '1') {
        _qtyController.clear();
      }
    });
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _itemSearchController.dispose();
    _qtyFocusNode.dispose();
    _itemFocusNode.dispose();
    for (var entry in cart) {
      (entry['priceController'] as TextEditingController?)?.dispose();
    }
    super.dispose();
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool isCartValid() {
    if (cart.isEmpty) return false;
    for (var entry in cart) {
      final priceStr = (entry['price'] ?? '').toString();
      if (priceStr.isEmpty || (int.tryParse(priceStr) ?? 0) <= 0) return false;
    }
    return true;
  }

  Future<void> _scanBuyerQr(BuildContext context) async {
    final scanned = await showQrScannerDialog(context);
    if (scanned == null || scanned.isEmpty) return;
    if (!mounted) return;

    // Try to find a member whose qr token matches the scanned value
    final memberRow = widget.members.cast<Map<String, dynamic>?>().firstWhere(
      (m) => (m?['qr'] ?? '').toString() == scanned,
      orElse: () => null,
    );

    if (memberRow != null) {
      setState(() {
        selectedBuyerId = memberRow['id'] as int?;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Buyer set to ${memberRow['firstName'] ?? ''} ${memberRow['lastName'] ?? ''}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No member matches this QR code'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPrice = cart.fold<int>(0, (acc, e) {
      final priceStr = (e['price'] ?? '').toString();
      final p = int.tryParse(priceStr) ?? 0;
      final q = e['quantity'] as int? ?? 0;
      return acc + (p * q);
    });

    return AlertDialog(
      title: const Text('Sell Items'),
      content: SizedBox(
        width: 650,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Buyer picker (member-picker) with QR scan
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          decoration: const InputDecoration(labelText: 'Buyer'),
                          initialValue: selectedBuyerId,
                          items: [
                            ...widget.members.map(
                              (m) => DropdownMenuItem<int?>(
                                value: m['id'] as int?,
                                child: Text(
                                  '${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'
                                      .trim(),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => selectedBuyerId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Scan member QR',
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: () => _scanBuyerQr(context),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 32),

                // Item search
                FocusScope(
                  child: Focus(
                    focusNode: _itemFocusNode,
                    child: Column(
                      children: [
                        TextField(
                          controller: _itemSearchController,
                          decoration: const InputDecoration(
                            labelText: 'Search Item',
                            hintText: 'Type to search item',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_itemFocusNode.hasFocus ||
                            _itemSearchController.text.isNotEmpty)
                          Container(
                            constraints: const BoxConstraints(maxHeight: 200),
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: ListView(
                              shrinkWrap: true,
                              children: widget.items
                                  .where((i) {
                                    final query = _itemSearchController.text
                                        .toLowerCase();
                                    return query.isEmpty ||
                                        i.toLowerCase().contains(query);
                                  })
                                  .map(
                                    (i) => ListTile(
                                      title: Text(i),
                                      onTap: () {
                                        setState(() {
                                          selectedItem = i;
                                          _itemSearchController.text = i;
                                          _itemFocusNode.unfocus();
                                        });
                                      },
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // quick add row
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Item'),
                        initialValue: selectedItem,
                        items: widget.items
                            .map(
                              (i) => DropdownMenuItem(value: i, child: Text(i)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => selectedItem = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _qtyController,
                        focusNode: _qtyFocusNode,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(labelText: 'Qty'),
                        onChanged: (v) =>
                            setState(() => quantity = int.tryParse(v) ?? 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        if (selectedItem == null) {
                          _showError('Please select an item');
                          return;
                        }
                        final matched = widget.items.contains(selectedItem);
                        if (!matched) {
                          _showError('Invalid item');
                          return;
                        }
                        // fetch item for validation (non-blocking best-effort)
                        repository.fetchItems().then((_) {
                          setState(() {
                            cart.add({
                              'item': selectedItem,
                              'quantity': quantity,
                              'price': '',
                              'priceController': TextEditingController(),
                            });
                          });
                        });
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // cart list
                if (cart.isNotEmpty)
                  SizedBox(
                    height: 240,
                    child: ListView.builder(
                      itemCount: cart.length,
                      itemBuilder: (context, index) {
                        final entry = cart[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ListTile(
                                  title: Text(entry['item']),
                                  subtitle: Text('Qty: ${entry['quantity']}'),
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: entry['priceController'],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Price',
                                    hintText: 'Enter Price',
                                    isDense: true,
                                  ),
                                  onChanged: (val) =>
                                      setState(() => entry['price'] = val),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    setState(() => cart.removeAt(index)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                // totals area placed under list
                if (cart.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Row(
                      children: [
                        const Spacer(),
                        Text(
                          'Total Price: $totalPrice',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (cart.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              'Total: ₱$totalPrice',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ElevatedButton(
          onPressed: isCartValid()
              ? () async {
                  final safeContext = context;
                  final transactionTs = DateTime.now();
                  for (var entry in cart) {
                    final dbItem = (await repository.fetchItems()).firstWhere(
                      (r) => r.name == entry['item'],
                    );
                    final q = entry['quantity'] as int;
                    final newStock = dbItem.stock - q;
                    final newStatus = statusFromStock(newStock);
                    final updated = dbItem.copyWith(
                      stock: newStock,
                      lastUpdated: Value(DateTime.now()),
                      status: Value(newStatus),
                    );
                    await repository.updateItem(updated);

                    final priceStr = (entry['price'] ?? '').toString();
                    final price = int.tryParse(priceStr) ?? 0;
                    await repository.addSale(
                      itemId: dbItem.id,
                      itemName: dbItem.name,
                      quantity: q,
                      price: price,
                      timestamp: transactionTs,
                      buyerId: selectedBuyerId,
                    );
                  }

                  widget.onSaleConfirmed();
                  if (!mounted) return;

                  // Build receipt line items from cart
                  final receiptItems = cart.map((entry) {
                    final priceStr = (entry['price'] ?? '').toString();
                    return ReceiptLineItem(
                      itemName: entry['item'] as String? ?? 'Unknown',
                      quantity: entry['quantity'] as int? ?? 0,
                      unitPrice: int.tryParse(priceStr) ?? 0,
                    );
                  }).toList();

                  // Lookup buyer name
                  String? buyerName;
                  if (selectedBuyerId != null) {
                    final m = widget.members.firstWhere(
                      (m) => (m['id'] as int?) == selectedBuyerId,
                      orElse: () => <String, dynamic>{},
                    );
                    final first = (m['firstName'] ?? '').toString().trim();
                    final last = (m['lastName'] ?? '').toString().trim();
                    buyerName = '$first $last'.trim();
                    if (buyerName.isEmpty) buyerName = null;
                  }

                  // Show receipt, only pop sell dialog after receipt is dismissed
                  if (!mounted) return;
                  await showDialog<void>(
                    context: safeContext,
                    builder: (_) => ReceiptDialog(
                      lineItems: receiptItems,
                      buyerName: buyerName,
                      transactionTime: transactionTs,
                    ),
                  );

                  if (!mounted) return;
                  // ignore: use_build_context_synchronously
                  Navigator.pop(safeContext, cart);
                  cart.clear();
                }
              : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
