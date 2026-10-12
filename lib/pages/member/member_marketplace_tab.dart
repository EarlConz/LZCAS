// lib/pages/member/member_marketplace_tab.dart
// Member Marketplace ("Marketplace" in the Member Shop & Orders design).
// Members browse what the store has in stock, listed WITHOUT a price (the
// cashier prices an order after it is placed), pick quantities, review, and
// place a delivery order with status 'Order Placed'. Nothing is paid here.
//
// Phone: one column of product rows and a bar at the foot with the order so
// far. Wide screens: a product grid with the order beside it. Reviewing the
// order is its own screen ([_ReviewOrderPage]) on both.
//
// The member's saved location (latitude/longitude/address) is the delivery
// destination; checkout asks for one when there is none.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../db/db.dart';
import '../../utils/fonts.dart';
import '../../utils/phone_formatter.dart';
import '../../widgets/location_selection_widget.dart';
import '../../widgets/map_kit.dart';
import 'member_order_kit.dart';

/// Products at or under this count say "Only N left".
const _lowStock = 5;

class MemberMarketplaceTab extends StatefulWidget {
  final Member member;

  /// Invoked right after an order is placed — lets the parent navigate to
  /// (and refresh) the Active Orders screen.
  final VoidCallback? onOrderPlaced;

  const MemberMarketplaceTab({
    super.key,
    required this.member,
    this.onOrderPlaced,
  });

  @override
  State<MemberMarketplaceTab> createState() => _MemberMarketplaceTabState();
}

class _MemberMarketplaceTabState extends State<MemberMarketplaceTab> {
  bool _loading = true;
  String? _error;
  List<Item> _items = [];
  final Map<int, int> _cart = {}; // itemId -> quantity

  /// The member as last read, for the delivery address shown at the top.
  late Member _member = widget.member;

  String _searchQuery = '';
  String? _selectedCategory; // null = "All"
  final TextEditingController _searchCtrl = TextEditingController();

  /// The "you see the price before you pay" note, until dismissed.
  bool _tipHidden = false;

  StreamSubscription<String>? _sub;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    // Products added, restocked, sold out, renamed or re-pictured on any
    // device show here without reopening (test U1). A POS sale moves stock
    // too, as an item update. Bursts (a whole cart) refresh once.
    _sub = repository.changes.listen((e) {
      if (!e.startsWith('item_')) return;
      _refresh?.cancel();
      _refresh = Timer(const Duration(milliseconds: 400), () => _load(quiet: true));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _refresh?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Distinct, sorted categories present on the loaded items — the chips
  /// always mirror what is actually sellable right now.
  List<String> get _categories {
    final seen = <String>{};
    for (final item in _items) {
      final c = (item.category ?? '').trim();
      if (c.isNotEmpty) seen.add(c);
    }
    return seen.toList()..sort();
  }

  /// Client-side, case-insensitive filter over the in-memory catalog.
  /// Matches product name or category; the category chip is AND-ed in.
  List<Item> get _filteredItems {
    final q = _searchQuery.trim().toLowerCase();
    return _items.where((item) {
      if (_selectedCategory != null &&
          (item.category ?? '').trim() != _selectedCategory) {
        return false;
      }
      if (q.isEmpty) return true;
      final name = item.name.toLowerCase();
      final category = (item.category ?? '').toLowerCase();
      return name.contains(q) || category.contains(q);
    }).toList();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _searchQuery = '';
      _selectedCategory = null;
    });
  }

  /// [quiet]: a live refresh. The list stays on screen while it loads, and
  /// a failure keeps what is shown rather than replacing it with an error.
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await repository.fetchMarketplaceItems();
      final member = await _freshMember();
      if (!mounted) return;
      setState(() {
        _items = items;
        _member = member;
        _loading = false;
        // Drop what sold out or went away since it was added, and keep
        // the rest within what is left.
        final stock = {for (final i in items) i.id: i.stock};
        _cart.removeWhere((id, _) => (stock[id] ?? 0) <= 0);
        _cart.updateAll((id, q) => q.clamp(1, stock[id]!));
      });
    } catch (_) {
      if (!mounted || quiet) return;
      setState(() {
        _error = 'Could not load the marketplace. Please try again.';
        _loading = false;
      });
    }
  }

  int get _cartCount => _cart.values.fold(0, (sum, q) => sum + q);

  void _setQty(Item item, int q) {
    final id = item.id;
    if (id == null) return;
    setState(() {
      if (q <= 0 || item.stock <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = q.clamp(1, item.stock);
      }
    });
  }

  /// Fetch the member's current profile record so checkout always uses the
  /// latest saved location — no live GPS fetch or permission prompt here.
  Future<Member> _freshMember() async {
    final id = widget.member.id;
    if (id == null) return widget.member;
    try {
      return await repository.getMemberById(id) ?? widget.member;
    } catch (_) {
      return widget.member;
    }
  }

  bool _hasSavedLocation(Member member) =>
      member.latitude != null && member.longitude != null;

  Future<void> _changeLocation() async {
    final updated = await showDialog<Member>(
      context: context,
      builder: (_) => _LocationPickerDialog(member: _member),
    );
    if (updated != null && mounted) setState(() => _member = updated);
  }

  Future<void> _openReview() async {
    final lines = [
      for (final e in _cart.entries)
        if (_items.any((i) => i.id == e.key))
          (item: _items.firstWhere((i) => i.id == e.key), quantity: e.value),
    ];
    if (lines.isEmpty) return;

    var member = await _freshMember();
    if (!mounted) return;
    // No saved location yet: one is needed before ordering.
    if (!_hasSavedLocation(member)) {
      final updated = await showDialog<Member>(
        context: context,
        builder: (_) => _LocationPickerDialog(member: member),
      );
      if (!mounted) return;
      if (updated == null || !_hasSavedLocation(updated)) return;
      member = updated;
    }
    setState(() => _member = member);

    final placed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ReviewOrderPage(member: member, lines: lines),
      ),
    );
    if (placed == true) {
      if (!mounted) return;
      setState(_cart.clear);
      BotToast.showText(text: 'Order placed. The cashier will send the price.');
      widget.onOrderPlaced?.call();
    } else {
      // The review screen may have changed the address.
      final fresh = await _freshMember();
      if (mounted) setState(() => _member = fresh);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = ShopColors.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: StockpileFonts.satoshi(color: c.muted)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    return ColoredBox(
      color: c.ground,
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= 980 ? _wide(c) : _narrow(c),
      ),
    );
  }

  Widget _narrow(ShopColors c) {
    final shown = _filteredItems;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              children: [
                _addressButton(c),
                const SizedBox(height: 12),
                _search(c),
                const SizedBox(height: 12),
                _chips(c, scroll: true),
                if (!_tipHidden) ...[
                  const SizedBox(height: 12),
                  _tip(c, dismissible: true),
                ],
                const SizedBox(height: 14),
                _countLine(c, shown),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  _noResults(c)
                else
                  ShopCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: c.line),
                          _row(c, shown[i]),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        _footer(c),
      ],
    );
  }

  Widget _wide(ShopColors c) {
    final shown = _filteredItems;
    // A card is its picture, name, stock line and button; the two lines of
    // text grow with the person's text size setting.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardHeight = 236 + (15 + 12) * 1.4 * textScale;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            children: [
              Row(
                children: [
                  Expanded(child: _search(c)),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: _addressButton(c, compact: true),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _chips(c, scroll: false),
              const SizedBox(height: 14),
              _countLine(c, shown),
              const SizedBox(height: 10),
              if (shown.isEmpty)
                _noResults(c)
              else
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisExtent: cardHeight,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  children: [for (final item in shown) _card(c, item)],
                ),
            ],
          ),
        ),
        Container(
          width: 340,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(left: BorderSide(color: c.line)),
          ),
          child: _orderPanel(c),
        ),
      ],
    );
  }

  // ── Pieces ─────────────────────────────────────────────────────────

  Widget _addressButton(ShopColors c, {bool compact = false}) {
    final address = (_member.address ?? '').trim();
    final label = address.isEmpty ? 'Set your delivery location' : address;
    final pin = Container(
      width: compact ? 24 : 36,
      height: compact ? 24 : 36,
      alignment: Alignment.center,
      decoration: compact
          ? null
          : BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
      child: Icon(Icons.location_on_outlined, size: 18, color: c.accent),
    );
    return Semantics(
      button: true,
      label: 'Deliver to $label. Change',
      child: ShopCard(
        onTap: _changeLocation,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 13 : 10,
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              pin,
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: compact
                    ? Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StockpileFonts.satoshi(
                          fontSize: 14,
                          color: c.text,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Deliver to',
                            style: StockpileFonts.satoshi(
                              fontSize: 12,
                              color: c.muted,
                            ),
                          ),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: StockpileFonts.satoshi(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.text,
                            ),
                          ),
                        ],
                      ),
              ),
              if (!compact)
                Text(
                  'Change',
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.accentText,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _search(ShopColors c) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c.line),
    );
    return TextField(
      controller: _searchCtrl,
      onChanged: (q) => setState(() => _searchQuery = q),
      textInputAction: TextInputAction.search,
      style: StockpileFonts.satoshi(fontSize: 15, color: c.text),
      decoration: InputDecoration(
        hintText: 'Search products',
        prefixIcon: Icon(Icons.search_rounded, color: c.muted),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        filled: true,
        fillColor: c.soft,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _chips(ShopColors c, {required bool scroll}) {
    Widget chip(String label, String? value) {
      final on = _selectedCategory == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: Semantics(
          button: true,
          selected: on,
          child: Material(
            color: on ? c.text : c.surface,
            shape: StadiumBorder(side: BorderSide(color: on ? c.text : c.line)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => setState(() => _selectedCategory = value),
              // Sized to its label: in a Wrap, an aligned Container would
              // stretch to the full row.
              child: SizedBox(
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        color: on ? c.surface : c.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final chips = [
      chip('All', null),
      for (final cat in _categories) chip(cat, cat),
    ];
    if (_categories.isEmpty) return const SizedBox.shrink();
    return scroll
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: chips),
          )
        : Wrap(children: chips);
  }

  Widget _tip(ShopColors c, {required bool dismissible}) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 12, dismissible ? 4 : 14, 12),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: c.accentText,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              const TextSpan(
                children: [
                  TextSpan(
                    text: 'You see the price before you pay. ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text:
                        'The cashier prices your items after you order. You can '
                        'agree, or offer a different delivery fee.',
                  ),
                ],
              ),
              style: StockpileFonts.satoshi(
                fontSize: 13,
                height: 1.45,
                color: c.text,
              ),
            ),
          ),
          if (dismissible)
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
              onPressed: () => setState(() => _tipHidden = true),
            ),
        ],
      ),
    );
  }

  Widget _countLine(ShopColors c, List<Item> shown) {
    final n = shown.length;
    final out = shown.where((i) => i.stock <= 0).length;
    return Row(
      children: [
        Expanded(
          child: Text(
            [
              '$n product${n == 1 ? '' : 's'}',
              if (out > 0) '$out out of stock',
            ].join(' · '),
            style: StockpileFonts.satoshi(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.muted,
            ),
          ),
        ),
        Text(
          out > 0 ? 'In stock first, A to Z' : 'A to Z',
          style: StockpileFonts.satoshi(fontSize: 12, color: c.muted),
        ),
      ],
    );
  }

  /// A sold-out product's picture, faded so the eye skips it.
  Widget _faded(Item item, Widget child) =>
      item.stock <= 0 ? Opacity(opacity: 0.45, child: child) : child;

  Widget _noResults(ShopColors c) {
    final q = _searchQuery.trim();
    return ShopCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: c.muted),
          const SizedBox(height: 10),
          Text(
            _items.isEmpty
                ? 'Nothing is available right now.'
                : q.isEmpty
                ? 'Nothing in this category right now.'
                : "No products match '$q'.",
            textAlign: TextAlign.center,
            style: StockpileFonts.satoshi(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _clearSearch,
              child: const Text('Show all products'),
            ),
          ],
        ],
      ),
    );
  }

  String _stockLine(Item item) {
    final cat = (item.category ?? '').trim();
    if (item.stock <= 0) return cat;
    if (item.stock <= _lowStock) return 'Only ${item.stock} left';
    return [if (cat.isNotEmpty) cat, '${item.stock} in stock'].join(' · ');
  }

  Widget _subLine(ShopColors c, Item item) {
    final low = item.stock > 0 && item.stock <= _lowStock;
    return Text(
      _stockLine(item),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: StockpileFonts.satoshi(
        fontSize: 12,
        fontWeight: low ? FontWeight.w600 : FontWeight.w400,
        color: low ? c.accentText : c.muted,
      ),
    );
  }

  /// "Add", or the count with − and + once it is in the order. At one, the
  /// minus is a bin: the next tap takes it out.
  Widget _picker(ShopColors c, Item item, {bool wide = false}) {
    final q = _cart[item.id] ?? 0;
    if (item.stock <= 0) {
      return Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          'Out of stock',
          style: StockpileFonts.satoshi(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.muted,
          ),
        ),
      );
    }
    if (q == 0) {
      return SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: () => _setQty(item, 1),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.accentText,
            side: BorderSide(color: c.accent),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
          ),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(wide ? 'Add to order' : 'Add'),
        ),
      );
    }
    Widget step(IconData icon, String label, VoidCallback? onTap) => IconButton(
      tooltip: label,
      onPressed: onTap,
      color: c.accentText,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: Icon(icon, size: 18),
    );
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: c.accentSoft,
        border: Border.all(color: c.accent),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          step(
            q == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
            q == 1 ? 'Remove' : 'One fewer',
            () => _setQty(item, q - 1),
          ),
          Text(
            wide ? '$q in order' : '$q',
            style: StockpileFonts.satoshi(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          step(
            Icons.add_rounded,
            'One more',
            q >= item.stock ? null : () => _setQty(item, q + 1),
          ),
        ],
      ),
    );
  }

  Widget _row(ShopColors c, Item item) {
    final out = item.stock <= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _faded(item, ProductTile(item.name, imagePath: item.imagePath, size: 56)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: StockpileFonts.satoshi(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: out ? c.muted : c.text,
                  ),
                ),
                const SizedBox(height: 2),
                _subLine(c, item),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _picker(c, item),
        ],
      ),
    );
  }

  Widget _card(ShopColors c, Item item) {
    final inOrder = (_cart[item.id] ?? 0) > 0;
    return ShopCard(
      borderColor: inOrder ? c.accent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _faded(item, ProductTile(item.name, imagePath: item.imagePath, height: 140)),
          const SizedBox(height: 12),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StockpileFonts.satoshi(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: item.stock <= 0 ? c.muted : c.text,
            ),
          ),
          const SizedBox(height: 2),
          _subLine(c, item),
          const Spacer(),
          _picker(c, item, wide: true),
        ],
      ),
    );
  }

  List<({Item item, int quantity})> get _lines => [
    for (final e in _cart.entries)
      if (_items.any((i) => i.id == e.key))
        (item: _items.firstWhere((i) => i.id == e.key), quantity: e.value),
  ];

  Widget _footer(ShopColors c) {
    final n = _cartCount;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  n == 0 ? 'No items yet' : '$n item${n == 1 ? '' : 's'}',
                  style: StockpileFonts.satoshi(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
                Text(
                  n == 0
                      ? 'Add products to start an order'
                      : 'Nothing to pay yet',
                  style: StockpileFonts.satoshi(fontSize: 12, color: c.muted),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: n == 0 ? null : _openReview,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Review order'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderPanel(ShopColors c) {
    final lines = _lines;
    final n = _cartCount;
    Widget row(String l, String r) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l,
              style: StockpileFonts.satoshi(fontSize: 14, color: c.muted),
            ),
          ),
          Text(
            r,
            style: StockpileFonts.satoshi(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your order',
            style: StockpileFonts.satoshi(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: lines.isEmpty
                ? Text(
                    'Add products and they appear here.',
                    style: StockpileFonts.satoshi(fontSize: 13, color: c.muted),
                  )
                : ListView(
                    children: [
                      for (final l in lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              ProductTile(
                                l.item.name,
                                imagePath: l.item.imagePath,
                                size: 36,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  l.item.name,
                                  style: StockpileFonts.satoshi(
                                    fontSize: 14,
                                    color: c.text,
                                  ),
                                ),
                              ),
                              Text(
                                '× ${l.quantity}',
                                style: StockpileFonts.satoshi(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: c.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          _tip(c, dismissible: false),
          const SizedBox(height: 8),
          row('Items', '$n'),
          row('To pay now', 'Nothing'),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: n == 0 ? null : _openReview,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Review order'),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Review & place order
// ═══════════════════════════════════════════════════════════════════════════

class _ReviewOrderPage extends StatefulWidget {
  final Member member;
  final List<({Item item, int quantity})> lines;

  const _ReviewOrderPage({required this.member, required this.lines});

  @override
  State<_ReviewOrderPage> createState() => _ReviewOrderPageState();
}

class _ReviewOrderPageState extends State<_ReviewOrderPage> {
  late Member _member;
  bool _submitting = false;

  /// Who takes the order at the door. Starts as the member; a relative at
  /// home is the usual reason to change it. The rider sees both fields.
  late final TextEditingController _receiverName;
  late final TextEditingController _receiverContact;

  String get _ownName =>
      '${widget.member.firstName ?? ''} ${widget.member.lastName ?? ''}'.trim();
  String get _ownContact => formatPhilippinePhone(widget.member.contactNo ?? '');

  @override
  void initState() {
    super.initState();
    _member = widget.member;
    _receiverName = TextEditingController(text: _ownName);
    _receiverContact = TextEditingController(text: _ownContact);
  }

  @override
  void dispose() {
    _receiverName.dispose();
    _receiverContact.dispose();
    super.dispose();
  }

  int get _count => widget.lines.fold(0, (n, l) => n + l.quantity);

  Future<void> _placeOrder() async {
    if (_submitting) return;

    final memberId = _member.id;
    final address = (_member.address ?? '').trim();
    if (memberId == null ||
        address.isEmpty ||
        _member.latitude == null ||
        _member.longitude == null) {
      BotToast.showText(text: 'Please set your delivery location first.');
      return;
    }

    // Explicit int keys, dropping any line whose product id is missing, so
    // the RPC never receives a null bigint.
    final items = <Map<String, dynamic>>[
      for (final line in widget.lines)
        if (line.item.id != null)
          {'product_id': line.item.id, 'quantity': line.quantity},
    ];
    if (items.isEmpty) {
      BotToast.showText(text: 'Your order is empty.');
      return;
    }

    // Always sent, even unchanged: the rider's screen reads the number
    // from the order, and without it they would have no one to call.
    final name = _receiverName.text.trim();
    final contact = _receiverContact.text.trim();
    if (name.isEmpty) {
      BotToast.showText(text: 'Please enter who will receive the order.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await repository.createDeliveryOrder(
        memberId: memberId,
        deliveryAddress: address,
        deliveryLatitude: _member.latitude,
        deliveryLongitude: _member.longitude,
        items: items,
        receiverName: name,
        receiverContact: contact.isEmpty ? null : contact,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      debugPrint('Place order RPC failed: ${e.message} ${e.details}');
      if (!mounted) return;
      BotToast.showText(text: _friendlyOrderError(e.message));
      setState(() => _submitting = false);
    } catch (e) {
      debugPrint('Place order failed unexpectedly: $e');
      if (!mounted) return;
      BotToast.showText(text: 'Could not place the order. Please try again.');
      setState(() => _submitting = false);
    }
  }

  /// Translate a raw PostgREST message into something the member can act on.
  String _friendlyOrderError(String raw) {
    final msg = raw.toLowerCase();
    if (msg.contains('check constraint') || msg.contains('null value')) {
      return 'Some order details are invalid. Please review your order and '
          'delivery address, then try again.';
    }
    if (msg.contains('permission') || msg.contains('rls')) {
      return 'You are not allowed to place this order.';
    }
    return 'Could not place the order. Please try again.';
  }

  Future<void> _editLocation() async {
    final updated = await showDialog<Member>(
      context: context,
      builder: (_) => _LocationPickerDialog(member: _member),
    );
    if (updated == null || !mounted) return;
    setState(() => _member = updated);
  }

  @override
  Widget build(BuildContext context) {
    final c = ShopColors.of(context);
    Widget title(String t) => Text(
      t,
      style: StockpileFonts.satoshi(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: c.text,
      ),
    );

    InputDecoration field(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: c.soft,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.line),
      ),
    );

    const steps = [
      'The cashier prices your items and says how it is sent: by rider, LBC '
          'or J&T. You get an alert.',
      'You agree to the total, or offer a different delivery fee.',
      'Pay from your Balance or Total Earnings, in cash to the rider, or (for '
          'LBC and J&T) outside the app.',
      'Your order arrives, and you confirm you received it.',
    ];

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: const Text('Review your order'),
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ShopCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: title('$_count item${_count == 1 ? '' : 's'}'),
                        ),
                        TextButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.pop(context, false),
                          child: const Text('Edit'),
                        ),
                      ],
                    ),
                    for (final l in widget.lines)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            ProductTile(
                              l.item.name,
                              imagePath: l.item.imagePath,
                              size: 36,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l.item.name,
                                style: StockpileFonts.satoshi(
                                  fontSize: 14,
                                  color: c.text,
                                ),
                              ),
                            ),
                            Text(
                              '× ${l.quantity}',
                              style: StockpileFonts.satoshi(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: c.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: c.line),
                    const SizedBox(height: 10),
                    Text(
                      'Prices: set by the cashier after you order',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ShopCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title('Deliver to'),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 20,
                          color: c.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (_member.address ?? '').trim().isEmpty
                                    ? 'No address on file'
                                    : _member.address!,
                                style: StockpileFonts.satoshi(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: c.text,
                                ),
                              ),
                              Text(
                                'Your order is sent to the pin on your map.',
                                style: StockpileFonts.satoshi(
                                  fontSize: 12,
                                  color: c.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _submitting ? null : _editLocation,
                      child: const Text('Change location'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ShopCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title('Who will receive it?'),
                    const SizedBox(height: 2),
                    Text(
                      'Change this if someone else will take the order at the door.',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Name',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _receiverName,
                      enabled: !_submitting,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: field('Receiver name'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Contact number',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _receiverContact,
                      enabled: !_submitting,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [PhilippinePhoneFormatter()],
                      textInputAction: TextInputAction.done,
                      decoration: field('Contact number'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title('What happens next'),
                    for (var i = 0; i < steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: i == 0 ? c.text : c.soft,
                                shape: BoxShape.circle,
                                border: i == 0
                                    ? null
                                    : Border.all(color: c.line),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: StockpileFonts.satoshi(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: i == 0 ? c.surface : c.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  steps[i],
                                  style: StockpileFonts.satoshi(
                                    fontSize: 14,
                                    height: 1.45,
                                    color: c.text,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: SafeArea(
          top: false,
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Nothing is charged now.',
                      textAlign: TextAlign.center,
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _submitting ? null : _placeOrder,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Place order'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A "Set / Edit delivery location" modal that reuses [LocationSelectionWidget].
///
/// Returns the updated [Member] (with the freshly saved location) when the
/// member confirms, or null when they cancel. The parent is responsible for
/// wiring the returned member into the checkout.
class _LocationPickerDialog extends StatefulWidget {
  final Member member;

  const _LocationPickerDialog({required this.member});

  @override
  State<_LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<_LocationPickerDialog> {
  final _picker = GlobalKey<LocationSelectionWidgetState>();
  bool _confirming = false;
  double? _lat;
  double? _lng;
  String? _address;

  @override
  void initState() {
    super.initState();
    _lat = widget.member.latitude;
    _lng = widget.member.longitude;
    _address = widget.member.address;
  }

  bool get _hasLocation => _lat != null && _lng != null;

  Future<SavedLocation?> _onLoad() async {
    final id = widget.member.id;
    if (id == null) return null;
    final m = await repository.getMemberById(id);
    if (m == null || m.latitude == null || m.longitude == null) return null;
    return SavedLocation(
      latitude: m.latitude!,
      longitude: m.longitude!,
      address: m.address,
      updatedAt: m.locationUpdatedAt,
    );
  }

  Future<void> _onSave(
    double latitude,
    double longitude,
    String address,
  ) async {
    final id = widget.member.id;
    if (id == null) return;
    await repository.updateMemberLocation(
      memberId: id,
      latitude: latitude,
      longitude: longitude,
      address: address,
    );
    if (!mounted) return;
    setState(() {
      _lat = latitude;
      _lng = longitude;
      _address = address;
    });
  }

  Future<void> _onClear() async {
    final id = widget.member.id;
    if (id == null) return;
    await repository.clearMemberLocation(memberId: id);
    if (!mounted) return;
    setState(() {
      _lat = null;
      _lng = null;
      _address = null;
    });
  }

  Future<void> _confirm() async {
    if (_confirming) return;
    // A pin moved or an address edited on the map counts even if the
    // member never tapped "Set my delivery location" (test R3).
    setState(() => _confirming = true);
    final saved = await _picker.currentState?.saveIfChanged() ?? true;
    if (!mounted) return;
    setState(() => _confirming = false);
    if (!saved) return;
    if (!_hasLocation) {
      BotToast.showText(text: 'Pick your delivery location on the map first.');
      return;
    }
    Member? fresh;
    final id = widget.member.id;
    if (id != null) {
      try {
        fresh = await repository.getMemberById(id);
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      fresh ??
          widget.member.copyWith(
            latitude: _lat,
            longitude: _lng,
            address: _address,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 32).clamp(280.0, 560.0).toDouble();
    final height = (size.height * 0.8).clamp(320.0, 640.0).toDouble();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Expanded(
              child: LocationSelectionWidget(
                key: _picker,
                scrollable: true,
                pinKind: MapPinKind.destination,
                title: 'Delivery Location',
                description:
                    'This is where your order will be delivered. The cashier '
                    'will see this address when they prepare your quote.',
                actionLabel: 'Set my delivery location',
                savedToast: 'Delivery location saved',
                approximateToast:
                    'Location saved (approximate, based on your IP address)',
                removeDialogTitle: 'Remove saved location?',
                removeDialogBody:
                    'Your saved delivery location will be cleared. You can '
                    'set it again at any time.',
                onLoad: _onLoad,
                onSave: _onSave,
                onClear: _onClear,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _confirming ? null : _confirm,
                    child: const Text('Use This Location'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
