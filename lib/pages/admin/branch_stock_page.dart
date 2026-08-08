// lib/pages/admin/branch_stock_page.dart
// Admin / main-cashier screen for the two-tier stock system.
//   • Give central stock to a branch cashier (deducts central, adds to branch).
//   • See every branch cashier's on-hand allocation.
//   • Return stock to central, or adjust (correct) a branch count.
//   • Audit trail of all transfers.
// All mutations go through SECURITY DEFINER RPCs (see migration_v30_branch_stock).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';

class BranchStockPage extends StatefulWidget {
  const BranchStockPage({super.key});

  @override
  State<BranchStockPage> createState() => _BranchStockPageState();
}

class _BranchStockPageState extends State<BranchStockPage> {
  bool _loading = true;
  String? _loadError;

  List<Map<String, dynamic>> _cashiers = []; // {id, username}
  List<Item> _central = []; // central items (for give-out picker)
  List<Map<String, dynamic>> _branchRows = []; // branch_stock_view rows
  List<Map<String, dynamic>> _transfers = []; // stock_transfers

  // Give-out form
  String? _giveCashierId;
  int? _giveItemId;
  final _qtyCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _giving = false;

  // Branch allocations: search + expand-all toggle so a long list stays compact.
  final _branchSearchCtrl = TextEditingController();
  String _branchSearch = '';
  bool _expandAll = false;

  // Which section is showing: 0 = Give Stock, 1 = Allocations, 2 = Transfers.
  int _section = 0;

  // Transfers: server-side paginated + filtered so history stays bounded.
  static const int _transferPageSize = 30;
  String? _transferFilterOwner; // to_owner_id, null = all branches
  String? _transferFilterType; // give_out | return | adjust, null = all
  int _transferOffset = 0;
  bool _transfersHasMore = false;
  bool _transfersLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    _branchSearchCtrl.dispose();
    super.dispose();
  }

  // ── Theme helpers ───────────────────────────────────────────────────────────
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _surface =>
      _isDark ? StockpileColors.darkSurface : StockpileColors.surface;
  Color get _textPrimary =>
      _isDark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
  Color get _textMuted =>
      _isDark ? StockpileColors.darkTextMuted : StockpileColors.mutedText;
  Color get _border =>
      _isDark ? StockpileColors.darkDivider : StockpileColors.divider;
  Color get _inputFill =>
      _isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg;

  // ── Data ────────────────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final cashiers = await repository.listBranchCashiers();
      final central = await repository.fetchItems();
      final branchRows = await repository.fetchAllBranchStock();
      if (!mounted) return;
      central
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() {
        _cashiers = cashiers;
        _central = central;
        _branchRows = branchRows;
        _loading = false;
      });
      await _loadTransfers(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  /// Loads a page of transfers with the current filters. [reset] starts over
  /// from the newest row (used on first load, refresh, or a filter change);
  /// otherwise it appends the next page ("Load more").
  Future<void> _loadTransfers({bool reset = false}) async {
    if (_transfersLoadingMore) return;
    setState(() => _transfersLoadingMore = true);
    final offset = reset ? 0 : _transferOffset;
    try {
      final page = await repository.fetchStockTransfers(
        ownerId: _transferFilterOwner,
        transferType: _transferFilterType,
        limit: _transferPageSize,
        offset: offset,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _transfers = page;
        } else {
          _transfers.addAll(page);
        }
        _transferOffset = offset + page.length;
        _transfersHasMore = page.length == _transferPageSize;
        _transfersLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _transfersLoadingMore = false);
      _snack(_cleanError(e), error: true);
    }
  }

  String _usernameFor(String? ownerId) {
    final m = _cashiers.firstWhere(
      (c) => c['id']?.toString() == ownerId,
      orElse: () => const {},
    );
    return (m['username']?.toString() ?? 'Unknown');
  }

  Item? get _selectedItem {
    if (_giveItemId == null) return null;
    for (final i in _central) {
      if (i.id == _giveItemId) return i;
    }
    return null;
  }

  int? get _selectedCentralStock => _selectedItem?.stock;

  String? get _qtyError {
    final txt = _qtyCtrl.text.trim();
    if (txt.isEmpty) return null;
    final q = int.tryParse(txt);
    if (q == null || q <= 0) return 'Enter a positive number';
    final avail = _selectedCentralStock;
    if (avail != null && q > avail) return 'Only $avail available in central';
    return null;
  }

  bool get _canGive {
    if (_giveCashierId == null || _giveItemId == null) return false;
    final q = int.tryParse(_qtyCtrl.text.trim());
    if (q == null || q <= 0) return false;
    final avail = _selectedCentralStock;
    if (avail != null && q > avail) return false;
    return true;
  }

  String _cleanError(Object e) {
    final s = e.toString();
    final marker = RegExp(r'message:\s*(.+?)(,\s*code:|\}|$)');
    final match = marker.firstMatch(s);
    return match != null ? match.group(1)!.trim() : s;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? StockpileColors.danger : StockpileColors.success,
        content: Row(
          children: [
            Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(msg, style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Future<void> _give() async {
    final ownerId = _giveCashierId;
    final itemId = _giveItemId;
    final qty = int.tryParse(_qtyCtrl.text.trim());
    if (ownerId == null) return _snack('Select a branch cashier.', error: true);
    if (itemId == null) return _snack('Select an item.', error: true);
    if (qty == null || qty <= 0) {
      return _snack('Enter a valid quantity.', error: true);
    }
    setState(() => _giving = true);
    try {
      await repository.transferStockToBranch(
        itemId: itemId,
        ownerId: ownerId,
        quantity: qty,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      _qtyCtrl.clear();
      _noteCtrl.clear();
      _snack('Stock given to ${_usernameFor(ownerId)}.');
      await _loadAll();
    } catch (e) {
      _snack(_cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _giving = false);
    }
  }

  Future<void> _return(String ownerId, Map<String, dynamic> row) async {
    final current = (row['stock'] as num?)?.toInt() ?? 0;
    final qty = await _promptQuantity(
      title: 'Return to central',
      message: '${row['name']} — branch has $current. How many to return?',
      initial: current,
      max: current,
    );
    if (qty == null) return;
    try {
      await repository.returnBranchStock(
        itemId: (row['id'] as num).toInt(),
        ownerId: ownerId,
        quantity: qty,
      );
      _snack('Returned $qty × ${row['name']} to central.');
      await _loadAll();
    } catch (e) {
      _snack(_cleanError(e), error: true);
    }
  }

  Future<void> _adjust(String ownerId, Map<String, dynamic> row) async {
    final current = (row['stock'] as num?)?.toInt() ?? 0;
    final qty = await _promptQuantity(
      title: 'Adjust branch count',
      message: '${row['name']} — set the branch\'s on-hand count '
          '(currently $current). Central stock is not affected.',
      initial: current,
    );
    if (qty == null) return;
    try {
      await repository.adjustBranchStock(
        itemId: (row['id'] as num).toInt(),
        ownerId: ownerId,
        newQuantity: qty,
      );
      _snack('${row['name']} set to $qty for ${_usernameFor(ownerId)}.');
      await _loadAll();
    } catch (e) {
      _snack(_cleanError(e), error: true);
    }
  }

  Future<int?> _promptQuantity({
    required String title,
    required String message,
    required int initial,
    int? max,
  }) async {
    final ctrl = TextEditingController(text: initial.toString());
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: StockpileFonts.satoshi(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: TextStyle(color: _textMuted, height: 1.4)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: _deco('Quantity'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v < 0) return;
              if (max != null && v > max) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  // ── Reusable UI pieces ──────────────────────────────────────────────────────
  InputDecoration _deco(String label,
      {String? helper, String? error, Widget? suffix, IconData? prefix}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      errorText: error,
      prefixIcon: prefix != null ? Icon(prefix, size: 20) : null,
      suffixIcon: suffix,
      isDense: true,
      filled: true,
      fillColor: _inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: StockpileColors.primary900, width: 1.6),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        padding: padding ?? const EdgeInsets.all(18),
        child: child,
      );

  Widget _cardHeader(IconData icon, Color color, String title, String sub) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withAlpha(28),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: StockpileFonts.satoshi(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary)),
                const SizedBox(height: 2),
                Text(sub,
                    style: StockpileFonts.satoshi(
                        fontSize: 12.5, color: _textMuted)),
              ],
            ),
          ),
        ],
      );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 44, color: _textMuted),
              const SizedBox(height: 12),
              Text('Could not load branch stock',
                  style: StockpileFonts.satoshi(
                      fontWeight: FontWeight.w700, color: _textPrimary)),
              const SizedBox(height: 6),
              Text(_loadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textMuted, fontSize: 12)),
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: _loadAll,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
                ),
                segments: [
                  const ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.local_shipping_rounded, size: 18),
                    label: Text('Give Stock'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: Text('Allocations (${_cashiers.length})'),
                  ),
                  const ButtonSegment(
                    value: 2,
                    icon: Icon(Icons.history_rounded, size: 18),
                    label: Text('Transfers'),
                  ),
                ],
                selected: {_section},
                onSelectionChanged: (s) => setState(() => _section = s.first),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: _border),
        Expanded(child: _sectionBody()),
      ],
    );
  }

  Widget _sectionBody() {
    switch (_section) {
      case 1:
        return RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _allocationsHeader(),
              const SizedBox(height: 12),
              if (_cashiers.isEmpty)
                _emptyState(Icons.groups_2_rounded,
                    'No branch cashier accounts yet',
                    'Create one in User Management to start allocating stock.')
              else
                ..._buildBranchList(),
            ],
          ),
        );
      case 2:
        return RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [_transfersSection()],
          ),
        );
      default:
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [_giveOutCard()],
        );
    }
  }

  Widget _emptyState(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(icon, size: 42, color: _textMuted),
            const SizedBox(height: 12),
            Text(title,
                style: StockpileFonts.satoshi(
                    fontWeight: FontWeight.w700, color: _textPrimary)),
            const SizedBox(height: 4),
            Text(sub,
                textAlign: TextAlign.center,
                style: TextStyle(color: _textMuted, fontSize: 12.5)),
          ],
        ),
      );

  // ── Give-out ────────────────────────────────────────────────────────────────
  Widget _giveOutCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.local_shipping_rounded, StockpileColors.primary900,
              'Give stock to a branch',
              'Move central stock into a branch cashier’s allocation.'),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 620;
              final cashierField = DropdownButtonFormField<String>(
                initialValue: _giveCashierId,
                isExpanded: true,
                decoration: _deco('Branch cashier',
                    prefix: Icons.person_outline_rounded),
                items: _cashiers
                    .map((c) => DropdownMenuItem(
                          value: c['id']?.toString(),
                          child: Text(c['username']?.toString() ?? '—'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _giveCashierId = v),
              );
              final itemField = DropdownButtonFormField<int>(
                initialValue: _giveItemId,
                isExpanded: true,
                decoration: _deco('Item',
                    prefix: Icons.inventory_2_outlined,
                    helper: _giveItemId == null
                        ? 'Pick an item to give'
                        : 'Central stock available: ${_selectedCentralStock ?? 0}'),
                selectedItemBuilder: (ctx) => _central
                    .where((i) => i.id != null)
                    .map((i) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(i.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                items: _central
                    .where((i) => i.id != null)
                    .map((i) => DropdownMenuItem<int>(
                          value: i.id!,
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(i.name,
                                      overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              _StockChip(stock: i.stock),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _giveItemId = v),
              );
              return Column(
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cashierField),
                        const SizedBox(width: 12),
                        Expanded(child: itemField),
                      ],
                    )
                  else ...[
                    cashierField,
                    const SizedBox(height: 14),
                    itemField,
                  ],
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: _qtyCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: _deco('Quantity',
                              error: _qtyError,
                              helper: _selectedCentralStock != null
                                  ? 'Max $_selectedCentralStock'
                                  : null,
                              suffix: (_selectedCentralStock != null &&
                                      _qtyError == null &&
                                      _qtyCtrl.text.trim().isNotEmpty)
                                  ? const Icon(Icons.check_circle_rounded,
                                      color: StockpileColors.success, size: 20)
                                  : null),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _noteCtrl,
                          decoration: _deco('Note (optional)',
                              prefix: Icons.sticky_note_2_outlined),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          _givePreview(),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: (_giving || !_canGive) ? null : _give,
              icon: _giving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_giving ? 'Giving…' : 'Give Stock',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  /// Live "you're about to give …" banner, shown only when the form is valid.
  Widget _givePreview() {
    if (!_canGive) return const SizedBox.shrink();
    final item = _selectedItem!;
    final qty = int.parse(_qtyCtrl.text.trim());
    final after = item.stock - qty;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: StockpileColors.primary900.withAlpha(_isDark ? 30 : 18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: StockpileColors.primary900.withAlpha(60)),
        ),
        child: Row(
          children: [
            const Icon(Icons.playlist_add_check_circle_rounded,
                color: StockpileColors.primary900, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: StockpileFonts.satoshi(
                      fontSize: 13, color: _textPrimary, height: 1.35),
                  children: [
                    const TextSpan(text: 'Give '),
                    TextSpan(
                        text: '$qty × ${item.name}',
                        style:
                            const TextStyle(fontWeight: FontWeight.w800)),
                    const TextSpan(text: ' to '),
                    TextSpan(
                        text: _usernameFor(_giveCashierId),
                        style:
                            const TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(
                        text: '   ·   central ${item.stock} → $after',
                        style: TextStyle(color: _textMuted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Allocations ─────────────────────────────────────────────────────────────
  Widget _allocationsHeader() {
    return Row(
      children: [
        Expanded(
          child: Text('Branch allocations',
              style: StockpileFonts.satoshi(
                  fontSize: 16, fontWeight: FontWeight.w800, color: _textPrimary)),
        ),
        if (_cashiers.length > 1)
          TextButton.icon(
            style: TextButton.styleFrom(
                foregroundColor: StockpileColors.primary900,
                visualDensity: VisualDensity.compact),
            onPressed: () => setState(() => _expandAll = !_expandAll),
            icon: Icon(
                _expandAll
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                size: 18),
            label: Text(_expandAll ? 'Collapse all' : 'Expand all'),
          ),
      ],
    );
  }

  List<Widget> _buildBranchList() {
    final term = _branchSearch.trim().toLowerCase();
    final filtered = term.isEmpty
        ? _cashiers
        : _cashiers
            .where((c) =>
                (c['username']?.toString().toLowerCase() ?? '').contains(term))
            .toList();

    return [
      if (_cashiers.length > 4)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _branchSearchCtrl,
            onChanged: (v) => setState(() => _branchSearch = v),
            decoration: _deco('Search branch cashier…',
                prefix: Icons.search_rounded,
                suffix: _branchSearch.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _branchSearchCtrl.clear();
                          setState(() => _branchSearch = '');
                        },
                      )),
          ),
        ),
      if (filtered.isEmpty)
        _emptyState(Icons.search_off_rounded, 'No match',
            'No branch cashier matches “$_branchSearch”.')
      else
        ...filtered.map(_branchSection),
    ];
  }

  Widget _branchSection(Map<String, dynamic> cashier) {
    final ownerId = cashier['id']?.toString() ?? '';
    final username = cashier['username']?.toString() ?? '—';
    final rows = _branchRows
        .where((r) => r['owner_id']?.toString() == ownerId)
        .toList()
      ..sort((a, b) => (a['name']?.toString() ?? '')
          .toLowerCase()
          .compareTo((b['name']?.toString() ?? '').toLowerCase()));

    final totalUnits =
        rows.fold<int>(0, (s, r) => s + ((r['stock'] as num?)?.toInt() ?? 0));
    final outCount =
        rows.where((r) => ((r['stock'] as num?)?.toInt() ?? 0) <= 0).length;
    final lowCount =
        rows.where((r) => r['status']?.toString() == 'Low Stock').length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Kill the ExpansionTile's default divider lines.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('branch_${ownerId}_$_expandAll'),
          initiallyExpanded: _expandAll,
          maintainState: true,
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: StockpileColors.primary900.withAlpha(30),
            child: Text(
              username.isNotEmpty ? username[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: StockpileColors.primary900),
            ),
          ),
          title: Text(username,
              style: StockpileFonts.satoshi(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: _textPrimary)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Pill('${rows.length} items', _textMuted),
                _Pill('$totalUnits units', StockpileColors.primary900),
                if (lowCount > 0)
                  _Pill('$lowCount low', Colors.orange.shade700),
                if (outCount > 0) _Pill('$outCount out', StockpileColors.danger),
              ],
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          children: rows.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No stock assigned yet.',
                          style: TextStyle(color: _textMuted, fontSize: 13)),
                    ),
                  ),
                ]
              : [
                  Divider(height: 1, color: _border),
                  const SizedBox(height: 4),
                  ...rows.map((r) => _branchRowTile(ownerId, r)),
                ],
        ),
      ),
    );
  }

  Widget _branchRowTile(String ownerId, Map<String, dynamic> r) {
    final qty = (r['stock'] as num?)?.toInt() ?? 0;
    final status = r['status']?.toString() ?? 'Good';
    final color = status == 'Out of Stock'
        ? StockpileColors.danger
        : (status == 'Low Stock' ? Colors.orange.shade700 : StockpileColors.success);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r['name']?.toString() ?? '—',
                    style: StockpileFonts.satoshi(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: _textPrimary)),
                Text(r['category']?.toString() ?? 'Uncategorized',
                    style: TextStyle(fontSize: 11.5, color: _textMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withAlpha(24),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$qty',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: color, fontSize: 14)),
                const SizedBox(width: 6),
                Text(status,
                    style: TextStyle(
                        fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _actionIcon(Icons.undo_rounded, 'Return to central',
              () => _return(ownerId, r)),
          _actionIcon(
              Icons.tune_rounded, 'Adjust count', () => _adjust(ownerId, r)),
        ],
      ),
    );
  }

  Widget _actionIcon(IconData icon, String tip, VoidCallback onTap) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 19, color: _textMuted),
        onPressed: onTap,
      );

  // ── Transfers ───────────────────────────────────────────────────────────────
  Widget _transfersSection() {
    final hasFilter =
        _transferFilterOwner != null || _transferFilterType != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Recent transfers',
                style: StockpileFonts.satoshi(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary)),
            const Spacer(),
            if (hasFilter)
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: StockpileColors.primary900,
                    visualDensity: VisualDensity.compact),
                onPressed: () {
                  setState(() {
                    _transferFilterOwner = null;
                    _transferFilterType = null;
                  });
                  _loadTransfers(reset: true);
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [_branchFilterChip(), _typeFilterChip()],
        ),
        const SizedBox(height: 14),
        if (_transfers.isEmpty)
          _transfersLoadingMore
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _emptyState(
                  Icons.history_rounded,
                  hasFilter ? 'No matching transfers' : 'No transfers yet',
                  hasFilter
                      ? 'Try clearing the filters.'
                      : 'Give stock to a branch and it will appear here.')
        else ...[
          _card(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < _transfers.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: _border),
                  _transferTile(_transfers[i]),
                ],
              ],
            ),
          ),
          if (_transfersHasMore)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed:
                      _transfersLoadingMore ? null : () => _loadTransfers(),
                  icon: _transfersLoadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.expand_more_rounded, size: 18),
                  label:
                      Text(_transfersLoadingMore ? 'Loading…' : 'Load more'),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _branchFilterChip() {
    return PopupMenuButton<String>(
      onSelected: (v) {
        setState(() => _transferFilterOwner = v == '__all__' ? null : v);
        _loadTransfers(reset: true);
      },
      itemBuilder: (_) => [
        const PopupMenuItem<String>(
            value: '__all__', child: Text('All branches')),
        ..._cashiers.map((c) => PopupMenuItem<String>(
              value: c['id']?.toString() ?? '__all__',
              child: Text(c['username']?.toString() ?? '—'),
            )),
      ],
      child: _filterPill(Icons.storefront_rounded, 'Branch',
          _transferFilterOwner == null ? 'All' : _usernameFor(_transferFilterOwner)),
    );
  }

  Widget _typeFilterChip() {
    const labels = {
      'give_out': 'Give out',
      'return': 'Return',
      'adjust': 'Adjust',
    };
    return PopupMenuButton<String>(
      onSelected: (v) {
        setState(() => _transferFilterType = v == '__all__' ? null : v);
        _loadTransfers(reset: true);
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(value: '__all__', child: Text('All types')),
        PopupMenuItem<String>(value: 'give_out', child: Text('Give out')),
        PopupMenuItem<String>(value: 'return', child: Text('Return')),
        PopupMenuItem<String>(value: 'adjust', child: Text('Adjust')),
      ],
      child: _filterPill(Icons.category_rounded, 'Type',
          labels[_transferFilterType] ?? 'All'),
    );
  }

  Widget _filterPill(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: _inputFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: _textMuted),
            const SizedBox(width: 7),
            Text('$label: ',
                style: TextStyle(color: _textMuted, fontSize: 12.5)),
            Text(value,
                style: StockpileFonts.satoshi(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: _textPrimary)),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, size: 18, color: _textMuted),
          ],
        ),
      );

  Widget _transferTile(Map<String, dynamic> t) {
    final type = t['transfer_type']?.toString() ?? 'give_out';
    final qty = (t['quantity'] as num?)?.toInt() ?? 0;
    final when = DateTime.tryParse(t['created_at']?.toString() ?? '');
    final note = t['note']?.toString();
    final (icon, tint, label) = switch (type) {
      'return' => (Icons.undo_rounded, Colors.orange.shade700, 'Return'),
      'adjust' => (Icons.tune_rounded, Colors.blue.shade600, 'Adjust'),
      _ => (Icons.local_shipping_rounded, StockpileColors.success, 'Give out'),
    };
    final sign = qty > 0 ? '+$qty' : '$qty';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: tint.withAlpha(28),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: tint, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(t['item_name']?.toString() ?? '—',
                          style: StockpileFonts.satoshi(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: _textPrimary)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: tint.withAlpha(24),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(sign,
                          style: TextStyle(
                              color: tint,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$label → ${_usernameFor(t['to_owner_id']?.toString())}'
                  '${note != null && note.isNotEmpty ? '  ·  $note' : ''}',
                  style: TextStyle(fontSize: 12, color: _textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            when != null ? DateFormat('MMM d\nh:mm a').format(when.toLocal()) : '',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 10.5, color: _textMuted, height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// Small colored pill (label + color) used for branch stat chips.
class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// Small colored pill showing an item's central stock in the give-out picker.
class _StockChip extends StatelessWidget {
  final int stock;
  const _StockChip({required this.stock});

  @override
  Widget build(BuildContext context) {
    final out = stock <= 0;
    final color = out ? StockpileColors.danger : StockpileColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        out ? 'Out of stock' : '$stock in stock',
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
