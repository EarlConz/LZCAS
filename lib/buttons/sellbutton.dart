import 'package:flutter/material.dart';
import 'package:lzcas/widgets/staff_table.dart' show StaffButton, StaffFab;
import 'package:flutter/services.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/action_guard.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/dialogs/receipt_dialog.dart';
import 'package:lzcas/dialogs/qr_scanner_dialog.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/member_search.dart';

class SellButton extends StatefulWidget {
  final bool compact;

  /// The phone's floating Sell, bottom-right on Transactions.
  final bool floating;

  /// When non-null, this POS sells from the given branch cashier's allocation
  /// (branch_stock) instead of central stock, and records the sale via the
  /// `record_branch_sale` RPC. Null = normal central-stock POS.
  final String? branchOwnerId;

  const SellButton({super.key, this.compact = false, this.floating = false, this.branchOwnerId});

  @override
  State<SellButton> createState() => _SellButtonState();
}

class _SellButtonState extends State<SellButton> {
  List<String> items = [];
  Map<String, int> _itemStock = {};

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final rows = widget.branchOwnerId != null
        ? await repository.fetchBranchStock(widget.branchOwnerId!)
        : await repository.fetchItems();
    if (!mounted) return;
    final inventory = inventoryItemsFromRows(rows).toList();
    setState(() {
      items = inventory.map((i) => i['name'].toString()).toList();
      _itemStock = {
        for (final i in inventory)
          i['name'].toString(): (i['stock'] is int
              ? i['stock'] as int
              : int.tryParse(i['stock']?.toString() ?? '0') ?? 0),
      };
    });
  }

  void _showSellDialog(BuildContext context) {
    _loadItems();
    showAnimatedDialog(
      context,
      builder: (_) => _SellDialog(
        items: items,
        itemStock: _itemStock,
        onSaleConfirmed: _loadItems,
        branchOwnerId: widget.branchOwnerId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.floating) {
      return StaffFab(
        label: 'Sell',
        icon: Icons.point_of_sale_outlined,
        onPressed: () => _showSellDialog(context),
      );
    }
    if (widget.compact) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.point_of_sale, size: 20),
        label: const Text('Sell'),
        onPressed: () => _showSellDialog(context),
      );
    }

    // The page's main button, as on the other staff tables.
    return StaffButton(
      label: 'Sell',
      icon: Icons.point_of_sale_outlined,
      onPressed: () => _showSellDialog(context),
    );
  }
}

class _SellDialog extends StatefulWidget {
  final List<String> items;
  final Map<String, int> itemStock;
  final VoidCallback onSaleConfirmed;

  /// When set, the sale draws from this branch cashier's allocation.
  final String? branchOwnerId;

  const _SellDialog({
    required this.items,
    required this.itemStock,
    required this.onSaleConfirmed,
    this.branchOwnerId,
  });

  @override
  State<_SellDialog> createState() => _SellDialogState();
}

class _SellDialogState extends State<_SellDialog> {
  String? selectedItem;
  int? selectedBuyerId;

  /// The chosen buyer's row (as [membersFromRows] shapes it), or null for a
  /// walk-in sale.
  Map<String, dynamic>? _buyer;

  /// The buyer field: suggestions come from the database as you type.
  final _buyerSearch = MemberSearch();
  TextEditingController? _buyerText;

  /// A name typed but not picked from the list. It must be picked or
  /// cleared before the sale: otherwise it would quietly be a walk-in sale
  /// and the member's upline would get no Group Sales.
  bool get _buyerUnpicked =>
      selectedBuyerId == null && (_buyerText?.text.trim().isNotEmpty ?? false);

  void _setBuyer(Member? m) {
    setState(() {
      _buyer = m == null ? null : membersFromRows([m]).first;
      selectedBuyerId = m?.id;
    });
    _buyerText?.text = m == null ? '' : _buyerLabel(m);
  }

  static String _buyerLabel(Member m) =>
      '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim();
  int quantity = 1;
  List<Map<String, dynamic>> cart = [];
  String? _stockWarning;

  /// Live stock source — the branch cashier's allocation when in branch mode,
  /// otherwise central stock. Returns [Item]s (stock = available quantity).
  Future<List<Item>> _fetchStockSource() => widget.branchOwnerId != null
      ? repository.fetchBranchStock(widget.branchOwnerId!)
      : repository.fetchItems();

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: StockpileColors.danger, width: 4),
        ),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: StockpileColors.danger, size: 24),
            SizedBox(width: 8),
            Text('Error', style: TextStyle(color: StockpileColors.danger)),
          ],
        ),
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

  void _validateStock(int qty) {
    if (selectedItem == null) {
      setState(() => _stockWarning = null);
      return;
    }
    final available = widget.itemStock[selectedItem] ?? 0;
    final alreadyInCart = cart
        .where((e) => e['item'] == selectedItem)
        .fold<int>(0, (sum, e) => sum + (e['quantity'] as int));
    final totalNeeded = alreadyInCart + qty;
    if (totalNeeded > available) {
      setState(
        () =>
            _stockWarning = 'Only $available in stock ($alreadyInCart in cart)',
      );
    } else {
      setState(() => _stockWarning = null);
    }
  }

  bool isCartValid() {
    if (cart.isEmpty) return false;
    for (var entry in cart) {
      final priceStr = (entry['price'] ?? '').toString();
      if (priceStr.isEmpty || (int.tryParse(priceStr) ?? 0) <= 0) return false;
    }
    return true;
  }

  /// The selected buyer's row, or null for a walk-in sale.
  Map<String, dynamic>? get _selectedBuyer => _buyer;

  /// Name of the package the selected buyer availed, or null when they have
  /// none (rendered as "None"). Falls back to null if the join didn't return
  /// a name, so a package-less member and a missing name read the same.
  String? get _selectedBuyerPackage {
    final name = (_selectedBuyer?['packageName'] ?? '').toString().trim();
    return name.isEmpty ? null : name;
  }

  Future<void> _scanBuyerQr(BuildContext context) async {
    final scanned = await showQrScannerDialog(context);
    if (scanned == null || scanned.isEmpty) return;
    if (!mounted) return;

    // Look the member up by their QR token.
    Member? member;
    try {
      member = await repository.getMemberByQr(scanned);
    } catch (_) {}
    if (!mounted) return;

    if (member != null) {
      _setBuyer(member);
      BotToast.showText(text: 'Buyer set to ${_buyerLabel(member)}');
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
                        child: Autocomplete<Member>(
                          displayStringForOption: _buyerLabel,
                          optionsBuilder: (v) => _buyerSearch(v.text),
                          optionsViewBuilder: (context, onSelected, options) => memberOptionsView(
                            context: context,
                            onSelected: onSelected,
                            options: options,
                            label: _buyerLabel,
                          ),
                          onSelected: _setBuyer,
                          fieldViewBuilder: (context, controller, focus, onSubmit) {
                            _buyerText = controller;
                            return TextField(
                              controller: controller,
                              focusNode: focus,
                              onChanged: (_) {
                                // Typing over a picked name un-picks it.
                                if (selectedBuyerId != null) {
                                  setState(() {
                                    _buyer = null;
                                    selectedBuyerId = null;
                                  });
                                } else {
                                  setState(() {});
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Buyer',
                                hintText: 'Walk-in, or type a name or number',
                                errorText: _buyerUnpicked
                                    ? 'Pick a name from the list, or clear it'
                                    : null,
                                suffixIcon: controller.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Walk-in (no member)',
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () => _setBuyer(null),
                                      ),
                              ),
                            );
                          },
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

                // Availed package of the selected buyer ("None" when they
                // have not availed one). Hidden entirely for a walk-in sale,
                // where there is no member to describe.
                if (selectedBuyerId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.workspace_premium_rounded,
                          size: 16,
                          color: theme.hintColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Package: ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _selectedBuyerPackage ?? 'None',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _selectedBuyerPackage == null
                                  ? theme.hintColor
                                  : theme.colorScheme.primary,
                            ),
                          ),
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
                                          _stockWarning = null;
                                          _validateStock(quantity);
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
                        onChanged: (v) => setState(() {
                          selectedItem = v;
                          _stockWarning = null;
                          _validateStock(quantity);
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _qtyController,
                            focusNode: _qtyFocusNode,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText: 'Qty',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              errorText: _stockWarning,
                            ),
                            onChanged: (v) {
                              final qty = int.tryParse(v) ?? 1;
                              setState(() {
                                quantity = qty;
                                _validateStock(qty);
                              });
                            },
                          ),
                        ],
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
                        _fetchStockSource().then((allItems) {
                          final dbItem = allItems.firstWhere(
                            (r) => r.name == selectedItem,
                            orElse: () => Item(name: '', stock: 0),
                          );
                          final alreadyInCart = cart
                              .where((e) => e['item'] == selectedItem)
                              .fold<int>(
                                0,
                                (sum, e) => sum + (e['quantity'] as int),
                              );
                          final totalNeeded = alreadyInCart + quantity;
                          if (totalNeeded > dbItem.stock) {
                            _showError(
                              'Insufficient stock for "$selectedItem". '
                              'Available: ${dbItem.stock}, in cart: $alreadyInCart, requested: $quantity.',
                            );
                            return;
                          }
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
              // Guard against a double-click creating the sale (and deducting
              // stock) twice.
              ? () => ActionGuard.run('pos_confirm_sale', () async {
                  if (_buyerUnpicked) {
                    BotToast.showText(
                      text: 'Pick the buyer from the list, or clear the field for a walk-in sale.',
                    );
                    return;
                  }
                  final safeContext = context;
                  final transactionTs = DateTime.now();

                  // Compute buyer name once before the sale loop
                  String? buyerName;
                  if (selectedBuyerId != null) {
                    final m = _buyer ?? const <String, dynamic>{};
                    final first = (m['firstName'] ?? '').toString().trim();
                    final last = (m['lastName'] ?? '').toString().trim();
                    buyerName = '$first $last'.trim();
                    if (buyerName.isEmpty) buyerName = null;
                  }

                  // ── Stock validation before sale ──────────────────
                  final allItems = await _fetchStockSource();
                  final stockMap = <String, int>{};
                  for (final item in allItems) {
                    stockMap[item.name] = item.stock;
                  }
                  final cartQtyByItem = <String, int>{};
                  for (var entry in cart) {
                    final name = entry['item'] as String;
                    final q = entry['quantity'] as int;
                    cartQtyByItem[name] = (cartQtyByItem[name] ?? 0) + q;
                  }
                  final insufficient = <String>[];
                  for (final name in cartQtyByItem.keys) {
                    final needed = cartQtyByItem[name]!;
                    final available = stockMap[name] ?? 0;
                    if (needed > available) {
                      insufficient.add('$name (need $needed, have $available)');
                    }
                  }
                  if (insufficient.isNotEmpty) {
                    _showError(
                      'Not enough stock for:\n${insufficient.join('\n')}',
                    );
                    return;
                  }

                  final lines = [
                    for (var entry in cart)
                      (
                        itemId: allItems
                            .firstWhere((r) => r.name == entry['item'])
                            .id!,
                        quantity: entry['quantity'] as int,
                        price:
                            int.tryParse((entry['price'] ?? '').toString()) ??
                            0,
                      ),
                  ];

                  if (widget.branchOwnerId != null) {
                    // Branch POS: decrement the cashier's own allocation and
                    // record each line atomically via the RPC.
                    for (final l in lines) {
                      await repository.recordBranchSale(
                        itemId: l.itemId,
                        quantity: l.quantity,
                        price: l.price,
                        buyerId: selectedBuyerId,
                        buyerName: buyerName,
                        timestamp: transactionTs,
                      );
                    }
                  } else {
                    // Central POS (v64): the database checks and subtracts
                    // the whole cart in one go, so two checkouts at once
                    // can't both sell the last one.
                    final error = await repository.recordPosSale(
                      lines: lines,
                      buyerId: selectedBuyerId,
                      buyerName: buyerName,
                      timestamp: transactionTs,
                    );
                    if (!mounted) return;
                    if (error != null) {
                      _showError(error);
                      return;
                    }
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
                      buyerPackage: _selectedBuyerPackage,
                      transactionTime: transactionTs,
                    ),
                  );

                  if (!mounted) return;
                  // ignore: use_build_context_synchronously
                  Navigator.pop(safeContext, cart);
                  cart.clear();
                })
              : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
