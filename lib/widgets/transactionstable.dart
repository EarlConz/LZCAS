import 'package:flutter/material.dart';
import 'package:lzcas/utils/animations.dart';
import '../utils/formatters.dart';
import 'dart:async';
import '../db/db.dart' show Sale, repository, PageResult;
import '../widgets/search.dart';
import '../buttons/sellbutton.dart';
import '../dialogs/receipt_dialog.dart';
import '../theme.dart';

// ── Grouped transaction model ─────────────────────────────────────────

/// Represents a single checkout — one or more [sales] rows that share the
/// same timestamp and buyerId.
class TransactionGroup {
  final DateTime? timestamp;
  final int? buyerId;
  final String buyerName;
  final List<Sale> sales;

  const TransactionGroup({
    required this.timestamp,
    required this.buyerId,
    required this.buyerName,
    required this.sales,
  });

  int get itemCount => sales.length;
  int get totalPrice => sales.fold(0, (sum, s) => sum + s.price * s.quantity);
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
  late final StreamSubscription<String> _sub;

  static const _pageSize = 25;

  // ── Mobile infinite-scroll state ──────────────────────────────────
  final List<TransactionGroup> _items = [];
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isInitialLoading = true;
  String? _error;
  late final ScrollController _scrollController;

  /// buyerId → availed package name (empty = no package). Filled while
  /// resolving buyer names; read by the receipt's "Package" row.
  final Map<int, String> _memberPackages = {};

  // ── Server-page state for desktop PaginatedDataTable ──────────────
  final List<TransactionGroup> _serverPage = [];
  int _totalCount = 0;
  bool _serverHasMore = true; // more server pages available (desktop paging)
  bool _fetchingServer = false; // a fetch loop is currently running
  int _serverPageLoaded = 0; // highest server page fetched into _serverPage
  int _pendingNeeded = 0; // highest requested row count (coalesces requests)
  bool _didInitialPrefetch = false; // primed page 2 once after first load
  late final _TxnDataSource _txnSource;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _txnSource = _TxnDataSource(
      _serverPage,
      () => _totalCount,
      () => _serverHasMore,
      onDelete: _deleteTransaction,
      onReceipt: _viewReceipt,
    );
    _loadData();
    _sub = repository.changes.listen((e) {
      if (e == 'sale_added' ||
          e == 'item_updated' ||
          e == 'sale_updated' ||
          e == 'sale_deleted' ||
          e == 'sale_imported' ||
          e == 'member_updated') {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _sub.cancel();
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

  void _loadMore() {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    setState(() {});
    _loadPage(_currentPage + 1);
  }

  Future<void> _loadPage(int page) async {
    try {
      final result = await _fetchPageInternal(page, _searchTerm);
      if (!mounted) return;

      setState(() {
        if (page == 1) {
          _items.clear();
          _serverPage.clear();
          _serverPage.addAll(result.rows);
          _serverPageLoaded = 1;
          _serverHasMore = result.hasMore;
          _pendingNeeded = _serverPage.length;
          _didInitialPrefetch = false;
        }
        _items.addAll(result.rows);
        _currentPage = page;
        _totalCount = result.totalCount;
        _hasMore = result.hasMore;
        _isInitialLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
      if (page == 1) {
        _txnSource.refresh();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  /// Load consecutive server pages until `_serverPage` holds at least
  /// [neededCount] displayed rows (grouped transactions), or the server has
  /// no more pages.
  ///
  /// NOTE: PaginatedDataTable.onPageChanged reports the *first row index* of
  /// the new table page — NOT a page number. Rows are also grouped, so one
  /// server page yields ≤ _pageSize display rows; we therefore page by
  /// server-page number and stop on "no more" or "no progress".
  Future<void> _ensureLoadedThrough(int neededCount) async {
    if (neededCount > _pendingNeeded) _pendingNeeded = neededCount;
    // A fetch loop is already running; it re-reads _pendingNeeded each
    // iteration, so it will honor this raised target too. This coalescing
    // means a fast multi-page jump (or a background prefetch racing a
    // navigation) never drops a request.
    if (_fetchingServer) return;
    _fetchingServer = true;
    try {
      while (_serverPage.length < _pendingNeeded && _serverHasMore) {
        final before = _serverPage.length;
        await _fetchServerPage(_serverPageLoaded + 1);
        if (_serverPage.length <= before) break; // no progress — stop
      }
    } finally {
      _fetchingServer = false;
    }
  }

  /// Quietly load ONE page beyond what's already loaded so the next forward
  /// step is instant. Fire-and-forget; the coalescing loader ignores it when a
  /// fetch is already running or there's nothing more to load.
  void _prefetchNext() {
    if (_serverHasMore) _ensureLoadedThrough(_serverPage.length + 1);
  }

  /// Fetch one server page for the desktop PaginatedDataTable and append its
  /// (grouped) rows to _serverPage. Advances _serverPageLoaded/_serverHasMore.
  Future<void> _fetchServerPage(int serverPage) async {
    if (serverPage <= _serverPageLoaded) return;
    try {
      final page = await _fetchPageInternal(serverPage, _searchTerm);
      if (!mounted) return;
      setState(() {
        _serverPage.addAll(page.rows);
        _totalCount = page.totalCount;
        _serverPageLoaded = serverPage;
        _serverHasMore = page.hasMore;
      });
      _txnSource.refresh();
    } catch (e) {
      if (!mounted) return;
    }
  }

  Future<PageResult<TransactionGroup>> _fetchPageInternal(
    int page,
    String? search,
  ) async {
    final salePage = await repository.fetchSalesPaginated(
      page: page,
      pageSize: _pageSize,
      search: search,
      sortColumn: 'timestamp',
      sortAscending: false,
      userId: widget.branchOwnerId,
    );

    final buyerIds = salePage.rows
        .map((s) => s.buyerId)
        .whereType<int>()
        .toSet();

    final Map<int, String> memberNames = {};
    if (buyerIds.isNotEmpty) {
      final allMembers = await repository.fetchMembers();
      for (final m in allMembers) {
        if (m.id != null && buyerIds.contains(m.id)) {
          final parts = [
            m.firstName,
            m.lastName,
          ].where((p) => p != null && p.trim().isNotEmpty);
          memberNames[m.id!] = parts.isNotEmpty ? parts.join(' ') : 'Unnamed';
          // Cached for the receipt's "Package" row.
          _memberPackages[m.id!] = m.packageName ?? '';
        }
      }
    }

    final filtered = <String, List<Sale>>{};
    for (final s in salePage.rows) {
      final key = '${s.timestamp?.millisecondsSinceEpoch ?? 0}_${s.buyerId}';
      filtered.putIfAbsent(key, () => []).add(s);
    }

    final txnfiltered =
        filtered.entries.map((entry) {
          final sales = entry.value;
          final first = sales.first;
          final buyerName =
              first.buyerName ??
              (first.buyerId != null
                  ? (memberNames[first.buyerId] ?? 'Unknown')
                  : 'Walk-in');
          return TransactionGroup(
            timestamp: first.timestamp,
            buyerId: first.buyerId,
            buyerName: buyerName,
            sales: sales,
          );
        }).toList()..sort((a, b) {
          final ta = a.timestamp ?? DateTime(2000);
          final tb = b.timestamp ?? DateTime(2000);
          return tb.compareTo(ta);
        });

    return PageResult(
      rows: txnfiltered,
      totalCount: salePage.totalCount,
      page: page,
      pageSize: _pageSize,
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _deleteTransaction(TransactionGroup group) async {
    final localCtx = context;
    final itemWord = group.itemCount == 1 ? 'item' : 'items';
    final ok = await showDialog<bool>(
      context: localCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction'),
        content: Text(
          'Delete this transaction? (${group.itemCount} $itemWord, '
          '₱${group.totalPrice})',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
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

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 900;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(appSpacing),
              child: isDesktop
                  ? Row(
                      children: [
                        Expanded(
                          child: SearchBarWidget(
                            onChanged: (v) => setState(() {
                              _searchTerm = v;
                              _loadData();
                            }),
                            hintText: "Search by buyer…",
                            borderRadius: 12,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SellButton(branchOwnerId: widget.branchOwnerId),
                      ],
                    )
                  : Column(
                      children: [
                        SearchBarWidget(
                          onChanged: (v) => setState(() {
                            _searchTerm = v;
                            _loadData();
                          }),
                          hintText: "Search by buyer…",
                          borderRadius: 12,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: SellButton(
                                compact: true,
                                branchOwnerId: widget.branchOwnerId,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            Expanded(child: isDesktop ? _buildTable(context) : _buildList()),
          ],
        );
      },
    );
  }

  // ── Desktop table ───────────────────────────────────────────────────

  Widget _buildTable(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Theme(
        data: Theme.of(context).copyWith(
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(appRadius),
              side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
            ),
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final reserved =
                120.0; // header (52) + footer (56) + internal padding
            var available = constraints.maxHeight - reserved;
            if (available < 56) available = 56;
            final estimated = (available ~/ 62).clamp(1, 10);

            // Desktop table is built → prime the second page once so the very
            // first "next" is already loaded. (Runs here so mobile never
            // wastes a fetch into _serverPage it doesn't read.)
            if (!_didInitialPrefetch && !_isInitialLoading && _serverHasMore) {
              _didInitialPrefetch = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _prefetchNext();
              });
            }

            return SizedBox(
              height: constraints.maxHeight,
              child: PaginatedDataTable(
                horizontalMargin: constraints.maxWidth < 1100 ? 12 : 20,
                columnSpacing: constraints.maxWidth < 1100 ? 18 : 32,
                rowsPerPage: estimated,
                headingRowHeight: 52,
                dataRowMinHeight: 56,
                dataRowMaxHeight: 62,
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Buyer')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Items')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Actions')),
                ],
                source: _txnSource,
                // pageIndex is the FIRST row index of the new page, not a page
                // number — load through the last row this page needs, then
                // quietly prime the following page so the next step is instant.
                onPageChanged: (pageIndex) => _ensureLoadedThrough(
                  pageIndex + estimated,
                ).then((_) => _prefetchNext()),
              ),
            ); // PaginatedDataTable + SizedBox + return
          },
        ),
      ),
    );
  }

  // ── Mobile list (infinite-scroll) ────────────────────────────────────

  Widget _buildList() {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Failed to load transactions.'),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No transactions yet'));
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, i) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return StaggeredItem(
          index: index,
          child: _TxnListCard(
            group: _items[index],
            onDelete: _deleteTransaction,
            onReceipt: _viewReceipt,
          ),
        );
      },
    );
  }
}

// ── Mobile card ───────────────────────────────────────────────────────

class _TxnListCard extends StatelessWidget {
  const _TxnListCard({
    required this.group,
    required this.onDelete,
    required this.onReceipt,
  });

  final TransactionGroup group;
  final Future<void> Function(TransactionGroup) onDelete;
  final Future<void> Function(TransactionGroup) onReceipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final itemWord = group.itemCount == 1 ? 'item' : 'items';

    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    group.buyerName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Transaction actions',
                  onSelected: (value) async {
                    if (value == 'receipt') {
                      await onReceipt(group);
                    } else if (value == 'delete') {
                      await onDelete(group);
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: 'receipt',
                      child: Text('View Receipt'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                  icon: const Icon(Icons.more_vert),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Pill(
                  icon: Icons.inventory_2_outlined,
                  text: '${group.itemCount} $itemWord',
                ),
                _Pill(
                  icon: Icons.payments_outlined,
                  text: '₱${group.totalPrice}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    formatDisplayDate(group.timestamp),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable pill ─────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(text, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

// ── Desktop data source ───────────────────────────────────────────────

class _TxnDataSource extends DataTableSource {
  final List<TransactionGroup> _items;
  final int Function() _getTotalCount;
  final bool Function() _getHasMore;
  final Future<void> Function(TransactionGroup)? onDelete;
  final Future<void> Function(TransactionGroup)? onReceipt;

  _TxnDataSource(
    this._items,
    this._getTotalCount,
    this._getHasMore, {
    this.onDelete,
    this.onReceipt,
  });

  @override
  int get rowCount {
    // _items are grouped transactions (a multi-item checkout collapses into
    // one row), so the raw sale count is only an UPPER bound on displayed
    // rows. While more server pages remain, report that upper bound so the
    // pager keeps advancing; once fully loaded, report the exact group count
    // so there are no permanent "Loading…" phantom rows.
    return _getHasMore() ? _getTotalCount() : _items.length;
  }

  @override
  DataRow getRow(int index) {
    if (index >= _items.length) {
      // Not fetched yet — show a shimmering skeleton row instead of raw text.
      return DataRow(
        cells: [
          skeletonCell(width: 130), // Buyer
          skeletonCell(width: 90), // Date
          skeletonCell(width: 60), // Items
          skeletonCell(width: 70), // Total
          skeletonCell(width: 32), // Actions
        ],
      );
    }
    final group = _items[index];
    final isEven = index % 2 == 0;
    final itemWord = group.itemCount == 1 ? 'item' : 'items';

    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.hovered)) {
          return StockpileColors.secondary500.withAlpha(18);
        }
        if (isEven) {
          return StockpileColors.mutedText.withAlpha(16);
        }
        return null;
      }),
      cells: [
        DataCell(Text(group.buyerName, overflow: TextOverflow.ellipsis)),
        DataCell(Text(formatDisplayDate(group.timestamp))),
        DataCell(Text('${group.itemCount} $itemWord')),
        DataCell(Text('₱${group.totalPrice}')),
        DataCell(_buildActions(group)),
      ],
    );
  }

  Widget _buildActions(TransactionGroup group) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'receipt') {
          if (onReceipt != null) await onReceipt!(group);
        } else if (value == 'delete') {
          if (onDelete != null) await onDelete!(group);
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'receipt', child: Text('View Receipt')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
      icon: const Icon(Icons.more_vert),
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => 0;

  /// Call after external data changes to refresh the table.
  void refresh() => notifyListeners();
}
