import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/utils/animations.dart';
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
    if (!mounted) return;
    setState(() {
      items = inventoryItemsFromRows(
        rows,
      ).map((i) => i['name'].toString()).toList();
    });
  }

  Future<void> _loadMembers() async {
    final memberRows = await repository.fetchMembers();
    if (!mounted) return;
    setState(() {
      members = membersFromRows(memberRows);
    });
  }

  void _showSellDialog(BuildContext context) {
    _loadItems();
    _loadMembers();
    showAnimatedDialog(
      context,
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
      return ElevatedButton.icon(
        icon: const Icon(Icons.point_of_sale, size: 20),
        label: const Text('Sell'),
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
    showAnimatedDialog(
      context,
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
        BotToast.showText(
          text:
              'Buyer set to ${memberRow['firstName'] ?? ''} ${memberRow['lastName'] ?? ''}',
        );
      }
    } else {
      if (mounted) {
        BotToast.showText(text: 'No member matches this QR code');
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

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Row(
        children: [
          Icon(Icons.point_of_sale, color: colorScheme.primary, size: 30),
          const SizedBox(width: 12),
          Text(
            'Sell Items',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.80,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Buyer picker (member-picker) with QR scan
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
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
                      const SizedBox(width: 12),
                      IconButton.filled(
                        tooltip: 'Scan member QR',
                        iconSize: 24,
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: () => _scanBuyerQr(context),
                      ),
                    ],
                  ),
                ),

                Divider(color: theme.dividerColor, height: 28),

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
                            constraints: const BoxConstraints(maxHeight: 240),
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              border: Border.all(color: theme.dividerColor),
                              borderRadius: BorderRadius.circular(10),
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
                                      title: Text(
                                        i,
                                        style: theme.textTheme.bodyLarge,
                                      ),
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

                const SizedBox(height: 20),

                // quick add row
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Item',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        initialValue: selectedItem,
                        items: widget.items
                            .map(
                              (i) => DropdownMenuItem(value: i, child: Text(i)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => selectedItem = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _qtyController,
                        focusNode: _qtyFocusNode,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Qty',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        onChanged: (v) =>
                            setState(() => quantity = int.tryParse(v) ?? 1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
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

                const SizedBox(height: 20),

                // cart list
                if (cart.isNotEmpty)
                  SizedBox(
                    height: 260,
                    child: ListView.builder(
                      itemCount: cart.length,
                      itemBuilder: (context, index) {
                        final entry = cart[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry['item'],
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      Text(
                                        'Qty: ${entry['quantity']}',
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 160,
                                  child: TextField(
                                    controller: entry['priceController'],
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'Price',
                                      hintText: 'Enter Price',
                                    ),
                                    onChanged: (val) =>
                                        setState(() => entry['price'] = val),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  iconSize: 28,
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Remove item',
                                  onPressed: () =>
                                      setState(() => cart.removeAt(index)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // totals area placed under list
                if (cart.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Row(
                      children: [
                        const Spacer(),
                        Text(
                          'Subtotal: ₱$totalPrice',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (cart.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Text(
              'Total: ₱$totalPrice',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        FilledButton(
          onPressed: isCartValid()
              ? () async {
                  final safeContext = context;
                  final transactionTs = DateTime.now();

                  // Compute buyer name once before the sale loop
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

                  for (var entry in cart) {
                    final dbItem = (await repository.fetchItems()).firstWhere(
                      (r) => r.name == entry['item'],
                    );
                    final q = entry['quantity'] as int;
                    final newStock = dbItem.stock - q;
                    final newStatus = statusFromStock(newStock);
                    final updated = dbItem.copyWith(
                      stock: newStock,
                      lastUpdated: DateTime.now(),
                      status: newStatus,
                    );
                    await repository.updateItem(updated);

                    final priceStr = (entry['price'] ?? '').toString();
                    final price = int.tryParse(priceStr) ?? 0;
                    await repository.addSale(
                      itemId: dbItem.id!,
                      itemName: dbItem.name,
                      quantity: q,
                      price: price,
                      timestamp: transactionTs,
                      buyerId: selectedBuyerId,
                      buyerName: buyerName,
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
