import 'package:flutter/material.dart';
import '../utils/formatters.dart';
import 'dart:async';
import 'dart:convert';
import '../db/db.dart' show Sale, repository;
import '../widgets/search.dart';
import '../buttons/sellbutton.dart';
import '../buttons/redeembutton.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:lzcas/widgets/custom_elevated_button.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:csv/csv.dart';
import 'package:lzcas/dialogs/import_preview_dialog.dart';
import '../db/csv_header_utils.dart';
import '../dialogs/sale_cart_editor.dart';
import '../theme.dart';

class TransactionsTable extends StatefulWidget {
  const TransactionsTable({super.key});

  @override
  State<TransactionsTable> createState() => _TransactionsTableState();
}

class _TransactionsTableState extends State<TransactionsTable> {
  List<Sale> _sales = [];
  bool _loading = false;
  String _searchTerm = '';
  late final StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    _loadSales();
    _sub = repository.changes.listen((e) {
      if (e == 'sale_added' ||
          e == 'item_updated' ||
          e == 'sale_updated' ||
          e == 'sale_deleted' ||
          e == 'sale_imported') {
        _loadSales();
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _loadSales() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final s = (await repository.fetchSales()).toList();
      if (!mounted) return;
      setState(() {
        _sales = s;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('TransactionPage: failed to load sales: $e\n$st');
      if (!mounted) return;
      setState(() {
        _sales = [];
        _loading = false;
      });
    }
  }

  Future<void> _onExportCsvPressed(BuildContext safeContext) async {
    if (!safeContext.mounted) return;

    // Show loading dialog
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
      Navigator.pop(safeContext); // Close loading dialog

      try {
        final fs.FileSaveLocation? loc = await fs.getSaveLocation(
          suggestedName: suggested,
        );
        if (loc != null) {
          // Use UTF-8 encoding instead of codeUnits for better compatibility
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
      } catch (e) {
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
      Navigator.pop(safeContext); // Close loading dialog
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
            'This file does not look like a Sales export. Missing headers: ${missing.join(', ')}',
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
    await _loadSales();
    if (!mounted || !localCtx.mounted) return;
    ScaffoldMessenger.of(localCtx).showSnackBar(
      SnackBar(
        content: Text('Inserted $inserted new sale${inserted == 1 ? '' : 's'}'),
      ),
    );
  }

  Future<void> _deleteSale(Sale sale) async {
    final localActionCtx = context;
    final ok = await showDialog<bool>(
      context: localActionCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete sale'),
        content: const Text('Are you sure you want to delete this sale?'),
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
      final res = await repository.deleteSaleById(sale.id);
      if (!mounted || !localActionCtx.mounted) return;
      if (res == -1) {
        await showDialog<void>(
          context: localActionCtx,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete failed'),
            content: const Text(
              'Cannot delete sale because the buyer does not have enough points to reverse the award.',
            ),
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
      if (!mounted || !localActionCtx.mounted) return;
      await showDialog<void>(
        context: localActionCtx,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete failed'),
          content: Text('Failed to delete sale: $e'),
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

  Future<void> _editSale(Sale sale) async {
    final localActionCtx = context;
    await showDialog<bool?>(
      context: localActionCtx,
      builder: (ctx) => SaleCartEditor(seedSale: sale),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredSales = _sales.where((sale) {
      final searchTerm = _searchTerm.toLowerCase();
      return sale.itemName.toLowerCase().contains(searchTerm) ||
          sale.id.toString().contains(searchTerm);
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
                            onChanged: (value) =>
                                setState(() => _searchTerm = value),
                            hintText: "Search transactions...",
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
                        const RedeemButton(),
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
                          onChanged: (value) =>
                              setState(() => _searchTerm = value),
                          hintText: "Search transactions...",
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
                            const RedeemButton(compact: true),
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
                  : filteredSales.isEmpty
                  ? const Center(child: Text('No transactions yet'))
                  : isDesktop
                  ? _buildTransactionsTable(context, filteredSales)
                  : _buildTransactionsList(filteredSales),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTransactionsTable(
    BuildContext context,
    List<Sale> filteredSales,
  ) {
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
            final reserved = 140.0;
            var available = constraints.maxHeight - reserved;
            if (available < 56) available = 56;
            final estimated = (available ~/ 56).clamp(1, 10);
            final tableWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : (constraints.minWidth.isFinite && constraints.minWidth > 0
                      ? constraints.minWidth
                      : MediaQuery.sizeOf(context).width);

            return SizedBox(
              width: tableWidth,
              child: PaginatedDataTable(
                horizontalMargin: constraints.maxWidth < 1100 ? 12 : 20,
                columnSpacing: constraints.maxWidth < 1100 ? 18 : 32,
                rowsPerPage: estimated,
                headingRowHeight: 42,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 52,
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Item Name')),
                  DataColumn(label: Text('Quantity')),
                  DataColumn(label: Text('Price')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Txn')),
                  DataColumn(label: Text('Sale ID')),
                  DataColumn(label: Text('Actions')),
                ],
                source: _TransactionsDataSource(
                  filteredSales,
                  context,
                  onDelete: _deleteSale,
                  onEdit: _editSale,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTransactionsList(List<Sale> filteredSales) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      itemCount: filteredSales.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _TransactionListCard(
          sale: filteredSales[index],
          onDelete: _deleteSale,
          onEdit: _editSale,
        );
      },
    );
  }
}

class _TransactionListCard extends StatelessWidget {
  const _TransactionListCard({
    required this.sale,
    required this.onDelete,
    required this.onEdit,
  });

  final Sale sale;
  final Future<void> Function(Sale) onDelete;
  final Future<void> Function(Sale) onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                    sale.itemName,
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
                    if (value == 'edit') {
                      await onEdit(sale);
                    } else if (value == 'delete') {
                      await onDelete(sale);
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
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
                _SaleMetaPill(
                  icon: Icons.inventory_2_outlined,
                  text: 'Qty ${sale.quantity}',
                ),
                _SaleMetaPill(
                  icon: Icons.payments_outlined,
                  text: 'PHP ${sale.price}',
                ),
                _SaleMetaPill(
                  icon: Icons.stars_outlined,
                  text: '${sale.points} pts',
                ),
                _SaleMetaPill(icon: Icons.tag_outlined, text: 'ID ${sale.id}'),
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
                    formatDisplayDate(sale.timestamp),
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

class _SaleMetaPill extends StatelessWidget {
  const _SaleMetaPill({required this.icon, required this.text});

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

class _TransactionsDataSource extends DataTableSource {
  final List<Sale> _sales;
  final BuildContext _context;
  final Future<void> Function(Sale)? onDelete;
  final Future<void> Function(Sale)? onEdit;

  _TransactionsDataSource(
    this._sales,
    this._context, {
    this.onDelete,
    this.onEdit,
  });

  @override
  DataRow getRow(int index) {
    if (index >= _sales.length) return const DataRow(cells: []);
    final sale = _sales[index];
    final isEven = index % 2 == 0;

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
        DataCell(Text(sale.itemName)),
        DataCell(Text(sale.quantity.toString())),
        DataCell(Text('₱${sale.price}')),
        DataCell(Text(formatDisplayDate(sale.timestamp))),
        DataCell(Text(sale.points.toString())),
        DataCell(Text('ID:${sale.id}')),
        DataCell(_buildActionsCell(_context, sale)),
      ],
    );
  }

  Widget _buildActionsCell(BuildContext context, Sale sale) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'delete') {
          if (onDelete != null) await onDelete!(sale);
        } else if (value == 'edit') {
          if (onEdit != null) await onEdit!(sale);
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
      icon: const Icon(Icons.more_vert),
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => _sales.length;

  @override
  int get selectedRowCount => 0;
}
