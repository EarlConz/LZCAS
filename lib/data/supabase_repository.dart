// lib/data/supabase_repository.dart
// Cloud-based repository using Supabase PostgreSQL.
// Mirrors DbRepository's public API exactly for drop-in replacement.

import 'dart:async';
import 'dart:math';
import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Repository that wraps Supabase and provides the same business operations
/// as the previous DbRepository (imports, exports, change notifications).
class SupabaseRepository {
  final SupabaseClient _supabase;
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

    final tables = ['items', 'members', 'sales', 'reseller_levels'];
    for (final table in tables) {
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

  // ── Borrow Methods ───────────────────────────────────────────────────────

  /// Record a borrow — deducts stock immediately, sets due date 10 days out.
  Future<int> addBorrow({
    required int memberId,
    required int itemId,
    required String itemName,
    required int quantity,
    int price = 0,
    String? notes,
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
    final dueDate = now.add(const Duration(days: 10));

    final result = await _supabase
        .from('borrows')
        .insert({
          'user_id': _uid,
          'member_id': memberId,
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
      'user_id': _uid,
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

  Future<int> addSale({
    required int itemId,
    String? itemName,
    required int quantity,
    int price = 0,
    DateTime? timestamp,
    int? buyerId,
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

  Future<int> deleteItemById(int id) async {
    await _supabase.from('items').delete().eq('id', id);
    _changes.add('item_deleted');
    return 1;
  }

  Future<int> deleteMemberById(int id) async {
    await _supabase.from('members').delete().eq('id', id);
    _changes.add('member_deleted');
    return 1;
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
      (level: 1, remMin: 500, remMax: 1500, ca: 0),
      (level: 2, remMin: 1501, remMax: 3000, ca: 500),
      (level: 3, remMin: 3001, remMax: 5000, ca: 1000),
      (level: 4, remMin: 5001, remMax: 10000, ca: 2000),
      (level: 5, remMin: 10001, remMax: 20000, ca: 5000),
      (level: 6, remMin: 20001, remMax: 35000, ca: 10000),
      (level: 7, remMin: 35001, remMax: 50000, ca: 15000),
      (level: 8, remMin: 50001, remMax: 75000, ca: 25000),
      (level: 9, remMin: 75001, remMax: 100000, ca: 35000),
      (level: 10, remMin: 100001, remMax: 999999, ca: 50000),
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
