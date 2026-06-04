// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lzcas/buttons/inventoryfilterbutton.dart';
import 'package:lzcas/widgets/search.dart';
import 'package:lzcas/dialogs/edit_stock_dialog.dart' show EditProductDialog;
import 'package:lzcas/dialogs/add_product_dialog.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/widgets/custom_elevated_button.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'dart:typed_data';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:lzcas/dialogs/import_preview_dialog.dart';
import 'package:csv/csv.dart';
import '../db/csv_header_utils.dart';

class InventoryTable extends StatefulWidget {
  const InventoryTable({super.key});

  @override
  State<InventoryTable> createState() => _InventoryTableState();
}

class _InventoryTableState extends State<InventoryTable> {
  String searchTerm = "";
  String? selectedStatus;
  String? selectedCategory;

  List<Map<String, dynamic>> items = [];
  late final StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _sub = repository.changes.listen((e) {
      if (e == 'item_updated' ||
          e == 'sale_added' ||
          e == 'item_imported' ||
          e == 'item_added' ||
          e == 'item_deleted') {
        _loadItems();
      }
    });
  }

  Future<void> _loadItems() async {
    try {
      final rows = await repository.fetchItems();
      if (!mounted) return;
      setState(() {
        items = inventoryItemsFromRows(rows).map((m) {
          final stockVal = (m['stock'] ?? 0) is int
              ? m['stock'] as int
              : int.tryParse(m['stock']?.toString() ?? '0') ?? 0;
          m['status'] = statusFromStock(stockVal);
          return m;
        }).toList();
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('InventoryTable: failed to load items: $e\n$st');
      if (!mounted) return;
      setState(() {
        items = [];
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "Good":
        return Colors.green;
      case "Low Stock":
        return Colors.orange;
      case "Out of Stock":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _refreshStatus(Map<String, dynamic> item) {
    if (item["stock"] <= 0) {
      item["status"] = "Out of Stock";
    } else if (item["stock"] < 50) {
      item["status"] = "Low Stock";
    } else {
      item["status"] = "Good";
    }
  }

  void _onUpdate(Map<String, dynamic> item) {
    setState(() {
      _refreshStatus(item);
    });
    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = items.where((item) {
      final matchesSearch = item["name"].toString().toLowerCase().contains(
            searchTerm.toLowerCase(),
          );
      final matchesStatus =
          selectedStatus == null || item["status"] == selectedStatus;
      final matchesCategory =
          selectedCategory == null || item["category"] == selectedCategory;
      return matchesSearch && matchesStatus && matchesCategory;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 650;
        final bool isTablet = constraints.maxWidth >= 650 && constraints.maxWidth < 1050;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: isMobile 
                  ? _buildMobileActionBar(context) 
                  : _buildDesktopActionBar(context, isTablet),
            ),
            
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    cardTheme: CardThemeData(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                      color: Theme.of(context).cardColor,
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: isMobile ? 800 : constraints.maxWidth,
                      child: PaginatedDataTable(
                        rowsPerPage: 7,
                        horizontalMargin: 16,
                        columnSpacing: isTablet ? 20 : 40,
                        columns: const [
                          DataColumn(label: Text("Item Name")),
                          DataColumn(label: Text("Category")),
                          DataColumn(label: Text("Stock")),
                          DataColumn(label: Text("Last Updated")),
                          DataColumn(label: Text("Status")),
                          DataColumn(label: Text("Action")),
                        ],
                        source: _InventoryDataSource(
                          filteredItems,
                          _getStatusColor,
                          _onUpdate,
                          context,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMobileActionBar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _buildSearchBar()),
            const SizedBox(width: 8),
            InventoryFilterButton(
              selectedStatus: selectedStatus,
              selectedCategory: selectedCategory,
              onStatusChanged: (status) => setState(() => selectedStatus = status),
              onCategoryChanged: (category) => setState(() => selectedCategory = category),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildAddButton(context)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildExportButton(context)),
            const SizedBox(width: 8),
            Expanded(child: _buildImportButton(context)),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopActionBar(BuildContext context, bool isTablet) {
    return Row(
      children: [
        Expanded(
          flex: isTablet ? 2 : 3, 
          child: _buildSearchBar(),
        ),
        const SizedBox(width: 8),
        InventoryFilterButton(
          selectedStatus: selectedStatus,
          selectedCategory: selectedCategory,
          onStatusChanged: (status) => setState(() => selectedStatus = status),
          onCategoryChanged: (category) => setState(() => selectedCategory = category),
        ),
        const SizedBox(width: 12),
        _buildAddButton(context),
        const SizedBox(width: 8),
        _buildExportButton(context),
        const SizedBox(width: 8),
        _buildImportButton(context),
      ],
    );
  }


  Widget _buildSearchBar() {
    return SearchBarWidget(
      onChanged: (value) => setState(() => searchTerm = value),
      hintText: "Search items...",
      borderRadius: 12,
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return CustomElevatedButton(
      icon: Icon(Icons.add_business, color: Theme.of(context).colorScheme.onPrimary),
      label: const Text('Add Product', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: Colors.blue[700],
      onPressed: () => _openAddProductDialog(context),
    );
  }

  Widget _buildExportButton(BuildContext context) {
    return CustomElevatedButton(
      icon: Icon(Icons.upload_file, color: Theme.of(context).colorScheme.onPrimary),
      label: const Text('Export CSV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: Colors.grey[700],
      onPressed: () => _handleExportCsv(context),
    );
  }

  Widget _buildImportButton(BuildContext context) {
    return CustomElevatedButton(
      icon: Icon(Icons.download, color: Theme.of(context).colorScheme.onPrimary),
      label: const Text('Import CSV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: Colors.grey[700],
      onPressed: () => _handleImportCsv(context),
    );
  }


  void _openAddProductDialog(BuildContext parentCtx) {
    showDialog(
      context: parentCtx,
      builder: (context) => AddProductDialog(
        onProductAdded: (p) async {
          await repository.addItem(
            name: p['name']?.toString() ?? '',
            points: (p['points'] ?? 0) is int
                ? p['points']
                : int.tryParse(p['points']?.toString() ?? '0') ?? 0,
            category: p['category']?.toString(),
            stock: (p['stock'] ?? 0) is int
                ? p['stock']
                : int.tryParse(p['stock']?.toString() ?? '0') ?? 0,
          );
          await _loadItems();
          if (!mounted) return;
          ScaffoldMessenger.of(parentCtx).showSnackBar(
            const SnackBar(content: Text('Product added')),
          );
        },
      ),
    );
  }

  Future<void> _handleExportCsv(BuildContext parentCtx) async {
    final csv = await repository.exportItemsCsvString();
    final suggested = 'items_export_${DateTime.now().millisecondsSinceEpoch}.csv';
    try {
      final fs.FileSaveLocation? loc = await fs.getSaveLocation(suggestedName: suggested);
      if (loc != null) {
        final xfile = fs.XFile.fromData(
          Uint8List.fromList(csv.codeUnits),
          mimeType: 'text/csv',
          name: suggested,
        );
        await xfile.saveTo(loc.path);
        if (!mounted) return;
        ScaffoldMessenger.of(parentCtx).showSnackBar(
          SnackBar(content: Text('Exported to ${loc.path}')),
        );
      }
    } catch (e) {
      final dir = Directory.current.path;
      final savePath = p.join(dir, suggested);
      await File(savePath).writeAsString(csv);
      if (!mounted) return;
      ScaffoldMessenger.of(parentCtx).showSnackBar(
        SnackBar(content: Text('Exported to $savePath')),
      );
    }
  }

  Future<void> _handleImportCsv(BuildContext localCtx) async {
    final files = await fs.openFiles(
      acceptedTypeGroups: [fs.XTypeGroup(label: 'CSV', extensions: ['csv'])],
    );
    if (files.isEmpty) return;
    final xfile = files.first;
    final content = await xfile.readAsString();
    final parsed = const CsvToListConverter().convert(content);
    if (parsed.isEmpty) return;
    final headers = parsed.first.map((e) => e.toString()).toList();
    final rows = parsed.sublist(1).map((r) => r.map((c) => c?.toString() ?? '').toList()).toList();
    if (!mounted) return;

    final expected = ['id', 'name', 'points', 'category', 'stock', 'lastupdated', 'status'];
    final missing = findMissingHeaders(headers.cast<String>(), expected);
    if (missing.isNotEmpty) {
      await showDialog<void>(
        context: localCtx,
        builder: (ctx) => AlertDialog(
          title: const Text('Invalid CSV'),
          content: Text('Missing headers: ${missing.join(', ')}'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    final sel = await showImportPreviewDialogWithSelection(
      localCtx,
      headers,
      rows,
      exists: (m) async {
        final idStr = (m['id'] ?? '').trim();
        if (idStr.isNotEmpty) {
          final id = int.tryParse(idStr);
          if (id != null) {
            final all = await repository.fetchItems();
            if (all.any((it) => it.id == id)) return true;
          }
        }
        final name = (m['name'] ?? '').trim();
        if (name.isEmpty) return false;
        final all = await repository.fetchItems();
        return all.any((it) => it.name.trim().toLowerCase() == name.toLowerCase());
      },
    );
    if (sel == null || sel.isEmpty) return;
    final rowsToImport = sel.map((i) => rows[i]).toList();
    final selectedCsv = const ListToCsvConverter().convert([headers, ...rowsToImport]);
    final count = await repository.importItemsCsv(selectedCsv);
    if (!mounted) return;
    await _loadItems();
    ScaffoldMessenger.of(localCtx).showSnackBar(
      SnackBar(content: Text('Imported $count rows from ${xfile.name}')),
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

class _InventoryDataSource extends DataTableSource {
  final List<Map<String, dynamic>> items;
  final Color Function(String) getStatusColor;
  final void Function(Map<String, dynamic>) onUpdate;
  final BuildContext _context;

  _InventoryDataSource(this.items, this.getStatusColor, this.onUpdate, this._context);

  @override
  DataRow getRow(int index) {
    if (index >= items.length) return const DataRow(cells: []);
    final item = items[index];
    final isEven = index % 2 == 0;
    
    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>((states) {
        if (isEven) return Theme.of(_context).colorScheme.surfaceContainerHighest;
        return null;
      }),
      cells: [
        DataCell(Text(item["name"] ?? "")),
        DataCell(Text(item["category"] ?? "")),
        DataCell(Text((item["stock"] ?? 0).toString())),
        DataCell(Text(item["lastUpdated"] ?? "")),
        DataCell(
          Text(
            item["status"]?.toString() ?? "",
            style: TextStyle(
              color: getStatusColor(item["status"]?.toString() ?? ""),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        DataCell(
          Builder(
            builder: (cellContext) => PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'edit') {
                  showDialog(
                    context: cellContext,
                    builder: (dialogContext) => EditProductDialog(
                      item: item,
                      onUpdated: () => onUpdate(item),
                    ),
                  );
                } else if (value == 'delete') {
                  final id = item['id'] as int?;
                  if (id != null) {
                    final confirm = await showDialog<bool>(
                      context: cellContext,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete product'),
                        content: const Text('Are you sure you want to delete this product? This action cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await repository.deleteItemById(id);
                      await repository.fetchItems();
                      onUpdate(item);
                      if (cellContext.mounted) {
                        ScaffoldMessenger.of(cellContext).showSnackBar(
                          const SnackBar(content: Text('Product deleted')),
                        );
                      }
                    }
                  }
                }
              },
              itemBuilder: (menuContext) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit Product')),
                const PopupMenuItem(value: 'delete', child: Text('Delete Product')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => items.length;
  @override
  int get selectedRowCount => 0;
}