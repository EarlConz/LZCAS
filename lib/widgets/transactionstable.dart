// ignore_for_file: use_build_context_synchronously
// ...existing code...
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
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
      if (e == 'sale_added' || e == 'item_updated' || e == 'sale_updated' || e == 'sale_deleted' || e == 'sale_imported') {
        // reload whenever sales change so UI reflects deletes/edits/imports immediately
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
        _sales = s.reversed.toList(); // show recent first
        _loading = false;
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('TransactionPage: failed to load sales: $e\n$st');
      if (!mounted) return;
      setState(() {
        _sales = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredSales = _sales.where((sale) {
      final searchTerm = _searchTerm.toLowerCase();
      return sale.itemName.toLowerCase().contains(searchTerm) ||
          sale.id.toString().contains(searchTerm);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: SearchBarWidget(
                  onChanged: (value) {
                    setState(() {
                      _searchTerm = value;
                    });
                  },
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
              // Export Sales button
              CustomElevatedButton(
        onPressed: () async {
          // capture context before awaits
                    final localCtx = context;
                    final csv = await repository.exportSalesCsvString();
                    final suggested = 'sales_export_${DateTime.now().millisecondsSinceEpoch}.csv';
                    try {
                      final fs.FileSaveLocation? loc = await fs.getSaveLocation(suggestedName: suggested);
                        if (loc != null) {
                        final xfile = fs.XFile.fromData(Uint8List.fromList(csv.codeUnits), mimeType: 'text/csv', name: suggested);
                        await xfile.saveTo(loc.path);
                        if (!mounted) return;
                        ScaffoldMessenger.of(localCtx).showSnackBar(SnackBar(content: Text('Exported to ${loc.path}')));
                      }
                    } catch (e) {
                      final dir = Directory.current.path;
                      final savePath = p.join(dir, suggested);
                      final file = File(savePath);
                      await file.writeAsString(csv);
                      if (!mounted) return;
                      ScaffoldMessenger.of(localCtx).showSnackBar(SnackBar(content: Text('Exported to $savePath')));
                    }
                  },
                icon: const Icon(Icons.upload_file),
                label: const Text('Export'),
                backgroundColor: Colors.grey[700],
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              const SizedBox(width: 8),
              // Import Sales button with preview
              CustomElevatedButton(
                onPressed: () async {
                  final localCtx = context;
                  final files = await fs.openFiles(acceptedTypeGroups: [fs.XTypeGroup(label: 'CSV', extensions: ['csv'])]);
                  if (files.isEmpty) return;
                  final xfile = files.first;
                  final content = await xfile.readAsString();

                  // parse CSV and show preview (reuse the shared dialog)
                  final conv = const CsvToListConverter();
                  final parsed = conv.convert(content);
                  if (parsed.isEmpty) return;
                  final headers = parsed.first.map((e) => e.toString()).toList();
                  final rows = parsed.sublist(1).map((r) => r.map((c) => c?.toString() ?? '').toList()).toList();
                  if (!mounted) return;
                  final expected = ['id', 'itemid', 'itemname', 'quantity', 'price', 'createdat', 'points'];
                  final missing = findMissingHeaders(headers.cast<String>(), expected);
                  if (missing.isNotEmpty) {
                    if (!mounted) return;
                    // Safe: using `localCtx` captured before async work and validated via mounted.
                    await showDialog<void>(
                      context: localCtx,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Invalid CSV'),
                        content: Text('This file does not look like a Sales export. Missing headers: ${missing.join(', ')}'),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                      ),
                    );
                    return;
                  }
                  if (!mounted) return;
                  // Provide a fast existence checker for sales CSV rows: check by id or by matching core fields
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
                      final sameCore = s.itemId == itemId && s.itemName == itemName && s.quantity == quantity && s.price == price && (buyerId == null ? s.buyerId == null : s.buyerId == buyerId);
                      return sameCore;
                    });
                  }

                  final sel = await showImportPreviewDialogWithSelection(localCtx, headers, rows, exists: (m) async => fastExists(m));
                  if (sel == null || sel.isEmpty) return;

                  final rowsToImport = sel.map((i) => rows[i]).toList();
                  // Rebuild CSV content for selected rows only
                  final selectedCsv = const ListToCsvConverter().convert([headers, ...rowsToImport]);
                  final inserted = await repository.importSalesCsv(selectedCsv);
                  if (!mounted) return;
                  ScaffoldMessenger.of(localCtx).showSnackBar(SnackBar(content: Text('Inserted $inserted new sale${inserted == 1 ? '' : 's'}')));
                },
                icon: const Icon(Icons.download),
                label: const Text('Import'),
                backgroundColor: Colors.grey[700],
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filteredSales.isEmpty
              ? const Center(child: Text('No transactions yet'))
              : SizedBox(
                  width: double.infinity,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        cardTheme: CardThemeData(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                          color: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final reserved = 140.0;
                        var available = constraints.maxHeight - reserved;
                        if (available < 56) available = 56;
                        var estimated = (available ~/ 56).clamp(1, 10);
                        return SingleChildScrollView(
          child: PaginatedDataTable(
                            columnSpacing: 40,
                            rowsPerPage: estimated,
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
                              onDelete: (sale) async {
                                final localActionCtx = context;
                                if (!mounted) return;
                                final ok = await showDialog<bool>(
                                  context: localActionCtx,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete sale'),
                                    content: const Text('Are you sure you want to delete this sale?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                try {
                                  final res = await repository.deleteSaleById(sale.id);
                                  if (!mounted) return;
                                  if (res == -1) {
                                    await showDialog<void>(
                                      context: localActionCtx,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete failed'),
                                        content: const Text('Cannot delete sale because the buyer does not have enough points to reverse the award.'),
                                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  await showDialog<void>(
                                    context: localActionCtx,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete failed'),
                                      content: Text('Failed to delete sale: $e'),
                                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                                    ),
                                  );
                                }
                              },
                              onEdit: (sale) async {
                                final localActionCtx = context;
                                if (!mounted) return;
                                await showDialog<bool?>(
                                  context: localActionCtx,
                                  builder: (ctx) => SaleCartEditor(seedSale: sale),
                                );
                                // SaleCartEditor will trigger repository.changes on success
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _TransactionsDataSource extends DataTableSource {
  final List<Sale> _sales;
  final BuildContext _context;
  final Future<void> Function(Sale)? onDelete;
  final Future<void> Function(Sale)? onEdit;

  _TransactionsDataSource(this._sales, this._context, {this.onDelete, this.onEdit});

  @override
  DataRow getRow(int index) {
    if (index >= _sales.length) return const DataRow(cells: []);
    final sale = _sales[index];
    final isEven = index % 2 == 0;

    return DataRow(
          color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
            if (isEven) return Theme.of(_context).colorScheme.surfaceContainerHighest;
            return null;
          }),
      cells: [
        DataCell(Text(sale.itemName)),
        DataCell(Text(sale.quantity.toString())),
        DataCell(Text('₱${sale.price}')),
        DataCell(Text(DateFormat.yMMMd().add_jm().format(sale.timestamp))),
  DataCell(Text('ID:${sale.id}')),
  DataCell(Text(sale.timestamp.toLocal().toIso8601String())),
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
