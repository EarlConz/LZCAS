import 'package:flutter/material.dart';
import '../utils/formatters.dart';
import 'dart:async';
import 'dart:convert';
import '../db/db.dart' show Sale, repository;
import '../widgets/search.dart';
import '../buttons/sellbutton.dart';
import '../buttons/borrowbutton.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:lzcas/widgets/custom_elevated_button.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:csv/csv.dart';
import 'package:lzcas/dialogs/import_preview_dialog.dart';
import '../db/csv_header_utils.dart';
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

  @override
  void initState() {
    super.initState();
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
    setState(() => _loading = true);
    try {
      final allSales = (await repository.fetchSales()).toList();
      final allMembers = await repository.fetchMembers();

      // Build member name lookup
      final Map<int, String> memberNames = {};
      for (final m in allMembers) {
        final parts = [
          m.firstName,
          m.lastName,
        ].where((p) => p != null && p.trim().isNotEmpty);
        if (m.id != null) {
          memberNames[m.id!] = parts.isNotEmpty ? parts.join(' ') : 'Unnamed';
        }
      }

      // Group sales by (timestamp ms, buyerId)
      final Map<String, List<Sale>> groups = {};
      for (final s in allSales) {
        final key = '${s.timestamp?.millisecondsSinceEpoch ?? 0}_${s.buyerId}';
        groups.putIfAbsent(key, () => []).add(s);
      }

      if (!mounted) return;
      setState(() {
        _txnGroups =
            groups.entries.map((entry) {
              final sales = entry.value;
              final first = sales.first;
              final buyerName = first.buyerId != null
                  ? (memberNames[first.buyerId] ?? 'Unknown')
                  : 'Walk-in';
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

  // ── Export / Import (unchanged) ─────────────────────────────────────

  Future<void> _onExportCsvPressed(BuildContext safeContext) async {
    if (!safeContext.mounted) return;
    showDialog(
      context: safeContext,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final csv = await repository.exportSalesCsvString();
      final suggested =
          'sales_export_${DateTime.now().millisecondsSinceEpoch}.csv';
      if (!mounted || !safeContext.mounted) return;
      Navigator.pop(safeContext);
      try {
        final fs.FileSaveLocation? loc = await fs.getSaveLocation(
          suggestedName: suggested,
        );
        if (loc != null) {
          final csvBytes = utf8.encode(csv);
          final xfile = fs.XFile.fromData(
            csvBytes,
            mimeType: 'text/csv',
            name: suggested,
          );
          await xfile.saveTo(loc.path);
          if (!mounted || !safeContext.mounted) return;
          ScaffoldMessenger.of(
            safeContext,
          ).showSnackBar(SnackBar(content: Text('Exported to ${loc.path}')));
        }
      } catch (_) {
        final dir = Directory.current.path;
        final savePath = p.join(dir, suggested);
        final file = File(savePath);
        await file.writeAsString(csv);
        if (!mounted || !safeContext.mounted) return;
        ScaffoldMessenger.of(
          safeContext,
        ).showSnackBar(SnackBar(content: Text('Exported to $savePath')));
      }
    } catch (e) {
      if (!mounted || !safeContext.mounted) return;
      Navigator.pop(safeContext);
      ScaffoldMessenger.of(
        safeContext,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _onImportCsvPressed(BuildContext localCtx) async {
    final files = await fs.openFiles(
      acceptedTypeGroups: [
        fs.XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (files.isEmpty) return;
    final xfile = files.first;
    final content = await xfile.readAsString();
    final conv = const CsvToListConverter();
    final parsed = conv.convert(content);
    if (parsed.isEmpty) return;
    final headers = parsed.first.map((e) => e.toString()).toList();
    final rows = parsed
        .sublist(1)
        .map((r) => r.map((c) => c?.toString() ?? '').toList())
        .toList();
    if (!mounted || !localCtx.mounted) return;
    final expected = [
      'id',
      'itemid',
      'itemname',
      'quantity',
      'price',
      'createdat',
      'points',
    ];
    final missing = findMissingHeaders(headers.cast<String>(), expected);
    if (missing.isNotEmpty) {
      if (!mounted || !localCtx.mounted) return;
      await showDialog<void>(
        context: localCtx,
        builder: (ctx) => AlertDialog(
          title: const Text('Invalid CSV'),
          content: Text(
            'This file does not look like a Sales export. '
            'Missing headers: ${missing.join(', ')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted || !localCtx.mounted) return;
    final existingSales = await repository.fetchSales();
    bool fastExists(Map<String, String> map) {
      final idStr = (map['id'] ?? '').trim();
      if (idStr.isNotEmpty) {
        final id = int.tryParse(idStr);
        if (id != null) {
          if (existingSales.any((s) => s.id == id)) return true;
        }
      }
      final itemIdStr = (map['itemid'] ?? map['itemId'] ?? '').trim();
      final itemName = (map['itemname'] ?? map['itemName'] ?? '').trim();
      final quantityStr = (map['quantity'] ?? '').trim();
      final priceStr = (map['price'] ?? '').trim();
      final buyerIdStr = (map['buyerid'] ?? map['buyerId'] ?? '').trim();
      final itemId = int.tryParse(itemIdStr) ?? -1;
      final quantity = int.tryParse(quantityStr) ?? -1;
      final price = int.tryParse(priceStr) ?? -1;
      final buyerId = int.tryParse(buyerIdStr);
      return existingSales.any((s) {
        final sameCore =
            s.itemId == itemId &&
            s.itemName == itemName &&
            s.quantity == quantity &&
            s.price == price &&
            (buyerId == null ? s.buyerId == null : s.buyerId == buyerId);
        return sameCore;
      });
    }

    if (!mounted || !localCtx.mounted) return;
    final sel = await showImportPreviewDialogWithSelection(
      localCtx,
      headers,
      rows,
      exists: (m) async => fastExists(m),
    );
    if (sel == null || sel.isEmpty) return;
    final rowsToImport = sel.map((i) => rows[i]).toList();
    final selectedCsv = const ListToCsvConverter().convert([
      headers,
      ...rowsToImport,
    ]);
    final inserted = await repository.importSalesCsv(selectedCsv);
    if (!mounted || !localCtx.mounted) return;
    await _loadData();
    if (!mounted || !localCtx.mounted) return;
    ScaffoldMessenger.of(localCtx).showSnackBar(
      SnackBar(
        content: Text('Inserted $inserted new sale${inserted == 1 ? '' : 's'}'),
      ),
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
                            onChanged: (v) => setState(() => _searchTerm = v),
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
                        const SizedBox(width: 8),
                        CustomElevatedButton(
                          onPressed: () => _onExportCsvPressed(context),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Export'),
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                        ),
                        const SizedBox(width: 8),
                        CustomElevatedButton(
                          onPressed: () => _onImportCsvPressed(context),
                          icon: const Icon(Icons.download),
                          label: const Text('Import'),
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        SearchBarWidget(
                          onChanged: (v) => setState(() => _searchTerm = v),
                          hintText: "Search by buyer…",
                          borderRadius: 12,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const SellButton(compact: true),
                            const SizedBox(width: 8),
                            const BorrowButton(compact: true),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              tooltip: 'Export CSV',
                              icon: const Icon(Icons.upload_file),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.grey[700],
                              ),
                              onPressed: () => _onExportCsvPressed(context),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              tooltip: 'Import CSV',
                              icon: const Icon(Icons.download),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.grey[700],
                              ),
                              onPressed: () => _onImportCsvPressed(context),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
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
            final reserved = 108.0; // header (52) + footer (56)
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
                source: _TxnDataSource(
                  filtered,
                  context,
                  onDelete: _deleteTransaction,
                  onReceipt: _viewReceipt,
                ),
              ),
            ); // PaginatedDataTable + SizedBox + return
          },
        ),
      ),
    );
  }

  // ── Mobile list ─────────────────────────────────────────────────────

  Widget _buildList(List<TransactionGroup> filtered) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      itemCount: filtered.length,
      separatorBuilder: (_, i) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _TxnListCard(
        group: filtered[index],
        onDelete: _deleteTransaction,
        onReceipt: _viewReceipt,
      ),
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
  final List<TransactionGroup> _groups;
  final BuildContext _context;
  final Future<void> Function(TransactionGroup)? onDelete;
  final Future<void> Function(TransactionGroup)? onReceipt;

  _TxnDataSource(this._groups, this._context, {this.onDelete, this.onReceipt});

  @override
  DataRow getRow(int index) {
    if (index >= _groups.length) return const DataRow(cells: []);
    final group = _groups[index];
    final isEven = index % 2 == 0;
    final itemWord = group.itemCount == 1 ? 'item' : 'items';

    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.hovered)) {
          return Theme.of(_context).colorScheme.primary.withAlpha(18);
        }
        if (isEven) {
          return Theme.of(
            _context,
          ).colorScheme.surfaceContainerHighest.withAlpha(90);
        }
        return null;
      }),
      cells: [
        DataCell(Text(group.buyerName)),
        DataCell(Text(formatDisplayDate(group.timestamp))),
        DataCell(Text('${group.itemCount} $itemWord')),
        DataCell(Text('₱${group.totalPrice}')),
        DataCell(_buildActions(_context, group)),
      ],
    );
  }

  Widget _buildActions(BuildContext context, TransactionGroup group) {
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
  int get rowCount => _groups.length;

  @override
  int get selectedRowCount => 0;
}
