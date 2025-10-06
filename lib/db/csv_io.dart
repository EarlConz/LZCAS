import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' show Value;
import 'app_db.dart';

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
  var inserted = 0;
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
    ['id', 'lastName', 'firstName', 'middleName', 'role', 'contactNo', 'birthday', 'address', 'referrer', 'points']
  ];
  for (final r in rows) {
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
        inserted++;
        continue;
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
      inserted++;
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
    );
    await db.insertMember(companion);
    inserted++;
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
    final itemName = parts.length > 0 ? parts[0].trim() : '';
    final quantity = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
    final price = parts.length > 2 ? int.tryParse(parts[2].trim()) ?? 0 : 0;
    final points = parts.length > 3 ? int.tryParse(parts[3].trim()) ?? 0 : 0;
    DateTime? ts;
    if (parts.length > 4) ts = DateTime.tryParse(parts[4].trim());
    if (itemName.isEmpty) continue;
    entries.add({'itemName': itemName, 'quantity': quantity, 'price': price, 'points': points, 'timestamp': ts});
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
  final fields = [
    ['id', 'itemId', 'itemName', 'quantity', 'price', 'points', 'createdAt']
  ];
  for (final r in rows) {
    fields.add([
      r.id.toString(),
      r.itemId.toString(),
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
  for (final row in rows) {
    final map = <String, String>{};
    for (var i = 0; i < headers.length && i < row.length; i++) {
      map[headers[i]] = row[i]?.toString() ?? '';
    }

    final itemId = int.tryParse(map['itemId'] ?? '') ?? 0;
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

    // Avoid duplicates: if an identical sale already exists (match by itemId/itemName/quantity/price
    // and timestamp when available), skip inserting.
    final existing = await db.getAllSales();
    bool alreadyExists = existing.any((s) {
      final sameCore = s.itemId == itemId && s.itemName == itemName && s.quantity == quantity && s.price == price;
      if (!sameCore) return false;
      if (ts != null) {
        // require exact timestamp match when provided in CSV
        return s.timestamp.toIso8601String() == ts.toIso8601String();
      }
      // no timestamp provided — treat matching core fields as duplicate
      return true;
    });
    if (alreadyExists) continue;

    final companion = SalesCompanion(
      itemId: Value(itemId),
      itemName: Value(itemName),
      quantity: Value(quantity),
      price: Value(price),
      points: Value(points),
      timestamp: ts != null ? Value(ts) : const Value.absent(),
    );
    await db.insertSale(companion);
    inserted++;
  }
  return inserted;
}
