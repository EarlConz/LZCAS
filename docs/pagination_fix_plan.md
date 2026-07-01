# Pagination Fix Plan

> Generated 2026-07-01 | 6 fixes across 5 files | ~30 minutes of work

---

## Fix 1 🔴 P0 — `fetchRequestsPaginated`: wrong Supabase range + fake totalCount

**File:** `lib/data/supabase_repository.dart` lines 1177–1220  
**Root cause:** Supabase `.range()` is **inclusive** on both ends. Sending `range(0, 25)` returns 26 rows. The `totalCount` is also fabricated instead of queried.

### Code change

Replace the body of `fetchRequestsPaginated` (from `final rangeStart` through the `return PageResult(...)`):

```dart
  Future<PageResult<PendingRequest>> fetchRequestsPaginated({
    int page = 1,
    int pageSize = 25,
    String? statusFilter,
    String? userIdFilter,
    String? typeFilter,
    String? search,
    String sortColumn = 'created_at',
    bool sortAscending = false,
  }) async {
    final rangeStart = (page - 1) * pageSize;
    final rangeEnd = page * pageSize - 1; // ← was page*pageSize (off-by-one)

    // Run count query in parallel with data query (same pattern as fetchItemsPaginated)
    dynamic dataQuery = _supabase
        .from('pending_requests')
        .select()
        .order(sortColumn, ascending: sortAscending)
        .range(rangeStart, rangeEnd);

    dynamic countQuery = _supabase.from('pending_requests').select('id');

    final results = await Future.wait<dynamic>([
      countQuery.count(CountOption.exact),
      dataQuery,
    ]);

    final totalCount = (results[0] as PostgrestResponse).count;
    var all = (results[1] as List)
        .map((j) => PendingRequest.fromJson(j as Map<String, dynamic>))
        .toList();

    // Apply filters client-side (unchanged — these filters are NOT on DB columns)
    if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'all') {
      if (statusFilter == 'history') {
        all = all.where((r) => r.status != 'pending').toList();
      } else {
        all = all.where((r) => r.status == statusFilter).toList();
      }
    }
    if (userIdFilter != null && userIdFilter.isNotEmpty) {
      all = all.where((r) => r.userId == userIdFilter).toList();
    }
    if (typeFilter != null && typeFilter.isNotEmpty && typeFilter != 'all') {
      all = all.where((r) => r.requestType == typeFilter).toList();
    }
    if (search != null && search.isNotEmpty) {
      final s = search.toLowerCase();
      all = all.where((r) {
        return (r.itemName?.toLowerCase().contains(s) ?? false) ||
            (r.memberName?.toLowerCase().contains(s) ?? false) ||
            (r.reason?.toLowerCase().contains(s) ?? false);
      }).toList();
    }

    return PageResult(
      rows: all.take(pageSize).toList(),
      totalCount: totalCount,        // ← was fabricated; now real count
      page: page,
      pageSize: pageSize,
    );
  }
```

**Key changes:**
1. `rangeEnd` from `page * pageSize` → `page * pageSize - 1`
2. Added `Future.wait` with a `count()` query (same pattern as `fetchItemsPaginated`)
3. `totalCount` now uses the real count from the DB instead of `(page-1)*pageSize + rows.length + (hasMore?1:0)`

---

## Fix 2 🔴 P0 — `_loadItems` / `_loadMembers` stale sync after guard

**Files:** `lib/widgets/inventorytable.dart` lines 79–90, `lib/widgets/memberstable.dart` lines 69–82  
**Root cause:** When stream fires mid-fetch, `_fetchServerPage(1)` returns immediately (`if (_loading) return;`), but `_loadItems` still copies old `_serverPage` into `items`.

### Code change — `_fetchServerPage` (both files)

**Before (inventorytable.dart ~L94):**
```dart
  Future<void> _fetchServerPage(int serverPage) async {
    if (_loading) return;
```

**After:**
```dart
  /// Returns true if page was actually fetched; false if guard hit.
  Future<bool> _fetchServerPage(int serverPage) async {
    if (_loading) return false;
```

Also add `return true;` before the closing `}` of the try block (both files).

### Code change — `_loadItems` (inventorytable.dart)

**Before (L79–90):**
```dart
  Future<void> _loadItems() async {
    await _fetchServerPage(1);
    // For mobile: keep accumulated items in sync with page 1
    if (mounted) {
      setState(() {
        items = List.of(_serverPage);
        _currentPage = 1;
        _hasMore = _totalCount > _pageSize;
        _displayPage = 1;
      });
    }
  }
```

**After:**
```dart
  Future<void> _loadItems() async {
    final didFetch = await _fetchServerPage(1);
    if (!didFetch || !mounted) return;
    setState(() {
      items = List.of(_serverPage);
      _currentPage = 1;
      _hasMore = _totalCount > _pageSize;
      _displayPage = 1;
    });
  }
```

### Code change — `_loadMembers` (memberstable.dart)

**Before (L69–82):**
```dart
  Future<void> _loadMembers() async {
    await _fetchServerPage(1);
    if (mounted) {
      setState(() {
        members = List.of(_serverPage);
        _currentPage = 1;
        _hasMore = _totalCount > _pageSize;
        _displayPage = 1;
        final currentIds = members
            .map((member) => member['id'])
            .whereType<int>()
            .toSet();
        _selectedMemberIds.removeWhere((id) => !currentIds.contains(id));
      });
    }
  }
```

**After:**
```dart
  Future<void> _loadMembers() async {
    final didFetch = await _fetchServerPage(1);
    if (!didFetch || !mounted) return;
    setState(() {
      members = List.of(_serverPage);
      _currentPage = 1;
      _hasMore = _totalCount > _pageSize;
      _displayPage = 1;
      final currentIds = members
          .map((member) => member['id'])
          .whereType<int>()
          .toSet();
      _selectedMemberIds.removeWhere((id) => !currentIds.contains(id));
    });
  }
```

---

## Fix 3 🟠 P1 — `MyRequestsTab._loadRequests`: no re-entrancy guard

**File:** `lib/widgets/my_requests_tab.dart` line 87  
**Root cause:** `_loadRequests()` sets `_loading = true` but never checks it at the top, so rapid calls race.

### Code change

**Before (L87):**
```dart
  Future<void> _loadRequests() async {
    _loading = true;
    if (mounted) setState(() {});
```

**After:**
```dart
  Future<void> _loadRequests() async {
    if (_loading) return;
    _loading = true;
    if (mounted) setState(() {});
```

---

## Fix 4 🟡 P2 — Split shared `_loading` flag (desktop vs mobile)

**Files:** `lib/widgets/transactionstable.dart`, `lib/widgets/inventorytable.dart`, `lib/widgets/memberstable.dart`  
**Root cause:** One `_loading` flag gates both `_fetchServerPage` (desktop `PaginatedDataTable`) and `_loadNextPage` (mobile Load More). Desktop pagination can block the mobile load-more button.

### Code change (apply to all 3 files — show diff for inventorytable.dart)

Add a new field:
```dart
  bool _loadingMore = false;   // ← ADD: separate flag for mobile load-more
```

In `_fetchServerPage`, use `_loading` (unchanged):
```dart
  Future<bool> _fetchServerPage(int serverPage) async {
    if (_loading) return false;   // unchanged
```

In `_loadNextPage`, use `_loadingMore`:
```dart
  Future<void> _loadNextPage() async {
    if (_loadingMore || !_hasMore) return;   // ← was _loading
    _loadingMore = true;
    setState(() {});
    try {
      final page = await repository.fetchItemsPaginated(/* ... */);
      if (!mounted) return;
      setState(() {
        items.addAll(/* ... */);
        _currentPage = page.page;
        _hasMore = page.hasMore;
        _loadingMore = false;   // ← was _loading = false
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);   // ← was _loading = false
    }
  }
```

In `_buildInventoryList`, check `_loadingMore` instead of `_loading`:
```dart
        if (_loadingMore)   // ← was _loading
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
```

And in `onPageChanged`:
```dart
              if (needed > items.length && _hasMore && !_loadingMore) {   // ← was !_loading
                _loadNextPage().then((_) {
```

---

## Fix 5 🟡 P2 — Mobile pagination: use server `_totalCount` for page bar, not client `filtered.length`

**Files:** `lib/widgets/transactionstable.dart` ~L449, `lib/widgets/inventorytable.dart` ~L372, `lib/widgets/memberstable.dart` (similar)  
**Root cause:** `totalPages = (filtered.length / _pageSize).ceil()` uses client-side filtered count, so the pagination bar shows wrong total pages and never triggers fetches beyond what's locally loaded.

### Code change — inventorytable.dart `_buildInventoryList`

**Before (~L372):**
```dart
    final totalPages = (filteredItems.length / _pageSize).ceil();
```

**After:**
```dart
    // Use server total for accurate page count; filteredItems is client-side
    final totalPages = _searchTerm.isNotEmpty || selectedCategory != null
        ? (_totalCount / _pageSize).ceil()
        : (items.length / _pageSize).ceil();
```

### Code change — inventorytable.dart `onPageChanged`

**Before (~L398):**
```dart
            onPageChanged: (page) {
              final needed = page * _pageSize;
              if (needed > items.length && _hasMore && !_loading) {
                _loadNextPage().then((_) {
                  if (mounted) setState(() => _displayPage = page);
                });
              } else {
                setState(() => _displayPage = page);
              }
            },
```

**After:**
```dart
            onPageChanged: (page) {
              final needed = page * _pageSize;
              final hasLocally = needed <= items.length;
              if (!hasLocally && _hasMore && !_loadingMore) {
                _loadNextPage().then((_) {
                  if (mounted) setState(() => _displayPage = page);
                });
              } else {
                setState(() => _displayPage = page);
              }
            },
```

Same pattern applies to `transactionstable.dart` (line ~449, ~468) and `memberstable.dart`.

---

## Fix 6 🟡 P2 — `PaginatedListState._goToPage`: concurrent fetch race

**File:** `lib/utils/paginated_state.dart` lines 80–96  
**Root cause:** `setSearch()` calls `loadFirstPage()` → `_goToPage(1)`. If already loading, a second concurrent fetch starts and the first response can overwrite the second.

### Code change

**Before (L80):**
```dart
  Future<void> _goToPage(int page) async {
    _loading = true;
    _error = null;
    notifyListeners();
```

**After:**
```dart
  Future<void> _goToPage(int page) async {
    if (_loading) return;   // ← ADD: prevent concurrent fetches
    _loading = true;
    _error = null;
    notifyListeners();
```

Also update `setSearch` / `setExtraFilter` to queue instead of fire-and-forget:
```dart
  void setSearch(String? term) {
    _searchTerm = (term != null && term.trim().isEmpty) ? null : term?.trim();
    if (!_loading) loadFirstPage();   // ← was: loadFirstPage() unconditionally
  }

  void setExtraFilter(String? filter) {
    _extraFilter = (filter != null && filter.isEmpty) ? null : filter;
    if (!_loading) loadFirstPage();   // ← same
  }
```

---

## Execution Order

| Step | Fix | File | Safe to do alone? |
|------|-----|------|-------------------|
| 1 | Fix 1 — `fetchRequestsPaginated` range + count | `supabase_repository.dart` | ✅ Yes |
| 2 | Fix 6 — `PaginatedListState` concurrent guard | `paginated_state.dart` | ✅ Yes |
| 3 | Fix 3 — `_loadRequests` re-entrancy guard | `my_requests_tab.dart` | ✅ Yes |
| 4 | Fix 2 — `_fetchServerPage` returns `bool` | `inventorytable.dart` | ✅ Yes |
| 5 | Fix 2 — `_fetchServerPage` returns `bool` | `memberstable.dart` | ✅ Yes |
| 6 | Fix 4 — split `_loading` / `_loadingMore` | `transactionstable.dart` | ⚠️ Pair with Fix 5 |
| 7 | Fix 5 — use server total for page bar | `transactionstable.dart` | ⚠️ Pair with Fix 4 |
| 8 | Fix 4 — split `_loading` / `_loadingMore` | `inventorytable.dart` | ⚠️ Pair with Fix 5 |
| 9 | Fix 5 — use server total for page bar | `inventorytable.dart` | ⚠️ Pair with Fix 4 |
| 10 | Fix 4 — split `_loading` / `_loadingMore` | `memberstable.dart` | ⚠️ Pair with Fix 5 |
| 11 | Fix 5 — use server total for page bar | `memberstable.dart` | ⚠️ Pair with Fix 4 |

After all fixes, run:
```
flutter pub run build_runner build --delete-conflicting-outputs
flutter test
flutter run
```

---

## Verification Checklist (post-fix)

- [ ] Search for an item → page bar shows server page count, not local count
- [ ] Rapid double-tap "Load More" → only one fetch in console logs
- [ ] Edit an item → list refreshes without items disappearing
- [ ] Desktop `PaginatedDataTable` page change → mobile Load More still works
- [ ] `MyRequestsTab` → pagination bar shows correct total pages
- [ ] Last page of any table → hasMore=false, no extra fetch
- [ ] Change stream fires mid-fetch → stale data is NOT copied
