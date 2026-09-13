// lib/pages/member/member_marketplace_tab.dart
// Member Marketplace — members browse available Cashier items (listed
// WITHOUT a fixed price: "Price set upon order"), build a cart, and submit
// a delivery order with status 'Order Placed'. No payment happens here.
//
// The member's saved location (latitude/longitude/address) is attached as
// the default delivery destination at checkout.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bot_toast/bot_toast.dart';
import '../../db/db.dart';
import '../../services/config_service.dart';
import '../../theme.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart' show formatMoney;
import '../../widgets/marketplace_search_bar.dart';
import '../../widgets/location_selection_widget.dart';

class MemberMarketplaceTab extends StatefulWidget {
  final Member member;

  const MemberMarketplaceTab({super.key, required this.member});

  @override
  State<MemberMarketplaceTab> createState() => _MemberMarketplaceTabState();
}

class _MemberMarketplaceTabState extends State<MemberMarketplaceTab> {
  bool _loading = true;
  String? _error;
  List<Item> _items = [];
  final Map<int, int> _cart = {}; // itemId -> quantity

  String _searchQuery = '';
  String? _selectedCategory; // null = "All"
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
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

  void _onSearchChanged(String query) {
    if (!mounted) return;
    setState(() => _searchQuery = query);
  }

  void _clearSearch() {
    _searchFocus.unfocus();
    _searchCtrl.clear();
    if (!mounted) return;
    setState(() => _searchQuery = '');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await repository.fetchMarketplaceItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the marketplace. Please try again.';
        _loading = false;
      });
    }
  }

  int get _cartCount => _cart.values.fold(0, (sum, q) => sum + q);

  int _available(int itemId) => _items.firstWhere((i) => i.id == itemId).stock;

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

  /// "Set Location" modal — reused when the member has no saved location yet
  /// and from the checkout's "Edit Location" action.
  Future<Member?> _promptSetLocation(Member member) {
    return showDialog<Member>(
      context: context,
      builder: (_) => _LocationPickerDialog(member: member),
    );
  }

  Future<void> _openCheckout() async {
    final lines = _cart.entries
        .map(
          (e) => (
            item: _items.firstWhere((i) => i.id == e.key),
            quantity: e.value,
          ),
        )
        .toList();

    // Resolve the latest saved profile location (no live GPS work here).
    var member = await _freshMember();
    if (!mounted) return;

    // Fallback: no saved location yet — require one before ordering.
    if (!_hasSavedLocation(member)) {
      final updated = await _promptSetLocation(member);
      if (!mounted) return;
      if (updated == null || !_hasSavedLocation(updated)) return;
      member = updated;
    }

    if (!mounted) return;
    final placed = await showDialog<bool>(
      context: context,
      builder: (_) => _CheckoutDialog(member: member, lines: lines),
    );
    if (placed == true) {
      if (!mounted) return;
      setState(_cart.clear);
      BotToast.showText(text: 'Order placed — the cashier will send a quote.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: StockpileFonts.satoshi(color: muted)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── Search bar (sticky at the top) ──────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: MarketplaceSearchBar(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            onSearchChanged: _onSearchChanged,
          ),
        ),
        // ── Category filter chips ───────────────────────────────────
        if (_categories.isNotEmpty) _buildCategoryChips(),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: StockpileColors.primary900.withAlpha(18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: StockpileColors.primary900,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Product prices are set by the cashier when your order '
                    'arrives. Only the delivery fee is negotiable.',
                    style: StockpileFonts.satoshi(fontSize: 13, color: text),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: _buildResults(isDark)),
        _buildCartBar(isDark),
      ],
    );
  }

  /// Category chips row — "All" plus one chip per distinct category.
  Widget _buildCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: _selectedCategory == null,
            onSelected: (_) => setState(() => _selectedCategory = null),
          ),
          for (final category in _categories) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(category),
              selected: _selectedCategory == category,
              onSelected: (_) => setState(() => _selectedCategory = category),
            ),
          ],
        ],
      ),
    );
  }

  /// The item list, or the appropriate empty state.
  Widget _buildResults(bool isDark) {
    final filtered = _filteredItems;
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'No items are available right now.',
          style: StockpileFonts.satoshi(
            color: isDark
                ? StockpileColors.darkTextMuted
                : StockpileColors.mutedText,
          ),
        ),
      );
    }
    if (filtered.isEmpty) {
      return _NoResultsEmptyState(
        query: _searchQuery.trim(),
        onClear: _clearSearch,
      );
    }
    return ListView.builder(
      // Dismiss the keyboard as the member scrolls through results.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _buildItemCard(filtered[index], isDark),
    );
  }

  Widget _buildItemCard(Item item, bool isDark) {
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final inCart = _cart[item.id] ?? 0;

    return Card(
      elevation: 0,
      color: surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: StockpileFonts.satoshi(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: text,
                    ),
                  ),
                  if ((item.category ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.category!,
                      style: StockpileFonts.satoshi(fontSize: 12, color: muted),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'Price set upon order · ${item.stock} in stock',
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      color: StockpileColors.primary900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _QtyStepper(
              quantity: inCart,
              max: item.stock,
              onChanged: (q) {
                final available = _available(item.id!);
                setState(() {
                  if (q <= 0) {
                    _cart.remove(item.id);
                  } else {
                    _cart[item.id!] = q.clamp(0, available);
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartBar(bool isDark) {
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: surface,
        border: Border(
          top: BorderSide(
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _cartCount == 0
                  ? 'Your cart is empty'
                  : '$_cartCount item${_cartCount == 1 ? '' : 's'} in cart',
              style: StockpileFonts.satoshi(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _cartCount == 0 ? null : _openCheckout,
            icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
            label: const Text('Checkout'),
          ),
        ],
      ),
    );
  }
}

/// Zero-result empty state: names the query and offers a one-tap reset.
class _NoResultsEmptyState extends StatelessWidget {
  final String query;
  final VoidCallback onClear;

  const _NoResultsEmptyState({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Center(
      child: Card(
        elevation: 0,
        color: surface,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 44, color: muted),
              const SizedBox(height: 12),
              Text(
                "No items found for '$query'",
                textAlign: TextAlign.center,
                style: StockpileFonts.satoshi(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Try a different search term or category.',
                textAlign: TextAlign.center,
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('Clear Search'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int quantity;
  final int max;
  final ValueChanged<int> onChanged;

  const _QtyStepper({
    required this.quantity,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepBtn(
          Icons.remove_rounded,
          () => onChanged(quantity - 1),
          enabled: quantity > 0,
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 28),
          alignment: Alignment.center,
          child: Text(
            '$quantity',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        _stepBtn(
          Icons.add_rounded,
          () => onChanged(quantity + 1),
          enabled: quantity < max,
        ),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap, {required bool enabled}) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _CheckoutDialog extends StatefulWidget {
  final Member member;
  final List<({Item item, int quantity})> lines;

  const _CheckoutDialog({required this.member, required this.lines});

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  late Member _member;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _member = widget.member;
  }

  Future<void> _placeOrder() async {
    if (_submitting) return;
    if (_member.latitude == null || _member.longitude == null) {
      BotToast.showText(text: 'Set a delivery location to continue.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final memberId = _member.id;
      if (memberId == null) throw Exception('Member id missing');
      await repository.createDeliveryOrder(
        memberId: memberId,
        deliveryAddress: _member.address,
        deliveryLatitude: _member.latitude,
        deliveryLongitude: _member.longitude,
        items: [
          for (final line in widget.lines)
            {'product_id': line.item.id, 'quantity': line.quantity},
        ],
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not place the order. Please try again.');
      setState(() => _submitting = false);
    }
  }

  Future<void> _editLocation() async {
    final updated = await showDialog<Member>(
      context: context,
      builder: (_) => _LocationPickerDialog(member: _member),
    );
    if (updated == null || !mounted) return;
    setState(() => _member = updated);
  }

  /// "Delivering To" confirmation card — the saved profile address with an
  /// inline "Edit Location" action.
  Widget _buildDeliveryCard(
    bool isDark,
    Color surface,
    Color text,
    Color muted,
  ) {
    final address = (_member.address ?? '').trim();
    final lat = _member.latitude;
    final lng = _member.longitude;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_shipping_outlined,
                size: 18,
                color: StockpileColors.primary900,
              ),
              const SizedBox(width: 8),
              Text(
                'Delivering To',
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            address.isEmpty ? 'No address on file' : address,
            style: StockpileFonts.satoshi(fontSize: 14, color: text),
          ),
          if (lat != null && lng != null) ...[
            const SizedBox(height: 4),
            Text(
              '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
              style: StockpileFonts.satoshi(fontSize: 11, color: muted),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _submitting ? null : _editLocation,
              icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
              label: const Text('Edit Location'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final currency = context.watch<ConfigService>().currencySymbol;

    return AlertDialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Review your order',
        style: StockpileFonts.satoshi(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Items',
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
              const SizedBox(height: 8),
              for (final line in widget.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${line.item.name} × ${line.quantity}',
                          style: StockpileFonts.satoshi(
                            fontSize: 14,
                            color: text,
                          ),
                        ),
                      ),
                      Text(
                        'Price set upon order',
                        style: StockpileFonts.satoshi(
                          fontSize: 12,
                          color: StockpileColors.primary900,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              _buildDeliveryCard(isDark, surface, text, muted),
              const SizedBox(height: 16),
              Text(
                'No payment now. The cashier will price your items and send '
                'a quote (${formatMoney(0, symbol: currency)} due until then).',
                style: StockpileFonts.satoshi(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _placeOrder,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Place Order'),
        ),
      ],
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
                scrollable: true,
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
                    onPressed: _hasLocation ? _confirm : null,
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
