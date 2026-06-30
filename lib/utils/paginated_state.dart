// lib/utils/paginated_state.dart
// Generic pagination, filtering, and sorting state holder.
// Built on top of PageResult from supabase_repository.dart.

import 'package:flutter/material.dart';
import '../data/supabase_repository.dart' show PageResult;

export '../data/supabase_repository.dart' show PageResult;

/// Generic state holder for a paginated, filterable, sortable list.
///
/// Usage:
/// ```dart
/// final _state = PaginatedListState<Item>(
///   fetcher: (page, search, extraFilter, pageSize) =>
///       repository.fetchItemsPaginated(page: page, search: search, pageSize: pageSize),
///   pageSize: 100,
/// );
/// _state.loadFirstPage();
/// ```
class PaginatedListState<T> extends ChangeNotifier {
  final Future<PageResult<T>> Function(
    int page,
    String? search,
    String? extraFilter,
    int pageSize,
  )
  _fetcher;

  final int pageSize;

  PaginatedListState({
    required Future<PageResult<T>> Function(
      int page,
      String? search,
      String? extraFilter,
      int pageSize,
    )
    fetcher,
    this.pageSize = 100,
  }) : _fetcher = fetcher;

  List<T> _rows = [];
  int _totalCount = 0;
  int _currentPage = 1;
  bool _loading = false;
  String? _error;
  String? _searchTerm;
  String? _extraFilter;

  List<T> get rows => _rows;
  int get totalCount => _totalCount;
  int get currentPage => _currentPage;
  int get totalPages => _totalCount == 0 ? 1 : (_totalCount / pageSize).ceil();
  bool get isLoading => _loading;
  String? get error => _error;
  bool get hasNext => _currentPage < totalPages;
  bool get hasPrevious => _currentPage > 1;
  int get startIndex =>
      _totalCount == 0 ? 0 : (_currentPage - 1) * pageSize + 1;
  int get endIndex => (_currentPage * pageSize).clamp(0, _totalCount);

  /// Load the first page (called on init or when filters change).
  Future<void> loadFirstPage() async {
    await _goToPage(1);
  }

  /// Go to a specific page.
  Future<void> goToPage(int page) async {
    final target = page.clamp(1, totalPages);
    if (target == _currentPage && _rows.isNotEmpty && _searchTerm == null) {
      return;
    }
    await _goToPage(target);
  }

  Future<void> _goToPage(int page) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _fetcher(page, _searchTerm, _extraFilter, pageSize);
      _rows = result.rows;
      _totalCount = result.totalCount;
      _currentPage = page;
    } catch (e) {
      _error = e.toString();
      _rows = [];
    }

    _loading = false;
    notifyListeners();
  }

  /// Apply a search filter and reload from page 1.
  void setSearch(String? term) {
    _searchTerm = (term != null && term.trim().isEmpty) ? null : term?.trim();
    loadFirstPage();
  }

  /// Apply an extra filter and reload from page 1.
  void setExtraFilter(String? filter) {
    _extraFilter = (filter != null && filter.isEmpty) ? null : filter;
    loadFirstPage();
  }

  /// Reload the current page (call after a mutation).
  void refresh() {
    _goToPage(_currentPage);
  }
}
