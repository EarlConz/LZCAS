import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/dialogs/borrow_receipt_dialog.dart';
import 'package:lzcas/dialogs/qr_scanner_dialog.dart';

class BorrowButton extends StatefulWidget {
  final bool compact;

  const BorrowButton({super.key, this.compact = false});

  @override
  State<BorrowButton> createState() => _BorrowButtonState();
}

class _BorrowButtonState extends State<BorrowButton> {
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

  void _showBorrowDialog(BuildContext context) {
    _loadItems();
    _loadMembers();
    showAnimatedDialog(
      context,
      builder: (_) => _BorrowDialog(
        items: items,
        members: members,
        onBorrowConfirmed: _loadItems,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.swap_horiz_rounded, size: 20),
        label: const Text('Borrow'),
        onPressed: () => _showBorrowDialog(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.shade700,
          foregroundColor: Colors.white,
        ),
      );
    }

    return ElevatedButton.icon(
      icon: const Icon(Icons.swap_horiz_rounded),
      label: const Text('Borrow'),
      onPressed: () => _showBorrowDialog(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _BorrowDialog extends StatefulWidget {
  final List<String> items;
  final List<Map<String, dynamic>> members;
  final VoidCallback onBorrowConfirmed;

  const _BorrowDialog({
    required this.items,
    required this.members,
    required this.onBorrowConfirmed,
  });

  @override
  State<_BorrowDialog> createState() => _BorrowDialogState();
}

class _BorrowDialogState extends State<_BorrowDialog> {
  String? selectedItem;
  int? selectedBuyerId;
  String? _borrowerName;
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
      final q = entry['quantity'] as int? ?? 0;
      if (q <= 0) return false;
    }
    return true;
  }

  Future<void> _scanBuyerQr(BuildContext context) async {
    final scanned = await showQrScannerDialog(context);
    if (scanned == null || scanned.isEmpty) return;
    if (!mounted) return;

    final memberRow = widget.members.cast<Map<String, dynamic>?>().firstWhere(
      (m) => (m?['qr'] ?? '').toString() == scanned,
      orElse: () => null,
    );

    if (memberRow != null) {
      setState(() {
        selectedBuyerId = memberRow['id'] as int?;
        final first = (memberRow['firstName'] ?? '').toString().trim();
        final last = (memberRow['lastName'] ?? '').toString().trim();
        _borrowerName = '$first $last'.trim();
        if (_borrowerName!.isEmpty) _borrowerName = null;
      });
      if (mounted) {
        BotToast.showText(
          text:
              'Borrower set to ${memberRow['firstName'] ?? ''} '
              '${memberRow['lastName'] ?? ''}',
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
    final totalQty = cart.fold<int>(0, (acc, e) {
      return acc + (e['quantity'] as int? ?? 0);
    });

    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Row(
        children: [
          Icon(
            Icons.swap_horiz_rounded,
            color: Colors.orange.shade700,
            size: 30,
          ),
          const SizedBox(width: 12),
          Text(
            'Borrow Stock',
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
                // Info banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Items are due for return or payment within 10 days.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Buyer picker with QR scan
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          decoration: const InputDecoration(
                            labelText: 'Reseller',
                          ),
                          initialValue: selectedBuyerId,
                          items: [
                            ...widget.members.map(
                              (m) => DropdownMenuItem<int?>(
                                value: m['id'] as int?,
                                child: Text(
                                  '${m['firstName'] ?? ''} '
                                          '${m['lastName'] ?? ''}'
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

                // Quick add row
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
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                      ),
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
                        if (quantity <= 0) {
                          _showError('Quantity must be at least 1');
                          return;
                        }
                        repository.fetchItems().then((_) {
                          setState(() {
                            cart.add({
                              'item': selectedItem,
                              'quantity': quantity,
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

                // Cart list
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

                // Totals
                if (cart.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Row(
                      children: [
                        const Spacer(),
                        Text(
                          'Total items: $totalQty',
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
              '$totalQty item${totalQty == 1 ? '' : 's'}',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
          ),
          onPressed: (isCartValid() && selectedBuyerId != null)
              ? () async {
                  final safeContext = context;
                  final auth = context.read<AuthState>();
                  final isAdmin = auth.userRole == UserRole.admin;

                  if (isAdmin) {
                    // ── Admin: instant borrow ────────────────────────
                    final borrows = <Borrow>[];
                    String? errorMsg;

                    for (var entry in cart) {
                      final dbItem = (await repository.fetchItems()).firstWhere(
                        (r) => r.name == entry['item'],
                      );
                      final q = entry['quantity'] as int;

                      if (dbItem.stock < q) {
                        errorMsg =
                            'Insufficient stock for ${dbItem.name} '
                            '(available: ${dbItem.stock})';
                        break;
                      }

                      try {
                        final borrowId = await repository.addBorrow(
                          memberId: selectedBuyerId!,
                          itemId: dbItem.id!,
                          itemName: dbItem.name,
                          quantity: q,
                          memberName: _borrowerName,
                        );
                        borrows.add(
                          Borrow(
                            id: borrowId,
                            memberId: selectedBuyerId!,
                            itemId: dbItem.id!,
                            itemName: dbItem.name,
                            quantity: q,
                            borrowedAt: DateTime.now(),
                            dueDate: DateTime.now().add(
                              const Duration(days: 10),
                            ),
                          ),
                        );
                      } catch (e) {
                        errorMsg = e.toString();
                        break;
                      }
                    }

                    if (errorMsg != null) {
                      if (!mounted) return;
                      _showError(errorMsg);
                      return;
                    }

                    widget.onBorrowConfirmed();

                    // Lookup member name
                    String? memberName;
                    if (selectedBuyerId != null) {
                      final m = widget.members.firstWhere(
                        (m) => (m['id'] as int?) == selectedBuyerId,
                        orElse: () => <String, dynamic>{},
                      );
                      final first = (m['firstName'] ?? '').toString().trim();
                      final last = (m['lastName'] ?? '').toString().trim();
                      memberName = '$first $last'.trim();
                      if (memberName.isEmpty) memberName = null;
                    }

                    if (!mounted) return;
                    await showDialog<void>(
                      context: safeContext,
                      builder: (_) => BorrowReceiptDialog(
                        borrows: borrows,
                        memberName: memberName,
                        borrowedAt: DateTime.now(),
                        dueDate: DateTime.now().add(const Duration(days: 10)),
                      ),
                    );

                    if (!mounted) return;
                    // ignore: use_build_context_synchronously
                    Navigator.pop(safeContext, cart);
                  } else {
                    // ── Cashier / Inventory: submit borrow request ───
                    String? errorMsg;
                    int submitted = 0;

                    // Lookup member name for the request
                    String? memberName;
                    if (selectedBuyerId != null) {
                      final m = widget.members.firstWhere(
                        (m) => (m['id'] as int?) == selectedBuyerId,
                        orElse: () => <String, dynamic>{},
                      );
                      final first = (m['firstName'] ?? '').toString().trim();
                      final last = (m['lastName'] ?? '').toString().trim();
                      memberName = '$first $last'.trim();
                      if (memberName.isEmpty) memberName = null;
                    }

                    for (var entry in cart) {
                      final dbItem = (await repository.fetchItems()).firstWhere(
                        (r) => r.name == entry['item'],
                      );
                      final q = entry['quantity'] as int;

                      if (dbItem.stock < q) {
                        errorMsg =
                            'Insufficient stock for ${dbItem.name} '
                            '(available: ${dbItem.stock})';
                        break;
                      }

                      try {
                        await repository.submitBorrowRequest(
                          memberId: selectedBuyerId!,
                          memberName: memberName ?? 'Member #$selectedBuyerId',
                          itemId: dbItem.id!,
                          itemName: dbItem.name,
                          quantity: q,
                        );
                        submitted++;
                      } catch (e) {
                        errorMsg = e.toString();
                        break;
                      }
                    }

                    if (!mounted) return;
                    if (errorMsg != null) {
                      _showError(errorMsg);
                      if (submitted > 0) widget.onBorrowConfirmed();
                      return;
                    }

                    widget.onBorrowConfirmed();
                    BotToast.showText(
                      text:
                          '$submitted borrow request${submitted == 1 ? '' : 's'} submitted for admin approval',
                    );
                    // ignore: use_build_context_synchronously
                    Navigator.pop(safeContext);
                  }
                }
              : null,
          child: const Text('Confirm Borrow'),
        ),
      ],
    );
  }
}
