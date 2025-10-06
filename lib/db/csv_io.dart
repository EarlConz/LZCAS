import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' show Value, Variable;
import 'app_db.dart';

// Simple QR token generator for CSV import path (keeps tokens stable when imported)
String _generateMemberQrToken() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final rnd = DateTime.now().millisecond ^ now;
  return '${now.toRadixString(36)}-${(rnd & 0xffffffff).toRadixString(16)}';
}

// Core CSV flows for Items and Members. These functions operate on the canonical
// AppDb instance (lib/db) and only deal with data-level conversions.

Future<String> exportItemsToCsvFile(AppDb db) async {
  final csv = await exportItemsToCsvString(db);

  final exportDir = Directory(p.join('lib', 'data', 'exports'));
  if (!await exportDir.exists()) await exportDir.create(recursive: true);
  final file = File(p.join(exportDir.path, 'items_export_${DateTime.now().millisecondsSinceEpoch}.csv'));
  await file.writeAsString(csv);
  return file.path;
}

Future<String> exportItemsToCsvString(AppDb db) async {
  final rows = await db.getAllItems();
  final fields = [
    ['id', 'name', 'points', 'category', 'stock', 'lastUpdated', 'status']
  ];
  for (final r in rows) {
    fields.add([
      r.id.toString(),
      r.name,
      r.points.toString(),
      r.category ?? '',
      r.stock.toString(),
      r.lastUpdated?.toIso8601String() ?? '',
      r.status ?? ''
    ]);
  }
  final csv = const ListToCsvConverter().convert(fields);
  return csv;
}

// ignore_for_file: prefer_is_empty

Future<int> importItemsFromCsvString(AppDb db, String csv) async {
  final converter = const CsvToListConverter(eol: '\n');
  final list = converter.convert(csv);
  if (list.isEmpty) return 0;
  // assume header present
  final headers = list.first.map((e) => e.toString()).toList();
  final rows = list.sublist(1);
  var inserted = 0; // only count newly created members
  for (final row in rows) {
    final map = <String, String>{};
    for (var i = 0; i < headers.length && i < row.length; i++) {
      map[headers[i]] = row[i]?.toString() ?? '';
    }
  final name = (map['name'] ?? '').trim();
  if (name.isEmpty) continue;
  final points = int.tryParse((map['points'] ?? '').trim()) ?? 0;
  final category = (map['category'] ?? '').trim();
  final stock = int.tryParse((map['stock'] ?? '').trim()) ?? 0;
  final lastUpdated = (map['lastUpdated'] != null && map['lastUpdated']!.trim().isNotEmpty)
    ? DateTime.tryParse(map['lastUpdated']!.trim())
    : null;
  final status = (map['status'] ?? '').trim();

    // Upsert logic: prefer id match, then name match, else insert
    final idStr = map['id'];
    int? id = idStr != null && idStr.isNotEmpty ? int.tryParse(idStr) : null;
    if (id != null) {
      final existing = await db.getItemById(id);
      if (existing != null) {
        final updated = existing.copyWith(
          name: name,
          category: Value(category.isEmpty ? null : category),
          stock: stock,
          lastUpdated: Value(lastUpdated),
          status: Value(status.isEmpty ? null : status),
        );
        await db.updateItemData(updated);
        inserted++;
        continue;
      }
    }

    // Try name match
    final all = await db.getAllItems();
    Item? byName;
    try {
      final target = name.toLowerCase();
      // `r.name` is non-nullable in the table definition, so access directly.
      byName = all.firstWhere((r) => r.name.trim().toLowerCase() == target);
    } catch (e) {
      byName = null;
    }
    if (byName != null) {
      final updated = byName.copyWith(
  points: points,
  category: Value(category),
  stock: stock,
  lastUpdated: Value(lastUpdated),
  status: Value(status),
      );
      await db.updateItemData(updated);
      inserted++;
      
      continue;
    }

    // Insert new
    final companion = ItemsCompanion.insert(
      name: name,
      points: Value(points),
      category: Value(category.isEmpty ? null : category),
      stock: Value(stock),
      lastUpdated: Value(lastUpdated),
      status: Value(status.isEmpty ? null : status),
    );
    await db.insertItem(companion);
    inserted++;
  }
  return inserted;
}


Future<String> exportMembersToCsvFile(AppDb db) async {
  final csv = await exportMembersToCsvString(db);

  final exportDir = Directory(p.join('lib', 'data', 'exports'));
  if (!await exportDir.exists()) await exportDir.create(recursive: true);
  final file = File(p.join(exportDir.path, 'members_export_${DateTime.now().millisecondsSinceEpoch}.csv'));
  await file.writeAsString(csv);
  return file.path;
}

Future<String> exportMembersToCsvString(AppDb db) async {
  final rows = await db.getAllMembers();
  final fields = [
    ['id', 'lastName', 'firstName', 'middleName', 'role', 'contactNo', 'birthday', 'address', 'referrer', 'points', 'qr', 'transactions']
  ];
  for (final r in rows) {
  // Serialize transactions: itemName|quantity|price|points|timestamp;... using sales for this member
  final allSales = await db.getAllSales();
  final sales = allSales.where((s) => s.buyerId == r.id).toList();
    final txParts = <String>[];
    for (final s in sales) {
      final ts = s.timestamp.toIso8601String();
      // Include itemId as the first field so imports can match items reliably.
      // Format (with id): itemId|itemName|quantity|price|points|timestamp
      // Format (without id): itemName|quantity|price|points|timestamp (still supported by parser)
      txParts.add('${s.itemId}|${s.itemName}|${s.quantity}|${s.price}|${s.points}|$ts');
    }
    final txField = txParts.join(';');

    fields.add([
      r.id.toString(),
      r.lastName ?? '',
      r.firstName ?? '',
      r.middleName ?? '',
      r.role ?? '',
      r.contactNo ?? '',
      r.birthday ?? '',
      r.address ?? '',
      r.referrer ?? '',
      r.points.toString(),
      r.qr ?? '',
      txField,
    ]);
  }

  final csv = const ListToCsvConverter().convert(fields);
  return csv;
}

Future<int> importMembersFromCsvString(AppDb db, String csv) async {
  final converter = const CsvToListConverter(eol: '\n');
  final list = converter.convert(csv);
  if (list.isEmpty) return 0;
  final headers = list.first.map((e) => e.toString()).toList();
  final rows = list.sublist(1);
  var inserted = 0;
  for (final row in rows) {
    final map = <String, String>{};
    for (var i = 0; i < headers.length && i < row.length; i++) {
      map[headers[i]] = row[i]?.toString() ?? '';
    }
    final lastName = (map['lastName'] ?? '').trim();
    final firstName = (map['firstName'] ?? '').trim();
    if (lastName.isEmpty && firstName.isEmpty) continue;

    // Upsert: prefer id match, then normalized name match, else insert
    final idStr = (map['id'] ?? '').trim();
    int? id = idStr.isNotEmpty ? int.tryParse(idStr) : null;
    int? memberId;
    if (id != null) {
      final existing = await db.getMemberById(id);
      if (existing != null) {
        final updated = existing.copyWith(
          lastName: Value(lastName.isEmpty ? null : lastName),
          firstName: Value(firstName.isEmpty ? null : firstName),
          middleName: Value((map['middleName'] ?? '').trim().isEmpty ? null : (map['middleName'] ?? '').trim()),
          role: Value((map['role'] ?? '').trim().isEmpty ? null : (map['role'] ?? '').trim()),
          contactNo: Value((map['contactNo'] ?? '').trim().isEmpty ? null : (map['contactNo'] ?? '').trim()),
          birthday: Value((map['birthday'] ?? '').trim().isEmpty ? null : (map['birthday'] ?? '').trim()),
          address: Value((map['address'] ?? '').trim().isEmpty ? null : (map['address'] ?? '').trim()),
          referrer: Value((map['referrer'] ?? '').trim().isEmpty ? null : (map['referrer'] ?? '').trim()),
          points: int.tryParse((map['points'] ?? '').trim()) ?? 0,
        );
        await db.updateMemberData(updated);
        memberId = existing.id;
        // do not count updates as inserted
      }
    }

    final all = await db.getAllMembers();
    Member? byName;
    try {
      final targetLast = lastName.toLowerCase();
      final targetFirst = firstName.toLowerCase();
      byName = all.firstWhere((r) => (r.lastName ?? '').trim().toLowerCase() == targetLast && (r.firstName ?? '').trim().toLowerCase() == targetFirst);
    } catch (e) {
      byName = null;
    }
    if (byName != null) {
      final updated = byName.copyWith(
        middleName: Value((map['middleName'] ?? '').trim().isEmpty ? null : (map['middleName'] ?? '').trim()),
        role: Value((map['role'] ?? '').trim().isEmpty ? null : (map['role'] ?? '').trim()),
        contactNo: Value((map['contactNo'] ?? '').trim().isEmpty ? null : (map['contactNo'] ?? '').trim()),
        birthday: Value((map['birthday'] ?? '').trim().isEmpty ? null : (map['birthday'] ?? '').trim()),
        address: Value((map['address'] ?? '').trim().isEmpty ? null : (map['address'] ?? '').trim()),
        referrer: Value((map['referrer'] ?? '').trim().isEmpty ? null : (map['referrer'] ?? '').trim()),
        points: int.tryParse((map['points'] ?? '').trim()) ?? 0,
      );
      await db.updateMemberData(updated);
      memberId = byName.id;
      // do not count updates as inserted
      continue;
    }

    final companion = MembersCompanion.insert(
      lastName: Value(lastName.isEmpty ? null : lastName),
      firstName: Value(firstName.isEmpty ? null : firstName),
      middleName: Value((map['middleName'] ?? '').trim().isEmpty ? null : (map['middleName'] ?? '').trim()),
      role: Value((map['role'] ?? '').trim().isEmpty ? null : (map['role'] ?? '').trim()),
      contactNo: Value((map['contactNo'] ?? '').trim().isEmpty ? null : (map['contactNo'] ?? '').trim()),
      birthday: Value((map['birthday'] ?? '').trim().isEmpty ? null : (map['birthday'] ?? '').trim()),
      address: Value((map['address'] ?? '').trim().isEmpty ? null : (map['address'] ?? '').trim()),
      referrer: Value((map['referrer'] ?? '').trim().isEmpty ? null : (map['referrer'] ?? '').trim()),
      points: Value(int.tryParse((map['points'] ?? '').trim()) ?? 0),
      qr: Value((map['qr'] ?? '').trim().isEmpty ? _generateMemberQrToken() : (map['qr'] ?? '').trim()),
    );
    final createdId = await db.insertMember(companion);
    memberId = createdId;
    inserted++;
    
    // If the imported row includes a referrer, attempt to award 15 points to that referrer
    final refRaw = (map['referrer'] ?? '').trim();
    if (refRaw.isNotEmpty) {
      try {
        Member? refMember;
        final parsed = int.tryParse(refRaw);
        if (parsed != null) {
          if (parsed != memberId) refMember = await db.getMemberById(parsed);
        } else {
          final allMembers = await db.getAllMembers();
          try {
            final target = refRaw.toLowerCase();
            refMember = allMembers.firstWhere((m) {
              final name = ('${m.firstName ?? ''} ${m.lastName ?? ''}').trim().toLowerCase();
              return name == target;
            });
            if (refMember.id == memberId) refMember = null;
          } catch (_) {
            refMember = null;
          }
        }
        if (refMember != null) {
          final updated = refMember.copyWith(points: refMember.points + 15);
          await db.update(db.members).replace(updated);
        }
      } catch (_) {
        // ignore failures here
      }
    }
    
    // If there are parsed transactions in the CSV, insert them as sales and update stock/points
    final txRaw = (map['transactions'] ?? '').trim();
    if (txRaw.isNotEmpty) {
      final parsedTx = parseMemberTransactionsColumn(txRaw);
      if (parsedTx.isNotEmpty) {
        // load current items and sales to make decisions
        final allItems = await db.getAllItems();
        final existingSales = await db.getAllSales();
        int totalPointsForMember = 0;
        final now = DateTime.now();
        for (final e in parsedTx) {
          final itemName = e['itemName'] as String? ?? '';
          final quantity = e['quantity'] as int? ?? 0;
          final price = e['price'] as int? ?? 0;
          // points from CSV is ignored in favor of item.points * quantity (computedPoints)
          final ts = e['timestamp'] as DateTime? ?? now;
          if (itemName.isEmpty) continue;
          // find item by exact name match
          Item? item;
          try {
            item = allItems.firstWhere((it) => it.name.trim().toLowerCase() == itemName.trim().toLowerCase());
          } catch (_) {
            item = null;
          }
          if (item == null) continue; // skip unknown items

          // Avoid duplicate sales: check existing by core fields
          final iid = item.id;
          final duplicate = existingSales.any((s) {
            return s.buyerId == memberId && s.itemId == iid && s.itemName == itemName && s.quantity == quantity && s.price == price && s.timestamp.toIso8601String() == ts.toIso8601String();
          });
          if (duplicate) continue;

          final computedPoints = (item.points * quantity).toInt();
          final saleComp = SalesCompanion.insert(
            itemId: item.id,
            buyerId: Value(memberId),
            itemName: itemName,
            quantity: quantity,
            price: Value(price),
            points: Value(computedPoints),
            timestamp: Value(ts),
          );
          await db.insertSale(saleComp);

          // decrement stock and update item
          final updatedItem = item.copyWith(stock: item.stock - quantity, lastUpdated: Value(ts));
          await db.update(db.items).replace(updatedItem);

          totalPointsForMember += computedPoints;
        }
        // award computed points to member
        if (totalPointsForMember > 0) {
          final m = await db.getMemberById(memberId);
          if (m != null) {
            final updatedM = m.copyWith(points: m.points + totalPointsForMember);
            await db.update(db.members).replace(updatedM);
          }
        }
      }
    }
  }
  return inserted;
}

/// Parse the `transactions` column for a single member CSV row and return a list
/// of simple parsed maps (itemName, quantity, price, points, timestamp).
List<Map<String, dynamic>> parseMemberTransactionsColumn(String txRaw) {
  final List<Map<String, dynamic>> entries = [];
  if (txRaw.trim().isEmpty) return entries;
  final txs = txRaw.split(';');
  for (final e in txs) {
    final parts = e.split('|');
    if (parts.isEmpty) continue;
    int? itemId;
    String itemName = '';
    int quantity = 0;
    int price = 0;
    int points = 0;
    DateTime? ts;

    // Support two formats:
    // With item id: itemId|itemName|quantity|price|points|timestamp
    // Without id: itemName|quantity|price|points|timestamp
    if (parts.length >= 6) {
      // assume first is itemId
      itemId = int.tryParse(parts[0].trim());
      itemName = parts[1].trim();
      quantity = parts.length > 2 ? int.tryParse(parts[2].trim()) ?? 0 : 0;
      price = parts.length > 3 ? int.tryParse(parts[3].trim()) ?? 0 : 0;
      points = parts.length > 4 ? int.tryParse(parts[4].trim()) ?? 0 : 0;
      if (parts.length > 5) ts = DateTime.tryParse(parts[5].trim());
    } else {
      itemName = parts.length > 0 ? parts[0].trim() : '';
      quantity = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
      price = parts.length > 2 ? int.tryParse(parts[2].trim()) ?? 0 : 0;
      points = parts.length > 3 ? int.tryParse(parts[3].trim()) ?? 0 : 0;
      if (parts.length > 4) ts = DateTime.tryParse(parts[4].trim());
    }

    if (itemName.isEmpty && itemId == null) continue;
    entries.add({'itemId': itemId, 'itemName': itemName, 'quantity': quantity, 'price': price, 'points': points, 'timestamp': ts});
  }
  return entries;
}

Future<String> exportSalesToCsvFile(AppDb db) async {
  final csv = await exportSalesToCsvString(db);

  final exportDir = Directory(p.join('lib', 'data', 'exports'));
  if (!await exportDir.exists()) await exportDir.create(recursive: true);
  final file = File(p.join(exportDir.path, 'sales_export_${DateTime.now().millisecondsSinceEpoch}.csv'));
  await file.writeAsString(csv);
  return file.path;
}

Future<String> exportSalesToCsvString(AppDb db) async {
  final rows = await db.getAllSales();
  // Include buyerId in exports so sales can be associated with the buyer on import.
  final fields = [
    ['id', 'itemId', 'buyerId', 'itemName', 'quantity', 'price', 'points', 'createdAt']
  ];
  for (final r in rows) {
    fields.add([
      r.id.toString(),
      r.itemId.toString(),
      (r.buyerId ?? '').toString(),
      r.itemName,
      r.quantity.toString(),
      r.price.toString(),
      r.points.toString(),
      r.timestamp.toIso8601String(),
    ]);
  }
  return const ListToCsvConverter().convert(fields);
}

Future<int> importSalesFromCsvString(AppDb db, String csv) async {
  final converter = const CsvToListConverter(eol: '\n');
  final list = converter.convert(csv);
  if (list.isEmpty) return 0;
  final headers = list.first.map((e) => e.toString()).toList();
  final rows = list.sublist(1);
  var inserted = 0;
  int maxImportedId = 0;
  for (final row in rows) {
    final map = <String, String>{};
    for (var i = 0; i < headers.length && i < row.length; i++) {
      map[headers[i]] = row[i]?.toString() ?? '';
    }
    final id = int.tryParse(map['id'] ?? '');
    final itemId = int.tryParse(map['itemId'] ?? '') ?? 0;
    final buyerId = int.tryParse(map['buyerId'] ?? '') ;
    final itemName = map['itemName'] ?? '';
    final quantity = int.tryParse(map['quantity'] ?? '') ?? 0;
    final price = int.tryParse(map['price'] ?? '') ?? 0;
  final points = int.tryParse(map['points'] ?? '') ?? 0;

    if (itemName.isEmpty) continue;

    // parse timestamp if provided (supports header 'createdAt' or 'timestamp')
    DateTime? ts;
    final tsStr = (map['createdAt'] ?? map['timestamp'])?.trim();
    if (tsStr != null && tsStr.isNotEmpty) {
      ts = DateTime.tryParse(tsStr);
    }

    // If an explicit id is provided, prefer inserting with that id (preserve ids).
    if (id != null) {
      // Skip if a sale with this id already exists
      final existingById = await db.getSaleById(id);
      if (existingById != null) continue;

      // Avoid duplicate semantic rows even if id differs: check existing by core fields
      final existing = await db.getAllSales();
      bool alreadyExists = existing.any((s) {
        final sameCore = s.itemId == itemId && s.itemName == itemName && s.quantity == quantity && s.price == price && (buyerId == null ? (s.buyerId == null) : s.buyerId == buyerId);
        if (!sameCore) return false;
        if (ts != null) {
          return s.timestamp.toIso8601String() == ts.toIso8601String();
        }
        return true;
      });
      if (alreadyExists) continue;

      try {
        // Use NULLIF(?, -1) so we can pass -1 to indicate NULL for buyer_id
        await db.customInsert(
          'INSERT INTO sales (id, item_id, buyer_id, item_name, quantity, price, points, timestamp) VALUES (?,?,NULLIF(?, -1),?,?,?,?,?)',
          variables: [
            Variable.withInt(id),
            Variable.withInt(itemId),
            Variable.withInt(buyerId ?? -1),
            Variable.withString(itemName),
            Variable.withInt(quantity),
            Variable.withInt(price),
            Variable.withInt(points),
            Variable.withString((ts ?? DateTime.now()).toIso8601String()),
          ],
        );
        if (id > maxImportedId) maxImportedId = id;
        inserted++;
      } catch (_) {
        // ignore insertion failures for explicit ids
        continue;
      }
    } else {
      // No explicit id provided — fallback to semantic duplicate detection and normal insert
      final existing = await db.getAllSales();
      bool alreadyExists = existing.any((s) {
        final sameCore = s.itemId == itemId && s.itemName == itemName && s.quantity == quantity && s.price == price && (buyerId == null ? (s.buyerId == null) : s.buyerId == buyerId);
        if (!sameCore) return false;
        if (ts != null) {
          return s.timestamp.toIso8601String() == ts.toIso8601String();
        }
        return true;
      });
      if (alreadyExists) continue;

      final companion = SalesCompanion(
        itemId: Value(itemId),
        buyerId: buyerId != null ? Value(buyerId) : const Value.absent(),
        itemName: Value(itemName),
        quantity: Value(quantity),
        price: Value(price),
        points: Value(points),
        timestamp: ts != null ? Value(ts) : const Value.absent(),
      );
      await db.insertSale(companion);
      inserted++;
    }
  }
  // If we imported explicit ids, ensure sqlite_sequence for sales at least matches the max id
  if (maxImportedId > 0) {
    try {
      await db.customStatement("UPDATE sqlite_sequence SET seq = (SELECT MAX(id) FROM sales) WHERE name='sales';");
    } catch (_) {
      // ignore if sqlite_sequence update fails
    }
  }
  return inserted;
}
