// lib/widgets/transactionstable.dart
//
// Transactions, as redesigned 2026-10-04 (canvas "Staff Tables Redesign"):
// a date range (Today by default) with its sales count and money; chips for
// Counter, Delivery and Branch sales; and one row per checkout showing
// when, who bought, what, who sold it, how it was paid and the total. A row
// opens the receipt; ⋯ holds Edit and Delete. On a phone the checkouts are
// grouped by day, and Sell floats bottom-right.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/modal_kit.dart' show confirmDestructive;
import 'package:lzcas/widgets/product_tile.dart';
import 'package:lzcas/widgets/staff_table.dart';
import '../db/db.dart' show Sale, SaleKind, SalesSummary, repository, PageResult, saleKindOf;
import '../buttons/sellbutton.dart';
import '../dialogs/receipt_dialog.dart';
import '../auth/auth_state.dart';
import '../dialogs/edit_sale_dialog.dart';

// ── Grouped transaction model ─────────────────────────────────────────

/// Represents a single checkout — one or more [sales] rows that share the
/// same timestamp and buyerId.
class TransactionGroup {
  final DateTime? timestamp;
  final int? buyerId;
  final String buyerName;
  final List<Sale> sales;

  /// The buyer's package, or null (no package, or a walk-in).
  final String? buyerPackage;

  /// Who rang it up (a staff username), or null when unknown.
  final String? seller;
  final SaleKind kind;

  const TransactionGroup({
    required this.timestamp,
    required this.buyerId,
    required this.buyerName,
    required this.sales,
    this.buyerPackage,
    this.seller,
    this.kind = SaleKind.counter,
  });

  int get itemCount => sales.length;
  int get totalPrice => sales.fold(0, (sum, s) => sum + s.price * s.quantity);

  /// The same time and buyer: one checkout.
  String get key => '${timestamp?.millisecondsSinceEpoch ?? 0}_$buyerId';

  /// A checkout the page boundary cut in two, put back together.
  TransactionGroup merge(TransactionGroup other) => TransactionGroup(
    timestamp: timestamp,
    buyerId: buyerId,
    buyerName: buyerName,
    sales: [...sales, ...other.sales],
    buyerPackage: buyerPackage,
    seller: seller,
    kind: kind,
  );

  /// "Vita Coffee ×2, Collagen Drink ×1".
  String get itemsText => sales.map((s) => '${s.itemName} ×${s.quantity}').join(', ');
}

/// The date ranges.
enum _Range {
  today('Today'),
  week('This week'),
  month('This month'),
  all('All time');

  final String label;
  const _Range(this.label);

  /// The start of the range, or null for all time.
  DateTime? since() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      _Range.today => today,
      // Weeks start on Monday.
      _Range.week => today.subtract(Duration(days: today.weekday - 1)),
      _Range.month => DateTime(now.year, now.month),
      _Range.all => null,
    };
  }
}

// ── Table widget ──────────────────────────────────────────────────────

class TransactionsTable extends StatefulWidget {
  /// When set, this table belongs to a branch cashier: the POS sells from that
  /// cashier's allocation, and the transaction list is scoped to their sales.
  final String? branchOwnerId;

  const TransactionsTable({super.key, this.branchOwnerId});

  @override
  State<TransactionsTable> createState() => _TransactionsTableState();
}

class _TransactionsTableState extends State<TransactionsTable> {
  String _searchTerm = '';
  _Range _range = _Range.today;
  SaleKind? _kind;
  late final StreamSubscription<String> _sub;

  static const _pageSize = 25;

  // ── The loaded checkouts: the table and the phone list scroll these ──
  final List<TransactionGroup> _items = [];
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isInitialLoading = true;
  String? _error;
  late final ScrollController _scrollController;

  /// Raised by every fresh load, so an older search's answer arriving late
  /// is dropped.
  int _generation = 0;

  /// buyerId → availed package name (empty = no package). Filled while
  /// resolving buyer names; read by the receipt's "Package" row.
  final Map<int, String> _memberPackages = {};

  /// Product pictures (v63) for the item tiles, by item id.
  final Map<int, String?> _images = {};

  /// The caption and chip counts for the range; null for all time.
  SalesSummary? _summary;

  Timer? _liveRefresh;
  Timer? _searchDebounce;

  bool get _isBranch => widget.branchOwnerId != null;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadData();
    _loadSummary();
    // Live changes from any device: one POS cart arrives as a sale and a
    // stock update per line. They make one refresh, in place, so the list
    // keeps its place instead of jumping back to the top.
    _sub = repository.changes.listen((e) {
      if (e == 'sale_added' ||
          e == 'item_updated' ||
          e == 'sale_updated' ||
          e == 'sale_deleted' ||
          e == 'sale_imported' ||
          e == 'member_updated') {
        _liveRefresh?.cancel();
        _liveRefresh = Timer(const Duration(milliseconds: 600), () {
          _refreshInPlace();
          if (e != 'item_updated' && e != 'member_updated') _loadSummary();
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _sub.cancel();
    _liveRefresh?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  void _loadData() {
    _loadPage(1);
  }

  Future<void> _loadSummary() async {
    final since = _range.since();
    if (since == null) {
      if (_summary != null) setState(() => _summary = null);
      return;
    }
    final range = _range;
    try {
      final s = await repository.fetchSalesSummary(since: since, userId: widget.branchOwnerId);
      if (!mounted || range != _range) return;
      setState(() => _summary = s);
    } catch (e) {
      debugPrint('[TransactionsTable] summary failed: $e');
    }
  }

  void _setRange(_Range r) {
    if (r == _range) return;
    setState(() {
      _range = r;
      _summary = null;
    });
    _loadData();
    _loadSummary();
  }

  void _setKind(SaleKind? k) {
    setState(() => _kind = k);
    _loadData();
  }

  void _onSearchChanged(String value) {
    _searchTerm = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadData();
    });
  }

  /// Re-reads every sale already loaded, in one query, and swaps the rows
  /// in: same place on screen. For live changes; a new search, chip or
  /// range still starts over at the top.
  Future<void> _refreshInPlace() async {
    final pages = _currentPage < 1 ? 1 : _currentPage;
    final gen = _generation;
    try {
      final result = await _fetchPageInternal(1, pageSize: pages * _pageSize);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.rows);
        _currentPage = pages;
        _hasMore = result.hasMore;
        _error = null;
      });
    } catch (_) {
      // Keep showing what is there; the next change tries again.
    }
  }

  void _loadMore() {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    setState(() {});
    _loadPage(_currentPage + 1);
  }

  Future<void> _loadPage(int page) async {
    if (page == 1) _generation++;
    final gen = _generation;
    try {
      final result = await _fetchPageInternal(page);
      if (!mounted || gen != _generation) return;

      setState(() {
        if (page == 1) _items.clear();
        var rows = result.rows;
        // A checkout split by the page boundary is one row again.
        if (_items.isNotEmpty && rows.isNotEmpty && _items.last.key == rows.first.key) {
          _items[_items.length - 1] = _items.last.merge(rows.first);
          rows = rows.sublist(1);
        }
        _items.addAll(rows);
        _currentPage = page;
        _hasMore = result.hasMore;
        _isInitialLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e.toString();
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<PageResult<TransactionGroup>> _fetchPageInternal(
    int page, {
    int pageSize = _pageSize,
  }) async {
    final salePage = await repository.fetchSalesPaginated(
      page: page,
      pageSize: pageSize,
      search: _searchTerm.trim().isEmpty ? null : _searchTerm.trim(),
      sortColumn: 'timestamp',
      sortAscending: false,
      userId: widget.branchOwnerId,
      since: _range.since(),
      kind: _isBranch ? null : _kind,
    );

    final buyerIds = salePage.rows.map((s) => s.buyerId).whereType<int>().toSet();
    final sellerIds = salePage.rows.map((s) => s.userId).whereType<String>().toSet();
    final itemIds = salePage.rows.map((s) => s.itemId).where((id) => id > 0).toSet();

    // Only this page's buyers, sellers and products, from the shared name
    // cache. Each lookup failing only blanks its own column.
    final results = await Future.wait<Object?>([
      repository.memberNamesFor(buyerIds).catchError((_) => <int, ({String name, String? package})>{}),
      repository.staffNamesFor(sellerIds).catchError((_) => <String, String?>{}),
      repository.productImages(itemIds).catchError((_) => <int, String?>{}),
      repository.branchCashierIds().catchError((_) => <String>{}),
    ]);
    final members = results[0] as Map<int, ({String name, String? package})>;
    final sellers = results[1] as Map<String, String?>;
    _images.addAll(results[2] as Map<int, String?>);
    final branchIds = results[3] as Set<String>;
    for (final e in members.entries) {
      // Cached for the receipt's "Package" row.
      _memberPackages[e.key] = e.value.package ?? '';
    }

    final grouped = <String, List<Sale>>{};
    for (final s in salePage.rows) {
      final key = '${s.timestamp?.millisecondsSinceEpoch ?? 0}_${s.buyerId}';
      grouped.putIfAbsent(key, () => []).add(s);
    }

    final groups = grouped.values.map((sales) {
      final first = sales.first;
      final member = first.buyerId == null ? null : members[first.buyerId];
      final buyerName =
          first.buyerName ??
          (first.buyerId != null ? (member?.name ?? 'Unknown') : 'Walk-in');
      return TransactionGroup(
        timestamp: first.timestamp,
        buyerId: first.buyerId,
        buyerName: buyerName,
        sales: sales,
        buyerPackage: member?.package,
        seller: first.userId == null ? null : sellers[first.userId],
        kind: saleKindOf(paymentMethod: first.paymentMethod, userId: first.userId, branchIds: branchIds),
      );
    }).toList()
      ..sort((a, b) {
        final ta = a.timestamp ?? DateTime(2000);
        final tb = b.timestamp ?? DateTime(2000);
        return tb.compareTo(ta);
      });

    return PageResult(
      rows: groups,
      totalCount: salePage.totalCount,
      page: page,
      pageSize: pageSize,
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────

  /// Edit Sale is for admins (v64), and only counter sales by one cashier:
  /// not delivery orders or package availments (see [isEditableSale]).
  bool _canEdit(TransactionGroup group) =>
      mounted &&
      context.read<AuthState>().userRole == UserRole.admin &&
      isEditableSale(group.sales);

  Future<void> _editTransaction(TransactionGroup group) async {
    if (!_canEdit(group)) return;
    await showAnimatedDialog(
      context,
      builder: (_) => EditSaleDialog(sales: group.sales, onSaved: _loadData),
    );
  }

  Future<void> _deleteTransaction(TransactionGroup group) async {
    final localCtx = context;
    final itemWord = group.itemCount == 1 ? 'item' : 'items';
    final ok = await confirmDestructive(
      localCtx,
      title: 'Delete this sale?',
      message: "It disappears from Transactions and the totals. This can't be undone.",
      detail: '${group.buyerName} · ${group.itemCount} $itemWord · ${_peso(group.totalPrice)}',
      confirmLabel: 'Delete sale',
    );
    if (ok != true) return;
    try {
      final ts = group.timestamp;
      if (ts == null) return;
      final res = await repository.deleteSaleGroup(ts, buyerId: group.buyerId);
      if (!mounted || !localCtx.mounted) return;
      if (res == -1) {
        await showDialog<void>(
          context: localCtx,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete failed'),
            content: const Text('Cannot delete this transaction.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted || !localCtx.mounted) return;
      await showDialog<void>(
        context: localCtx,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete failed'),
          content: Text('Failed to delete transaction: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _viewReceipt(TransactionGroup group) async {
    final localCtx = context;
    final lineItems = group.sales.map((s) {
      return ReceiptLineItem(
        itemName: s.itemName,
        quantity: s.quantity,
        unitPrice: s.price,
      );
    }).toList();
    if (!mounted || !localCtx.mounted) return;
    await ReceiptDialog(
      lineItems: lineItems,
      buyerName: group.buyerId != null ? group.buyerName : null,
      buyerPackage: group.buyerId != null
          ? _memberPackages[group.buyerId!]
          : null,
      transactionTime: group.timestamp,
    ).show(localCtx);
  }

  List<StaffMenuItem> _menu(TransactionGroup g) => [
    StaffMenuItem('View receipt', Icons.receipt_long_outlined, () => _viewReceipt(g)),
    if (_canEdit(g)) StaffMenuItem('Edit sale', Icons.edit_outlined, () => _editTransaction(g)),
    StaffMenuItem('Delete', Icons.delete_outline_rounded, () => _deleteTransaction(g), danger: true),
  ];

  // ── Shared pieces ───────────────────────────────────────────────────

  static String _peso(int n) => '₱${NumberFormat('#,###').format(n)}';

  /// "Today · 37 sales · ₱18,450".
  String _caption() {
    final s = _summary;
    if (_range == _Range.all) return 'All time';
    if (s == null) return _range.label;
    return '${_range.label} · ${staffCount(s.checkouts)} sale${s.checkouts == 1 ? '' : 's'} · ${_peso(s.total)}';
  }

  /// How many checkouts the list will hold, when known.
  int? _knownTotal() {
    final s = _summary;
    if (!_hasMore) return _items.length;
    if (s == null || _searchTerm.trim().isNotEmpty) return null;
    return switch (_kind) {
      null => s.checkouts,
      SaleKind.counter => s.counter,
      SaleKind.delivery => s.delivery,
      SaleKind.branch => s.branch,
    };
  }

  String _footer() {
    final total = _knownTotal();
    if (total != null) return staffShowing(_items.length, total);
    return _items.isEmpty ? '' : 'Showing ${staffCount(_items.length)} · more load as you scroll';
  }

  String _emptyText() {
    final q = _searchTerm.trim();
    if (q.isNotEmpty) return 'No sales match "$q".';
    final when = switch (_range) {
      _Range.today => 'today',
      _Range.week => 'this week',
      _Range.month => 'this month',
      _Range.all => 'yet',
    };
    return _kind == null ? 'No sales $when.' : 'No ${_kind!.name} sales $when.';
  }

  Widget _rangeChip() => StaffSelectChip<_Range>(
    label: '',
    icon: Icons.calendar_today_outlined,
    value: _range,
    options: [for (final r in _Range.values) (r, r.label)],
    onChanged: _setRange,
  );

  List<Widget> _kindChips() {
    final s = _summary;
    return [
      StaffChip(label: 'All', count: s?.checkouts, selected: _kind == null, onTap: () => _setKind(null)),
      StaffChip(label: 'Counter', count: s?.counter, selected: _kind == SaleKind.counter, onTap: () => _setKind(SaleKind.counter)),
      StaffChip(label: 'Delivery', count: s?.delivery, selected: _kind == SaleKind.delivery, onTap: () => _setKind(SaleKind.delivery)),
      StaffChip(label: 'Branch', count: s?.branch, selected: _kind == SaleKind.branch, onTap: () => _setKind(SaleKind.branch)),
    ];
  }

  /// How it was paid: Counter, Branch, Package, or Delivery and how.
  static Widget _paidPill(TransactionGroup g, {bool small = false}) {
    if (g.sales.any((s) => s.isPackage)) return StaffPill('Package', tone: StaffTone.orange, small: small);
    switch (g.kind) {
      case SaleKind.counter:
        return StaffPill('Counter', small: small);
      case SaleKind.branch:
        return StaffPill('Branch', tone: StaffTone.green, small: small);
      case SaleKind.delivery:
        final how = switch (g.sales.first.paymentMethod) {
          'funds' => 'funds',
          'cod' => 'cash',
          'counter' => 'at counter',
          'outside' => 'outside',
          _ => '',
        };
        return StaffPill(how.isEmpty ? 'Delivery' : 'Delivery · $how', tone: StaffTone.blue, small: small);
    }
  }

  /// The products as overlapping tiles (up to three).
  Widget _tiles(TransactionGroup g, {required double size, required double step}) {
    final shown = g.sales.take(3).toList();
    return SizedBox(
      width: size + step * (shown.length - 1) + 4,
      height: size + 4,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: StaffTableStyle.of(context).surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ProductTile(shown[i].itemName, imagePath: _images[shown[i].itemId], size: size),
              ),
            ),
        ],
      ),
    );
  }

  static bool _isToday(DateTime? t) {
    if (t == null) return false;
    final l = t.toLocal(), n = DateTime.now();
    return l.year == n.year && l.month == n.month && l.day == n.day;
  }

  static String _time(DateTime? t) => t == null ? '' : DateFormat('h:mm a').format(t.toLocal());

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kStaffTableBreakpoint) return _buildPhone(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaffTableTop(
              caption: _caption(),
              searchWidth: 320,
              search: StaffSearchField(hint: 'Buyer or product', initialValue: _searchTerm, onChanged: _onSearchChanged),
              actions: [SellButton(branchOwnerId: widget.branchOwnerId)],
            ),
            const SizedBox(height: 14),
            StaffChipBar(
              chips: [
                if (!_isBranch) ..._kindChips(),
                _rangeChip(),
              ],
              hint: 'Click a row for the receipt',
            ),
            const SizedBox(height: 14),
            Expanded(child: _buildTable(context)),
          ],
        );
      },
    );
  }

  /// Wide screens: When · Buyer · Items · Sold by · Paid · Total · ⋯
  Widget _buildTable(BuildContext context) {
    final s = StaffTableStyle.of(context);
    return StaffTable(
      controller: _scrollController,
      loading: _isInitialLoading,
      error: _error,
      onRetry: _loadData,
      loadingMore: _hasMore && _items.isNotEmpty,
      onLoadMore: _loadMore,
      emptyText: _emptyText(),
      footer: _footer(),
      itemCount: _items.length,
      onRowTap: (i) => _viewReceipt(_items[i]),
      columns: const [
        StaffColumn('When', width: 110),
        StaffColumn('Buyer', flex: 15),
        StaffColumn('Items', flex: 22),
        StaffColumn('Sold by', flex: 10),
        StaffColumn('Paid', flex: 12),
        StaffColumn('Total', width: 110, alignEnd: true),
        StaffColumn('', width: 48),
      ],
      cells: (context, i) {
        final g = _items[i];
        final walkIn = g.buyerId == null;
        return [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_time(g.timestamp), style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w600, color: s.text)),
              if (!_isToday(g.timestamp) && g.timestamp != null)
                Text(
                  DateFormat('d MMM').format(g.timestamp!.toLocal()),
                  style: StockpileFonts.satoshi(fontSize: 13, color: s.muted),
                ),
            ],
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                g.buyerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w700, color: s.text),
              ),
              Text(
                walkIn ? 'No member' : (g.buyerPackage == null ? 'No package' : '${g.buyerPackage} package'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StockpileFonts.satoshi(fontSize: 13, color: s.muted),
              ),
            ],
          ),
          Row(
            children: [
              _tiles(g, size: 32, step: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  g.itemsText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(fontSize: 15, color: s.body),
                ),
              ),
            ],
          ),
          Text(
            g.seller ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StockpileFonts.satoshi(fontSize: 15, color: s.body),
          ),
          Align(alignment: Alignment.centerLeft, child: _paidPill(g)),
          Text(
            _peso(g.totalPrice),
            style: StockpileFonts.satoshi(fontSize: 17, fontWeight: FontWeight.w800, color: s.text),
          ),
          StaffMoreButton(tooltip: 'More for this sale', items: _menu(g)),
        ];
      },
    );
  }

  /// Phones: the range, search and chips; checkouts grouped by day; Sell
  /// floating bottom-right.
  Widget _buildPhone(BuildContext context) {
    final s = StaffTableStyle.of(context);
    final Widget list;
    if (_isInitialLoading) {
      list = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _items.isEmpty) {
      list = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load the sales.'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _loadData, child: const Text('Try again')),
          ],
        ),
      );
    } else if (_items.isEmpty) {
      list = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_emptyText(), textAlign: TextAlign.center, style: StockpileFonts.satoshi(fontSize: 15, color: s.muted)),
        ),
      );
    } else {
      // Day by day, in the order loaded (newest first).
      final days = <({DateTime day, List<TransactionGroup> groups})>[];
      for (final g in _items) {
        final t = (g.timestamp ?? DateTime(2000)).toLocal();
        final day = DateTime(t.year, t.month, t.day);
        if (days.isEmpty || days.last.day != day) {
          days.add((day: day, groups: [g]));
        } else {
          days.last.groups.add(g);
        }
      }
      String dayLabel(DateTime d) {
        final n = DateTime.now();
        final today = DateTime(n.year, n.month, n.day);
        if (d == today) return 'Today';
        if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
        return DateFormat('EEE d MMM').format(d);
      }

      list = ListView(
        controller: _scrollController,
        // Room under the last row for the Sell button.
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final d in days) ...[
            StaffGroupLabel(
              '${dayLabel(d.day)} · ${d.groups.length} sale${d.groups.length == 1 ? '' : 's'}',
              trailing: _peso(d.groups.fold(0, (sum, g) => sum + g.totalPrice)),
            ),
            StaffPhoneCard(
              rows: [
                for (final g in d.groups)
                  StaffPhoneRow(
                    leading: SizedBox(width: 56, child: _tiles(g, size: 32, step: 18)),
                    title: g.buyerName,
                    lines: [
                      g.itemsText,
                      [_time(g.timestamp), if (g.seller != null) g.seller!].join(' · '),
                    ],
                    trailing: StaffPhoneValue(_peso(g.totalPrice), pill: _paidPill(g, small: true)),
                    menu: _menu(g),
                    onTap: () => _viewReceipt(g),
                  ),
              ],
            ),
          ],
          if (_hasMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      );
    }

    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: StaffPhoneTop(
            caption: _caption(),
            captionTrailing: _rangeChip(),
            search: StaffSearchField(hint: 'Buyer or product', height: 48, initialValue: _searchTerm, onChanged: _onSearchChanged),
            chips: _isBranch ? const [] : _kindChips(),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: list),
              // Hidden while the keyboard is up: it would ride over the rows.
              if (!keyboard)
                Positioned(
                  right: 16,
                  bottom: 16 + safeBottom,
                  child: SellButton(floating: true, branchOwnerId: widget.branchOwnerId),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
