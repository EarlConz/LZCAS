// lib/data/supabase_repository.dart
// Cloud-based repository using Supabase PostgreSQL.
// Mirrors DbRepository's public API exactly for drop-in replacement.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' hide Category;
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

  /// Active Realtime channels, tracked so they can be severed cleanly on
  /// logout / dispose (see [_teardownRealtime]) — this is what keeps the
  /// free-tier connection count from leaking.
  final List<RealtimeChannel> _channels = [];

  /// The repository is built at app boot, *before* any session is restored,
  /// so realtime must (re)subscribe when the user actually signs in.
  StreamSubscription? _authSub;

  SupabaseRepository({required SupabaseClient supabase})
    : _supabase = supabase {
    _initRealtime();
    _authSub = _supabase.auth.onAuthStateChange.listen((state) {
      switch (state.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
          if (_channels.isEmpty) _initRealtime();
          break;
        case AuthChangeEvent.signedOut:
          _teardownRealtime();
          break;
        default:
          break;
      }
    });
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

  /// Maps a realtime table name to the singular prefix of the granular change
  /// events the UI already listens for (e.g. `items` → `item_added`).
  static const Map<String, String> _tableSingular = {
    'items': 'item',
    'members': 'member',
    'sales': 'sale',
  };

  /// Initialize Supabase Realtime subscriptions for all tables.
  void _initRealtime() {
    if (_supabase.auth.currentUser == null || _channels.isNotEmpty) return;

    // Shared business tables. Deliberately NO user_id filter: reads are
    // unfiltered (RLS scopes visibility) and each row is stamped with the
    // *writer's* user_id, so a filter here would hide a cashier's sale from
    // the admin's device. Realtime delivery is still gated by RLS.
    for (final table in _tableSingular.keys) {
      final channel = _supabase
          .channel('public:$table')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (payload) => _emitGranular(table, payload.eventType),
          )
          .subscribe();
      _channels.add(channel);
    }

    // Approval queues — admin must see every request regardless of author.
    for (final table in ['pending_requests', 'withdrawal_requests']) {
      final channel = _supabase
          .channel('public:$table')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (payload) => _changes.add('${table}_changed'),
          )
          .subscribe();
      _channels.add(channel);
    }
  }

  /// Translates a realtime payload into the same granular event names the local
  /// mutation helpers emit, so every existing `repository.changes` listener
  /// reacts to a cross-device change exactly as it does to a local one. The
  /// coarse `<table>_changed` name is also emitted for listeners that use it.
  void _emitGranular(String table, PostgresChangeEvent event) {
    final singular = _tableSingular[table]!;
    switch (event) {
      case PostgresChangeEvent.insert:
        _changes.add('${singular}_added');
        break;
      case PostgresChangeEvent.update:
        _changes.add('${singular}_updated');
        break;
      case PostgresChangeEvent.delete:
        _changes.add('${singular}_deleted');
        break;
      default:
        _changes.add('${singular}_updated');
    }
    _changes.add('${table}_changed');
  }

  /// Unsubscribes every channel and frees the free-tier connection slot.
  void _teardownRealtime() {
    for (final channel in _channels) {
      _supabase.removeChannel(channel);
    }
    _channels.clear();
  }

  void notifyCloudRestored() {
    _changes.add('item_imported');
    _changes.add('member_imported');
    _changes.add('sale_imported');
    _changes.add('cloud_restored');
  }

  // ── Idempotent migrations (no-ops in cloud) ──────────────────────────────

  Future<void> ensureVerifiedResellerConsistency() async {}
  Future<void> ensureReferrerIdBackfill() async {}

  // ── Fetch Methods ────────────────────────────────────────────────────────

  Future<List<Item>> fetchItems() async {
    final data = await _supabase.from('items').select();
    return (data as List).map((j) => Item.fromJson(j)).toList();
  }

  /// Fetch members. Soft-deleted members are hidden by default; pass
  /// [includeDeleted] for referral-tree/earnings computations, where
  /// historical earnings must survive member deletion.
  /// (Filtered client-side so the app keeps working even before the
  /// is_deleted migration has been applied.)
  Future<List<Member>> fetchMembers({bool includeDeleted = false}) async {
    final data = await _supabase.from('members').select();
    final members = (data as List).map((j) => Member.fromJson(j)).toList();
    if (includeDeleted) return members;
    return members.where((m) => !m.isDeleted).toList();
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
    final member = await getMemberById(memberId);
    // Soft-deleted members must not be able to log in to a dashboard.
    if (member != null && member.isDeleted) return null;
    return member;
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

  /// Replace package availment names with the current catalog name so
  /// renamed packages display correctly in purchase history.
  /// Prices are left as recorded (what the member actually paid).
  /// Falls back to the stored snapshot if the catalog is unavailable or
  /// the package was deleted.
  Future<List<Sale>> _withCurrentPackageNames(List<Sale> sales) async {
    if (!sales.any((s) => s.isPackage)) return sales;
    try {
      final packages = await fetchPackages();
      final byId = {
        for (final p in packages)
          if (p.id != null) p.id!: p,
      };
      return sales.map((s) {
        final current = byId[s.packageId];
        return (s.isPackage && current != null)
            ? s.copyWith(itemName: current.name)
            : s;
      }).toList();
    } catch (_) {
      return sales;
    }
  }

  Future<List<Sale>> fetchSalesForMember(int memberId) async {
    final data = await _supabase
        .from('sales')
        .select()
        .eq('buyer_id', memberId);
    final sales = (data as List).map((j) => Sale.fromJson(j)).toList();
    return _withCurrentPackageNames(sales);
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
    final sales = (data as List).map((j) => Sale.fromJson(j)).toList();
    return _withCurrentPackageNames(sales);
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

  /// Fetch items that need restocking — Low Stock *and* Out of Stock
  /// (per-category threshold aware, via the items_with_status view). Used by
  /// the notification popover. Ordered by stock ascending so the most urgent
  /// (out-of-stock) items surface first.
  Future<List<Item>> fetchLowStockItems() async {
    final data = await _supabase
        .from('items_with_status')
        .select()
        .neq('stock_status', 'Good')
        .order('stock', ascending: true);
    return (data as List).map((j) {
      final map = j as Map<String, dynamic>;
      return Item.fromJson(
        map,
      ).copyWith(status: map['stock_status'] as String?);
    }).toList();
  }

  // ── Paginated Fetch Methods ──────────────────────────────────────────────

  /// Fetch a page of items with optional search and sort.
  Future<PageResult<Item>> fetchItemsPaginated({
    int page = 1,
    int pageSize = 100,
    String? search,
    String? categoryFilter,
    String? statusFilter,
    String sortColumn = 'name',
    bool sortAscending = true,
  }) async {
    // Read from the items_with_status view so the per-category status
    // (Low / Out / Good) is computed server-side and stays consistent with
    // pagination and the total count. `stock_status` is the authoritative
    // status carried back into each Item.
    dynamic dataQuery = _supabase.from('items_with_status').select('*');
    dynamic countQuery = _supabase.from('items_with_status').select('id');

    if (search != null && search.isNotEmpty) {
      dataQuery = dataQuery.ilike('name', '%$search%');
      countQuery = countQuery.ilike('name', '%$search%');
    }
    if (categoryFilter != null && categoryFilter.isNotEmpty) {
      dataQuery = dataQuery.eq('category', categoryFilter);
      countQuery = countQuery.eq('category', categoryFilter);
    }
    if (statusFilter != null && statusFilter.isNotEmpty) {
      if (statusFilter == 'Needs Restocking') {
        // Low Stock + Out of Stock combined = anything not 'Good'.
        dataQuery = dataQuery.neq('stock_status', 'Good');
        countQuery = countQuery.neq('stock_status', 'Good');
      } else {
        dataQuery = dataQuery.eq('stock_status', statusFilter);
        countQuery = countQuery.eq('stock_status', statusFilter);
      }
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
    final rows = (results[1] as List).map((j) {
      final map = j as Map<String, dynamic>;
      // The view's computed status overrides the stored `status` column.
      return Item.fromJson(
        map,
      ).copyWith(status: map['stock_status'] as String?);
    }).toList();

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
    // Hide soft-deleted members from paginated lists (server-side so the
    // total count stays accurate). Requires the is_deleted migration.
    dynamic dataQuery = _supabase
        .from('members')
        .select('*')
        .neq('is_deleted', true);
    dynamic countQuery = _supabase
        .from('members')
        .select('id')
        .neq('is_deleted', true);

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
    String? userId,
  }) async {
    dynamic dataQuery = _supabase.from('sales').select('*');
    dynamic countQuery = _supabase.from('sales').select('id');

    // Scope to a single seller (e.g. a branch cashier sees only their sales).
    if (userId != null) {
      dataQuery = dataQuery.eq('user_id', userId);
      countQuery = countQuery.eq('user_id', userId);
    }

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
  }) async {
    final results = await Future.wait<dynamic>([
      // This month's sales
      _supabase
          .from('sales')
          .select('price, quantity, package_id')
          .gte('timestamp', thisMonthStart.toIso8601String())
          .lt('timestamp', thisMonthEnd.toIso8601String()),
      // Last month's sales
      _supabase
          .from('sales')
          .select('price, quantity, package_id')
          .gte('timestamp', lastMonthStart.toIso8601String())
          .lt('timestamp', lastMonthEnd.toIso8601String()),
      // Low stock items (id only, lightweight) — per-category threshold
      // aware via the items_with_status view.
      _supabase
          .from('items_with_status')
          .select('id')
          .eq('stock_status', 'Low Stock'),
    ]);

    final thisMonthSales = results[0] as List;
    final lastMonthSales = results[1] as List;
    final lowStockRows = results[2] as List;

    // Aggregate client-side (rows limited to one month each, not all time).
    // price is per-unit, so a line's revenue is price × quantity.
    // Package availments (package_id set) are tallied separately — they are
    // not products and must not inflate revenue or order counts.
    int monthlyRevenue = 0;
    int activeOrders = 0;
    int packageRevenue = 0;
    int packagesSold = 0;
    for (final row in thisMonthSales) {
      final price = (row['price'] as int?) ?? 0;
      final qty = (row['quantity'] as int?) ?? 0;
      final lineRevenue = price * qty;
      if (row['package_id'] != null) {
        packageRevenue += lineRevenue;
        packagesSold += qty;
      } else {
        monthlyRevenue += lineRevenue;
        activeOrders++;
      }
    }

    int previousMonthRevenue = 0;
    int previousMonthOrders = 0;
    int previousPackageRevenue = 0;
    int previousPackagesSold = 0;
    for (final row in lastMonthSales) {
      final price = (row['price'] as int?) ?? 0;
      final qty = (row['quantity'] as int?) ?? 0;
      final lineRevenue = price * qty;
      if (row['package_id'] != null) {
        previousPackageRevenue += lineRevenue;
        previousPackagesSold += qty;
      } else {
        previousMonthRevenue += lineRevenue;
        previousMonthOrders++;
      }
    }

    return {
      'monthlyRevenue': monthlyRevenue,
      'activeOrders': activeOrders,
      'previousMonthRevenue': previousMonthRevenue,
      'previousMonthOrders': previousMonthOrders,
      'lowStockItems': lowStockRows.length,
      'packageRevenue': packageRevenue,
      'packagesSold': packagesSold,
      'previousPackageRevenue': previousPackageRevenue,
      'previousPackagesSold': previousPackagesSold,
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
        .select('price, quantity, timestamp, package_id')
        .gte('timestamp', startDate.toIso8601String())
        .lt('timestamp', endDate.toIso8601String());

    // Aggregate by YYYY-MM key. Includes BOTH product sales and package
    // availments so this matches the dashboard's Total Revenue card.
    // price is per-unit: revenue is price × quantity. Timestamps are
    // bucketed in LOCAL time so a sale near a month boundary lands in the
    // month the user actually made it.
    final Map<String, Map<String, dynamic>> monthly = {};
    for (final row in (data as List)) {
      final rowMap = row as Map<String, dynamic>;
      final ts = DateTime.parse(rowMap['timestamp'] as String).toLocal();
      final key = '${ts.year}-${ts.month.toString().padLeft(2, '0')}';
      monthly.putIfAbsent(
        key,
        () => {'month': key, 'revenue': 0, 'transactions': 0},
      );
      monthly[key]!['revenue'] =
          (monthly[key]!['revenue'] as int) +
          ((rowMap['price'] as int?) ?? 0) *
              ((rowMap['quantity'] as int?) ?? 0);
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
    int? packageId,
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
          if (packageId != null) 'package_id': packageId,
        })
        .select('id');

    _changes.add('member_added');
    if (data is List && data.isNotEmpty) {
      return (data.first['id'] as num).toInt();
    }
    return 0;
  }

  /// Sync a member's LOGIN account role to match their reseller status.
  /// Reseller status is derived from package availment; when a package is
  /// added/removed at edit time this updates profiles.role via a
  /// staff-only SECURITY DEFINER RPC so the member sees the right tabs.
  /// No-ops for members without a login account.
  Future<void> syncMemberLoginRole(int memberId, bool isReseller) async {
    try {
      await _supabase.rpc(
        'set_member_account_role',
        params: {'p_member_id': memberId, 'p_is_reseller': isReseller},
      );
    } catch (e) {
      debugPrint('[Repo] syncMemberLoginRole failed: $e');
    }
  }

  // ── Package CRUD ───────────────────────────────────────────────────────

  Future<List<Package>> fetchPackages() async {
    try {
      final data = await _supabase.from('packages').select().order('id');
      return (data as List).map((j) => Package.fromJson(j)).toList();
    } catch (e) {
      debugPrint('[Repo] fetchPackages ERROR: $e');
      rethrow;
    }
  }

  Future<Package?> getPackageById(int id) async {
    final data = await _supabase
        .from('packages')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return Package.fromJson(data);
  }

  Future<int> addPackage({
    required String name,
    int price = 0,
    int directReferralBonus = 0,
    int indirectReferralBonus = 0,
    int chairmansBonus = 0,
    int upgradeReferralBonus = 0,
    int groupSalesDirect = 0,
    int groupSalesIndirect = 0,
    int hierarchyRank = 0,
  }) async {
    final data = await _supabase
        .from('packages')
        .insert({
          'name': name,
          'price': price,
          'direct_referral_bonus': directReferralBonus,
          'indirect_referral_bonus': indirectReferralBonus,
          'chairmans_bonus': chairmansBonus,
          'upgrade_referral_bonus': upgradeReferralBonus,
          'group_sales_direct': groupSalesDirect,
          'group_sales_indirect': groupSalesIndirect,
          'hierarchy_rank': hierarchyRank,
        })
        .select('id');
    _changes.add('package_added');
    if (data is List && data.isNotEmpty) {
      return (data.first['id'] as num).toInt();
    }
    return 0;
  }

  Future<bool> updatePackage(Package pkg) async {
    if (pkg.id == null) return false;
    await _supabase.from('packages').update(pkg.toJson()).eq('id', pkg.id!);
    // Keep availment records in sync: package sales display the package
    // name from sales.item_name, so a rename must propagate to them
    // (unlike product sales, where item_name is a historical snapshot).
    await _supabase
        .from('sales')
        .update({'item_name': pkg.name})
        .eq('package_id', pkg.id!);
    _changes.add('package_updated');
    _changes.add('sale_updated');
    return true;
  }

  Future<bool> deletePackage(int id) async {
    await _supabase.from('packages').delete().eq('id', id);
    _changes.add('package_deleted');
    return true;
  }

  /// Count members who selected each package.
  Future<Map<int, int>> fetchPackageAvailerCounts() async {
    final data = await _supabase
        .from('members')
        .select('package_id')
        .not('package_id', 'is', null);
    final counts = <int, int>{};
    for (final row in (data as List)) {
      final pid = (row['package_id'] as num).toInt();
      counts[pid] = (counts[pid] ?? 0) + 1;
    }
    return counts;
  }

  /// Fetch members who selected a specific package.
  Future<List<Member>> fetchMembersByPackage(int packageId) async {
    final data = await _supabase
        .from('members')
        .select()
        .eq('package_id', packageId);
    return (data as List).map((j) => Member.fromJson(j)).toList();
  }

  Future<int> addSale({
    required int itemId,
    String? itemName,
    required int quantity,
    int price = 0,
    DateTime? timestamp,
    int? buyerId,
    String? buyerName,
    int? packageId,
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
          if (packageId != null) 'package_id': packageId,
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

  // ── Branch Stock (two-tier inventory) ──────────────────────────────────────

  /// A branch cashier's own on-hand allocation, shaped as [Item]s (stock =
  /// their quantity, status = Good/Low/Out). Reads `branch_stock_view`.
  Future<List<Item>> fetchBranchStock(String ownerId) async {
    final data = await _supabase
        .from('branch_stock_view')
        .select()
        .eq('owner_id', ownerId);
    return (data as List).map((j) => Item.fromJson(j)).toList();
  }

  /// All branches' stock rows (admin overview). Each row includes owner_id,
  /// id (item), name, category, stock (quantity), status.
  Future<List<Map<String, dynamic>>> fetchAllBranchStock() async {
    final data = await _supabase
        .from('branch_stock_view')
        .select()
        .order('owner_id');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Branch-cashier accounts (id + username) for the give-out picker.
  Future<List<Map<String, dynamic>>> listBranchCashiers() async {
    final data = await _supabase
        .from('profiles')
        .select('id, username')
        .eq('role', 'branch_cashier')
        .order('username');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Give central stock to a branch cashier (admin / main cashier only).
  Future<void> transferStockToBranch({
    required int itemId,
    required String ownerId,
    required int quantity,
    String? note,
  }) async {
    await _supabase.rpc(
      'transfer_stock_to_branch',
      params: {
        'p_item_id': itemId,
        'p_owner_id': ownerId,
        'p_quantity': quantity,
        'p_note': note,
      },
    );
    _changes.add('branch_stock_changed');
  }

  /// Return stock from a branch back to central.
  Future<void> returnBranchStock({
    required int itemId,
    required String ownerId,
    required int quantity,
    String? note,
  }) async {
    await _supabase.rpc(
      'return_branch_stock',
      params: {
        'p_item_id': itemId,
        'p_owner_id': ownerId,
        'p_quantity': quantity,
        'p_note': note,
      },
    );
    _changes.add('branch_stock_changed');
  }

  /// Set a branch's count for an item to an absolute value (correction).
  Future<void> adjustBranchStock({
    required int itemId,
    required String ownerId,
    required int newQuantity,
    String? note,
  }) async {
    await _supabase.rpc(
      'adjust_branch_stock',
      params: {
        'p_item_id': itemId,
        'p_owner_id': ownerId,
        'p_new_quantity': newQuantity,
        'p_note': note,
      },
    );
    _changes.add('branch_stock_changed');
  }

  /// Record a sale from the CURRENT branch cashier's allocation. Decrements
  /// their branch stock and writes a normal sales row. Returns the sale id.
  Future<int> recordBranchSale({
    required int itemId,
    required int quantity,
    int price = 0,
    int? buyerId,
    String? buyerName,
    DateTime? timestamp,
  }) async {
    final data = await _supabase.rpc(
      'record_branch_sale',
      params: {
        'p_item_id': itemId,
        'p_quantity': quantity,
        'p_price': price,
        'p_buyer_id': buyerId,
        'p_buyer_name': buyerName,
        'p_timestamp': timestamp?.toUtc().toIso8601String(),
      },
    );
    _changes.add('sale_added');
    if (data is num) return data.toInt();
    return 0;
  }

  /// Transfer/return/adjust audit history (newest first), paginated and
  /// optionally filtered by branch cashier and/or transfer type. Server-side
  /// `range` keeps the payload bounded no matter how much history accrues.
  Future<List<Map<String, dynamic>>> fetchStockTransfers({
    String? ownerId,
    String? transferType, // 'give_out' | 'return' | 'adjust'
    int limit = 50,
    int offset = 0,
  }) async {
    var q = _supabase.from('stock_transfers').select();
    if (ownerId != null) q = q.eq('to_owner_id', ownerId);
    if (transferType != null) q = q.eq('transfer_type', transferType);
    final data = await q
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(data as List);
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

  /// Check whether a username is available across all user types
  /// (staff in profiles, members with accounts in members.email).
  /// Returns true if available, false if already taken.
  /// Case-insensitive: "Tep" and "tep" collide.
  Future<bool> isUsernameAvailable(String username) async {
    final email = '$username@lzcas.local'.toLowerCase();
    try {
      final profile = await _supabase
          .from('profiles')
          .select('username')
          .ilike('username', username)
          .maybeSingle();
      if (profile != null) return false;

      final member = await _supabase
          .from('members')
          .select('email')
          .ilike('email', email)
          .maybeSingle();
      if (member != null) return false;

      return true;
    } catch (_) {
      return false; // Can't verify — block to be safe
    }
  }

  /// Create a Supabase Auth account for an existing member.
  /// Accepts a username and password; email is auto-generated as
  /// '{username}@lzcas.local' (Supabase Auth requires email format).
  /// Calls the create-member-user edge function and updates the member's email.
  /// Returns a map with {email, password, id} on success,
  /// {error: 'message'} on a known edge-function failure, or null on
  /// unexpected errors.
  Future<Map<String, dynamic>?> createMemberAuthAccount({
    required int memberId,
    required String username,
    required String password,
  }) async {
    final member = await getMemberById(memberId);
    if (member == null) return null;
    final email = '$username@lzcas.local';

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

      // Handle success (200) and error responses (4xx/5xx).
      // The SDK may parse JSON into a Map, or return the raw body as a String.
      Map<String, dynamic>? data;
      if (result.data is Map) {
        data = (result.data as Map).cast<String, dynamic>();
      } else if (result.data is String) {
        try {
          data = (jsonDecode(result.data as String) as Map)
              .cast<String, dynamic>();
        } catch (_) {
          data = {'error': result.data.toString()};
        }
      }

      if (data != null) {
        if (data['success'] == true) {
          final authUserId = data['id'] as String? ?? '';
          final updated = member.copyWith(email: email);
          await updateMember(updated);
          return {'email': email, 'password': password, 'id': authUserId};
        }
        final err = data['error']?.toString() ?? '';
        if (err.isNotEmpty) {
          return {'error': _friendlyAuthError(err)};
        }
      }
      return null;
    } on FunctionException catch (e) {
      // functions_client v2 throws on non-2xx; the JSON body is in e.details.
      String err = '';
      final details = e.details;
      if (details is Map && details['error'] != null) {
        err = details['error'].toString();
      } else if (details is String) {
        err = details;
      } else {
        err = e.reasonPhrase ?? '';
      }
      debugPrint('[createMemberAuthAccount] edge function error: $err');
      if (err.isNotEmpty) return {'error': _friendlyAuthError(err)};
      return null;
    } catch (e) {
      debugPrint('[createMemberAuthAccount] error: $e');
      return null;
    }
  }

  /// Map raw auth/edge-function error messages to user-friendly text.
  String _friendlyAuthError(String err) {
    final lower = err.toLowerCase();
    return (lower.contains('already') || lower.contains('exists'))
        ? 'Username already exists'
        : err;
  }

  /// Fetch packages with a higher [hierarchyRank] than [currentRank],
  /// ordered from lowest to highest rank.
  Future<List<Package>> fetchAvailableUpgrades(int currentRank) async {
    final data = await _supabase
        .from('packages')
        .select()
        .gt('hierarchy_rank', currentRank)
        .order('hierarchy_rank', ascending: true);
    return (data as List).map((j) => Package.fromJson(j)).toList();
  }

  /// Execute a validated upgrade via the Supabase RPC.
  /// Throws on downgrade/side-grade or if RPC fails.
  Future<void> submitUpgrade({
    required int memberId,
    required int targetPackageId,
  }) async {
    await _supabase.rpc(
      'process_package_upgrade',
      params: {'p_member_id': memberId, 'p_target_package_id': targetPackageId},
    );
    _changes.add('member_updated');
  }

  /// Compute live earnings for a member from their package.
  ///
  /// Delegates to the SECURITY DEFINER RPC `get_member_earnings`, which
  /// walks the referral tree server-side and returns only this member's
  /// totals. This is what keeps one reseller from reading another's
  /// financial data — the client never reads the whole members/sales
  /// tree anymore. The RPC enforces that the caller is either staff or
  /// the member themselves.
  ///
  /// Returns component keys: totalEarnings, balance, indirectBonus,
  /// passiveIncome, repeatPurchase, chairmanBonus, upgradeBonus.
  Future<Map<String, int>> fetchMemberEarningsBreakdown(int memberId) async {
    final data = await _supabase.rpc(
      'get_member_earnings',
      params: {'p_member_id': memberId},
    );
    final map = (data as Map).cast<String, dynamic>();
    int asInt(String k) => (map[k] as num?)?.toInt() ?? 0;
    return {
      'totalEarnings': asInt('totalEarnings'),
      'balance': asInt('balance'),
      'indirectBonus': asInt('indirectBonus'),
      'passiveIncome': asInt('passiveIncome'),
      'repeatPurchase': asInt('repeatPurchase'),
      'chairmanBonus': asInt('chairmanBonus'),
      'upgradeBonus': asInt('upgradeBonus'),
      // Legacy key from the old weekly-Friday chairman model; the RPC now
      // always returns 0 (v24 made Chairman's Bonus per-direct-referral).
      'chairmanFridays': asInt('chairmanFridays'),
    };
  }

  /// Returns the true gross lifetime earnings for a member — the sum of
  /// ALL earning/credit transactions ever recorded, regardless of withdrawals.
  /// This value never decreases; it represents the absolute cumulative gross
  /// income from account creation to the present moment.
  ///
  /// Queries the member_transactions ledger directly (RLS scoped to the
  /// authenticated member), which is the canonical source of all frozen
  /// earning records (direct/indirect referral, group sales, chairman's
  /// bonus, upgrade bonus).
  Future<int> fetchMemberGrossLifetimeEarnings(int memberId) async {
    try {
      final data = await _supabase
          .from('member_transactions')
          .select('price')
          .eq('member_id', memberId);
      return (data as List).fold<int>(
        0,
        (sum, row) => sum + ((row['price'] as num?)?.toInt() ?? 0),
      );
    } catch (e) {
      debugPrint('[fetchMemberGrossLifetimeEarnings] failed: $e');
      return 0;
    }
  }

  // ── Earnings history (snapshot ledger) ────────────────────────────

  /// Record a snapshot of the member's computed earnings/balance — but
  /// only when the values changed since the last snapshot, so the log
  /// reads as a ledger of changes rather than one row per page view.
  /// Returns true when a new snapshot was written.
  Future<bool> recordEarningsSnapshot({
    required int memberId,
    required int totalEarnings,
    required int balance,
    int indirectBonus = 0,
    int groupSales = 0,
    int passiveIncome = 0,
    int repeatPurchase = 0,
    int chairmanBonus = 0,
    int upgradeBonus = 0, // included in totalEarnings, tracked for audit
  }) async {
    try {
      // Nothing earned yet and nothing to compare against — don't write
      // a meaningless all-zero first entry.
      final allZero =
          totalEarnings == 0 &&
          balance == 0 &&
          indirectBonus == 0 &&
          groupSales == 0 &&
          passiveIncome == 0 &&
          repeatPurchase == 0 &&
          chairmanBonus == 0 &&
          upgradeBonus == 0;

      final last = await _supabase
          .from('earnings_history')
          .select(
            'total_earnings, balance, indirect_bonus, group_sales, '
            'passive_income, repeat_purchase, chairman_bonus, upgrade_bonus',
          )
          .eq('member_id', memberId)
          .order('recorded_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (last == null && allZero) return false;

      final lastEarnings = last?['total_earnings'] as int? ?? 0;
      final lastBalance = last?['balance'] as int? ?? 0;
      final unchanged =
          last != null &&
          lastEarnings == totalEarnings &&
          lastBalance == balance &&
          (last['indirect_bonus'] as int? ?? 0) == indirectBonus &&
          (last['group_sales'] as int? ?? 0) == groupSales &&
          (last['passive_income'] as int? ?? 0) == passiveIncome &&
          (last['repeat_purchase'] as int? ?? 0) == repeatPurchase &&
          (last['chairman_bonus'] as int? ?? 0) == chairmanBonus &&
          (last['upgrade_bonus'] as int? ?? 0) == upgradeBonus;
      if (unchanged) return false; // nothing changed — no log entry

      await _supabase.from('earnings_history').insert({
        'member_id': memberId,
        'total_earnings': totalEarnings,
        'balance': balance,
        'earnings_delta': totalEarnings - lastEarnings,
        'balance_delta': balance - lastBalance,
        'indirect_bonus': indirectBonus,
        'group_sales': groupSales,
        'passive_income': passiveIncome,
        'repeat_purchase': repeatPurchase,
        'chairman_bonus': chairmanBonus,
        'upgrade_bonus': upgradeBonus,
      });
      return true;
    } catch (e) {
      debugPrint('[recordEarningsSnapshot] failed: $e');
      return false;
    }
  }

  /// Fetch a member's earnings history, newest first.
  Future<List<EarningsSnapshot>> fetchEarningsHistory(
    int memberId, {
    int limit = 30,
  }) async {
    try {
      final data = await _supabase
          .from('earnings_history')
          .select()
          .eq('member_id', memberId)
          .order('recorded_at', ascending: false)
          .limit(limit);
      return (data as List)
          .map((j) => EarningsSnapshot.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[fetchEarningsHistory] failed: $e');
      return [];
    }
  }

  // ── Category CRUD ──────────────────────────────────────────────────────

  Future<List<Category>> fetchProductCategories() async {
    final data = await _supabase.from('categories').select().order('id');
    return (data as List).map((j) => Category.fromJson(j)).toList();
  }

  Future<int> addCategory({
    required String name,
    int? lowStockThreshold,
  }) async {
    final data = await _supabase
        .from('categories')
        .insert({
          'name': name,
          if (lowStockThreshold != null)
            'low_stock_threshold': lowStockThreshold,
        })
        .select('id');
    if (data is List && data.isNotEmpty) {
      return (data.first['id'] as num).toInt();
    }
    return 0;
  }

  Future<bool> updateCategory(Category cat) async {
    if (cat.id == null) return false;
    await _supabase.from('categories').update(cat.toJson()).eq('id', cat.id!);
    return true;
  }

  Future<bool> deleteCategory(int id) async {
    try {
      await _supabase.from('categories').delete().eq('id', id);
      return true;
    } on PostgrestException catch (e) {
      // P0001 = RAISE EXCEPTION from the prevent_active_category_deletion
      // trigger — the category is still referenced by inventory items.
      if (e.code == 'P0001') {
        return false;
      }
      rethrow;
    }
  }

  // ── Delete Methods ───────────────────────────────────────────────────────

  Future<int> deleteItemById(int id) async {
    await _supabase.from('items').delete().eq('id', id);
    _changes.add('item_deleted');
    return 1;
  }

  /// Soft-delete: the member disappears from lists and can no longer log
  /// in, but the row stays so the referral tree — and every bonus their
  /// upline already earned from them — remains intact. Historical
  /// earnings are permanent; deletion must never deduct them.
  Future<bool> deleteMemberById(int id) async {
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
      }
    }

    await _supabase.from('members').update({'is_deleted': true}).eq('id', id);
    _changes.add('member_deleted');
    return true;
  }

  /// Restore a soft-deleted member (clears is_deleted so they reappear in
  /// lists and can log in again). Returns true on success.
  Future<bool> restoreMemberById(int id) async {
    try {
      await _supabase
          .from('members')
          .update({'is_deleted': false})
          .eq('id', id);
      _changes.add('member_updated');
      return true;
    } catch (e) {
      debugPrint('[Repo] restoreMemberById failed: $e');
      return false;
    }
  }

  /// Find a soft-deleted member whose login account uses [username]
  /// (email '{username}@lzcas.local'). Used to detect when a "taken"
  /// username actually belongs to a deleted member — the admin can then
  /// restore that member instead of being blocked. Returns null if none.
  Future<Member?> findDeletedMemberByUsername(String username) async {
    final email = '$username@lzcas.local'.toLowerCase();
    try {
      final data = await _supabase
          .from('members')
          .select()
          .ilike('email', email)
          .eq('is_deleted', true)
          .limit(1);
      final list = data as List;
      if (list.isEmpty) return null;
      return Member.fromJson(list.first as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[Repo] findDeletedMemberByUsername failed: $e');
      return null;
    }
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

  /// Get the count of items that need restocking — Low Stock *and* Out of
  /// Stock (per-category threshold aware, via the items_with_status view).
  /// Out-of-stock is the more urgent case, so it must be included, not
  /// dropped once an item hits zero.
  Future<int> fetchLowStockCount() async {
    final resp = await _supabase
        .from('items_with_status')
        .select('id')
        .neq('stock_status', 'Good')
        .count(CountOption.exact);
    return resp.count;
  }

  /// Aggregate inventory figures for the summary strip: total SKUs, low
  /// stock count, out-of-stock count, and total units on hand. Runs the
  /// three counts and the units scan in parallel. `needsRestock` (Low +
  /// Out) is simply low + out.
  Future<Map<String, int>> fetchInventorySummary() async {
    // Low / Out counts come from the items_with_status view so they honour
    // each category's own threshold; Products and Units are plain item scans.
    final results = await Future.wait<dynamic>([
      _supabase.from('items').select('id').count(CountOption.exact),
      _supabase
          .from('items_with_status')
          .select('id')
          .eq('stock_status', 'Low Stock')
          .count(CountOption.exact),
      _supabase
          .from('items_with_status')
          .select('id')
          .eq('stock_status', 'Out of Stock')
          .count(CountOption.exact),
      // Units total — items table is small, so a client-side sum is cheap.
      _supabase.from('items').select('stock'),
    ]);

    final skuCount = (results[0] as PostgrestResponse).count;
    final lowCount = (results[1] as PostgrestResponse).count;
    final outCount = (results[2] as PostgrestResponse).count;

    int totalUnits = 0;
    for (final row in (results[3] as List)) {
      final s = (row as Map<String, dynamic>)['stock'];
      totalUnits += s is int
          ? s
          : s is num
          ? s.toInt()
          : int.tryParse(s?.toString() ?? '0') ?? 0;
    }

    return {
      'skuCount': skuCount,
      'lowCount': lowCount,
      'outCount': outCount,
      'totalUnits': totalUnits,
    };
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

  /// Fetch the stored password for a staff user from profiles.password.
  Future<String?> fetchUserPassword(String userId) async {
    try {
      final data = await _supabase
          .from('profiles')
          .select('password')
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return null;
      return data['password'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Fetch the stored password for a member from members.password.
  Future<String?> fetchMemberPassword(int memberId) async {
    try {
      final data = await _supabase
          .from('members')
          .select('password')
          .eq('id', memberId)
          .maybeSingle();
      if (data == null) return null;
      return data['password'] as String?;
    } catch (_) {
      return null;
    }
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
  /// Supports: delete, reduce_stock, delete_member.
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

  // ── Withdrawal Requests ──────────────────────────────────────────────────

  /// Submit a withdrawal request for admin approval.
  Future<String?> submitWithdrawalRequest({
    required int memberId,
    required String sourceBucket,
    required int amount,
  }) async {
    final result = await _supabase
        .from('withdrawal_requests')
        .insert({
          'member_id': memberId,
          'source_bucket': sourceBucket,
          'requested_amount': amount,
          'status': 'pending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id');

    _changes.add('withdrawal_request_added');
    if (result is List && result.isNotEmpty) {
      return result.first['id'] as String?;
    }
    return null;
  }

  /// Fetch pending withdrawal requests, ordered newest first.
  Future<List<WithdrawalRequest>> fetchPendingWithdrawals() async {
    final data = await _supabase
        .from('withdrawal_requests')
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return (data as List)
        .map((j) => WithdrawalRequest.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Fetch withdrawal history (approved + rejected), ordered newest first.
  Future<List<WithdrawalRequest>> fetchWithdrawalHistory() async {
    final data = await _supabase
        .from('withdrawal_requests')
        .select()
        .neq('status', 'pending')
        .order('created_at', ascending: false);
    return (data as List)
        .map((j) => WithdrawalRequest.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Fetch withdrawal requests for a specific member.
  Future<List<WithdrawalRequest>> fetchWithdrawalsForMember(
    int memberId,
  ) async {
    final data = await _supabase
        .from('withdrawal_requests')
        .select()
        .eq('member_id', memberId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((j) => WithdrawalRequest.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Get the count of pending withdrawal requests (for notification badge).
  Future<int> fetchWithdrawalPendingCount() async {
    final resp = await _supabase
        .from('withdrawal_requests')
        .select('id')
        .eq('status', 'pending')
        .count(CountOption.exact);
    return resp.count;
  }

  /// Approve a withdrawal request — deducts from the member's earnings/balance
  /// by recording a negative snapshot entry.
  Future<String?> approveWithdrawalRequest(String requestId) async {
    final data = await _supabase
        .from('withdrawal_requests')
        .select()
        .eq('id', requestId)
        .eq('status', 'pending')
        .maybeSingle();
    if (data == null) return 'Withdrawal request not found';

    final req = WithdrawalRequest.fromJson(data as Map<String, dynamic>);
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      // Fetch current earnings breakdown to get the value being deducted
      final breakdown = await fetchMemberEarningsBreakdown(req.memberId);
      final currentTotalEarnings = breakdown['totalEarnings'] ?? 0;
      final currentBalance = breakdown['balance'] ?? 0;

      // Deduct the requested amount from the appropriate pool
      int newTotalEarnings = currentTotalEarnings;
      int newBalance = currentBalance;
      if (req.sourceBucket == 'total_earnings') {
        newTotalEarnings = (currentTotalEarnings - req.requestedAmount).clamp(
          0,
          currentTotalEarnings,
        );
      } else {
        newBalance = (currentBalance - req.requestedAmount).clamp(
          0,
          currentBalance,
        );
      }

      // Record a negative snapshot to reflect the deduction
      await _supabase.from('earnings_history').insert({
        'member_id': req.memberId,
        'total_earnings': newTotalEarnings,
        'balance': newBalance,
        'earnings_delta': newTotalEarnings - currentTotalEarnings,
        'balance_delta': newBalance - currentBalance,
        'indirect_bonus': breakdown['indirectBonus'] ?? 0,
        'group_sales': breakdown['groupSales'] ?? 0,
        'passive_income': breakdown['passiveIncome'] ?? 0,
        'repeat_purchase': breakdown['repeatPurchase'] ?? 0,
        'chairman_bonus': breakdown['chairmanBonus'] ?? 0,
        'upgrade_bonus': breakdown['upgradeBonus'] ?? 0,
      });
    } catch (e) {
      debugPrint('[approveWithdrawalRequest] deduction failed: $e');
      return 'Failed to process deduction: $_friendlyError(e)';
    }

    // Mark as approved
    await _supabase
        .from('withdrawal_requests')
        .update({'status': 'approved', 'reviewed_by': _uid, 'reviewed_at': now})
        .eq('id', requestId);

    _changes.add('withdrawal_request_approved');
    return null; // success
  }

  /// Reject a withdrawal request — no deduction, just marks status.
  Future<bool> rejectWithdrawalRequest(
    String requestId, {
    required String rejectionReason,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await _supabase
        .from('withdrawal_requests')
        .update({
          'status': 'rejected',
          'reviewed_by': _uid,
          'reviewed_at': now,
          'rejection_reason': rejectionReason,
        })
        .eq('id', requestId)
        .eq('status', 'pending');

    _changes.add('withdrawal_request_rejected');
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

  /// Export the CURRENT filtered/sorted inventory view as a CSV string.
  /// Reads the items_with_status view so filters and the exported Status
  /// column honour each category's own threshold, and returns every
  /// matching row (no pagination).
  Future<String> exportItemsCsvFiltered({
    String? search,
    String? categoryFilter,
    String? statusFilter,
    String sortColumn = 'name',
    bool sortAscending = true,
  }) async {
    dynamic query = _supabase.from('items_with_status').select('*');

    if (search != null && search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }
    if (categoryFilter != null && categoryFilter.isNotEmpty) {
      query = query.eq('category', categoryFilter);
    }
    if (statusFilter != null && statusFilter.isNotEmpty) {
      if (statusFilter == 'Needs Restocking') {
        query = query.neq('stock_status', 'Good');
      } else {
        query = query.eq('stock_status', statusFilter);
      }
    }

    final data = await query.order(sortColumn, ascending: sortAscending);
    final list = (data as List).cast<Map<String, dynamic>>();

    final rows = <List<String>>[
      ['Name', 'Category', 'Stock', 'Status', 'Last Updated'],
      for (final j in list)
        [
          (j['name'] ?? '').toString(),
          (j['category'] ?? '').toString(),
          (j['stock'] ?? 0).toString(),
          (j['stock_status'] ?? '').toString(),
          (j['last_updated'] ?? '').toString(),
        ],
    ];
    return const ListToCsvConverter().convert(rows);
  }

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

  void dispose() {
    _teardownRealtime();
    _supabase.removeAllChannels();
    _authSub?.cancel();
    _changes.close();
  }
}
