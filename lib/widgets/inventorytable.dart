// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:lzcas/auth/auth_state.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/dialogs/edit_stock_dialog.dart' show EditProductDialog;
import 'package:lzcas/dialogs/add_product_dialog.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/widgets/modal_kit.dart' show confirmDestructive;
import 'package:lzcas/services/poster_service.dart' show PreparedPoster;
import 'package:lzcas/widgets/product_tile.dart';
import 'package:lzcas/widgets/staff_table.dart';
import '../services/config_service.dart';

/// When a product last changed, as a row says it: "12 min ago", "Today
/// 9:41 AM", "Yesterday", "1 Oct".
String _updated(dynamic raw) {
  if (raw == null) return '';
  final dt = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
  return dt == null ? raw.toString() : staffWhen(dt);
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
  List<String> _categories = [];

  // ── The counts on the caption and the chips ────────────────────────
  int _skuCount = 0;
  int _lowCount = 0;
  int _outCount = 0;
  int _totalUnits = 0;
  bool _summaryLoaded = false;

  // ── Sort (server-side; the column headers) ─────────────────────────
  String _sortColumn = 'name';
  bool _sortAscending = true;

  late final StreamSubscription<String> _sub;
  Timer? _liveRefresh;
  Timer? _searchDebounce;

  static const _pageSize = 25;

  // ── The loaded rows: the table and the phone list both scroll these ──
  final List<Map<String, dynamic>> _items = [];
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isInitialLoading = true;
  String? _error;
  late final ScrollController _scrollController;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadItems();
    _loadCategories();
    _loadSummary();
    // Live changes from any device: one POS cart arrives as a sale and a
    // stock update per line. They make one refresh, in place, so the list
    // keeps its place instead of jumping back to the top.
    _sub = repository.changes.listen((e) {
      if (e == 'item_updated' ||
          e == 'sale_added' ||
          e == 'item_imported' ||
          e == 'item_added' ||
          e == 'item_deleted') {
        _liveRefresh?.cancel();
        _liveRefresh = Timer(const Duration(milliseconds: 600), () {
          _refreshInPlace();
          _loadCategories();
          _loadSummary();
        });
      }
    });
  }

  /// Load the distinct category list that feeds the filter menu.
  Future<void> _loadCategories() async {
    try {
      final cats = await repository.fetchCategories();
      if (!mounted) return;
      setState(() => _categories = cats);
    } catch (_) {
      // Non-fatal — the menu just won't offer category options.
    }
  }

  /// Refresh the caption's and the chips' counts.
  Future<void> _loadSummary() async {
    if (!mounted) return;
    try {
      final s = await repository.fetchInventorySummary();
      if (!mounted) return;
      setState(() {
        _skuCount = s['skuCount'] ?? 0;
        _lowCount = s['lowCount'] ?? 0;
        _outCount = s['outCount'] ?? 0;
        _totalUnits = s['totalUnits'] ?? 0;
        _summaryLoaded = true;
      });
    } catch (_) {
      // Non-fatal — the strip just stays hidden / the chip shows no count.
    }
  }

  /// Apply a new sort and reload from the first page.
  void _applySort(String column, bool ascending) {
    if (_sortColumn == column && _sortAscending == ascending) return;
    setState(() {
      _sortColumn = column;
      _sortAscending = ascending;
    });
    _loadItems();
  }

  /// A header click: the same column flips; another starts the natural way
  /// (names A to Z, stock low first, newest change first).
  void _sortBy(String column) {
    if (_sortColumn == column) {
      _applySort(column, !_sortAscending);
    } else {
      _applySort(column, column != 'last_updated');
    }
  }

  bool? _arrow(String column) => _sortColumn == column ? _sortAscending : null;

  void _setStatus(String? status) {
    setState(() => selectedStatus = status);
    _loadItems();
  }

  void _setCategory(String? category) {
    setState(() => selectedCategory = category);
    _loadItems();
  }

  void _onSearchChanged(String value) {
    searchTerm = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadItems();
    });
  }

  /// Two-digit zero-pad for filename timestamps.
  String _two(int n) => n.toString().padLeft(2, '0');

  /// Export the current filtered/sorted view to a CSV file, then open it
  /// (desktop) so it drops straight into Excel/Sheets.
  Future<void> _exportCsv() async {
    if (_totalCount == 0) {
      BotToast.showText(text: 'Nothing to export');
      return;
    }
    BotToast.showText(text: 'Exporting…');
    try {
      final csv = await repository.exportItemsCsvFiltered(
        search: searchTerm.isNotEmpty ? searchTerm : null,
        categoryFilter:
            (selectedCategory != null && selectedCategory!.isNotEmpty)
            ? selectedCategory
            : null,
        statusFilter: (selectedStatus != null && selectedStatus!.isNotEmpty)
            ? selectedStatus
            : null,
        sortColumn: _sortColumn,
        sortAscending: _sortAscending,
      );

      // Downloads on desktop; app documents as a fallback (e.g. Android).
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory();

      final now = DateTime.now();
      final ts =
          '${now.year}${_two(now.month)}${_two(now.day)}_'
          '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
      final file = File(p.join(dir.path, 'inventory_$ts.csv'));
      await file.writeAsString(csv);

      // Open with the system default app so it lands in Excel/Sheets.
      if (Platform.isWindows) {
        await Process.run('cmd', [
          '/c',
          'start',
          '',
          file.path,
        ], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [file.path]);
      }

      if (!mounted) return;
      BotToast.showText(text: 'Exported to ${file.path}');
    } catch (e) {
      if (!mounted) return;
      BotToast.showText(text: 'Export failed: $e');
    }
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
  /// One page of the current search, filters and sort.
  Future<PageResult<Item>> _fetch(int page, int pageSize) =>
      repository.fetchItemsPaginated(
        page: page,
        pageSize: pageSize,
        search: searchTerm.isNotEmpty ? searchTerm : null,
        categoryFilter:
            (selectedCategory != null && selectedCategory!.isNotEmpty)
            ? selectedCategory
            : null,
        statusFilter: (selectedStatus != null && selectedStatus!.isNotEmpty)
            ? selectedStatus
            : null,
        sortColumn: _sortColumn,
        sortAscending: _sortAscending,
      );

  /// Re-reads every row already loaded, in one query, and swaps them in:
  /// same pages, same place on screen. For live changes; a new search,
  /// filter or sort still starts over at page 1.
  Future<void> _refreshInPlace() async {
    final loaded = _items.length;
    final pages = loaded <= _pageSize ? 1 : (loaded + _pageSize - 1) ~/ _pageSize;
    try {
      final result = await _fetch(1, pages * _pageSize);
      if (!mounted) return;
      final rows = inventoryItemsFromRows(result.rows);
      setState(() {
        _items
          ..clear()
          ..addAll(rows);
        _currentPage = pages;
        _totalCount = result.totalCount;
        _hasMore = result.hasMore;
        _error = null;
      });
    } catch (_) {
      // Keep showing what is there; the next change or a manual refresh
      // tries again.
    }
  }

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
        statusFilter: (selectedStatus != null && selectedStatus!.isNotEmpty)
            ? selectedStatus
            : null,
        sortColumn: _sortColumn,
        sortAscending: _sortAscending,
      );
      if (!mounted) return;
      // Status comes from the view (per-category threshold), carried in
      // each Item's status field — no client-side recompute needed.
      final newItems = inventoryItemsFromRows(result.rows);

      setState(() {
        if (page == 1) _items.clear();
        _items.addAll(newItems);
        _currentPage = page;
        _totalCount = result.totalCount;
        _hasMore = result.hasMore;
        _isInitialLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _onUpdate(Map<String, dynamic> item) {
    _refreshStatus(item);
    _loadItems();
  }

  void _refreshStatus(Map<String, dynamic> item) {
    // Optimistic per-category status; a reload from the view corrects it.
    final threshold = context.read<ConfigService>().thresholdForCategory(
      item["category"]?.toString(),
    );
    if (item["stock"] <= 0) {
      item["status"] = "Out of Stock";
    } else if ((item["stock"] as num) < threshold) {
      item["status"] = "Low Stock";
    } else {
      item["status"] = "Good";
    }
  }

  void _edit(Map<String, dynamic> item) {
    showAnimatedDialog(
      context,
      builder: (dialogContext) => EditProductDialog(
        item: item,
        onUpdated: () => _onUpdate(item),
      ),
    );
  }

  List<StaffMenuItem> _menu(Map<String, dynamic> item) => [
    StaffMenuItem('Edit product', Icons.edit_outlined, () => _edit(item)),
    StaffMenuItem('Delete product', Icons.delete_outline_rounded, () => _deleteItem(context, item), danger: true),
  ];

  /// The status pill: Good, Low, Out of stock.
  static Widget _statusPill(String status, {bool small = false}) => switch (status) {
    'Out of Stock' => StaffPill('Out of stock', tone: StaffTone.red, small: small),
    'Low Stock' => StaffPill('Low', tone: StaffTone.orange, small: small),
    'Good' => StaffPill('Good', tone: StaffTone.green, small: small),
    _ => StaffPill(status.isEmpty ? 'Unknown' : status, small: small),
  };

  String _caption() {
    if (!_summaryLoaded) return 'Products';
    return '${staffCount(_skuCount)} product${_skuCount == 1 ? '' : 's'} · '
        '${staffCount(_totalUnits)} units in stock';
  }

  List<Widget> _chips({required bool phone}) => [
    StaffChip(
      label: 'All',
      count: _summaryLoaded ? _skuCount : null,
      selected: selectedStatus == null,
      onTap: () => _setStatus(null),
    ),
    StaffChip(
      label: phone ? 'Low' : 'Low stock',
      count: _summaryLoaded ? _lowCount : null,
      selected: selectedStatus == 'Low Stock',
      tone: StaffTone.orange,
      onTap: () => _setStatus('Low Stock'),
    ),
    StaffChip(
      label: phone ? 'Out' : 'Out of stock',
      count: _summaryLoaded ? _outCount : null,
      selected: selectedStatus == 'Out of Stock',
      tone: StaffTone.red,
      onTap: () => _setStatus('Out of Stock'),
    ),
    StaffSelectChip<String?>(
      label: 'Category',
      value: selectedCategory,
      options: [(null, 'All'), for (final c in _categories) (c, c)],
      onChanged: _setCategory,
    ),
  ];

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
              search: StaffSearchField(hint: 'Search products', initialValue: searchTerm, onChanged: _onSearchChanged),
              actions: [
                StaffButton(label: 'Export', icon: Icons.file_download_outlined, primary: false, onPressed: _exportCsv),
                StaffButton(label: 'Add product', icon: Icons.add_rounded, onPressed: () => _openAddProductDialog(context)),
              ],
            ),
            const SizedBox(height: 14),
            StaffChipBar(chips: _chips(phone: false), hint: 'Click a row to edit'),
            const SizedBox(height: 14),
            Expanded(child: _buildTable(context)),
          ],
        );
      },
    );
  }

  /// Wide screens: Product · Category · Stock · Updated · ⋯
  Widget _buildTable(BuildContext context) {
    final s = StaffTableStyle.of(context);
    final q = searchTerm.trim();
    return StaffTable(
      controller: _scrollController,
      loading: _isInitialLoading,
      error: _error,
      onRetry: _loadItems,
      loadingMore: _hasMore && _items.isNotEmpty,
      onLoadMore: _loadMore,
      emptyText: q.isNotEmpty
          ? 'No products match "$q".'
          : (selectedStatus != null || selectedCategory != null)
          ? 'No products in this filter.'
          : 'No products yet.',
      footer: staffShowing(_items.length, _totalCount),
      itemCount: _items.length,
      onRowTap: (i) => _edit(_items[i]),
      columns: [
        StaffColumn('Product', flex: 26, onSort: () => _sortBy('name'), sortAscending: _arrow('name')),
        StaffColumn('Category', flex: 13, onSort: () => _sortBy('category'), sortAscending: _arrow('category')),
        StaffColumn('Stock', flex: 13, onSort: () => _sortBy('stock'), sortAscending: _arrow('stock')),
        StaffColumn('Updated', flex: 11, onSort: () => _sortBy('last_updated'), sortAscending: _arrow('last_updated')),
        const StaffColumn('', width: 48),
      ],
      cells: (context, i) {
        final item = _items[i];
        final name = (item['name'] ?? '').toString();
        return [
          Row(
            children: [
              ProductTile(name, imagePath: item['imagePath'] as String?, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name.isEmpty ? 'Unnamed product' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w700, color: s.text),
                ),
              ),
            ],
          ),
          Text(
            (item['category'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StockpileFonts.satoshi(fontSize: 16, color: s.body),
          ),
          Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44),
                child: Text(
                  '${item['stock'] ?? 0}',
                  style: StockpileFonts.satoshi(fontSize: 17, fontWeight: FontWeight.w800, color: s.text),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(child: _statusPill((item['status'] ?? '').toString())),
            ],
          ),
          Text(
            _updated(item['lastUpdated']),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StockpileFonts.satoshi(fontSize: 15, color: s.muted),
          ),
          StaffMoreButton(tooltip: 'More for $name', items: _menu(item)),
        ];
      },
    );
  }

  /// Phones: count, search, chips; the products in a card; Add product
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
            const Text('Could not load the products.'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _loadItems, child: const Text('Try again')),
          ],
        ),
      );
    } else if (_items.isEmpty) {
      list = Center(
        child: Text(
          searchTerm.trim().isEmpty ? 'No products here.' : 'No products match "${searchTerm.trim()}".',
          style: StockpileFonts.satoshi(fontSize: 15, color: s.muted),
        ),
      );
    } else {
      list = ListView(
        controller: _scrollController,
        // Room under the last row for the Add product button.
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          StaffPhoneCard(
            rows: [
              for (final item in _items)
                StaffPhoneRow(
                  leading: ProductTile(
                    (item['name'] ?? '').toString(),
                    imagePath: item['imagePath'] as String?,
                    size: 44,
                  ),
                  title: (item['name'] ?? '').toString().isEmpty ? 'Unnamed product' : item['name'].toString(),
                  lines: [
                    [
                      (item['category'] ?? '').toString(),
                      _updated(item['lastUpdated']),
                    ].where((p) => p.isNotEmpty).join(' · '),
                  ],
                  trailing: StaffPhoneValue(
                    '${item['stock'] ?? 0}',
                    pill: _statusPill((item['status'] ?? '').toString(), small: true),
                  ),
                  menu: _menu(item),
                  onTap: () => _edit(item),
                ),
            ],
          ),
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
        // The page around it already keeps the edges clear.
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: StaffPhoneTop(
            caption: _summaryLoaded ? '${staffCount(_skuCount)} products' : null,
            search: StaffSearchField(hint: 'Search products', height: 48, initialValue: searchTerm, onChanged: _onSearchChanged),
            chips: _chips(phone: true),
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
                  child: StaffFab(
                    label: 'Add product',
                    icon: Icons.add_rounded,
                    onPressed: () => _openAddProductDialog(context),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _openAddProductDialog(BuildContext parentCtx) {
    showAnimatedDialog(
      parentCtx,
      builder: (context) => AddProductDialog(
        onProductAdded: (p) async {
          final id = await repository.addItem(
            name: p['name']?.toString() ?? '',
            category: p['category']?.toString(),
            stock: (p['stock'] ?? 0) is int
                ? p['stock']
                : int.tryParse(p['stock']?.toString() ?? '0') ?? 0,
            lastUpdated: p['lastUpdated'] is DateTime
                ? p['lastUpdated'] as DateTime
                : null,
          );
          // The picture goes up once the product exists. If it fails, the
          // product is still added and the picture can be added from Edit.
          final photo = p['photo'];
          var photoFailed = false;
          if (photo is PreparedPoster && id > 0) {
            String? path;
            try {
              path = await repository.uploadProductImage(
                photo.bytes,
                extension: photo.extension,
                contentType: photo.contentType,
              );
              await repository.setItemImage(id, path);
            } catch (e) {
              debugPrint('Adding product picture failed: $e');
              await repository.deleteProductImage(path);
              photoFailed = true;
            }
          }
          _loadItems();
          if (!mounted) return;
          BotToast.showText(
            text: photoFailed
                ? 'Product added, but the picture could not be saved. '
                      'Add it from Edit product.'
                : 'Product added',
          );
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
    final stock = item['stock'] as int? ?? 0;
    // An admin's delete is a plain confirmation; an inventory user's is a
    // request with a required reason, so it keeps its own form.
    final confirm = !needsApproval
        ? await confirmDestructive(
            context,
            title: 'Delete ${item['name'] ?? 'this product'}?',
            message: "It disappears from the POS and inventory. This can't be undone.",
            detail: stock > 0 ? '$stock still in stock will be removed with it.' : null,
            confirmLabel: 'Delete product',
          )
        : await showDialog<bool>(
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
      await repository.submitPendingRequest(
        itemId: id,
        itemName: item['name']?.toString() ?? '',
        requestType: 'delete',
        reason: reason,
      );
      if (!context.mounted) return;
      BotToast.showText(text: 'Deletion request sent to admin for approval');
    } else {
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
    _liveRefresh?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }
}
