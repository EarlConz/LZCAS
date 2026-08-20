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
  /// Pseudo-status for the quick "Needs restocking" filter (Low + Out).
  static const _needsRestockStatus = 'Needs Restocking';

  String searchTerm = "";
  String? selectedStatus;
  String? selectedCategory;
  List<String> _categories = [];

  // ── Summary strip figures ──────────────────────────────────────────
  int _skuCount = 0;
  int _lowCount = 0;
  int _outCount = 0;
  int _totalUnits = 0;
  bool _summaryLoaded = false;
  int get _needsRestockCount => _lowCount + _outCount;

  // ── Sort state (server-side; exposed via headers/menu) ─────────────
  String _sortColumn = 'name';
  bool _sortAscending = true;

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
  bool _fetchingServer = false; // a fetch loop is currently running
  int _pendingNeeded = 0; // highest requested row count (coalesces requests)
  bool _didInitialPrefetch = false; // primed page 2 once after first load
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
    _loadCategories();
    _loadSummary();
    _sub = repository.changes.listen((e) {
      if (e == 'item_updated' ||
          e == 'sale_added' ||
          e == 'item_imported' ||
          e == 'item_added' ||
          e == 'item_deleted') {
        _loadItems();
        _loadCategories();
        _loadSummary();
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

  /// Refresh the summary-strip figures (also feeds the "Needs restocking"
  /// quick filter count).
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

  /// Column index the desktop table header arrow should highlight, or
  /// null when the active sort isn't one of the sortable columns.
  int? _sortColumnIndex() {
    switch (_sortColumn) {
      case 'name':
        return 0;
      case 'category':
        return 1;
      case 'stock':
        return 2;
      case 'last_updated':
        return 3;
      default:
        return null;
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

  /// Clear every active filter in a single reload.
  void _clearFilters() {
    setState(() {
      selectedStatus = null;
      selectedCategory = null;
    });
    _loadItems();
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
        if (page == 1) {
          _items.clear();
          _serverPage.clear();
          _serverPage.addAll(newItems);
          _pendingNeeded = _serverPage.length;
          _didInitialPrefetch = false;
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

  /// Ensure `_serverPage` holds at least [neededCount] rows by loading
  /// consecutive server pages until it does (or all rows are loaded).
  ///
  /// NOTE: PaginatedDataTable.onPageChanged reports the *first row index* of
  /// the new table page — NOT a page number — so we translate the required
  /// row count into however many server pages that takes.
  Future<void> _ensureLoadedThrough(int neededCount) async {
    if (neededCount > _pendingNeeded) _pendingNeeded = neededCount;
    // A running loop re-reads _pendingNeeded each iteration, so a fast
    // multi-page jump (or a background prefetch racing a navigation) never
    // drops a request.
    if (_fetchingServer) return;
    _fetchingServer = true;
    try {
      while (_serverPage.length < _pendingNeeded &&
          (_totalCount == 0 || _serverPage.length < _totalCount)) {
        final nextPage = (_serverPage.length ~/ _pageSize) + 1;
        final before = _serverPage.length;
        await _fetchServerPage(nextPage);
        if (_serverPage.length <= before) break; // no progress — stop
      }
    } finally {
      _fetchingServer = false;
    }
  }

  /// Quietly load ONE page beyond what's loaded so the next forward step is
  /// instant. Fire-and-forget; ignored when a fetch is running or all rows
  /// are already loaded.
  void _prefetchNext() {
    final hasMore = _totalCount == 0 || _serverPage.length < _totalCount;
    if (hasMore) _ensureLoadedThrough(_serverPage.length + 1);
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
        statusFilter: (selectedStatus != null && selectedStatus!.isNotEmpty)
            ? selectedStatus
            : null,
        sortColumn: _sortColumn,
        sortAscending: _sortAscending,
      );
      if (!mounted) return;
      final newItems = inventoryItemsFromRows(page.rows);
      setState(() {
        _serverPage.addAll(newItems);
        _totalCount = page.totalCount;
      });
      _inventorySource.refresh();
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
            _buildSummaryStrip(context, isMobile),
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

                        // Desktop table is built → prime the second page once so
                        // the first "next" is already loaded. (Runs here so the
                        // mobile list never wastes a fetch into _serverPage.)
                        if (!_didInitialPrefetch && !_isInitialLoading) {
                          _didInitialPrefetch = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _prefetchNext();
                          });
                        }

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
                                    sortColumnIndex: _sortColumnIndex(),
                                    sortAscending: _sortAscending,
                                    columns: [
                                      DataColumn(
                                        label: const Text("Item Name"),
                                        onSort: (i, asc) =>
                                            _applySort('name', asc),
                                      ),
                                      DataColumn(
                                        label: const Text("Category"),
                                        onSort: (i, asc) =>
                                            _applySort('category', asc),
                                      ),
                                      DataColumn(
                                        label: const Text("Stock"),
                                        onSort: (i, asc) =>
                                            _applySort('stock', asc),
                                      ),
                                      DataColumn(
                                        label: const Text("Last Updated"),
                                        onSort: (i, asc) =>
                                            _applySort('last_updated', asc),
                                      ),
                                      const DataColumn(label: Text("Status")),
                                      const DataColumn(label: Text("Action")),
                                    ],
                                    source: _inventorySource,
                                    // pageIndex is the FIRST row index of the
                                    // new page, not a page number — load through
                                    // the last row this page needs, then quietly
                                    // prime the following page.
                                    onPageChanged: (pageIndex) =>
                                        _ensureLoadedThrough(
                                          pageIndex + rowsPerPage,
                                        ).then((_) => _prefetchNext()),
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
            _buildSortButton(),
            _buildExportButton(),
            InventoryFilterButton(
              selectedStatus: selectedStatus,
              selectedCategory: selectedCategory,
              categories: _categories,
              onStatusChanged: (status) {
                setState(() => selectedStatus = status);
                _loadItems();
              },
              onCategoryChanged: (category) {
                setState(() => selectedCategory = category);
                _loadItems();
              },
              onClear: _clearFilters,
            ),
          ],
        ),
        _buildActiveFilterChips(),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: _buildAddButton(context))]),
      ],
    );
  }

  Widget _buildDesktopActionBar(BuildContext context, bool isTablet) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: isTablet ? 2 : 3, child: _buildSearchBar()),
            const SizedBox(width: 8),
            InventoryFilterButton(
              selectedStatus: selectedStatus,
              selectedCategory: selectedCategory,
              categories: _categories,
              onStatusChanged: (status) {
                setState(() => selectedStatus = status);
                _loadItems();
              },
              onCategoryChanged: (category) {
                setState(() => selectedCategory = category);
                _loadItems();
              },
              onClear: _clearFilters,
            ),
            _buildExportButton(),
            const SizedBox(width: 12),
            _buildAddButton(context),
          ],
        ),
        _buildActiveFilterChips(),
      ],
    );
  }

  // ── Sort menu (mobile; desktop uses column headers) ────────────────

  /// Available sort orders as (label, column, ascending). Kept in sync
  /// with the server-side `sortColumn` values in fetchItemsPaginated.
  static const List<(String, String, bool)> _sortOptions = [
    ('Name (A–Z)', 'name', true),
    ('Name (Z–A)', 'name', false),
    ('Stock (low → high)', 'stock', true),
    ('Stock (high → low)', 'stock', false),
    ('Recently updated', 'last_updated', false),
  ];

  Widget _buildSortButton() {
    return PopupMenuButton<String>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort),
      onSelected: (value) {
        final parts = value.split('|');
        _applySort(parts[0], parts[1] == 'asc');
      },
      itemBuilder: (context) => [
        for (final (label, col, asc) in _sortOptions)
          CheckedPopupMenuItem(
            value: '$col|${asc ? 'asc' : 'desc'}',
            checked: _sortColumn == col && _sortAscending == asc,
            child: Text(label),
          ),
      ],
    );
  }

  Widget _buildExportButton() {
    return IconButton(
      tooltip: 'Export current view to CSV',
      icon: const Icon(Icons.file_download_outlined),
      onPressed: _exportCsv,
    );
  }

  // ── Active-filter chips ────────────────────────────────────────────

  Widget _buildActiveFilterChips() {
    final needsSelected = selectedStatus == _needsRestockStatus;
    final hasStatus = selectedStatus != null && selectedStatus!.isNotEmpty;
    final hasCategory =
        selectedCategory != null && selectedCategory!.isNotEmpty;
    final showQuick = _needsRestockCount > 0 || needsSelected;

    final children = <Widget>[];

    // Quick "Needs restocking" toggle — an entry point even with no other
    // filters, so it shows whenever there's anything to restock.
    if (showQuick) {
      final label = _needsRestockCount > 0
          ? '$_needsRestockCount ${_needsRestockCount == 1 ? 'item needs' : 'items need'} restocking'
          : 'Needs restocking';
      children.add(
        FilterChip(
          avatar: Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Colors.orange.shade800,
          ),
          label: Text(label),
          labelStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          selected: needsSelected,
          showCheckmark: false,
          selectedColor: Colors.orange.withValues(alpha: 0.20),
          onSelected: (sel) {
            setState(() => selectedStatus = sel ? _needsRestockStatus : null);
            _loadItems();
          },
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    // Generic status chip — skipped for the needs-restock pseudo status,
    // which the quick chip above already represents.
    if (hasStatus && !needsSelected) {
      children.add(
        _filterChip('Status: $selectedStatus', () {
          setState(() => selectedStatus = null);
          _loadItems();
        }),
      );
    }
    if (hasCategory) {
      children.add(
        _filterChip('Category: $selectedCategory', () {
          setState(() => selectedCategory = null);
          _loadItems();
        }),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();

    // "Clear all" only when more than one filter dimension is active.
    final activeDims = (hasStatus ? 1 : 0) + (hasCategory ? 1 : 0);

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...children,
            if (activeDims > 1)
              TextButton(
                onPressed: _clearFilters,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Clear all'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, VoidCallback onRemove) {
    return InputChip(
      label: Text(label),
      labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close, size: 16),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // ── Summary strip ──────────────────────────────────────────────────

  /// Group an integer with thousands separators, e.g. 1240 → "1,240".
  String _grouped(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return (n < 0 ? '-' : '') + buf.toString();
  }

  Widget _buildSummaryStrip(BuildContext context, bool isMobile) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final divider = theme.dividerColor.withValues(alpha: 0.5);

    // Before the first load resolves, render the strip's SHELL with shimmer
    // placeholders rather than returning an empty box. Collapsing it made the
    // page render as though the stats feature didn't exist, then pop in and
    // shove the table down — which reads as "the old design loaded first".
    // Reserving the space keeps the layout stable and shows zeros never.
    if (!_summaryLoaded) {
      return _summaryShell(
        theme,
        divider,
        List.generate(
          4,
          (_) => const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SkeletonBlock(width: 34, height: 18, borderRadius: 6),
                    SizedBox(height: 6),
                    SkeletonBlock(width: 46, height: 9, borderRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget stat(String value, String label, Color color) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: theme.hintColor,
            ),
          ),
        ],
      ),
    );

    Widget sep() => Container(width: 1, height: 30, color: divider);

    return _summaryShell(theme, divider, [
          stat('$_skuCount', 'Products', onSurface),
          sep(),
          stat(
            '$_lowCount',
            'Low',
            _lowCount > 0 ? Colors.orange.shade800 : onSurface,
          ),
          sep(),
          stat(
            '$_outCount',
            'Out',
            _outCount > 0 ? Colors.red.shade700 : onSurface,
          ),
          sep(),
      stat(_grouped(_totalUnits), 'Units', onSurface),
    ]);
  }

  /// The summary strip's outer container. Shared by the loaded and loading
  /// states so both occupy exactly the same space — that's what stops the
  /// table shifting once the figures arrive.
  Widget _summaryShell(ThemeData theme, Color divider, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.fromLTRB(appSpacing, appSpacing, appSpacing, 0),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(appRadius),
        border: Border.all(color: divider),
      ),
      child: Row(children: children),
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
      // Not fetched yet — show a shimmering skeleton row instead of raw text.
      return DataRow(
        cells: [
          skeletonCell(width: 150), // Item Name
          skeletonCell(width: 90), // Category
          skeletonCell(width: 50), // Stock
          skeletonCell(width: 100), // Last Updated
          skeletonCell(width: 70), // Status
          skeletonCell(width: 40), // Action
        ],
      );
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
