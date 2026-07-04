// lib/data/supabase_repository.dart
// Cloud-based repository using Supabase PostgreSQL.
// Mirrors DbRepository's public API exactly for drop-in replacement.

import 'dart:async';
import 'dart:math';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Describes a page of results with metadata.
class PageResult<T> {
  final List<T> rows;
  final int totalCount;
  final int page;
  final int pageSize;

  const PageResult({
    required this.rows,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  int get totalPages => totalCount == 0 ? 1 : (totalCount / pageSize).ceil();
  bool get hasMore => page < totalPages;
}

/// Repository that wraps Supabase and provides the same business operations
/// as the previous DbRepository (imports, exports, change notifications).
class SupabaseRepository {
  final SupabaseClient _supabase;

  /// Public access for raw Supabase queries (reports, filters, etc.)
  SupabaseClient get supabase => _supabase;
  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  /// Real-time subscription to Supabase postgres changes.
  StreamSubscription? _realtimeSub;

  SupabaseRepository({required SupabaseClient supabase})
    : _supabase = supabase {
    _initRealtime();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Get the current authenticated user's ID.
  String get _uid {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('Not authenticated');
    return id;
  }

  String _generateMemberQr() {
    final rnd = Random();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${rnd.nextInt(1 << 32).toRadixString(16)}';
  }

  // ── Change Stream ────────────────────────────────────────────────────────

  Stream<String> get changes => _changes.stream;

  /// Initialize Supabase Realtime subscriptions for all tables.
  void _initRealtime() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Tables filtered by the current user's user_id
    final userTables = ['items', 'members', 'sales', 'reseller_levels'];
    for (final table in userTables) {
      _supabase
          .channel('public:$table')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              _changes.add('${table}_changed');
            },
          )
          .subscribe();
    }

    // pending_requests — no user_id filter (admin must see all requests)
    _supabase
        .channel('public:pending_requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pending_requests',
          callback: (payload) {
            _changes.add('pending_requests_changed');
          },
        )
        .subscribe();
  }

  void notifyCloudRestored() {
    _changes.add('item_imported');
    _changes.add('member_imported');
    _changes.add('sale_imported');
    _changes.add('cloud_restored');
  }

  // ── Idempotent migrations (no-ops in cloud) ──────────────────────────────

  Future<void> ensurePointsConsistency() async {}
  Future<void> ensureVerifiedResellerConsistency() async {}
  Future<void> ensureReferrerIdBackfill() async {}

  // ── Fetch Methods ────────────────────────────────────────────────────────

  Future<List<Item>> fetchItems() async {
    final data = await _supabase.from('items').select();
    return (data as List).map((j) => Item.fromJson(j)).toList();
  }

  Future<List<Member>> fetchMembers() async {
    final data = await _supabase.from('members').select();
    return (data as List).map((j) => Member.fromJson(j)).toList();
  }

  /// Fetch the member record linked to an auth user via profiles.member_id.
  Future<Member?> fetchMemberByAuthUserId(String authUserId) async {
    final profile = await _supabase
        .from('profiles')
        .select('member_id')
        .eq('id', authUserId)
        .maybeSingle();
    if (profile == null) return null;
    final memberId = profile['member_id'] as int?;
    if (memberId == null) return null;
    return getMemberById(memberId);
  }

  /// Fetch all verified resellers with their stats for the rankings tab.
  Future<List<Map<String, dynamic>>> fetchAllResellers() async {
    final members = await _supabase
        .from('members')
        .select()
        .eq('role', 'Verified Reseller')
        .order('level', ascending: false);
    final results = <Map<String, dynamic>>[];
    for (final m in (members as List)) {
      final id = m['id'] as int? ?? 0;
      final boxes = await getTotalRemittedBoxes(id);
      final earnings = await fetchMemberEarnings(id);
      results.add({
        'id': id,
        'name': '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
        'level': m['level'] as int? ?? 1,
        'boxes': boxes,
        'earnings': earnings,
      });
    }
    // Sort by level desc then boxes desc (preserving the DB order + custom logic)
    results.sort((a, b) {
      final levelCmp = (b['level'] as int).compareTo(a['level'] as int);
      if (levelCmp != 0) return levelCmp;
      return (b['boxes'] as int).compareTo(a['boxes'] as int);
    });
    return results;
  }

  Future<List<Sale>> fetchSales() async {
    final data = await _supabase.from('sales').select();
    return (data as List).map((j) => Sale.fromJson(j)).toList();
  }

  Future<List<Sale>> fetchSalesBetween(DateTime start, DateTime end) async {
    final data = await _supabase
        .from('sales')
        .select()
        .gte('timestamp', start.toIso8601String())
        .lte('timestamp', end.toIso8601String());
    return (data as List).map((j) => Sale.fromJson(j)).toList();
  }

  Future<List<Sale>> fetchSalesForMember(int memberId) async {
    final data = await _supabase
        .from('sales')
        .select()
        .eq('buyer_id', memberId);
    return (data as List).map((j) => Sale.fromJson(j)).toList();
  }

  /// Fetch purchase history for a member (sales where they were the buyer).
  Future<List<Sale>> fetchMemberPurchaseHistory(
    int memberId, {
    int? limit,
  }) async {
    var query = _supabase
        .from('sales')
        .select()
        .eq('buyer_id', memberId)
        .order('timestamp', ascending: false);
    if (limit != null) query = query.limit(limit);
    final data = await query;
    return (data as List).map((j) => Sale.fromJson(j)).toList();
  }

  Future<List<Sale>> fetchSalesForReferrer(int referrerMemberId) async {
    // Fetch the referrer member to get their name for text matching
    final member = await getMemberById(referrerMemberId);
    if (member == null) return [];

    final memberName = '${member.firstName ?? ''} ${member.lastName ?? ''}'
        .trim();

    // Fetch only referred member IDs (not all members)
    final referredData = await _supabase
        .from('members')
        .select('id')
        .or('referrer_id.eq.$referrerMemberId,referrer.ilike.%$memberName%');
    final referredIds = (referredData as List)
        .map((r) => (r['id'] as num).toInt())
        .toSet();

    if (referredIds.isEmpty) return [];

    // Fetch only sales for referred members using IN filter (server-side)
    final salesData = await _supabase
        .from('sales')
        .select()
        .inFilter('buyer_id', referredIds.toList());
    return (salesData as List).map((j) => Sale.fromJson(j)).toList();
  }

  Future<Member?> getMemberById(int id) async {
    final data = await _supabase
        .from('members')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return Member.fromJson(data);
  }

  Future<Item?> getItemById(int id) async {
    final data = await _supabase
        .from('items')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return Item.fromJson(data);
  }

  Future<List<ResellerLevel>> fetchResellerLevels({
    String? tenantUserId,
  }) async {
    final uid = tenantUserId ?? _uid;
    final data = await _supabase
        .from('reseller_levels')
        .select()
        .eq('user_id', uid)
        .order('level');
    final levels = (data as List)
        .map((j) => ResellerLevel.fromJson(j))
        .toList();
    if (levels.isEmpty) {
      await _seedDefaultLevels(tenantUserId: tenantUserId);
      final newData = await _supabase
          .from('reseller_levels')
          .select()
          .eq('user_id', uid)
          .order('level');
      return (newData as List).map((j) => ResellerLevel.fromJson(j)).toList();
    }
    return levels;
  }

  /// Fetch only items whose stock is below [threshold] but above 0.
  /// Used by the notification popover — avoids loading all items.
  Future<List<Item>> fetchLowStockItems(int threshold) async {
    final data = await _supabase
        .from('items')
        .select()
        .lt('stock', threshold)
        .gt('stock', 0);
    return (data as List).map((j) => Item.fromJson(j)).toList();
  }

  // ── Paginated Fetch Methods ──────────────────────────────────────────────

  /// Fetch a page of items with optional search and sort.
  Future<PageResult<Item>> fetchItemsPaginated({
    int page = 1,
    int pageSize = 100,
    String? search,
    String? categoryFilter,
    String sortColumn = 'name',
    bool sortAscending = true,
  }) async {
    // Build data query — filters first, then order/range
    dynamic dataQuery = _supabase.from('items').select('*');
    dynamic countQuery = _supabase.from('items').select('id');

    if (search != null && search.isNotEmpty) {
      dataQuery = dataQuery.ilike('name', '%$search%');
      countQuery = countQuery.ilike('name', '%$search%');
    }
    if (categoryFilter != null && categoryFilter.isNotEmpty) {
      dataQuery = dataQuery.eq('category', categoryFilter);
      countQuery = countQuery.eq('category', categoryFilter);
    }

    // Apply order and range AFTER filters
    dataQuery = dataQuery
        .order(sortColumn, ascending: sortAscending)
        .range((page - 1) * pageSize, page * pageSize - 1);

    final results = await Future.wait<dynamic>([
      countQuery.count(CountOption.exact),
      dataQuery,
    ]);

    final totalCount = (results[0] as PostgrestResponse).count;
    final rows = (results[1] as List)
        .map((j) => Item.fromJson(j as Map<String, dynamic>))
        .toList();

    return PageResult(
      rows: rows,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
    );
  }

  /// Fetch only distinct categories (lightweight).
  Future<List<String>> fetchCategories() async {
    final data = await _supabase.from('items').select('category');
    final categories = <String>{};
    for (final row in (data as List)) {
      final c = (row as Map<String, dynamic>)['category'] as String?;
      if (c != null && c.trim().isNotEmpty) categories.add(c.trim());
    }
    return categories.toList()..sort();
  }

  /// Fetch a page of members with optional search and role filter.
  Future<PageResult<Member>> fetchMembersPaginated({
    int page = 1,
    int pageSize = 100,
    String? search,
    String? roleFilter,
    String sortColumn = 'last_name',
    bool sortAscending = true,
  }) async {
    dynamic dataQuery = _supabase.from('members').select('*');
    dynamic countQuery = _supabase.from('members').select('id');

    if (search != null && search.isNotEmpty) {
      final orFilter =
          'first_name.ilike.%$search%,last_name.ilike.%$search%,middle_name.ilike.%$search%';
      countQuery = countQuery.or(orFilter);
      dataQuery = dataQuery.or(orFilter);
    }
    if (roleFilter != null && roleFilter.isNotEmpty) {
      countQuery = countQuery.eq('role', roleFilter);
      dataQuery = dataQuery.eq('role', roleFilter);
    }

    dataQuery = dataQuery
        .order(sortColumn, ascending: sortAscending)
        .range((page - 1) * pageSize, page * pageSize - 1);

    final results = await Future.wait<dynamic>([
      countQuery.count(CountOption.exact),
      dataQuery,
    ]);

    final totalCount = (results[0] as PostgrestResponse).count;
    final rows = (results[1] as List)
        .map((j) => Member.fromJson(j as Map<String, dynamic>))
        .toList();

    return PageResult(
      rows: rows,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
    );
  }

  /// Fetch a page of sales with optional search.
  Future<PageResult<Sale>> fetchSalesPaginated({
    int page = 1,
    int pageSize = 100,
    String? search,
    String sortColumn = 'timestamp',
    bool sortAscending = false,
  }) async {
    dynamic dataQuery = _supabase.from('sales').select('*');
    dynamic countQuery = _supabase.from('sales').select('id');

    if (search != null && search.isNotEmpty) {
      final orFilter = 'buyer_name.ilike.%$search%,item_name.ilike.%$search%';
      countQuery = countQuery.or(orFilter);
      dataQuery = dataQuery.or(orFilter);
    }

    dataQuery = dataQuery
        .order(sortColumn, ascending: sortAscending)
        .range((page - 1) * pageSize, page * pageSize - 1);

    final results = await Future.wait<dynamic>([
      countQuery.count(CountOption.exact),
      dataQuery,
    ]);

    final totalCount = (results[0] as PostgrestResponse).count;
    final rows = (results[1] as List)
        .map((j) => Sale.fromJson(j as Map<String, dynamic>))
        .toList();

    return PageResult(
      rows: rows,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
    );
  }

  /// Pre-aggregated dashboard stats — avoids loading all rows.
  ///
  /// Uses date-range queries (not aggregate functions which PostgREST
  /// blocks by default). Still vastly more efficient than fetchSales().
  Future<Map<String, dynamic>> fetchDashboardStats({
    required DateTime thisMonthStart,
    required DateTime thisMonthEnd,
    required DateTime lastMonthStart,
    required DateTime lastMonthEnd,
    required int lowStockThreshold,
  }) async {
    final results = await Future.wait<dynamic>([
      // This month's sales
      _supabase
          .from('sales')
          .select('price, quantity')
          .gte('timestamp', thisMonthStart.toIso8601String())
          .lt('timestamp', thisMonthEnd.toIso8601String()),
      // Last month's sales
      _supabase
          .from('sales')
          .select('price')
          .gte('timestamp', lastMonthStart.toIso8601String())
          .lt('timestamp', lastMonthEnd.toIso8601String()),
      // Low stock items (id only, lightweight)
      _supabase
          .from('items')
          .select('id')
          .lt('stock', lowStockThreshold)
          .gt('stock', 0),
    ]);

    final thisMonthSales = results[0] as List;
    final lastMonthSales = results[1] as List;
    final lowStockRows = results[2] as List;

    // Aggregate client-side (rows limited to one month each, not all time)
    int monthlyRevenue = 0;
    int activeOrders = thisMonthSales.length;
    for (final row in thisMonthSales) {
      monthlyRevenue += (row['price'] as int?) ?? 0;
    }

    int previousMonthRevenue = 0;
    int previousMonthOrders = lastMonthSales.length;
    for (final row in lastMonthSales) {
      previousMonthRevenue += (row['price'] as int?) ?? 0;
    }

    return {
      'monthlyRevenue': monthlyRevenue,
      'activeOrders': activeOrders,
      'previousMonthRevenue': previousMonthRevenue,
      'previousMonthOrders': previousMonthOrders,
      'lowStockItems': lowStockRows.length,
    };
  }

  /// Fetch monthly revenue history for the last [months] months.
  ///
  /// Returns one entry per month with revenue, transaction count,
  /// and average ticket size. Missing months are filled with zeros.
  Future<List<Map<String, dynamic>>> fetchMonthlyRevenueHistory(
    int months,
  ) async {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month - months + 1, 1);
    final endDate = DateTime(now.year, now.month + 1, 1);

    final data = await _supabase
        .from('sales')
        .select('price, timestamp')
        .gte('timestamp', startDate.toIso8601String())
        .lt('timestamp', endDate.toIso8601String());

    // Aggregate by YYYY-MM key
    final Map<String, Map<String, dynamic>> monthly = {};
    for (final row in (data as List)) {
      final rowMap = row as Map<String, dynamic>;
      final ts = DateTime.parse(rowMap['timestamp'] as String);
      final key = '${ts.year}-${ts.month.toString().padLeft(2, '0')}';
      monthly.putIfAbsent(
        key,
        () => {'month': key, 'revenue': 0, 'transactions': 0},
      );
      monthly[key]!['revenue'] =
          (monthly[key]!['revenue'] as int) + ((rowMap['price'] as int?) ?? 0);
      monthly[key]!['transactions'] =
          (monthly[key]!['transactions'] as int) + 1;
    }

    // Build result with zero-filled missing months
    final result = <Map<String, dynamic>>[];
    for (int i = months - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      final entry =
          monthly[key] ?? {'month': key, 'revenue': 0, 'transactions': 0};
      result.add(entry);
    }
    return result;
  }

  // ── App Config ───────────────────────────────────────────────────────────

  /// Fetch all app config entries as a map of key → value.
  Future<Map<String, String>> fetchAppConfig() async {
    try {
      final data = await _supabase.from('app_config').select();
      final map = <String, String>{};
      for (final row in (data as List)) {
        final j = row as Map<String, dynamic>;
        map[j['key'] as String] = j['value'] as String? ?? '';
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Upsert a single app config entry.
  Future<void> updateAppConfig(String key, String value) async {
    await _supabase.from('app_config').upsert({
      'key': key,
      'value': value,
    }, onConflict: 'key');
  }

  // ── Borrow Methods ───────────────────────────────────────────────────────

  /// Record a borrow — deducts stock immediately, sets due date.
  Future<int> addBorrow({
    required int memberId,
    required int itemId,
    required String itemName,
    required int quantity,
    int price = 0,
    int dueDays = 10,
    String? notes,
    String? memberName,
  }) async {
    final item = await getItemById(itemId);
    if (item == null) throw Exception('Item not found: $itemId');
    if (item.stock < quantity) {
      throw Exception('Insufficient stock for $itemName');
    }

    // Deduct stock
    final updated = item.copyWith(stock: item.stock - quantity);
    await updateItem(updated);

    final now = DateTime.now();
    final dueDate = now.add(Duration(days: dueDays));

    final result = await _supabase
        .from('borrows')
        .insert({
          'user_id': _uid,
          'member_id': memberId,
          if (memberName != null) 'member_name': memberName,
          'item_id': itemId,
          'item_name': itemName,
          'quantity': quantity,
          'price': price,
          'borrowed_at': now.toUtc().toIso8601String(),
          'due_date': dueDate.toUtc().toIso8601String(),
          'status': 'active',
          if (notes != null) 'notes': notes,
        })
        .select('id');

    _changes.add('borrow_added');
    if (result is List && result.isNotEmpty) {
      return (result.first['id'] as num).toInt();
    }
    return 0;
  }

  Future<List<Borrow>> fetchBorrows() async {
    final data = await _supabase.from('borrows').select();
    return (data as List).map((j) => Borrow.fromJson(j)).toList();
  }

  Future<List<Borrow>> fetchBorrowsForMember(int memberId) async {
    final data = await _supabase
        .from('borrows')
        .select()
        .eq('member_id', memberId);
    return (data as List).map((j) => Borrow.fromJson(j)).toList();
  }

  /// Fetch only active (unsettled) borrows for a single member.
  Future<List<Borrow>> fetchActiveBorrowsForMember(int memberId) async {
    final data = await _supabase
        .from('borrows')
        .select()
        .eq('member_id', memberId)
        .inFilter('status', ['active', 'overdue', 'partially_settled']);
    return (data as List).map((j) => Borrow.fromJson(j)).toList();
  }

  /// Active borrows — not yet fully settled.
  Future<List<Borrow>> fetchActiveBorrows() async {
    final data = await _supabase.from('borrows').select().inFilter('status', [
      'active',
      'overdue',
      'partially_settled',
    ]);
    return (data as List).map((j) => Borrow.fromJson(j)).toList();
  }

  /// Overdue borrows — past due date and not fully settled.
  /// Also auto-updates status to 'overdue' for qualifying rows.
  Future<List<Borrow>> fetchOverdueBorrows() async {
    final now = DateTime.now().toUtc().toIso8601String();

    // Auto-flag overdue rows
    await _supabase
        .from('borrows')
        .update({'status': 'overdue'})
        .lt('due_date', now)
        .inFilter('status', ['active', 'partially_settled']);

    final data = await _supabase
        .from('borrows')
        .select()
        .eq('status', 'overdue');
    return (data as List).map((j) => Borrow.fromJson(j)).toList();
  }

  /// Return unsold borrowed items — restores stock.
  Future<bool> returnBorrowedItem(int borrowId, int returnQty) async {
    final data = await _supabase
        .from('borrows')
        .select()
        .eq('id', borrowId)
        .maybeSingle();
    if (data == null) return false;

    final borrow = Borrow.fromJson(data);
    if (returnQty <= 0 || returnQty > borrow.outstandingQuantity) return false;

    final newReturned = borrow.quantityReturned + returnQty;
    final newStatus = _computeBorrowStatus(
      quantity: borrow.quantity,
      returned: newReturned,
      remitted: borrow.quantityRemitted,
      dueDate: borrow.dueDate,
    );

    await _supabase
        .from('borrows')
        .update({
          'quantity_returned': newReturned,
          'status': newStatus,
          if (newStatus == 'returned' || newStatus == 'remitted')
            'settled_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', borrowId);

    // Restore stock
    final item = await getItemById(borrow.itemId);
    if (item != null) {
      final updated = item.copyWith(stock: item.stock + returnQty);
      await updateItem(updated);
    }

    _changes.add('borrow_updated');
    return true;
  }

  /// Remit payment for sold borrowed items — creates a Sale record.
  Future<bool> remitBorrowedItem(int borrowId, int remitQty) async {
    final data = await _supabase
        .from('borrows')
        .select()
        .eq('id', borrowId)
        .maybeSingle();
    if (data == null) return false;

    final borrow = Borrow.fromJson(data);
    if (remitQty <= 0 || remitQty > borrow.outstandingQuantity) return false;

    final newRemitted = borrow.quantityRemitted + remitQty;
    final newStatus = _computeBorrowStatus(
      quantity: borrow.quantity,
      returned: borrow.quantityReturned,
      remitted: newRemitted,
      dueDate: borrow.dueDate,
    );

    await _supabase
        .from('borrows')
        .update({
          'quantity_remitted': newRemitted,
          'status': newStatus,
          if (newStatus == 'returned' || newStatus == 'remitted')
            'settled_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', borrowId);

    // Create a Sale record for the remitted quantity
    await addSale(
      itemId: borrow.itemId,
      itemName: borrow.itemName,
      quantity: remitQty,
      price: borrow.price,
      buyerId: borrow.memberId,
    );

    // Auto-level-up: check if reseller now qualifies for a higher level
    await _autoLevelUp(borrow.memberId);

    _changes.add('borrow_updated');
    return true;
  }

  /// Compute borrow status from current quantities and due date.
  String _computeBorrowStatus({
    required int quantity,
    required int returned,
    required int remitted,
    required DateTime dueDate,
  }) {
    final outstanding = quantity - returned - remitted;
    if (outstanding <= 0) {
      if (returned >= quantity) return 'returned';
      if (remitted >= quantity) return 'remitted';
      return 'returned'; // fully settled by combination
    }
    // Outstanding > 0
    if (dueDate.isBefore(DateTime.now())) return 'overdue';
    if (returned > 0 || remitted > 0) return 'partially_settled';
    return 'active';
  }

  // ── Stock Movement Methods ──────────────────────────────────────────────

  /// Add stock with audit trail.
  Future<bool> addStock({
    required int itemId,
    required String itemName,
    required int quantity,
    String? reason,
  }) async {
    final item = await getItemById(itemId);
    if (item == null) return false;

    final newStock = item.stock + quantity;
    final updated = item.copyWith(
      stock: newStock,
      lastUpdated: DateTime.now(),
      status: statusFromStock(newStock),
    );
    await updateItem(updated);

    await _supabase.from('stock_movements').insert({
      'user_id': _uid,
      'item_id': itemId,
      'item_name': itemName,
      'quantity': quantity,
      'movement_type': 'stock_in',
      if (reason != null) 'reason': reason,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    _changes.add('stock_movement_added');
    return true;
  }

  /// Reduce stock with audit trail and mandatory reason.
  Future<bool> reduceStock({
    required int itemId,
    required String itemName,
    required int quantity,
    required String reason,
    String?
    overriddenUserId, // if set, uses this user_id for audit instead of _uid
  }) async {
    final item = await getItemById(itemId);
    if (item == null) return false;
    if (item.stock < quantity) return false;

    final newStock = item.stock - quantity;
    final updated = item.copyWith(
      stock: newStock,
      lastUpdated: DateTime.now(),
      status: statusFromStock(newStock),
    );
    await updateItem(updated);

    await _supabase.from('stock_movements').insert({
      'user_id': overriddenUserId ?? _uid,
      'item_id': itemId,
      'item_name': itemName,
      'quantity': quantity,
      'movement_type': 'stock_out',
      'reason': reason,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    _changes.add('stock_movement_added');
    return true;
  }

  Future<List<StockMovement>> fetchStockMovements() async {
    final data = await _supabase.from('stock_movements').select();
    return (data as List).map((j) => StockMovement.fromJson(j)).toList();
  }

  // ── Add Methods ──────────────────────────────────────────────────────────

  Future<int> addItem({
    required String name,
    String? category,
    int stock = 0,
    DateTime? lastUpdated,
    String? status,
  }) async {
    final result = await _supabase
        .from('items')
        .insert({
          'user_id': _uid,
          'name': name,
          if (category != null) 'category': category,
          'stock': stock,
          if (lastUpdated != null)
            'last_updated': lastUpdated.toIso8601String(),
          if (status != null) 'status': status,
        })
        .select('id');

    _changes.add('item_added');

    // If the new item has stock > 0, record it as a stock-in movement
    final itemId = result is List && result.isNotEmpty
        ? (result.first['id'] as num).toInt()
        : 0;
    if (itemId > 0 && stock > 0) {
      await _supabase.from('stock_movements').insert({
        'user_id': _uid,
        'item_id': itemId,
        'item_name': name,
        'quantity': stock,
        'movement_type': 'stock_in',
        'reason': 'new_product',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      _changes.add('stock_movement_added');
    }

    return itemId;
  }

  Future<int> addMember({
    String? lastName,
    String? firstName,
    String? middleName,
    String? role,
    String? contactNo,
    String? birthday,
    String? address,
    String? referrer,
    int? referrerId,
    int level = 1,
    String? idType,
    String? idNumber,
    String? idImagePath,
  }) async {
    final data = await _supabase
        .from('members')
        .insert({
          'user_id': _uid,
          if (lastName != null) 'last_name': lastName,
          if (firstName != null) 'first_name': firstName,
          if (middleName != null) 'middle_name': middleName,
          if (role != null) 'role': role,
          if (contactNo != null) 'contact_no': contactNo,
          if (birthday != null) 'birthday': birthday,
          if (address != null) 'address': address,
          if (referrer != null) 'referrer': referrer,
          if (referrerId != null) 'referrer_id': referrerId,
          'qr': _generateMemberQr(),
          if (idType != null) 'id_type': idType,
          if (idNumber != null) 'id_number': idNumber,
          if (idImagePath != null) 'id_image_path': idImagePath,
          'level': level,
        })
        .select('id');

    _changes.add('member_added');
    if (data is List && data.isNotEmpty) {
      return (data.first['id'] as num).toInt();
    }
    return 0;
  }

  /// Upload a member ID image to Supabase Storage so it's accessible
  /// from any device. Returns the public URL on success, null on failure.
  Future<String?> uploadMemberImage(
    int memberId,
    Uint8List bytes,
    String ext,
  ) async {
    try {
      final path = '$memberId.$ext';
      await _supabase.storage
          .from('member-ids')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return _supabase.storage.from('member-ids').getPublicUrl(path);
    } catch (e) {
      print('[Stockpile] uploadMemberImage failed: $e');
      return null;
    }
  }

  Future<int> addSale({
    required int itemId,
    String? itemName,
    required int quantity,
    int price = 0,
    DateTime? timestamp,
    int? buyerId,
    String? buyerName,
  }) async {
    final result = await _supabase
        .from('sales')
        .insert({
          'user_id': _uid,
          'item_id': itemId,
          'item_name': itemName ?? '',
          'quantity': quantity,
          'price': price,
          if (buyerId != null) 'buyer_id': buyerId,
          if (buyerName != null) 'buyer_name': buyerName,
          'timestamp': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
        })
        .select('id');

    _changes.add('sale_added');
    if (result is List && result.isNotEmpty) {
      return (result.first['id'] as num).toInt();
    }
    return 0;
  }

  // ── Update Methods ───────────────────────────────────────────────────────

  Future<bool> updateItem(Item item) async {
    if (item.id == null) return false;
    await _supabase.from('items').update(item.toJson()).eq('id', item.id!);
    _changes.add('item_updated');
    return true;
  }

  Future<bool> updateMember(Member member) async {
    if (member.id == null) return false;
    await _supabase
        .from('members')
        .update(member.toJson())
        .eq('id', member.id!);
    _changes.add('member_updated');
    return true;
  }

  Future<bool> updateSale(Sale sale) async {
    if (sale.id == null) return false;
    await _supabase.from('sales').update(sale.toJson()).eq('id', sale.id!);
    _changes.add('sale_updated');
    return true;
  }

  Future<bool> verifyAsReseller(int memberId) async {
    final member = await getMemberById(memberId);
    if (member == null) return false;
    final updated = member.copyWith(role: 'Verified Reseller');
    await updateMember(updated);
    return true;
  }

  /// Create a Supabase Auth account for an existing member.
  /// Calls the create-member-user edge function and updates the member's email.
  /// Returns a map with {email, password, id} on success, or null on failure.
  Future<Map<String, dynamic>?> createMemberAuthAccount({
    required int memberId,
    required String email,
    required String password,
  }) async {
    final member = await getMemberById(memberId);
    if (member == null) return null;

    try {
      final result = await _supabase.functions.invoke(
        'create-member-user',
        body: {
          'email': email,
          'password': password,
          'member_id': memberId,
          'member_name': '${member.firstName ?? ''} ${member.lastName ?? ''}'
              .trim(),
          'role': (member.role == 'Verified Reseller') ? 'reseller' : 'member',
        },
      );

      if (result.status == 200 && result.data is Map) {
        final data = result.data as Map;
        if (data['success'] == true) {
          // Update the member record with the email locally.
          // Note: user_id on the members table is the staff creator's ID,
          // not the member's auth ID — so only update email here.
          final authUserId = data['id'] as String? ?? '';
          final updated = member.copyWith(email: email);
          await updateMember(updated);
          return {'email': email, 'password': password, 'id': authUserId};
        }
      }
      return null;
    } catch (e) {
      debugPrint('[createMemberAuthAccount] error: $e');
      return null;
    }
  }

  Future<bool> setMemberLevel(int memberId, int level) async {
    final member = await getMemberById(memberId);
    if (member == null) return false;
    final updated = member.copyWith(level: level.clamp(1, 10));
    await updateMember(updated);
    return true;
  }

  /// Compute the total number of boxes this reseller has ever remitted
  /// across all borrows (settled or not).
  Future<int> getTotalRemittedBoxes(int memberId) async {
    final data = await _supabase
        .from('borrows')
        .select('quantity_remitted')
        .eq('member_id', memberId);
    if (data == null || (data as List).isEmpty) return 0;
    var total = 0;
    for (final row in data) {
      total += (row['quantity_remitted'] as int? ?? 0);
    }
    return total;
  }

  /// Compute total remitted earnings for a member.
  /// Sum of (quantity_remitted × price) across all borrows.
  Future<int> fetchMemberEarnings(int memberId) async {
    final data = await _supabase
        .from('borrows')
        .select('quantity_remitted, price')
        .eq('member_id', memberId);
    if (data == null || (data as List).isEmpty) return 0;
    var total = 0;
    for (final row in data) {
      final qty = row['quantity_remitted'] as int? ?? 0;
      final price = row['price'] as int? ?? 0;
      total += qty * price;
    }
    return total;
  }

  /// Automatically level up a reseller if their total remitted boxes
  /// meet the threshold for a higher level. Returns the new level (or
  /// current level if no change).
  Future<int> _autoLevelUp(int memberId) async {
    final member = await getMemberById(memberId);
    if (member == null) return 1;
    // Only auto-level verified resellers
    if ((member.role ?? '') != 'Verified Reseller') return member.level;

    final totalBoxes = await getTotalRemittedBoxes(memberId);
    final levels = await fetchResellerLevels();

    // Find the highest level whose boxes_required <= totalBoxes
    int newLevel = member.level;
    for (final lvl in levels) {
      if (totalBoxes >= lvl.boxesRequired && lvl.level > newLevel) {
        newLevel = lvl.level;
      }
    }

    if (newLevel > member.level) {
      final updated = member.copyWith(level: newLevel);
      await updateMember(updated);
      _changes.add('reseller_level_up');
    }

    return newLevel;
  }

  Future<void> upsertResellerLevel({
    required int level,
    required int remittanceMin,
    required int remittanceMax,
    required int cashAdvance,
    required int boxesRequired,
  }) async {
    await _supabase.from('reseller_levels').upsert({
      'level': level,
      'user_id': _uid,
      'remittance_min': remittanceMin,
      'remittance_max': remittanceMax,
      'cash_advance': cashAdvance,
      'boxes_required': boxesRequired,
    });
    _changes.add('reseller_levels_updated');
  }

  // ── Delete Methods ───────────────────────────────────────────────────────

  /// Returns true if [itemId] has any unsettled borrows (active, overdue,
  /// or partially_settled). Deletion should be blocked when this is true.
  Future<bool> hasActiveBorrows(int itemId) async {
    final data = await _supabase
        .from('borrows')
        .select('id')
        .eq('item_id', itemId)
        .inFilter('status', ['active', 'overdue', 'partially_settled']);
    return (data as List).isNotEmpty;
  }

  /// Returns true if [memberId] has any unsettled borrows.
  Future<bool> hasActiveBorrowsForMember(int memberId) async {
    final data = await _supabase
        .from('borrows')
        .select('id')
        .eq('member_id', memberId)
        .inFilter('status', ['active', 'overdue', 'partially_settled']);
    return (data as List).isNotEmpty;
  }

  Future<int> deleteItemById(int id) async {
    // Guard: block deletion if the item has active borrows
    final active = await hasActiveBorrows(id);
    if (active) {
      throw Exception(
        'Cannot delete item #$id — it has unsettled borrows. '
        'Settle or return all borrows first.',
      );
    }
    await _supabase.from('items').delete().eq('id', id);
    _changes.add('item_deleted');
    return 1;
  }

  Future<bool> deleteMemberById(int id) async {
    // Guard: block deletion if member has active borrows
    final active = await hasActiveBorrowsForMember(id);
    if (active) {
      throw Exception(
        'Cannot delete member #$id — they have unsettled borrows. '
        'Settle or return all borrows first.',
      );
    }

    // Backfill buyer_name on existing sales so names survive deletion
    final member = await _supabase
        .from('members')
        .select('first_name, last_name')
        .eq('id', id)
        .maybeSingle();
    if (member != null) {
      final fullName = [
        member['first_name'] as String?,
        member['last_name'] as String?,
      ].where((p) => p != null && p.trim().isNotEmpty).join(' ');
      if (fullName.isNotEmpty) {
        await _supabase
            .from('sales')
            .update({'buyer_name': fullName})
            .eq('buyer_id', id)
            .filter('buyer_name', 'is', null);
        await _supabase
            .from('borrows')
            .update({'member_name': fullName})
            .eq('member_id', id)
            .filter('member_name', 'is', null);
      }
    }

    await _supabase.from('members').delete().eq('id', id);
    _changes.add('member_deleted');
    return true;
  }

  Future<int> deleteSaleById(int id) async {
    // Restore item stock before deleting
    try {
      final data = await _supabase
          .from('sales')
          .select('item_id, quantity')
          .eq('id', id)
          .maybeSingle();
      if (data != null) {
        final itemId = (data['item_id'] as num).toInt();
        final qty = (data['quantity'] as num).toInt();
        final item = await _supabase
            .from('items')
            .select('stock')
            .eq('id', itemId)
            .maybeSingle();
        if (item != null) {
          final currentStock = (item['stock'] as num).toInt();
          await _supabase
              .from('items')
              .update({'stock': currentStock + qty})
              .eq('id', itemId);
        }
      }
    } catch (_) {
      // Best-effort stock restore
    }

    await _supabase.from('sales').delete().eq('id', id);
    _changes.add('sale_deleted');
    return 1;
  }

  Future<int> deleteSaleGroup(DateTime timestamp, {int? buyerId}) async {
    // Get all sales at this timestamp, restore stock, then delete
    final timestampStr = timestamp.toUtc().toIso8601String();
    var query = _supabase.from('sales').select().eq('timestamp', timestampStr);
    if (buyerId != null) {
      query = query.eq('buyer_id', buyerId);
    }
    final sales = await query;

    // Restore stock for each sale
    for (final s in (sales as List)) {
      try {
        final itemId = (s['item_id'] as num).toInt();
        final qty = (s['quantity'] as num).toInt();
        final item = await _supabase
            .from('items')
            .select('stock')
            .eq('id', itemId)
            .maybeSingle();
        if (item != null) {
          final currentStock = (item['stock'] as num).toInt();
          await _supabase
              .from('items')
              .update({'stock': currentStock + qty})
              .eq('id', itemId);
        }
      } catch (_) {}
    }

    var deleteQuery = _supabase
        .from('sales')
        .delete()
        .eq('timestamp', timestampStr);
    if (buyerId != null) {
      deleteQuery = deleteQuery.eq('buyer_id', buyerId);
    }
    final result = await deleteQuery;
    _changes.add('sale_deleted');
    return (result as List?)?.length ?? sales.length;
  }

  // ── Pending Request Methods (Approval Workflow) ──────────────────────────

  /// Submit an approval request for admin review (delete or reduce_stock).
  /// Inventory users cannot delete/reduce directly; they go through this.
  Future<int> submitPendingRequest({
    required int itemId,
    required String itemName,
    required String requestType,
    int? quantity,
    String? reason,
  }) async {
    final result = await _supabase
        .from('pending_requests')
        .insert({
          'user_id': _uid,
          'item_id': itemId,
          'item_name': itemName,
          'request_type': requestType,
          if (quantity != null) 'quantity': quantity,
          if (reason != null) 'reason': reason,
          'status': 'pending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id');

    _changes.add('pending_request_added');
    if (result is List && result.isNotEmpty) {
      return (result.first['id'] as num).toInt();
    }
    return 0;
  }

  /// Submit a borrow request for admin approval.
  /// Cashiers and inventory users route through this instead of direct borrow.
  Future<int> submitBorrowRequest({
    required int memberId,
    required String memberName,
    required int itemId,
    required String itemName,
    required int quantity,
    int price = 0,
    String? notes,
  }) async {
    final result = await _supabase
        .from('pending_requests')
        .insert({
          'user_id': _uid,
          'member_id': memberId,
          'member_name': memberName,
          'item_id': itemId,
          'item_name': itemName,
          'request_type': 'borrow',
          'quantity': quantity,
          'price': price,
          if (notes != null) 'notes': notes,
          'status': 'pending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id');

    _changes.add('pending_request_added');
    if (result is List && result.isNotEmpty) {
      return (result.first['id'] as num).toInt();
    }
    return 0;
  }

  /// Fetch all pending requests (status = 'pending').
  Future<List<PendingRequest>> fetchPendingRequests() async {
    final data = await _supabase
        .from('pending_requests')
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return (data as List).map((j) => PendingRequest.fromJson(j)).toList();
  }

  /// Get the count of pending requests (for notification badge).
  Future<int> fetchPendingCount() async {
    final resp = await _supabase
        .from('pending_requests')
        .select('id')
        .eq('status', 'pending')
        .count(CountOption.exact);
    return resp.count;
  }

  /// Get the count of low-stock items (stock > 0 and stock < threshold).
  Future<int> fetchLowStockCount(int threshold) async {
    final resp = await _supabase
        .from('items')
        .select('id')
        .lt('stock', threshold)
        .gt('stock', 0)
        .count(CountOption.exact);
    return resp.count;
  }

  /// Fetch all non-pending requests (approved and rejected) for history view.
  Future<List<PendingRequest>> fetchAllRequests() async {
    final data = await _supabase
        .from('pending_requests')
        .select()
        .neq('status', 'pending')
        .order('created_at', ascending: false);
    return (data as List).map((j) => PendingRequest.fromJson(j)).toList();
  }

  /// Fetch all requests (pending + resolved) made by the current user,
  /// ordered by most recent first. Used by cashiers to track their requests.
  Future<List<PendingRequest>> fetchMyRequests() async {
    final data = await _supabase
        .from('pending_requests')
        .select()
        .eq('user_id', _uid)
        .order('created_at', ascending: false);
    return (data as List).map((j) => PendingRequest.fromJson(j)).toList();
  }

  /// Paginated fetch of pending requests with optional filters.
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
    final rangeEnd = page * pageSize - 1;

    // Build data and count queries with server-side filters
    dynamic dataQuery = _supabase.from('pending_requests').select('*');
    dynamic countQuery = _supabase.from('pending_requests').select('id');

    // Push all filters to the server so pagination is correct
    if (statusFilter != null &&
        statusFilter.isNotEmpty &&
        statusFilter != 'all') {
      if (statusFilter == 'history') {
        dataQuery = dataQuery.neq('status', 'pending');
        countQuery = countQuery.neq('status', 'pending');
      } else {
        dataQuery = dataQuery.eq('status', statusFilter);
        countQuery = countQuery.eq('status', statusFilter);
      }
    }
    if (userIdFilter != null && userIdFilter.isNotEmpty) {
      dataQuery = dataQuery.eq('user_id', userIdFilter);
      countQuery = countQuery.eq('user_id', userIdFilter);
    }
    if (typeFilter != null && typeFilter.isNotEmpty && typeFilter != 'all') {
      dataQuery = dataQuery.eq('request_type', typeFilter);
      countQuery = countQuery.eq('request_type', typeFilter);
    }
    if (search != null && search.isNotEmpty) {
      // Use ILIKE on item_name and member_name via OR filter
      final orFilter =
          'item_name.ilike.%$search%,member_name.ilike.%$search%,reason.ilike.%$search%';
      dataQuery = dataQuery.or(orFilter);
      countQuery = countQuery.or(orFilter);
    }

    // Apply order and range AFTER filters
    dataQuery = dataQuery
        .order(sortColumn, ascending: sortAscending)
        .range(rangeStart, rangeEnd);

    final results = await Future.wait<dynamic>([
      countQuery.count(CountOption.exact),
      dataQuery,
    ]);

    final totalCount = (results[0] as PostgrestResponse).count;
    final rows = (results[1] as List)
        .map((j) => PendingRequest.fromJson(j as Map<String, dynamic>))
        .toList();

    return PageResult(
      rows: rows,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
    );
  }

  /// Fetch a map of userId → username from profiles table.
  Future<Map<String, String>> fetchProfilesMap() async {
    final data = await _supabase.from('profiles').select('id, username');
    return Map<String, String>.fromEntries(
      (data as List).map(
        (p) =>
            MapEntry(p['id'] as String, p['username'] as String? ?? 'Unknown'),
      ),
    );
  }

  /// Submit a member deletion request for admin approval.
  Future<int> submitMemberDeletionRequest({
    required int memberId,
    required String memberName,
    required String reason,
  }) async {
    final result = await _supabase
        .from('pending_requests')
        .insert({
          'user_id': _uid,
          'member_id': memberId,
          'member_name': memberName,
          'request_type': 'delete_member',
          'reason': reason,
          'status': 'pending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id');

    _changes.add('pending_request_added');
    if (result is List && result.isNotEmpty) {
      return (result.first['id'] as num).toInt();
    }
    return 0;
  }

  /// Approve a pending request — executes the actual action.
  /// Supports: delete, reduce_stock, delete_member, borrow.
  /// Returns null on success, or an error message string on failure.
  Future<String?> approveRequest(int requestId) async {
    final data = await _supabase
        .from('pending_requests')
        .select()
        .eq('id', requestId)
        .eq('status', 'pending')
        .maybeSingle();
    if (data == null) return 'Request not found';

    final req = PendingRequest.fromJson(data);
    final now = DateTime.now().toUtc().toIso8601String();

    // Execute the actual action
    try {
      if (req.requestType == 'delete') {
        await deleteItemById(req.itemId!);
      } else if (req.requestType == 'reduce_stock') {
        final ok = await reduceStock(
          itemId: req.itemId!,
          itemName: req.itemName!,
          quantity: req.quantity ?? 0,
          reason: req.reason ?? 'Admin-approved stock reduction',
          overriddenUserId: req.userId, // credit the original requester
        );
        if (!ok) return 'Insufficient stock for this item';
      } else if (req.requestType == 'delete_member' && req.memberId != null) {
        final ok = await deleteMemberById(req.memberId!);
        if (!ok) return 'Failed to delete member';
      } else if (req.requestType == 'borrow') {
        // Create the actual borrow record (addBorrow deducts stock)
        await addBorrow(
          memberId: req.memberId!,
          memberName: req.memberName,
          itemId: req.itemId!,
          itemName: req.itemName!,
          quantity: req.quantity ?? 0,
          price: req.price ?? 0,
          notes: req.notes,
        );
      }
    } catch (e) {
      print('[Stockpile] approveRequest failed: $e');
      return _friendlyError(e);
    }

    // Mark as approved
    await _supabase
        .from('pending_requests')
        .update({'status': 'approved', 'reviewed_by': _uid, 'reviewed_at': now})
        .eq('id', requestId);

    _changes.add('pending_request_approved');
    return null; // success
  }

  /// Reject a pending request — no action taken, just marks status.
  /// Optionally records a [rejectionReason] from the admin.
  Future<bool> rejectRequest(int requestId, {String? rejectionReason}) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await _supabase
        .from('pending_requests')
        .update({
          'status': 'rejected',
          'reviewed_by': _uid,
          'reviewed_at': now,
          if (rejectionReason != null) 'rejection_reason': rejectionReason,
        })
        .eq('id', requestId)
        .eq('status', 'pending');

    _changes.add('pending_request_rejected');
    return true;
  }

  // ── Bulk Data Operations ─────────────────────────────────────────────────

  Future<void> clearAllData() async {
    await _supabase.from('member_transactions').delete().neq('id', 0);
    await _supabase.from('sales').delete().neq('id', 0);
    await _supabase.from('items').delete().neq('id', 0);
    await _supabase.from('members').delete().neq('id', 0);
    _changes.add('db_cleared');
  }

  // ── Transactional Methods ────────────────────────────────────────────────

  /// Commit member transactions atomically.
  /// Validates stock, inserts sales, updates items, writes audit rows.
  Future<String?> commitMemberTransactions(
    int memberId,
    List<MemberTransactionEntry> entries, {
    bool applyEffects = true,
  }) async {
    try {
      final buyer = await getMemberById(memberId);
      if (buyer == null) return 'Member not found';

      final items = await fetchItems();
      final existingSales = await fetchSales();
      final now = DateTime.now();

      for (final e in entries) {
        Item? item;
        // Find item by ID or name
        if (e.itemId != null && e.itemId! > 0) {
          try {
            item = items.firstWhere((it) => it.id == e.itemId);
          } catch (_) {}
        }
        item ??= items.cast<Item?>().firstWhere(
          (it) =>
              it!.name.trim().toLowerCase() == e.itemName.trim().toLowerCase(),
          orElse: () => null,
        );
        if (item == null) return 'Item ${e.itemName} not found';
        if (item.stock < e.quantity) {
          return 'Insufficient stock for ${item.name}';
        }
      }

      for (final e in entries) {
        Item? item;
        if (e.itemId != null && e.itemId! > 0) {
          try {
            item = items.firstWhere((it) => it.id == e.itemId);
          } catch (_) {}
        }
        item ??= items.cast<Item?>().firstWhere(
          (it) =>
              it!.name.trim().toLowerCase() == e.itemName.trim().toLowerCase(),
          orElse: () => null,
        );
        if (item == null) continue;

        // Check for duplicate
        final duplicate = existingSales.any((s) {
          final sameCore =
              s.itemId == item!.id &&
              s.itemName == e.itemName &&
              s.quantity == e.quantity &&
              s.price == e.price &&
              (s.buyerId == memberId);
          if (!sameCore) return false;
          if (e.timestamp != null) {
            return s.timestamp?.toIso8601String() ==
                e.timestamp!.toIso8601String();
          }
          return true;
        });
        if (duplicate) continue;

        final saleId = await addSale(
          itemId: item.id!,
          itemName: e.itemName,
          quantity: e.quantity,
          price: e.price,
          timestamp: e.timestamp ?? now,
          buyerId: memberId,
        );

        if (applyEffects) {
          final updatedItem = item.copyWith(
            stock: item.stock - e.quantity,
            lastUpdated: now,
          );
          await updateItem(updatedItem);
        }

        // Write audit row
        try {
          await _supabase.from('member_transactions').insert({
            'user_id': _uid,
            'member_id': memberId,
            'sale_id': saleId,
            'item_id': item.id,
            'item_name': e.itemName,
            'quantity': e.quantity,
            'price': e.price,
            'timestamp': (e.timestamp ?? now).toUtc().toIso8601String(),
          });
        } catch (_) {
          // ignore audit failures
        }
      }

      _changes.add('member_transactions_committed');
      return null;
    } catch (e) {
      print('[Stockpile] recordMemberTransactions failed: $e');
      return _friendlyError(e);
    }
  }

  /// Edit a grouped sale atomically.
  Future<String?> editSaleGroup({
    required DateTime timestamp,
    int? buyerId,
    required List<Sale> newLines,
  }) async {
    try {
      final allSales = await fetchSales();
      final timestampStr = timestamp.toUtc().toIso8601String();
      final originals = allSales
          .where((s) => s.timestamp?.toUtc().toIso8601String() == timestampStr)
          .toList();

      // Compute per-item quantity deltas
      final Map<int, int> origQty = {};
      for (final o in originals) {
        origQty[o.itemId] = (origQty[o.itemId] ?? 0) + o.quantity;
      }
      final Map<int, int> newQty = {};
      for (final n in newLines) {
        newQty[n.itemId] = (newQty[n.itemId] ?? 0) + n.quantity;
      }

      final items = await fetchItems();
      final now = DateTime.now();

      // Validate stock
      for (final itemId in {...origQty.keys, ...newQty.keys}) {
        final before = origQty[itemId] ?? 0;
        final after = newQty[itemId] ?? 0;
        final deltaQ = after - before;
        final item = items.cast<Item?>().firstWhere(
          (it) => it!.id == itemId,
          orElse: () => null,
        );
        if (item == null) return 'Item id=$itemId not found';
        if (deltaQ > 0 && item.stock < deltaQ) {
          return 'Insufficient stock for ${item.name}';
        }
      }

      // Apply stock adjustments
      for (final itemId in {...origQty.keys, ...newQty.keys}) {
        final before = origQty[itemId] ?? 0;
        final after = newQty[itemId] ?? 0;
        final deltaQ = after - before;
        final item = items.firstWhere((it) => it.id == itemId);
        if (deltaQ != 0) {
          final updated = item.copyWith(
            stock: item.stock - deltaQ,
            lastUpdated: now,
          );
          await updateItem(updated);
        }
      }

      // Remove original grouped sales
      await _supabase.from('sales').delete().eq('timestamp', timestampStr);

      // Insert new sale rows
      for (final n in newLines) {
        await addSale(
          itemId: n.itemId,
          itemName: n.itemName,
          quantity: n.quantity,
          price: n.price,
          timestamp: timestamp,
          buyerId: buyerId,
        );
      }

      return null;
    } catch (e) {
      print('[Stockpile] editSaleGroup failed: $e');
      return _friendlyError(e);
    }
  }

  // ── CSV Import ───────────────────────────────────────────────────────────

  Future<int> importItemsCsv(String csv) async {
    final converter = const CsvToListConverter(eol: '\n');
    final list = converter.convert(csv);
    if (list.length < 2) return 0;
    final headers = list.first.map((e) => e.toString().toLowerCase()).toList();
    final nameIdx = headers.indexOf('name');
    final catIdx = headers.indexOf('category');
    final stockIdx = headers.indexOf('stock');
    if (nameIdx < 0) return 0;

    int count = 0;
    for (final row in list.sublist(1)) {
      if (row.isEmpty) continue;
      await _supabase.from('items').insert({
        'user_id': _uid,
        'name': row[nameIdx].toString(),
        if (catIdx >= 0 && catIdx < row.length)
          'category': row[catIdx].toString(),
        if (stockIdx >= 0 && stockIdx < row.length)
          'stock': int.tryParse(row[stockIdx].toString()) ?? 0,
      });
      count++;
    }
    if (count > 0) _changes.add('item_imported');
    return count;
  }

  Future<int> importMembersCsv(String csv) async {
    final converter = const CsvToListConverter(eol: '\n');
    final list = converter.convert(csv);
    if (list.isEmpty) return 0;
    final headers = list.first.map((e) => e.toString()).toList();
    final rows = list
        .sublist(1)
        .map((r) => r.map((c) => c?.toString() ?? '').toList())
        .toList();
    return await importMembersFromRows(headers, rows);
  }

  Future<int> importMembersFromRows(
    List<String> headers,
    List<List<String>> rows,
  ) async {
    final lnIdx = headers.indexWhere(
      (h) => h.toLowerCase() == 'last_name' || h.toLowerCase() == 'lastname',
    );
    final fnIdx = headers.indexWhere(
      (h) => h.toLowerCase() == 'first_name' || h.toLowerCase() == 'firstname',
    );
    final mnIdx = headers.indexWhere(
      (h) =>
          h.toLowerCase() == 'middle_name' || h.toLowerCase() == 'middlename',
    );
    final roleIdx = headers.indexWhere((h) => h.toLowerCase() == 'role');
    final contactIdx = headers.indexWhere(
      (h) => h.toLowerCase() == 'contact_no',
    );
    final bdayIdx = headers.indexWhere((h) => h.toLowerCase() == 'birthday');
    final addrIdx = headers.indexWhere((h) => h.toLowerCase() == 'address');
    final refIdx = headers.indexWhere((h) => h.toLowerCase() == 'referrer');

    final allMembers = await fetchMembers();
    int inserted = 0;

    for (final row in rows) {
      final lastName = lnIdx >= 0 && lnIdx < row.length ? row[lnIdx] : '';
      final firstName = fnIdx >= 0 && fnIdx < row.length ? row[fnIdx] : '';

      // Check for duplicate
      final dup = allMembers.any(
        (m) =>
            (m.lastName ?? '') == lastName && (m.firstName ?? '') == firstName,
      );
      if (dup) continue;

      await _supabase.from('members').insert({
        'user_id': _uid,
        if (lnIdx >= 0) 'last_name': lastName,
        if (fnIdx >= 0) 'first_name': firstName,
        if (mnIdx >= 0 && mnIdx < row.length) 'middle_name': row[mnIdx],
        if (roleIdx >= 0 && roleIdx < row.length) 'role': row[roleIdx],
        if (contactIdx >= 0 && contactIdx < row.length)
          'contact_no': row[contactIdx],
        if (bdayIdx >= 0 && bdayIdx < row.length) 'birthday': row[bdayIdx],
        if (addrIdx >= 0 && addrIdx < row.length) 'address': row[addrIdx],
        if (refIdx >= 0 && refIdx < row.length) 'referrer': row[refIdx],
        'qr': _generateMemberQr(),
        'level': 1,
      });
      inserted++;
    }

    if (inserted > 0) _changes.add('member_imported');
    return inserted;
  }

  Future<int> importSalesCsv(String csv) async {
    final converter = const CsvToListConverter(eol: '\n');
    final list = converter.convert(csv);
    if (list.length < 2) return 0;
    final headers = list.first.map((e) => e.toString().toLowerCase()).toList();
    final itemIdx = headers.indexOf('item_name');
    final qtyIdx = headers.indexOf('quantity');
    final priceIdx = headers.indexOf('price');
    final tsIdx = headers.indexOf('timestamp');

    int count = 0;
    for (final row in list.sublist(1)) {
      if (row.isEmpty || itemIdx < 0) continue;
      await _supabase.from('sales').insert({
        'user_id': _uid,
        'item_id': 0, // Placeholder; real items should match by name
        'item_name': row[itemIdx].toString(),
        'quantity': qtyIdx >= 0 ? int.tryParse(row[qtyIdx].toString()) ?? 1 : 1,
        'price': priceIdx >= 0
            ? int.tryParse(row[priceIdx].toString()) ?? 0
            : 0,
        if (tsIdx >= 0 && tsIdx < row.length)
          'timestamp': row[tsIdx].toString(),
      });
      count++;
    }
    if (count > 0) _changes.add('sale_imported');
    return count;
  }

  // ── CSV Export ───────────────────────────────────────────────────────────

  Future<String> exportItemsCsvString() async {
    final items = await fetchItems();
    final rows = <List<String>>[
      ['ID', 'Name', 'Category', 'Stock', 'Last Updated', 'Status'],
      for (final i in items)
        [
          i.id?.toString() ?? '',
          i.name,
          i.category ?? '',
          i.stock.toString(),
          i.lastUpdated?.toIso8601String() ?? '',
          i.status ?? '',
        ],
    ];
    return const ListToCsvConverter().convert(rows);
  }

  Future<String> exportItemsCsv() => exportItemsCsvString();

  Future<String> exportMembersCsvString() async {
    final members = await fetchMembers();
    final rows = <List<String>>[
      [
        'ID',
        'Last Name',
        'First Name',
        'Middle Name',
        'Role',
        'Contact No',
        'Birthday',
        'Address',
        'Referrer',
        'Level',
      ],
      for (final m in members)
        [
          m.id?.toString() ?? '',
          m.lastName ?? '',
          m.firstName ?? '',
          m.middleName ?? '',
          m.role ?? '',
          m.contactNo ?? '',
          m.birthday ?? '',
          m.address ?? '',
          m.referrer ?? '',
          m.level.toString(),
        ],
    ];
    return const ListToCsvConverter().convert(rows);
  }

  Future<String> exportMembersCsv() => exportMembersCsvString();

  Future<String> exportSalesCsvString() async {
    final sales = await fetchSales();
    final rows = <List<String>>[
      [
        'ID',
        'Item Name',
        'Quantity',
        'Price',
        'Total',
        'Timestamp',
        'Buyer ID',
      ],
      for (final s in sales)
        [
          s.id?.toString() ?? '',
          s.itemName,
          s.quantity.toString(),
          s.price.toString(),
          (s.quantity * s.price).toString(),
          s.timestamp?.toIso8601String() ?? '',
          s.buyerId?.toString() ?? '',
        ],
    ];
    return const ListToCsvConverter().convert(rows);
  }

  Future<String> exportSalesCsv() => exportSalesCsvString();

  // ── Private Helpers ──────────────────────────────────────────────────────

  /// Converts a raw exception into a user-friendly error message.
  /// Prevents leaking technical details like ClientException / SocketException.
  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('ClientException')) {
      return 'Unable to connect. Check your internet connection.';
    }
    if (msg.contains('TimeoutException')) {
      return 'Request timed out. Please try again.';
    }
    if (msg.contains('AuthException') || msg.contains('401')) {
      return 'Session expired. Please log in again.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _seedDefaultLevels({String? tenantUserId}) async {
    final uid = tenantUserId ?? _uid;
    final defaults = [
      (level: 1, remMin: 500, remMax: 500, ca: 0, boxes: 0),
      (level: 2, remMin: 800, remMax: 1000, ca: 100, boxes: 10),
      (level: 3, remMin: 1700, remMax: 2100, ca: 200, boxes: 50),
      (level: 4, remMin: 3400, remMax: 4200, ca: 400, boxes: 150),
      (level: 5, remMin: 6800, remMax: 8400, ca: 800, boxes: 300),
      (level: 6, remMin: 13600, remMax: 16800, ca: 1600, boxes: 500),
      (level: 7, remMin: 27200, remMax: 33600, ca: 3200, boxes: 800),
      (level: 8, remMin: 54400, remMax: 67200, ca: 6400, boxes: 1200),
      (level: 9, remMin: 108800, remMax: 134400, ca: 12800, boxes: 1800),
      (level: 10, remMin: 217600, remMax: 268800, ca: 25600, boxes: 2500),
    ];
    for (final d in defaults) {
      await _supabase.from('reseller_levels').upsert({
        'level': d.level,
        'user_id': uid,
        'remittance_min': d.remMin,
        'remittance_max': d.remMax,
        'cash_advance': d.ca,
        'boxes_required': d.boxes,
      });
    }
  }

  void dispose() {
    _realtimeSub?.cancel();
    _changes.close();
  }
}
