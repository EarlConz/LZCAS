// lib/data/supabase_repository.dart
// Cloud-based repository using Supabase PostgreSQL.
// Mirrors DbRepository's public API exactly for drop-in replacement.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

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

  Future<List<Sale>> fetchSalesForReferrer(int referrerMemberId) async {
    // Fetch all members whose referrerId matches, then get their sales
    final allSales = await fetchSales();
    final member = await getMemberById(referrerMemberId);
    if (member == null) return [];

    final memberName = '${member.firstName ?? ''} ${member.lastName ?? ''}'
        .trim();
    final allMembers = await fetchMembers();
    final referredMembers = allMembers.where(
      (m) =>
          m.referrerId == referrerMemberId ||
          (m.referrer ?? '').trim().toLowerCase() == memberName.toLowerCase(),
    );

    final referredIds = referredMembers.map((m) => m.id).toSet();
    return allSales.where((s) => referredIds.contains(s.buyerId)).toList();
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

  Future<List<ResellerLevel>> fetchResellerLevels() async {
    final data = await _supabase.from('reseller_levels').select();
    final levels = (data as List)
        .map((j) => ResellerLevel.fromJson(j))
        .toList();
    if (levels.isEmpty) {
      await _seedDefaultLevels();
      final newData = await _supabase.from('reseller_levels').select();
      return (newData as List).map((j) => ResellerLevel.fromJson(j)).toList();
    }
    return levels;
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

  Future<bool> setMemberLevel(int memberId, int level) async {
    final member = await getMemberById(memberId);
    if (member == null) return false;
    final updated = member.copyWith(level: level.clamp(1, 10));
    await updateMember(updated);
    return true;
  }

  Future<void> upsertResellerLevel({
    required int level,
    required int remittanceMin,
    required int remittanceMax,
    required int cashAdvance,
  }) async {
    await _supabase.from('reseller_levels').upsert({
      'level': level,
      'user_id': _uid,
      'remittance_min': remittanceMin,
      'remittance_max': remittanceMax,
      'cash_advance': cashAdvance,
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
    final data = await _supabase
        .from('pending_requests')
        .select('id')
        .eq('status', 'pending');
    return (data as List).length;
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
      return e.toString().replaceFirst('Exception: ', '');
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
      return e.toString();
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
      return e.toString();
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

  Future<void> _seedDefaultLevels() async {
    final defaults = [
      (level: 1, remMin: 500, remMax: 500, ca: 0),
      (level: 2, remMin: 800, remMax: 1000, ca: 100),
      (level: 3, remMin: 1700, remMax: 2100, ca: 200),
      (level: 4, remMin: 3400, remMax: 4200, ca: 400),
      (level: 5, remMin: 6800, remMax: 8400, ca: 800),
      (level: 6, remMin: 13600, remMax: 16800, ca: 1600),
      (level: 7, remMin: 27200, remMax: 33600, ca: 3200),
      (level: 8, remMin: 54400, remMax: 67200, ca: 6400),
      (level: 9, remMin: 108800, remMax: 134400, ca: 12800),
      (level: 10, remMin: 217600, remMax: 268800, ca: 25600),
    ];
    for (final d in defaults) {
      await _supabase.from('reseller_levels').upsert({
        'level': d.level,
        'user_id': _uid,
        'remittance_min': d.remMin,
        'remittance_max': d.remMax,
        'cash_advance': d.ca,
      });
    }
  }

  void dispose() {
    _realtimeSub?.cancel();
    _changes.close();
  }
}
