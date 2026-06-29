// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth_state.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/buttons/inventoryfilterbutton.dart';
import 'package:lzcas/widgets/search.dart';
import 'package:lzcas/dialogs/edit_stock_dialog.dart' show EditProductDialog;
import 'package:lzcas/dialogs/add_product_dialog.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/widgets/custom_elevated_button.dart';
import '../theme.dart';
import '../utils/formatters.dart';

/// Formats a raw ISO 8601 string using the shared POS timestamp format.
String _formatLastUpdated(dynamic raw) {
  if (raw == null) return '';
  final dt = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
  if (dt == null) return raw.toString();
  return formatDisplayDate(dt);
}

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
        final bool isMobile = constraints.maxWidth < 780;
        final bool isTablet =
            constraints.maxWidth >= 780 && constraints.maxWidth < 1050;
        final tableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        const minTableWidth = 860.0;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(appSpacing),
              child: isMobile
                  ? _buildMobileActionBar(context)
                  : _buildDesktopActionBar(context, isTablet),
            ),

            Expanded(
              child: isMobile
                  ? _buildInventoryList(context, filteredItems)
                  : LayoutBuilder(
                      builder: (context, tableConstraints) {
                        final availableHeight =
                            tableConstraints.hasBoundedHeight
                            ? tableConstraints.maxHeight
                            : MediaQuery.sizeOf(context).height;
                        // headingRowHeight(52) + internalPad(~62) + footer(~56) ≈ 170
                        final rowsPerPage = ((availableHeight - 170) ~/ 62)
                            .clamp(1, 7);

                        return SizedBox(
                          height: availableHeight,
                          width: double.infinity,
                          child: ClipRect(
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                cardTheme: CardThemeData(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      appRadius,
                                    ),
                                    side: BorderSide(
                                      color: Theme.of(context).dividerColor,
                                      width: 1,
                                    ),
                                  ),
                                  color: Theme.of(context).colorScheme.surface,
                                ),
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  height: availableHeight,
                                  width: tableWidth < minTableWidth
                                      ? minTableWidth
                                      : tableWidth,
                                  child: PaginatedDataTable(
                                    rowsPerPage: rowsPerPage,
                                    horizontalMargin: isTablet ? 12 : 16,
                                    columnSpacing: isTablet ? 20 : 36,
                                    headingRowHeight: 52,
                                    dataRowMinHeight: 56,
                                    dataRowMaxHeight: 62,
                                    showCheckboxColumn: false,
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
                        );
                      },
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
              onStatusChanged: (status) =>
                  setState(() => selectedStatus = status),
              onCategoryChanged: (category) =>
                  setState(() => selectedCategory = category),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: _buildAddButton(context))]),
      ],
    );
  }

  Widget _buildDesktopActionBar(BuildContext context, bool isTablet) {
    return Row(
      children: [
        Expanded(flex: isTablet ? 2 : 3, child: _buildSearchBar()),
        const SizedBox(width: 8),
        InventoryFilterButton(
          selectedStatus: selectedStatus,
          selectedCategory: selectedCategory,
          onStatusChanged: (status) => setState(() => selectedStatus = status),
          onCategoryChanged: (category) =>
              setState(() => selectedCategory = category),
        ),
        const SizedBox(width: 12),
        _buildAddButton(context),
      ],
    );
  }

  Widget _buildInventoryList(
    BuildContext context,
    List<Map<String, dynamic>> filteredItems,
  ) {
    if (filteredItems.isEmpty) {
      return const Center(child: Text('No items found'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      itemCount: filteredItems.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = filteredItems[index];
        return StaggeredItem(
          index: index,
          child: _InventoryListCard(
            item: item,
            statusColor: _getStatusColor(item['status']?.toString() ?? ''),
            onEdit: () {
              showAnimatedDialog(
                context,
                builder: (dialogContext) => EditProductDialog(
                  item: item,
                  onUpdated: () => _onUpdate(item),
                ),
              );
            },
            onDelete: () => _deleteItem(context, item),
          ),
        );
      },
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
      icon: Icon(
        Icons.add_business,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
      label: const Text(
        'Add Product',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      backgroundColor: Colors.blue[700],
      onPressed: () => _openAddProductDialog(context),
    );
  }

  void _openAddProductDialog(BuildContext parentCtx) {
    showAnimatedDialog(
      parentCtx,
      builder: (context) => AddProductDialog(
        onProductAdded: (p) async {
          await repository.addItem(
            name: p['name']?.toString() ?? '',
            category: p['category']?.toString(),
            stock: (p['stock'] ?? 0) is int
                ? p['stock']
                : int.tryParse(p['stock']?.toString() ?? '0') ?? 0,
            lastUpdated: p['lastUpdated'] is DateTime
                ? p['lastUpdated'] as DateTime
                : null,
          );
          await _loadItems();
          if (!mounted) return;
          BotToast.showText(text: 'Product added');
        },
      ),
    );
  }

  Future<void> _deleteItem(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final id = item['id'] as int?;
    if (id == null) return;

    // Check if current user is inventory (needs admin approval)
    final role = context.read<AuthState>().userRole;
    final needsApproval = role == UserRole.inventory;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(needsApproval ? 'Request deletion' : 'Delete product'),
        content: Text(
          needsApproval
              ? 'This will send a deletion request to an admin for approval. The product "${item['name']}" will not be deleted until approved.'
              : 'Are you sure you want to delete this product? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: needsApproval ? Colors.orange.shade700 : null,
            ),
            child: Text(needsApproval ? 'Send Request' : 'Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (needsApproval) {
      // Guard: block request if the item has active borrows
      final hasBorrows = await repository.hasActiveBorrows(id);
      if (!context.mounted) return;
      if (hasBorrows) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cannot request deletion'),
            content: const Text(
              'This product has unsettled borrows. '
              'All borrowed items must be returned or paid for '
              'before a deletion request can be submitted.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      await repository.submitPendingRequest(
        itemId: id,
        itemName: item['name']?.toString() ?? '',
        requestType: 'delete',
      );
      if (!context.mounted) return;
      BotToast.showText(text: 'Deletion request sent to admin for approval');
    } else {
      // Guard: block deletion if the item has active borrows
      final hasBorrows = await repository.hasActiveBorrows(id);
      if (!context.mounted) return;
      if (hasBorrows) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cannot delete'),
            content: const Text(
              'This product has unsettled borrows. '
              'All borrowed items must be returned or paid for '
              'before this product can be deleted.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      await repository.deleteItemById(id);
      await repository.fetchItems();
      _onUpdate(item);
      if (!context.mounted) return;
      BotToast.showText(text: 'Product deleted');
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

class _InventoryListCard extends StatelessWidget {
  const _InventoryListCard({
    required this.item,
    required this.statusColor,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> item;
  final Color statusColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = (item['name'] ?? '').toString().trim();
    final category = (item['category'] ?? '').toString().trim();
    final lastUpdated = (item['lastUpdated'] ?? '').toString().trim();
    final status = (item['status'] ?? '').toString().trim();

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
                    name.isEmpty ? 'Unnamed Product' : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Product actions',
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit Product')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Product'),
                    ),
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
                _InventoryMetaPill(
                  icon: Icons.inventory_2_outlined,
                  text: 'Stock ${item['stock'] ?? 0}',
                ),
                if (category.isNotEmpty)
                  _InventoryMetaPill(
                    icon: Icons.category_outlined,
                    text: category,
                  ),
                _InventoryMetaPill(
                  icon: Icons.circle,
                  text: status.isEmpty ? 'Unknown' : status,
                  color: statusColor,
                ),
              ],
            ),
            if (lastUpdated.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.update_outlined,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _formatLastUpdated(lastUpdated),
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
          ],
        ),
      ),
    );
  }
}

class _InventoryMetaPill extends StatelessWidget {
  const _InventoryMetaPill({
    required this.icon,
    required this.text,
    this.color,
  });

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = color ?? theme.colorScheme.onSurfaceVariant;

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
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 5),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryDataSource extends DataTableSource {
  final List<Map<String, dynamic>> items;
  final Color Function(String) getStatusColor;
  final void Function(Map<String, dynamic>) onUpdate;
  final BuildContext _context;

  _InventoryDataSource(
    this.items,
    this.getStatusColor,
    this.onUpdate,
    this._context,
  );

  @override
  DataRow getRow(int index) {
    if (index >= items.length) return const DataRow(cells: []);
    final item = items[index];
    final isEven = index % 2 == 0;

    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>((states) {
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
        DataCell(Text(item["name"] ?? "")),
        DataCell(Text(item["category"] ?? "")),
        DataCell(Text((item["stock"] ?? 0).toString())),
        DataCell(Text(_formatLastUpdated(item["lastUpdated"]))),
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
                  showAnimatedDialog(
                    cellContext,
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
                        content: const Text(
                          'Are you sure you want to delete this product? This action cannot be undone.',
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
                    if (confirm == true) {
                      // Guard: block deletion if the item has active borrows
                      final hasBorrows = await repository.hasActiveBorrows(id);
                      if (cellContext.mounted && hasBorrows) {
                        await showDialog<void>(
                          context: cellContext,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Cannot delete'),
                            content: const Text(
                              'This product has unsettled borrows. '
                              'All borrowed items must be returned or paid for '
                              'before this product can be deleted.',
                            ),
                            actions: [
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      } else if (cellContext.mounted) {
                        await repository.deleteItemById(id);
                        await repository.fetchItems();
                        onUpdate(item);
                        BotToast.showText(text: 'Product deleted');
                      }
                    }
                  }
                }
              },
              itemBuilder: (menuContext) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit Product')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete Product'),
                ),
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
