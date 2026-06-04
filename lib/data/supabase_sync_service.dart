import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lzcas/db/app_db.dart';

class SupabaseSyncService {
  SupabaseSyncService({
    required this.db,
    required this.client,
  });

  final AppDb db;
  final SupabaseClient client;

  Future<void> uploadLocalSnapshot() async {
    final items = await db.getAllItems();
    final members = await db.getAllMembers();
    final sales = await db.getAllSales();

    await _clearRemoteSnapshot();

    if (items.isNotEmpty) {
      await client.from('items').upsert(
            items.map(_itemToSupabase).toList(),
            onConflict: 'id',
          );
    }

    if (members.isNotEmpty) {
      await client.from('members').upsert(
            members.map(_memberToSupabase).toList(),
            onConflict: 'id',
          );
    }

    if (sales.isNotEmpty) {
      await client.from('sales').upsert(
            sales.map(_saleToSupabase).toList(),
            onConflict: 'id',
          );
    }
  }

  Future<void> _clearRemoteSnapshot() async {
    await client.from('member_transactions').delete().gte('id', 0);
    await client.from('sales').delete().gte('id', 0);
    await client.from('members').delete().gte('id', 0);
    await client.from('items').delete().gte('id', 0);
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
}
