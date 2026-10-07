import 'package:flutter/material.dart';
import 'package:lzcas/widgets/staff_table.dart' show StaffButton, StaffFab;
import 'package:flutter/services.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/action_guard.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/dialogs/receipt_dialog.dart';
import 'package:lzcas/dialogs/qr_scanner_dialog.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/phone_formatter.dart';
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

/// The Sell window on its own, for the layout test
/// (test/sell_phone_layout_test.dart). Selling still needs the database.
@visibleForTesting
Widget sellDialogForTest({required List<String> items, required Map<String, int> itemStock}) =>
    _SellDialog(items: items, itemStock: itemStock, onSaleConfirmed: () {});

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

  /// The product field's text, to clear it after an item is added.
  TextEditingController? _itemText;

  /// An Add is checking stock: further presses wait (Part 6: quick taps
  /// each passed the check and added the same product several times).
  bool _adding = false;
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
  final FocusNode _qtyFocusNode = FocusNode();

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
    _qtyFocusNode.dispose();
    _phoneSearch.dispose();
    _phoneSearchFocus.dispose();
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

  /// Confirm: checks stock, records the sale, shows the receipt, closes.
  /// Guarded against a double press creating the sale (and deducting
  /// stock) twice. The PC dialog and the phone screen both use it.
  void _confirm() {
    ActionGuard.run('pos_confirm_sale', _confirmSale);
  }

  Future<void> _confirmSale() async {
    if (_buyerUnpicked) {
      BotToast.showText(
        text: 'Pick the buyer from the list, or clear the field for a walk-in sale.',
      );
      return;
    }
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
      context: context,
      builder: (_) => ReceiptDialog(
        lineItems: receiptItems,
        buyerName: buyerName,
        buyerPackage: _selectedBuyerPackage,
        transactionTime: transactionTs,
      ),
    );

    if (!mounted) return;
    Navigator.pop(context, cart);
    cart.clear();
  }

  @override
  Widget build(BuildContext context) {
    // A phone gets its own full screen (below).
    if (MediaQuery.sizeOf(context).width < 600) return _buildPhone(context);

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

                // quick add row
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      // Type to find a product (Part 6: the drop-down opened
                      // with an empty gap on phones, and was long to scroll).
                      child: LayoutBuilder(
                        builder: (context, box) => Autocomplete<String>(
                          optionsBuilder: (v) {
                            final q = v.text.trim().toLowerCase();
                            if (q.isEmpty || q == selectedItem?.toLowerCase()) {
                              return widget.items;
                            }
                            return widget.items.where((n) => n.toLowerCase().contains(q));
                          },
                          onSelected: (v) => setState(() {
                            selectedItem = v;
                            _stockWarning = null;
                            _validateStock(quantity);
                          }),
                          fieldViewBuilder: (context, controller, focus, onSubmit) {
                            _itemText = controller;
                            return TextField(
                              controller: controller,
                              focusNode: focus,
                              decoration: const InputDecoration(
                                labelText: 'Item',
                                hintText: 'Type to search',
                                prefixIcon: Icon(Icons.search_rounded, size: 20),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                              ),
                              // Typing over a picked product un-picks it.
                              onChanged: (t) {
                                if (selectedItem != null && t != selectedItem) {
                                  setState(() => selectedItem = null);
                                }
                              },
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) => Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(12),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: 280,
                                  // At least readable on a phone, where the
                                  // field is narrow.
                                  maxWidth: box.maxWidth < 260 ? 260 : box.maxWidth,
                                ),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, i) {
                                    final name = options.elementAt(i);
                                    final stock = widget.itemStock[name] ?? 0;
                                    return ListTile(
                                      dense: true,
                                      minTileHeight: 48,
                                      enabled: stock > 0,
                                      title: Text(name, overflow: TextOverflow.ellipsis),
                                      trailing: Text(
                                        stock > 0 ? '$stock in stock' : 'Out of stock',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      onTap: () => onSelected(name),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
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
                      onPressed: _adding
                          ? null
                          : () {
                        if (selectedItem == null) {
                          _showError('Please pick an item from the list');
                          return;
                        }
                        final matched = widget.items.contains(selectedItem);
                        if (!matched) {
                          _showError('Invalid item');
                          return;
                        }
                        setState(() => _adding = true);
                        _fetchStockSource().whenComplete(() {
                          if (mounted) setState(() => _adding = false);
                        }).then((allItems) {
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
                            // The same product again adds to its line
                            // instead of making a second one.
                            final line = cart.indexWhere((e) => e['item'] == selectedItem);
                            if (line >= 0) {
                              cart[line]['quantity'] = (cart[line]['quantity'] as int) + quantity;
                            } else {
                              cart.add({
                                'item': selectedItem,
                                'quantity': quantity,
                                'price': '',
                                'priceController': TextEditingController(),
                              });
                            }
                            // Ready for the next product.
                            selectedItem = null;
                            _itemText?.clear();
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
              ? _confirm
              : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }

  // ── Phone ─────────────────────────────────────────────────────────────
  //
  // Under 600 px wide the dialog was a PC window squeezed onto the screen,
  // and its product list opened under the keyboard (Part 7: PS1, AT3). On
  // a phone Sell is a full screen with three views, as in the approved
  // mockup (canvas S1bkM3VHH3u8A988sTAaEB): the cart; adding products,
  // listed right under the search field so the keyboard never covers them,
  // where a tap adds one; and choosing the buyer. Checking out is the same
  // as on a PC (_confirmSale).

  _PhoneView _view = _PhoneView.cart;
  final _phoneSearch = TextEditingController();
  final _phoneSearchFocus = FocusNode();

  /// Why the last tap added nothing (no more stock), until the next one.
  String? _flash;

  /// Members matching the buyer search.
  Iterable<Member> _memberHits = const [];

  void _go(_PhoneView view) {
    setState(() {
      _view = view;
      _flash = null;
      _memberHits = const [];
    });
    _phoneSearch.clear();
    if (view == _PhoneView.cart) {
      _phoneSearchFocus.unfocus();
    } else {
      _phoneSearchFocus.requestFocus();
    }
  }

  int _inCart(String name) => cart
      .where((e) => e['item'] == name)
      .fold<int>(0, (sum, e) => sum + (e['quantity'] as int));

  int _stockOf(String name) => widget.itemStock[name] ?? 0;

  /// A tap on a product: one more, as long as there is stock. Stock is
  /// checked again against the database at checkout.
  void _phoneAdd(String name) {
    final stock = _stockOf(name);
    if (_inCart(name) + 1 > stock) {
      setState(() => _flash = 'Only $stock of $name in stock, all in the cart.');
      return;
    }
    setState(() {
      _flash = null;
      final line = cart.indexWhere((e) => e['item'] == name);
      if (line >= 0) {
        cart[line]['quantity'] = (cart[line]['quantity'] as int) + 1;
      } else {
        cart.add({
          'item': name,
          'quantity': 1,
          'price': '',
          'priceController': TextEditingController(),
        });
      }
    });
  }

  void _phoneStep(int index, int by) {
    setState(() {
      final line = cart[index];
      final next = (line['quantity'] as int) + by;
      if (next <= 0) {
        _disposeLater(line['priceController']);
        cart.removeAt(index);
      } else if (next <= _stockOf(line['item'] as String)) {
        line['quantity'] = next;
      }
    });
  }

  void _phoneRemove(int index) {
    setState(() {
      _disposeLater(cart[index]['priceController']);
      cart.removeAt(index);
    });
  }

  /// Disposed after this frame, once its field has left the screen.
  void _disposeLater(Object? controller) {
    if (controller is! TextEditingController) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  Future<void> _searchMembers(String text) async {
    final found = await _buyerSearch(text);
    if (mounted && _view == _PhoneView.buyer) setState(() => _memberHits = found);
  }

  static String _peso(int n) => '₱${NumberFormat.decimalPattern('en_PH').format(n)}';

  Widget _buildPhone(BuildContext context) {
    final c = _PhoneColors.of(context);
    return PopScope(
      // Back from adding products or choosing the buyer returns to the
      // cart; only the cart's back closes Sell.
      canPop: _view == _PhoneView.cart,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_PhoneView.cart);
      },
      child: Dialog.fullscreen(
        backgroundColor: c.bg,
        child: Scaffold(
          backgroundColor: c.bg,
          body: SafeArea(
            child: Column(
              children: [
                _phoneTopBar(c),
                if (_view != _PhoneView.buyer) _phoneBuyerRow(c),
                _phoneSearchField(c),
                Expanded(
                  child: switch (_view) {
                    _PhoneView.search => _phoneProducts(c),
                    _PhoneView.cart => _phoneCart(c),
                    _PhoneView.buyer => _phoneMembers(c),
                  },
                ),
                if (_view == _PhoneView.search) _phoneDoneBar(c),
                if (_view == _PhoneView.cart) _phoneTotalBar(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneTopBar(_PhoneColors c) {
    final title = switch (_view) {
      _PhoneView.cart => 'Sell items',
      _PhoneView.search => 'Add products',
      _PhoneView.buyer => 'Choose the buyer',
    };
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: _view == _PhoneView.cart ? 'Close' : 'Back to the cart',
            icon: Icon(
              _view == _PhoneView.cart ? Icons.close_rounded : Icons.arrow_back_rounded,
              color: c.text,
            ),
            onPressed: () => _view == _PhoneView.cart
                ? Navigator.pop(context)
                : _go(_PhoneView.cart),
          ),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: StockpileFonts.satoshi(fontSize: 18, fontWeight: FontWeight.w800, color: c.text),
            ),
          ),
          if (_view == _PhoneView.cart && cart.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${cart.length} product${cart.length == 1 ? '' : 's'}',
                style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w700, color: c.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _phoneBuyerRow(_PhoneColors c) {
    final m = _buyer;
    final name = m == null
        ? 'Walk-in (no member)'
        : '${'${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'.trim()} · ID $selectedBuyerId';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.line),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _go(_PhoneView.buyer),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      Icon(Icons.person_outline_rounded, size: 20, color: c.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m == null ? 'Buyer' : 'Buyer · ${_selectedBuyerPackage ?? 'no'} package',
                              style: StockpileFonts.satoshi(fontSize: 12, fontWeight: FontWeight.w600, color: c.muted),
                            ),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: c.muted),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            height: 52,
            child: IconButton.filled(
              tooltip: 'Scan member QR',
              style: IconButton.styleFrom(
                backgroundColor: c.text,
                foregroundColor: c.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: () => _scanBuyerQr(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneSearchField(_PhoneColors c) {
    final buyer = _view == _PhoneView.buyer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _phoneSearch,
        focusNode: _phoneSearchFocus,
        textInputAction: TextInputAction.search,
        onTap: () {
          if (_view == _PhoneView.cart) _go(_PhoneView.search);
        },
        onChanged: (t) {
          if (buyer) {
            _searchMembers(t);
          } else {
            setState(() => _flash = null);
          }
        },
        style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w600, color: c.text),
        decoration: InputDecoration(
          hintText: buyer ? 'Name, number or ID' : 'Search products',
          prefixIcon: Icon(Icons.search_rounded, color: c.muted),
          filled: true,
          fillColor: c.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          suffixIcon: _phoneSearch.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.close_rounded, color: c.muted),
                  onPressed: () {
                    _phoneSearch.clear();
                    setState(() => _memberHits = const []);
                  },
                ),
        ),
      ),
    );
  }

  Widget _phoneLabel(_PhoneColors c, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
    child: Text(
      text,
      style: StockpileFonts.satoshi(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: c.muted,
      ).copyWith(letterSpacing: 0.7),
    ),
  );

  /// A white box with rows divided by lines, as the mockup's lists.
  Widget _phoneListBox(_PhoneColors c, List<Widget> rows) => Material(
    // A Material, not a coloured box: the rows' tap ripple paints on it.
    color: c.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: c.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: c.line),
          rows[i],
        ],
      ],
    ),
  );

  Widget _phoneProducts(_PhoneColors c) {
    final q = _phoneSearch.text.trim().toLowerCase();
    final matches = widget.items.where((n) => q.isEmpty || n.toLowerCase().contains(q)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _phoneLabel(c, 'TAP A PRODUCT TO ADD ONE'),
        if (matches.isEmpty)
          _phoneListBox(c, [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.items.isEmpty ? 'No products to sell.' : 'No product matches "${_phoneSearch.text.trim()}".',
                style: StockpileFonts.satoshi(fontSize: 14, color: c.muted),
              ),
            ),
          ])
        else
          _phoneListBox(c, [for (final name in matches) _phoneProductRow(c, name)]),
        if (_flash != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.warnBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _flash!,
                style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: c.warn),
              ),
            ),
          ),
      ],
    );
  }

  Widget _phoneProductRow(_PhoneColors c, String name) {
    final stock = _stockOf(name);
    final have = _inCart(name);
    final out = stock <= 0;
    final full = !out && have >= stock;
    final stockText = out
        ? 'Out of stock'
        : full
        ? 'All $stock in the cart'
        : '${stock - have} left in stock';
    return Material(
      color: out ? c.bg : c.surface,
      child: InkWell(
        onTap: out ? null : () => _phoneAdd(name),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: StockpileFonts.satoshi(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: out ? c.muted : c.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stockText,
                        style: StockpileFonts.satoshi(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: !out && stock <= 5 ? c.warn : c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (have > 0) ...[
                  Container(
                    constraints: const BoxConstraints(minWidth: 28),
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '×$have',
                      style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w800, color: c.accentText),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (!out && !full)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                    child: Icon(Icons.add_rounded, size: 20, color: c.onAccent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneDoneBar(_PhoneColors c) {
    final units = cart.fold<int>(0, (s, e) => s + (e['quantity'] as int));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              units == 0
                  ? 'Nothing in the cart yet'
                  : '$units item${units == 1 ? '' : 's'} in the cart',
              style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: c.text),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.text,
              foregroundColor: c.surface,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => _go(_PhoneView.cart),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _phoneCart(_PhoneColors c) {
    if (cart.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'The cart is empty.\nSearch above to add a product.',
            textAlign: TextAlign.center,
            style: StockpileFonts.satoshi(fontSize: 15, color: c.muted).copyWith(height: 1.5),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: cart.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _phoneCartLine(c, i),
    );
  }

  Widget _phoneCartLine(_PhoneColors c, int i) {
    final line = cart[i];
    final name = line['item'] as String;
    final qty = line['quantity'] as int;
    final stock = _stockOf(name);
    final price = int.tryParse((line['price'] ?? '').toString()) ?? 0;
    final atMax = qty >= stock;
    final note = price <= 0
        ? 'Enter the price'
        : atMax
        ? 'That is all the stock'
        : '${_peso(price)} × $qty';

    Widget step(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      color: c.text,
      disabledColor: c.line,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w800, color: c.text),
                    ),
                    Text(
                      '$stock in stock',
                      style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove $name',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline_rounded, color: c.muted),
                onPressed: () => _phoneRemove(i),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quantity',
                    style: StockpileFonts.satoshi(fontSize: 12, fontWeight: FontWeight.w700, color: c.muted),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.bg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        step(Icons.remove_rounded, qty == 1 ? 'Take it out' : 'One less', () => _phoneStep(i, -1)),
                        SizedBox(
                          width: 32,
                          child: Text(
                            '$qty',
                            textAlign: TextAlign.center,
                            style: StockpileFonts.satoshi(fontSize: 17, fontWeight: FontWeight.w800, color: c.text),
                          ),
                        ),
                        step(Icons.add_rounded, 'One more', atMax ? null : () => _phoneStep(i, 1)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Price each (₱)',
                      style: StockpileFonts.satoshi(fontSize: 12, fontWeight: FontWeight.w700, color: c.muted),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 44,
                      child: TextField(
                        controller: line['priceController'] as TextEditingController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (v) => setState(() => line['price'] = v),
                        style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w700, color: c.text),
                        decoration: InputDecoration(
                          hintText: '0',
                          isDense: true,
                          filled: true,
                          fillColor: c.surface,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: price > 0
                                ? BorderSide(color: c.line)
                                : BorderSide(color: c.warn, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: c.line),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  note,
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: price <= 0 || atMax ? c.warn : c.muted,
                  ),
                ),
              ),
              Text(
                price > 0 ? _peso(price * qty) : '—',
                style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w800, color: c.text),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _phoneTotalBar(_PhoneColors c) {
    var total = 0, units = 0, missing = 0;
    for (final e in cart) {
      final q = e['quantity'] as int;
      final p = int.tryParse((e['price'] ?? '').toString()) ?? 0;
      units += q;
      total += p * q;
      if (p <= 0) missing++;
    }
    final ready = cart.isNotEmpty && missing == 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Total',
                style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: c.muted),
              ),
              const Spacer(),
              Text(
                _peso(total),
                style: StockpileFonts.satoshi(fontSize: 24, fontWeight: FontWeight.w800, color: c.text),
              ),
            ],
          ),
          if (missing > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Enter a price for every item ($missing missing)',
              style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w700, color: c.warn),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: ready ? _confirm : null,
            child: Text(units == 0 ? 'Sell' : 'Sell $units item${units == 1 ? '' : 's'}'),
          ),
        ],
      ),
    );
  }

  Widget _phoneMembers(_PhoneColors c) {
    final typed = _phoneSearch.text.trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _phoneListBox(c, [
          ListTile(
            minTileHeight: 56,
            title: Text(
              'Walk-in (no member)',
              style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
            ),
            trailing: selectedBuyerId == null ? Icon(Icons.check_rounded, color: c.accentText) : null,
            onTap: () {
              _setBuyer(null);
              _go(_PhoneView.cart);
            },
          ),
        ]),
        const SizedBox(height: 10),
        _phoneLabel(c, 'MEMBERS · NAME, NUMBER OR ID'),
        if (_memberHits.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
            child: Text(
              typed
                  ? 'No member found yet. Keep typing: 2 letters of a name, part of a number, or an ID.'
                  : 'Type 2 letters of a name, part of a number, or a member ID.',
              style: StockpileFonts.satoshi(fontSize: 14, color: c.muted),
            ),
          )
        else
          _phoneListBox(c, [
            for (final m in _memberHits)
              ListTile(
                minTileHeight: 64,
                leading: CircleAvatar(
                  backgroundColor: c.accentSoft,
                  foregroundColor: c.accentText,
                  child: Text(
                    _initials(m),
                    style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w800, color: c.accentText),
                  ),
                ),
                title: Text(
                  _buyerLabel(m).isEmpty ? 'Member #${m.id}' : _buyerLabel(m),
                  style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
                ),
                subtitle: Text(
                  [
                    'ID ${m.id}',
                    if ((m.packageName ?? '').trim().isNotEmpty) '${m.packageName!.trim()} package',
                    if ((m.contactNo ?? '').trim().isNotEmpty) formatPhilippinePhone(m.contactNo!),
                  ].join(' · '),
                  style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted),
                ),
                trailing: m.id == selectedBuyerId ? Icon(Icons.check_rounded, color: c.accentText) : null,
                onTap: () {
                  _setBuyer(m);
                  _go(_PhoneView.cart);
                },
              ),
          ]),
      ],
    );
  }

  static String _initials(Member m) {
    final f = (m.firstName ?? '').trim(), l = (m.lastName ?? '').trim();
    final s = '${f.isEmpty ? '' : f[0]}${l.isEmpty ? '' : l[0]}'.toUpperCase();
    return s.isEmpty ? '#' : s;
  }
}

/// The phone Sell screen's views.
enum _PhoneView { cart, search, buyer }

/// The phone Sell screen's colours, light and dark, from the app's theme.
class _PhoneColors {
  final Color bg, surface, line, text, muted, accent, onAccent, accentSoft, accentText, warn, warnBg;

  const _PhoneColors({
    required this.bg,
    required this.surface,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentText,
    required this.warn,
    required this.warnBg,
  });

  factory _PhoneColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? _PhoneColors(
            bg: StockpileColors.darkBg,
            surface: StockpileColors.darkSurface,
            line: StockpileColors.darkDivider,
            text: StockpileColors.darkTextPrimary,
            muted: StockpileColors.darkTextMuted,
            accent: scheme.primary,
            onAccent: scheme.onPrimary,
            accentSoft: const Color(0xFF3A2A12),
            accentText: StockpileColors.primary300,
            warn: StockpileColors.error300,
            warnBg: const Color(0xFF3A1A12),
          )
        : _PhoneColors(
            bg: StockpileColors.scaffoldBg,
            surface: StockpileColors.surface,
            line: StockpileColors.divider,
            text: StockpileColors.darkText,
            muted: const Color(0xFF6E6E7A),
            accent: scheme.primary,
            onAccent: scheme.onPrimary,
            accentSoft: StockpileColors.primary50,
            accentText: const Color(0xFF8F3A00),
            warn: StockpileColors.error700,
            warnBg: StockpileColors.error50,
          );
  }
}
