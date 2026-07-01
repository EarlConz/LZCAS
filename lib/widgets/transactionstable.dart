import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/utils/animations.dart';
import '../utils/formatters.dart';
import 'dart:async';
import '../db/db.dart' show Sale, repository, PageResult;
import '../widgets/search.dart';
import '../buttons/sellbutton.dart';
import '../buttons/borrowbutton.dart';
import '../dialogs/receipt_dialog.dart';
import '../widgets/pagination_bar.dart';
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
  int get totalPrice => sales.fold(0, (sum, s) => sum + s.price);
}

// ── Table widget ──────────────────────────────────────────────────────

class TransactionsTable extends StatefulWidget {
  const TransactionsTable({super.key});

  @override
  State<TransactionsTable> createState() => _TransactionsTableState();
}

class _TransactionsTableState extends State<TransactionsTable> {
  List<TransactionGroup> _txnGroups = [];
  bool _loading = false;
  String _searchTerm = '';
  late final StreamSubscription<String> _sub;

  static const _pageSize = 25;
  int _displayPage = 1;
  int _currentPage = 0;
  bool _hasMore = true;

  // ── Server-page state for desktop PaginatedDataTable ──────────────
  final List<TransactionGroup> _serverPage = [];
  int _totalCount = 0;
  int _currentServerPage = 1;
  late final _TxnDataSource _txnSource;

  @override
  void initState() {
    super.initState();
    _txnSource = _TxnDataSource(
      _serverPage,
      () => _totalCount,
      () => _currentServerPage,
      _pageSize,
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
    _sub.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    _loading = true;
    _currentPage = 1;
    _hasMore = true;
    setState(() {});

    try {
      final page = await _fetchPage(1, _searchTerm);
      if (!mounted) return;
      // Desktop: update server-page state
      _serverPage.clear();
      _serverPage.addAll(page.rows);
      _totalCount = page.totalCount;
      _currentServerPage = 1;
      _txnSource.refresh();
      // Mobile: set accumulated list
      setState(() {
        _txnGroups = List.of(page.rows);
        _hasMore = page.hasMore;
        _displayPage = 1;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('TransactionsTable: failed to load: $e\n$st');
      if (!mounted) return;
      setState(() {
        _txnGroups = [];
        _loading = false;
      });
    }
  }

  /// Fetch a specific server page for desktop PaginatedDataTable.
  Future<void> _fetchServerPage(int serverPage) async {
    if (_loading) return;
    _loading = true;
    setState(() {});
    try {
      final page = await _fetchPage(serverPage, _searchTerm);
      if (!mounted) return;
      _serverPage.clear();
      _serverPage.addAll(page.rows);
      setState(() {
        _totalCount = page.totalCount;
        _currentServerPage = serverPage;
        _loading = false;
      });
      _txnSource.refresh();
    } catch (e) {
      debugPrint('TransactionsTable: failed to load page $serverPage: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    setState(() {});

    try {
      final page = await _fetchPage(_currentPage + 1, _searchTerm);
      if (!mounted) return;
      setState(() {
        _txnGroups.addAll(page.rows);
        _currentPage = page.page;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      debugPrint('TransactionsTable: failed to load more: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<PageResult<TransactionGroup>> _fetchPage(
    int page,
    String? search,
  ) async {
    final salePage = await repository.fetchSalesPaginated(
      page: page,
      pageSize: _pageSize,
      search: search,
      sortColumn: 'timestamp',
      sortAscending: false,
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
      transactionTime: group.timestamp,
    ).show(localCtx);
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final term = _searchTerm.toLowerCase();
    final filtered = _txnGroups.where((g) {
      return g.buyerName.toLowerCase().contains(term);
    }).toList();

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
                        const SellButton(),
                        const SizedBox(width: 8),
                        const BorrowButton(),
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
                            const Expanded(child: SellButton(compact: true)),
                            const SizedBox(width: 10),
                            const Expanded(child: BorrowButton(compact: true)),
                          ],
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: _loading && _txnGroups.isEmpty
                  ? const SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(0, 8, 0, 8),
                      child: SkeletonList(count: 5),
                    )
                  : filtered.isEmpty
                  ? const Center(child: Text('No transactions yet'))
                  : isDesktop
                  ? _buildTable(context, filtered)
                  : _buildList(filtered),
            ),
          ],
        );
      },
    );
  }

  // ── Desktop table ───────────────────────────────────────────────────

  Widget _buildTable(BuildContext context, List<TransactionGroup> filtered) {
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
                onPageChanged: (pageIndex) => _fetchServerPage(pageIndex + 1),
              ),
            ); // PaginatedDataTable + SizedBox + return
          },
        ),
      ),
    );
  }

  // ── Mobile list ─────────────────────────────────────────────────────

  Widget _buildList(List<TransactionGroup> filtered) {
    final totalPages = (filtered.length / _pageSize).ceil();
    final start = (_displayPage - 1) * _pageSize;
    final pageItems = filtered.skip(start).take(_pageSize).toList();

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            itemCount: pageItems.length,
            separatorBuilder: (_, i) => const SizedBox(height: 8),
            itemBuilder: (context, index) => StaggeredItem(
              index: index,
              child: _TxnListCard(
                group: pageItems[index],
                onDelete: _deleteTransaction,
                onReceipt: _viewReceipt,
              ),
            ),
          ),
        ),
        if (totalPages > 1)
          PaginationBar(
            currentPage: _displayPage,
            totalPages: totalPages,
            compact: true,
            onPageChanged: (page) {
              final needed = page * _pageSize;
              if (needed > _txnGroups.length && _hasMore && !_loading) {
                _loadNextPage().then((_) {
                  if (mounted) setState(() => _displayPage = page);
                });
              } else {
                setState(() => _displayPage = page);
              }
            },
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
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
  final int Function() _getPageNumber;
  final int _pageSize;
  final Future<void> Function(TransactionGroup)? onDelete;
  final Future<void> Function(TransactionGroup)? onReceipt;

  _TxnDataSource(
    this._items,
    this._getTotalCount,
    this._getPageNumber,
    this._pageSize, {
    this.onDelete,
    this.onReceipt,
  });

  @override
  int get rowCount => _getTotalCount();

  @override
  DataRow getRow(int index) {
    final pageNumber = _getPageNumber();
    final pageStart = (pageNumber - 1) * _pageSize;
    final localIndex = index - pageStart;
    if (localIndex < 0 || localIndex >= _items.length) {
      return DataRow(cells: List.filled(5, const DataCell(Text(''))));
    }
    final group = _items[localIndex];
    final isEven = index % 2 == 0;
    final itemWord = group.itemCount == 1 ? 'item' : 'items';

    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.hovered)) {
          return Colors.blue.withAlpha(18);
        }
        if (isEven) {
          return Colors.grey.withAlpha(20);
        }
        return null;
      }),
      cells: [
        DataCell(Text(group.buyerName)),
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
