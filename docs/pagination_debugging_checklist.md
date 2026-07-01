# Pagination Debugging Checklist & Audit Report

> Generated 2026-07-01 — based on audit of `lib/widgets/transactionstable.dart`, `lib/widgets/inventorytable.dart`, `lib/widgets/memberstable.dart`, `lib/widgets/my_requests_tab.dart`, `lib/utils/paginated_state.dart`, and `lib/data/supabase_repository.dart`.

---

## 🚨 Critical Bugs Found (fix these first)

### 1.  `fetchRequestsPaginated` — wrong range + fake totalCount

**File:** `lib/data/supabase_repository.dart` ~L1177  
**Problem:** Uses `rangeEnd = page * pageSize` instead of `page * pageSize - 1`.  
Supabase uses **inclusive** ranges, so page 1 with size 25 sends `range(0, 25)` which returns **26 rows**, not 25.  
`totalCount` is fabricated: `(page - 1) * pageSize + rows.length + (hasMore ? 1 : 0)`. This drifts with every page.

**Symptoms:** Pagination bar shows wrong total pages. `_displayPage` skips around.

**Fix:**
```dart
// Change:
final rangeEnd = page * pageSize;
// To:
final rangeEnd = page * pageSize - 1;

// Also: add a proper count query (like fetchItemsPaginated does):
final countData = await _supabase.from('pending_requests').select('id').count(CountOption.exact);
```

---

### 2.  `_loadItems()` / `_loadMembers()` sync stale `_serverPage` after guard rejects

**Files:** `inventorytable.dart` ~L82, `memberstable.dart` ~L72  
**Problem:**
```dart
Future<void> _loadItems() async {
  await _fetchServerPage(1);       // ← returns early if _loading == true
  if (mounted) {
    setState(() {
      items = List.of(_serverPage); // ← copies STALE data!
      _currentPage = 1;
      _hasMore = _totalCount > _pageSize;
      _displayPage = 1;
    });
  }
}
```
When a change-stream event fires while a fetch is already in-flight, `_fetchServerPage` returns immediately (guard: `if (_loading) return;`). Then `_loadItems` overwrites `items` with the **previous** page's data — wiping newly loaded rows.

**Symptom:** Items/members "disappear" after a sale or edit.

**Fix:**
```dart
Future<void> _loadItems() async {
  final didFetch = await _fetchServerPage(1);
  if (!didFetch || !mounted) return; // ← only sync if fetch actually ran
  setState(() {
    items = List.of(_serverPage);
    _currentPage = 1;
    _hasMore = _totalCount > _pageSize;
    _displayPage = 1;
  });
}

// Change _fetchServerPage to return bool:
Future<bool> _fetchServerPage(int serverPage) async {
  if (_loading) return false; // ← return false, guard hit
  _loading = true;
  // ... fetch logic ...
  return true; // ← successful fetch
}
```

---

### 3.  `MyRequestsTab._loadRequests()` — no re-entrancy guard

**File:** `my_requests_tab.dart` ~L87  
**Problem:** `_loadRequests()` sets `_loading = true` but **doesn't check it at the top**. If called rapidly (fast double-tap, stream event), two network calls race and the second `setState` overwrites the first.

**Fix:** Add `if (_loading) return;` at the top of `_loadRequests()`.

---

### 4.  Desktop `PaginatedDataTable` + mobile list share `_loading` flag — false conflicts

**Files:** `transactionstable.dart`, `inventorytable.dart`, `memberstable.dart`  
**Problem:** The same `_loading` flag gates both `_fetchServerPage()` (desktop) and `_loadNextPage()` (mobile). On desktop, if you change pages rapidly, the guard prevents the second call — correct. But the guard in `_fetchServerPage` ALSO blocks the mobile "Load More" from working if a desktop fetch is in-flight.

**Symptom:** "Load More" appears stuck on tablet/desktop breakpoints.

**Fix:** Split into `_loadingServer` (for `PaginatedDataTable`) and `_loadingMore` (for mobile infinite-scroll). Only the mobile variant should show a spinner at the bottom.

---

### 5.  `PaginationBar` `onPageChanged` checks unfiltered `_txnGroups` length, not filtered

**Files:** `transactionstable.dart` ~L370, `inventorytable.dart` ~L380, `memberstable.dart` (similar pattern)  
**Problem:**
```dart
onPageChanged: (page) {
  final needed = page * _pageSize;
  if (needed > _txnGroups.length && _hasMore && !_loading) {
    _loadNextPage();  // ← fetches from SERVER (not filtered)
  }
}
```
`_txnGroups` is the **unfiltered** accumulated list. If the user searches "John" and the first 25 server rows contain 3 matching rows, `needed` will be `50` and `_txnGroups.length` might be `25`, so it fetches more from the server. But the server doesn't know about the client-side search filter on `buyerName` — the search is applied client-side!

**Wait —** in `transactionstable.dart`, `_loadNextPage` does pass `_searchTerm` to the API. But in `_buildList`, the search on `_txnGroups` is **also** client-side. So the flow is:
1. Server returns 25 sales (all buyers)
2. Client-side filter reduces to 3 matching "John"
3. Pagination bar shows "page 1 of 1" (3 items / 25 = 1 page)
4. User can't reach page 2, so `_loadNextPage` never fires
5. → Items on server page 2+ are never fetched → **items disappear**

This is actually a **design flaw**, not just a bug. The search should be passed to `_fetchPage` which DOES filter server-side (`ilike`), but the pagination bar uses client-side `filtered.length` for page count, creating a mismatch.

**Fix:** The mobile list pagination should use server-side page counts (`_totalCount`) for the pagination bar, not client-side `filtered.length`. Or, when `_searchTerm` is non-empty, always fetch from the server for every page.

---

### 6.  `PaginatedListState<T>` — setSearch while loading race

**File:** `lib/utils/paginated_state.dart` ~L91  
**Problem:** `setSearch()` calls `loadFirstPage()` → `_goToPage(1)`. If a fetch is already in-flight, `_goToPage` overwrites `_loading = true` and starts a **second concurrent fetch**. The first fetch's response will then overwrite the second's results.

**Fix:** Cancel or ignore if already loading, and queue the reload:
```dart
void setSearch(String? term) {
  _searchTerm = (term != null && term.trim().isEmpty) ? null : term?.trim();
  _pendingReload = true;
  if (!_loading) loadFirstPage();
}
```

---

## 📋 5-State Debugging Checklist

For each paginated widget, verify these 5 states. Use `PaginationLogger` (in `lib/utils/pagination_logger.dart`) to instrument:

### State 1: Before Network Call

| Check | Pass? |
|-------|-------|
| `requestedPage` ≤ `totalPages`? | ☐ |
| `isLoading` is `false` (no concurrent call)? | ☐ |
| If `isLoading` is `true`, is there a guard at the top of the method (`if (_loading) return;`)? | ☐ |
| `_currentPage` reflects the last successfully fetched page (not about to be overwritten)? | ☐ |
| No stale `_searchTerm` from a previous filter? | ☐ |

### State 2: Network Call Parameters

| Check | Pass? |
|-------|-------|
| Page is 1-indexed (not 0-indexed)? Supabase `range()` expects inclusive `[start, end]`. | ☐ |
| `rangeStart = (page - 1) * pageSize` is correct? | ☐ |
| `rangeEnd = page * pageSize - 1` (NOT `page * pageSize`)? | ☐ |
| Search term is passed to the API (not only client-side filtered)? | ☐ |
| Sort column + direction are explicit (not relying on DB defaults)? | ☐ |

### State 3: Response Payload

| Check | Pass? |
|-------|-------|
| `rowCount` matches expected `pageSize` (or less on last page)? | ☐ |
| If `rowCount == 0`, is `totalCount` also 0? | ☐ |
| `hasMore` is computed from `page < totalPages` (using server `totalCount`)? | ☐ |
| `totalCount` comes from a `count()` query — NOT estimated? | ☐ |
| No extra row fetched (range off-by-one)? | ☐ |

### State 4: State Transition

| Check | Pass? |
|-------|-------|
| For page 1: `items = page.rows` (assignment, not addAll)? | ☐ |
| For page N>1: `items.addAll(page.rows)` (addAll, not assignment)? | ☐ |
| `_currentPage` updated to `page` (from server response, not request)? | ☐ |
| `_hasMore` updated from `page.hasMore`? | ☐ |
| `isLoading` set to `false` in BOTH success AND error paths? | ☐ |
| No `setState` after `if (!mounted) return`? | ☐ |

### State 5: Final Local Count

| Check | Pass? |
|-------|-------|
| `localCount` matches expected: `previousCount + newRows.length` (or `newRows.length` for page 1)? | ☐ |
| If `localCount == 0` but API returned data, check the `.map()` / converter pipeline. | ☐ |
| `totalPages = (totalCount / pageSize).ceil()` matches the pagination bar? | ☐ |
| The pagination bar uses server `_totalCount`, not client-side `filtered.length`, for page count? | ☐ |
| On desktop: `PaginatedDataTable.onPageChanged` fires `_fetchServerPage(pageIndex + 1)` (0→1 conversion)? | ☐ |

---

## 🔁 Infinite Fetch Loop Checklist

| Check | Pass? |
|-------|-------|
| `_hasMore` is set to `false` when `page >= totalPages`? | ☐ |
| Guard at top of fetch method: `if (_loading || !_hasMore) return;`? | ☐ |
| Guard at top of `_loadNextPage()`: `if (_loading || !_hasMore) return;`? | ☐ |
| Stream listener doesn't call fetch when `_loading == true`? | ☐ |
| `PaginationBar.onPageChanged` doesn't trigger `_loadNextPage` when `needed <= items.length`? | ☐ |
| No `setState(() => _loading = true)` without corresponding `_loading = false` in error path? | ☐ |
| `refresh()` / `loadFirstPage()` doesn't create a fetch→stream→fetch cycle? | ☐ |

---

## 🧪 How to Use the Logger

### Option A: Static calls (no code changes needed in widget class)

```dart
import 'package:lzcas/utils/pagination_logger.dart';

Future<void> _loadNextPage() async {
  if (_loading || !_hasMore) {
    PaginationLogger.logGuardHit('InventoryTable', reason: 'loading=$_loading, hasMore=$_hasMore');
    return;
  }
  _loading = true;
  final countBefore = items.length;

  PaginationLogger.logFetchStart('InventoryTable',
    requestedPage: _currentPage + 1,
    totalPages: (_totalCount / _pageSize).ceil(),
    currentServerPage: _currentPage,
    hasMore: _hasMore,
    isLoading: _loading,
    search: searchTerm,
  );

  PaginationLogger.logNetworkCall('InventoryTable',
    endpoint: 'items',
    page: _currentPage + 1,
    pageSize: _pageSize,
    search: searchTerm,
    sortColumn: 'name',
    sortAscending: true,
  );

  try {
    final page = await repository.fetchItemsPaginated(
      page: _currentPage + 1, pageSize: _pageSize, /* ... */,
    );

    PaginationLogger.logResponse('InventoryTable',
      rowCount: page.rows.length,
      totalCount: page.totalCount,
      serverPage: page.page,
      hasMore: page.hasMore,
    );

    if (!mounted) return;
    setState(() {
      items.addAll(/* ... */);
      _currentPage = page.page;
      _hasMore = page.hasMore;
      _loading = false;
    });

    PaginationLogger.logTransition('InventoryTable',
      isLoading: false,
      localCountBefore: countBefore,
      localCountAfter: items.length,
      isAddAll: true,
      currentPageAfter: _currentPage,
      displayPageAfter: _displayPage,
      hasMoreAfter: _hasMore,
    );
  } catch (e) {
    if (mounted) setState(() => _loading = false);
    PaginationLogger.logFinalCount('InventoryTable',
      localCount: items.length,
      totalPages: (_totalCount / _pageSize).ceil(),
      displayPage: _displayPage,
      hasMore: _hasMore,
      success: false,
      error: e.toString(),
    );
    return;
  }

  PaginationLogger.logFinalCount('InventoryTable',
    localCount: items.length,
    totalPages: (_totalCount / _pageSize).ceil(),
    displayPage: _displayPage,
    hasMore: _hasMore,
    success: true,
  );
}
```

### Option B: Mixin (cleaner, but requires `with PaginationLogMixin`)

```dart
class _MyTableState extends State<MyTable> with PaginationLogMixin {
  @override
  String get logTag => 'MyTable';

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) {
      logGuardHit(reason: 'loading=$_loading');
      return;
    }
    final countBefore = items.length;
    _loading = true;

    logFetchStart(requestedPage: _currentPage + 1, /* ... */);
    logNetworkCall(endpoint: 'items', page: _currentPage + 1, /* ... */);

    try {
      final page = await repository.fetchItemsPaginated(/* ... */);
      logResponse(rowCount: page.rows.length, /* ... */);
      // ... update state ...
      logTransition(localCountBefore: countBefore, /* ... */);
      logFinalCount(localCount: items.length, /* ... */);
    } catch (e) {
      logFinalCount(localCount: items.length, success: false, error: e.toString());
    }
  }
}
```

---

## 🛠️ Suggested Fix Priority

| Priority | Bug | Effort |
|----------|-----|--------|
| 🔴 P0 | `fetchRequestsPaginated` wrong Supabase range | Small |
| 🔴 P0 | `_loadItems`/`_loadMembers` stale sync after guard | Medium |
| 🟠 P1 | `_loadRequests` no re-entrancy guard | Small |
| 🟠 P1 | Mobile search uses client-side pagination against server data | Large |
| 🟡 P2 | Shared `_loading` flag across desktop + mobile paths | Medium |
| 🟡 P2 | `PaginatedListState.setSearch` concurrent fetch race | Small |

---

## 📝 After Fixing

1. Instrument each table with `PaginationLogger` (Option A for quickest drop-in).
2. Run the app and reproduce: search → filter → paginate → edit an item → verify stream reload doesn't wipe data.
3. Check console for the 5-state lifecycle on every page change.
4. Verify `hasMore: false` appears on the last page.
5. Verify `GUARD BLOCKED` appears when rapid clicks happen (not duplicate fetches).
