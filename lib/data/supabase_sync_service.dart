import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:drift/drift.dart';

import 'package:lzcas/db/app_db.dart';

class CloudRestoreSummary {
  const CloudRestoreSummary({
    required this.items,
    required this.members,
    required this.sales,
  });

  final int items;
  final int members;
  final int sales;
}

class SupabaseSyncService {
  SupabaseSyncService({required this.db, required this.client});

  final AppDb db;
  final SupabaseClient client;

  Future<void> uploadLocalSnapshot() async {
    final items = await db.getAllItems();
    final members = await db.getAllMembers();
    final sales = await db.getAllSales();

    await _clearRemoteSnapshot();

    if (items.isNotEmpty) {
      await client
          .from('items')
          .upsert(items.map(_itemToSupabase).toList(), onConflict: 'id');
    }

    if (members.isNotEmpty) {
      await client
          .from('members')
          .upsert(members.map(_memberToSupabase).toList(), onConflict: 'id');
    }

    if (sales.isNotEmpty) {
      await client
          .from('sales')
          .upsert(sales.map(_saleToSupabase).toList(), onConflict: 'id');
    }
  }

  Future<CloudRestoreSummary> restoreRemoteSnapshot() async {
    final remoteItems = await client.from('items').select();
    final remoteMembers = await client.from('members').select();
    final remoteSales = await client.from('sales').select();

    await db.transaction(() async {
      await db.delete(db.sales).go();
      await db.delete(db.members).go();
      await db.delete(db.items).go();

      for (final row in remoteItems) {
        await db.into(db.items).insert(_itemFromSupabase(row));
      }

      for (final row in remoteMembers) {
        await db.into(db.members).insert(_memberFromSupabase(row));
      }

      for (final row in remoteSales) {
        await db.into(db.sales).insert(_saleFromSupabase(row));
      }

      await _resetLocalSequences();
    });

    return CloudRestoreSummary(
      items: remoteItems.length,
      members: remoteMembers.length,
      sales: remoteSales.length,
    );
  }

  Future<void> _clearRemoteSnapshot() async {
    await client.from('member_transactions').delete().gte('id', 0);
    await client.from('sales').delete().gte('id', 0);
    await client.from('members').delete().gte('id', 0);
    await client.from('items').delete().gte('id', 0);
  }

  Future<void> _resetLocalSequences() async {
    await db.customStatement(
      "DELETE FROM sqlite_sequence WHERE name IN ('items','members','sales');",
    );

    final maxItemId = await _maxId('items');
    final maxMemberId = await _maxId('members');
    final maxSaleId = await _maxId('sales');

    if (maxItemId > 0) {
      await _setSequence('items', maxItemId);
    }
    if (maxMemberId > 0) {
      await _setSequence('members', maxMemberId);
    }
    if (maxSaleId > 0) {
      await _setSequence('sales', maxSaleId);
    }
  }

  Future<int> _maxId(String table) async {
    final row = await db
        .customSelect('SELECT MAX(id) AS max_id FROM $table')
        .getSingle();
    return row.read<int?>('max_id') ?? 0;
  }

  Future<void> _setSequence(String table, int value) {
    return db.customStatement(
      'INSERT INTO sqlite_sequence(name, seq) VALUES (?, ?)',
      [table, value],
    );
  }

  Map<String, Object?> _itemToSupabase(Item item) {
    return {
      'id': item.id,
      'name': item.name,
      'points': item.points,
      'category': item.category,
      'stock': item.stock,
      'last_updated': item.lastUpdated?.toIso8601String(),
      'status': item.status,
    };
  }

  Map<String, Object?> _memberToSupabase(Member member) {
    return {
      'id': member.id,
      'last_name': member.lastName,
      'first_name': member.firstName,
      'middle_name': member.middleName,
      'role': member.role,
      'contact_no': member.contactNo,
      'birthday': member.birthday,
      'address': member.address,
      'referrer': member.referrer,
      'referrer_id': member.referrerId,
      'points': member.points,
      'qr': member.qr,
    };
  }

  Map<String, Object?> _saleToSupabase(Sale sale) {
    return {
      'id': sale.id,
      'item_id': sale.itemId,
      'buyer_id': sale.buyerId,
      'item_name': sale.itemName,
      'quantity': sale.quantity,
      'points': sale.points,
      'price': sale.price,
      'timestamp': sale.timestamp.toIso8601String(),
    };
  }

  ItemsCompanion _itemFromSupabase(Map<String, dynamic> row) {
    return ItemsCompanion(
      id: Value(_readInt(row['id'])),
      name: Value(_readString(row['name']) ?? ''),
      points: Value(_readInt(row['points'])),
      category: Value(_readString(row['category'])),
      stock: Value(_readInt(row['stock'])),
      lastUpdated: Value(_readDateTime(row['last_updated'])),
      status: Value(_readString(row['status'])),
    );
  }

  MembersCompanion _memberFromSupabase(Map<String, dynamic> row) {
    return MembersCompanion(
      id: Value(_readInt(row['id'])),
      lastName: Value(_readString(row['last_name'])),
      firstName: Value(_readString(row['first_name'])),
      middleName: Value(_readString(row['middle_name'])),
      role: Value(_readString(row['role'])),
      contactNo: Value(_readString(row['contact_no'])),
      birthday: Value(_readString(row['birthday'])),
      address: Value(_readString(row['address'])),
      referrer: Value(_readString(row['referrer'])),
      referrerId: Value(_readNullableInt(row['referrer_id'])),
      points: Value(_readInt(row['points'])),
      qr: Value(_readString(row['qr'])),
    );
  }

  SalesCompanion _saleFromSupabase(Map<String, dynamic> row) {
    return SalesCompanion(
      id: Value(_readInt(row['id'])),
      itemId: Value(_readInt(row['item_id'])),
      buyerId: Value(_readNullableInt(row['buyer_id'])),
      itemName: Value(_readString(row['item_name']) ?? ''),
      quantity: Value(_readInt(row['quantity'])),
      points: Value(_readInt(row['points'])),
      price: Value(_readInt(row['price'])),
      timestamp: Value(_readDateTime(row['timestamp']) ?? DateTime.now()),
    );
  }

  int _readInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _readNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  String? _readString(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  DateTime? _readDateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
