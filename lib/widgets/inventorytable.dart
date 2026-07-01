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
import '../services/config_service.dart';

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

  late final StreamSubscription<String> _sub;

  static const _pageSize = 25;

  // ── Mobile infinite-scroll state ──────────────────────────────────
  final List<Map<String, dynamic>> _items = [];
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isInitialLoading = true;
  String? _error;
  late final ScrollController _scrollController;

  // ── Server-page state for desktop PaginatedDataTable ──────────────
  final List<Map<String, dynamic>> _serverPage = [];
  int _totalCount = 0;
  late final _InventoryDataSource _inventorySource;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _inventorySource = _InventoryDataSource(
      _serverPage,
      () => _totalCount,
      _getStatusColor,
      _onUpdate,
      _deleteItem,
    );
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

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  /// Reload from page 1 — resets both mobile and desktop data.
  void _loadItems() {
    _loadPage(1);
  }

  void _loadMore() {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    setState(() {});
    _loadPage(_currentPage + 1);
  }

  /// Core page fetcher.  page=1 resets accumulated items; page>1 appends.
  Future<void> _loadPage(int page) async {
    try {
      final result = await repository.fetchItemsPaginated(
        page: page,
        pageSize: _pageSize,
        search: searchTerm.isNotEmpty ? searchTerm : null,
        categoryFilter:
            (selectedCategory != null && selectedCategory!.isNotEmpty)
            ? selectedCategory
            : null,
        sortColumn: 'name',
        sortAscending: true,
      );
      if (!mounted) return;
      final threshold = context.read<ConfigService>().lowStockThreshold;
      final newItems = inventoryItemsFromRows(result.rows).map((m) {
        final stockVal = (m['stock'] ?? 0) is int
            ? m['stock'] as int
            : int.tryParse(m['stock']?.toString() ?? '0') ?? 0;
        m['status'] = statusFromStock(stockVal, threshold: threshold);
        return m;
      }).toList();

      setState(() {
        if (page == 1) {
          _items.clear();
          _serverPage.clear();
          _serverPage.addAll(newItems);
        }
        _items.addAll(newItems);
        _currentPage = page;
        _totalCount = result.totalCount;
        _hasMore = result.hasMore;
        _isInitialLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
      if (page == 1) {
        _inventorySource.refresh();
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

  /// Fetch a specific server page — updates desktop PaginatedDataTable.
  /// Accumulates pages into _serverPage; getRow reads _serverPage[index]
  /// directly, so table pages and server pages don’t need to align.
  Future<void> _fetchServerPage(int serverPage) async {
    // Already loaded enough data for this page?
    final neededEnd = serverPage * _pageSize;
    if (_serverPage.length >= neededEnd) return;
    try {
      final page = await repository.fetchItemsPaginated(
        page: serverPage,
        pageSize: _pageSize,
        search: searchTerm.isNotEmpty ? searchTerm : null,
        categoryFilter:
            (selectedCategory != null && selectedCategory!.isNotEmpty)
            ? selectedCategory
            : null,
        sortColumn: 'name',
        sortAscending: true,
      );
      if (!mounted) return;
      final threshold = context.read<ConfigService>().lowStockThreshold;
      final newItems = inventoryItemsFromRows(page.rows).map((m) {
        final stockVal = (m['stock'] ?? 0) is int
            ? m['stock'] as int
            : int.tryParse(m['stock']?.toString() ?? '0') ?? 0;
        m['status'] = statusFromStock(stockVal, threshold: threshold);
        return m;
      }).toList();
      setState(() {
        _serverPage.addAll(newItems);
        _totalCount = page.totalCount;
      });
    } catch (e) {
      if (!mounted) return;
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
    final threshold = context.read<ConfigService>().lowStockThreshold;
    if (item["stock"] <= 0) {
      item["status"] = "Out of Stock";
    } else if ((item["stock"] as num) < threshold) {
      item["status"] = "Low Stock";
    } else {
      item["status"] = "Good";
    }
  }

  void _onUpdate(Map<String, dynamic> item) {
    _refreshStatus(item);
    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
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
                  ? _buildInventoryList(context)
                  : LayoutBuilder(
                      builder: (context, tableConstraints) {
                        final availableHeight =
                            tableConstraints.hasBoundedHeight
                            ? tableConstraints.maxHeight
                            : MediaQuery.sizeOf(context).height;
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
                                    source: _inventorySource,
                                    onPageChanged: (pageIndex) =>
                                        _fetchServerPage(pageIndex + 1),
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

  // ── Action Bar ─────────────────────────────────────────────────────

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
              onCategoryChanged: (category) {
                setState(() => selectedCategory = category);
                _loadItems();
              },
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
          onCategoryChanged: (category) {
            setState(() => selectedCategory = category);
            _loadItems();
          },
        ),
        const SizedBox(width: 12),
        _buildAddButton(context),
      ],
    );
  }

  // ── Mobile List (infinite-scroll) ──────────────────────────────────

  Widget _buildInventoryList(BuildContext context) {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Failed to load items.'),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadItems, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No items found'));
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final item = _items[index];
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

  // ── Desktop Table ──────────────────────────────────────────────────
  // (uses PaginatedDataTable which paginates the already-loaded data in-memory)

  Widget _buildSearchBar() {
    return SearchBarWidget(
      onChanged: (value) {
        searchTerm = value;
        _loadItems();
      },
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
          _loadItems();
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

    final role = context.read<AuthState>().userRole;
    final needsApproval = role == UserRole.inventory;

    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(needsApproval ? 'Request deletion' : 'Delete product'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                needsApproval
                    ? 'This will send a deletion request to an admin for approval. The product "${item['name']}" will not be deleted until approved.'
                    : 'Are you sure you want to delete this product? This action cannot be undone.',
              ),
              if (needsApproval) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  autofocus: true,
                  maxLines: 3,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Reason for deletion',
                    hintText: 'Explain why this product should be deleted',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: needsApproval && reasonController.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: needsApproval ? Colors.orange.shade700 : null,
              ),
              child: Text(needsApproval ? 'Send Request' : 'Delete'),
            ),
          ],
        ),
      ),
    );
    final reason = reasonController.text.trim();

    if (confirm != true) return;

    if (needsApproval) {
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
        reason: reason,
      );
      if (!context.mounted) return;
      BotToast.showText(text: 'Deletion request sent to admin for approval');
    } else {
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
    _scrollController.dispose();
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
  final List<Map<String, dynamic>> _items;
  final int Function() _getTotalCount;
  final Color Function(String) getStatusColor;
  final void Function(Map<String, dynamic>) onUpdate;
  final Future<void> Function(BuildContext, Map<String, dynamic>) onDelete;

  _InventoryDataSource(
    this._items,
    this._getTotalCount,
    this.getStatusColor,
    this.onUpdate,
    this.onDelete,
  );

  @override
  int get rowCount => _getTotalCount();

  @override
  DataRow getRow(int index) {
    if (index >= _items.length) {
      return DataRow(cells: List.filled(6, const DataCell(Text('Loading…'))));
    }
    final item = _items[index];
    final isEven = index % 2 == 0;

    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.hovered)) {
          return Colors.grey.withAlpha(18);
        }
        if (isEven) {
          return Colors.grey.withAlpha(20);
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
                  await onDelete(cellContext, item);
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
  int get selectedRowCount => 0;

  /// Call after external data changes to refresh the table.
  void refresh() => notifyListeners();
}
