// lib/dialogs/edit_sale_dialog.dart
//
// Edit Sale, from the "Staff Modals Redesign" canvas: one checkout (the
// rows one cashier recorded at one moment), its buyer and its lines. Admins
// only (client decision 2026-10-03). A dialog on desktop, a full screen on
// a phone (widgets/modal_kit.dart).
//
// Stock is checked as it is typed against what is left plus what this sale
// already took, and again by the database, which saves it all in one
// locked transaction (admin_edit_sale_group, v64). Group Sales credit is
// recalculated there by the sales triggers.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bot_toast/bot_toast.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart' show formatDisplayDate;
import 'package:lzcas/utils/member_search.dart';
import 'package:lzcas/widgets/modal_kit.dart';

/// Whether [sales] (one checkout) can be edited here: counter sales by one
/// cashier, not a delivery order or a package availment. Branch sales are
/// refused by the database, which knows the seller's role.
bool isEditableSale(List<Sale> sales) =>
    sales.isNotEmpty &&
    sales.first.userId != null &&
    sales.first.timestamp != null &&
    sales.every(
      (s) =>
          s.userId == sales.first.userId &&
          s.packageId == null &&
          s.paymentMethod == null &&
          s.itemId > 0,
    );

class _Line {
  int? itemId;
  final TextEditingController qty;
  final TextEditingController price;
  _Line(this.itemId, int q, int p)
    : qty = TextEditingController(text: '$q'),
      price = TextEditingController(text: '$p');

  int get quantity => int.tryParse(qty.text.trim()) ?? 0;
  int get unitPrice => int.tryParse(price.text.trim()) ?? 0;

  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

class EditSaleDialog extends StatefulWidget {
  /// One checkout's rows, as [isEditableSale] accepts them.
  final List<Sale> sales;
  final VoidCallback onSaved;

  const EditSaleDialog({super.key, required this.sales, required this.onSaved});

  @override
  State<EditSaleDialog> createState() => _EditSaleDialogState();
}

class _EditSaleDialogState extends State<EditSaleDialog> {
  late final List<_Line> _lines = [
    for (final s in widget.sales) _Line(s.itemId, s.quantity, s.price),
  ];
  late int? _buyerId = widget.sales.first.buyerId;
  late String _buyerName = (widget.sales.first.buyerName ?? '').trim();

  List<Item> _items = const [];
  bool _loading = true;

  /// Buyer suggestions come from the database as you type.
  final _buyerSearch = MemberSearch();

  /// What the buyer field shows. A name typed but not picked holds Save:
  /// it would otherwise keep the old buyer, or record a walk-in.
  late String _buyerTyped = _buyerName;
  bool get _buyerUnpicked => _buyerId == null && _buyerTyped.trim().isNotEmpty;
  bool _saving = false;

  /// What this sale took of each product: it comes back if the line shrinks.
  late final Map<int, int> _taken = () {
    final m = <int, int>{};
    for (final s in widget.sales) {
      m[s.itemId] = (m[s.itemId] ?? 0) + s.quantity;
    }
    return m;
  }();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await repository.fetchItems();
      if (!mounted) return;
      setState(() {
        _items = items..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      BotToast.showText(text: 'Could not load the products.');
    }
  }

  Item? _item(int? id) => _items.where((i) => i.id == id).firstOrNull;

  /// What a product can go up to in this sale: what is left now, plus what
  /// this sale already took of it.
  int _available(int itemId) => (_item(itemId)?.stock ?? 0) + (_taken[itemId] ?? 0);

  /// Quantity asked for each product across all lines.
  Map<int, int> get _wanted {
    final m = <int, int>{};
    for (final l in _lines) {
      if (l.itemId != null) m[l.itemId!] = (m[l.itemId!] ?? 0) + l.quantity;
    }
    return m;
  }

  String? _lineError(_Line l) {
    if (l.itemId == null) return null;
    if (l.quantity <= 0) return 'At least 1';
    final want = _wanted[l.itemId!] ?? 0;
    final can = _available(l.itemId!);
    if (want > can) return 'Only $can available';
    return null;
  }

  bool get _changed {
    if (_buyerId != widget.sales.first.buyerId) return true;
    if (_lines.length != widget.sales.length) return true;
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i], s = widget.sales[i];
      if (l.itemId != s.itemId || l.quantity != s.quantity || l.unitPrice != s.price) return true;
    }
    return false;
  }

  String? get _blocker {
    if (_loading) return 'Loading products…';
    if (_lines.isEmpty) return 'A sale needs at least one item. To remove it, delete the sale.';
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      final n = _lines.length > 1 ? 'line ${i + 1}' : 'the quantity';
      if (l.itemId == null) return 'Pick a product for line ${i + 1}.';
      if (_lineError(l) != null) return 'Fix $n to save.';
    }
    if (_buyerUnpicked) return 'Pick the buyer from the list, or clear it for a walk-in.';
    if (!_changed) return 'Nothing changed yet.';
    return null;
  }

  int get _total => _lines.fold(0, (n, l) => n + l.quantity * l.unitPrice);
  int get _oldTotal => widget.sales.fold(0, (n, s) => n + s.quantity * s.price);

  Future<void> _save() async {
    if (_saving || _blocker != null) return;
    setState(() => _saving = true);
    final first = widget.sales.first;
    final error = await repository.adminEditSaleGroup(
      userId: first.userId!,
      timestamp: first.timestamp!,
      buyerId: _buyerId,
      lines: [
        for (final l in _lines) (itemId: l.itemId!, quantity: l.quantity, price: l.unitPrice),
      ],
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      BotToast.showText(text: error, duration: const Duration(seconds: 6));
      return;
    }
    BotToast.showText(text: 'Sale updated');
    widget.onSaved();
    Navigator.pop(context);
  }

  // ── UI ─────────────────────────────────────────────────────────────

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _muted => _dark ? StockpileColors.darkTextMuted : const Color(0xFF6E6E7A);
  Color get _text => _dark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;

  @override
  Widget build(BuildContext context) {
    final single = widget.sales.length == 1 && _lines.length == 1;
    final first = widget.sales.first;
    final when = formatDisplayDate(first.timestamp);
    final n = _lines.length;
    // The buyer has its own field just below.
    final subtitle = single
        ? '${_item(_lines.first.itemId)?.name ?? first.itemName} · sold $when'
        : 'Sold $when · $n item${n == 1 ? '' : 's'}';
    final blocker = _blocker;
    final fixing = blocker != null && blocker.startsWith('Fix');

    return AppModal(
      title: 'Edit sale',
      subtitle: subtitle,
      leading: const ModalIconTile(Icons.receipt_long_outlined),
      maxWidth: single ? 560 : 860,
      gap: 18,
      body: _loading
          ? [const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))]
          : [
              _buyerField(),
              if (single) _singleLine(_lines.first) else _cart(),
              ModalNote(
                body: 'Saving also recalculates the Group Sales credit this '
                    "sale gave ${_buyerName.isEmpty ? 'the buyer' : _buyerName}'s upline.",
              ),
            ],
      footerNote: Text(
        blocker ?? '',
        style: StockpileFonts.satoshi(
          fontSize: 13,
          fontWeight: fixing ? FontWeight.w600 : FontWeight.w400,
          color: fixing ? const Color(0xFFB91C1C) : _muted,
        ),
      ),
      primaryAction: FilledButton(
        onPressed: _saving || blocker != null ? null : _save,
        child: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Save changes'),
      ),
    );
  }

  Widget _buyerField() {
    return LabeledField(
      label: 'Buyer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Autocomplete<Member>(
            initialValue: TextEditingValue(text: _buyerName),
            displayStringForOption: _name,
            optionsBuilder: (v) => _buyerSearch(v.text),
            onSelected: (m) => setState(() {
              _buyerId = m.id;
              _buyerName = _name(m);
              _buyerTyped = _buyerName;
            }),
            fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
              controller: controller,
              focusNode: focus,
              // Typing over the chosen buyer un-picks them.
              onChanged: (text) => setState(() {
                _buyerTyped = text;
                if (text.trim() != _buyerName) _buyerId = null;
              }),
              decoration: InputDecoration(
                hintText: 'Walk-in (no member)',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _buyerTyped.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'No member',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          controller.clear();
                          _buyerId = null;
                          _buyerName = '';
                          _buyerTyped = '';
                        }),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Type a name to search. Changing the buyer moves the Group Sales credit to their upline.',
            style: StockpileFonts.satoshi(fontSize: 12, color: _muted),
          ),
        ],
      ),
    );
  }

  static String _name(Member m) {
    final n = '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim();
    return n.isEmpty ? 'Member #${m.id}' : n;
  }

  /// One line: quantity and price side by side, then what changes.
  Widget _singleLine(_Line l) {
    final s = widget.sales.first;
    final item = _item(l.itemId);
    final err = _lineError(l);
    final stockNow = item?.stock ?? 0;
    final stockAfter = _available(l.itemId!) - l.quantity;
    final diff = l.quantity - s.quantity;

    Widget compare(String label, String before, String after, [String? note]) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: StockpileFonts.satoshi(fontSize: 14, color: _muted))),
          if (before != after) ...[
            Text(before, style: StockpileFonts.satoshi(fontSize: 14, color: _muted, decoration: TextDecoration.lineThrough)),
            const SizedBox(width: 8),
          ],
          Text(after, style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: _text)),
          if (note != null) ...[
            const SizedBox(width: 6),
            Text(note, style: StockpileFonts.satoshi(fontSize: 13, color: _muted)),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldPair(
          LabeledField(
            label: 'Quantity',
            child: NumberStepper(
              controller: l.qty,
              semanticLabel: 'Quantity',
              min: 1,
              max: _available(l.itemId!),
              expand: true,
              errorText: err,
              helperText: err == null ? (l.quantity == s.quantity ? 'Unchanged' : 'Was ${s.quantity}') : null,
              onChanged: (_) => setState(() {}),
            ),
          ),
          LabeledField(
            label: 'Price each',
            child: _priceField(l, helper: l.unitPrice == s.price ? 'Unchanged' : 'Was ₱${s.price}'),
          ),
          keepPaired: true,
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: _dark ? StockpileColors.darkDivider : const Color(0xFFE8E8EC)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              compare('Sale total', '₱$_oldTotal', '₱$_total'),
              Divider(height: 1, color: _dark ? StockpileColors.darkDivider : const Color(0xFFE8E8EC)),
              compare(
                'Stock of ${item?.name ?? 'this product'}',
                '$stockNow',
                '$stockAfter',
                diff == 0 ? null : (diff > 0 ? '($diff more sold)' : '(${-diff} back in stock)'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _priceField(_Line l, {String? helper}) => TextField(
    controller: l.price,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(prefixText: '₱ ', helperText: helper),
  );

  /// Several lines: a row each on a wide screen, a card each on a phone.
  Widget _cart() {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 640;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _lines.length; i++) wide ? _row(i) : _card(i),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _lines.add(_Line(null, 1, 0))),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    foregroundColor: const Color(0xFFB24800),
                    side: const BorderSide(color: Color(0xFFCC4900)),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add item'),
                ),
                const Spacer(),
                Text('Sale total', style: StockpileFonts.satoshi(fontSize: 14, color: _muted)),
                const SizedBox(width: 12),
                Text('₱$_total', style: StockpileFonts.satoshi(fontSize: 22, fontWeight: FontWeight.w700, color: _text)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _itemPicker(_Line l, int i) => DropdownButtonFormField<int>(
    isExpanded: true,
    initialValue: _items.any((it) => it.id == l.itemId) ? l.itemId : null,
    hint: const Text('Pick a product'),
    decoration: const InputDecoration(isDense: true),
    items: [
      for (final it in _items)
        DropdownMenuItem(
          value: it.id,
          child: Text('${it.name} · ${_available(it.id!)} left', overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (v) => setState(() => l.itemId = v),
  );

  Widget _removeButton(int i) => IconButton(
    tooltip: 'Remove line ${i + 1}',
    onPressed: () => setState(() => _lines.removeAt(i).dispose()),
    icon: Icon(Icons.delete_outline_rounded, color: _muted),
  );

  Widget _row(int i) {
    final l = _lines[i];
    final err = _lineError(l);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: err != null ? (_dark ? const Color(0x33B91C1C) : const Color(0xFFFEF2F2)) : null,
        border: Border(top: BorderSide(color: _dark ? StockpileColors.darkDivider : const Color(0xFFE8E8EC))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _itemPicker(l, i)),
          const SizedBox(width: 10),
          SizedBox(
            width: 160,
            child: NumberStepper(
              controller: l.qty,
              semanticLabel: 'Quantity, line ${i + 1}',
              min: 1,
              errorText: err,
              expand: true,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 130, child: _priceField(l)),
          SizedBox(
            width: 100,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                '₱${l.quantity * l.unitPrice}',
                textAlign: TextAlign.right,
                style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w600, color: _text),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _removeButton(i),
        ],
      ),
    );
  }

  Widget _card(int i) {
    final l = _lines[i];
    final err = _lineError(l);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: err != null ? const Color(0xFFB91C1C) : (_dark ? StockpileColors.darkDivider : const Color(0xFFE8E8EC)),
          width: err != null ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [Expanded(child: _itemPicker(l, i)), _removeButton(i)]),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: NumberStepper(
                    controller: l.qty,
                    semanticLabel: 'Quantity, line ${i + 1}',
                    min: 1,
                    errorText: err,
                    expand: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 120, child: _priceField(l)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Line total ₱${l.quantity * l.unitPrice}',
              textAlign: TextAlign.right,
              style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w600, color: _text),
            ),
          ),
        ],
      ),
    );
  }
}
