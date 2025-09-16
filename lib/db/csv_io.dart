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
    ['id', 'name', 'category', 'stock', 'lastUpdated', 'status']
  ];
  for (final r in rows) {
    fields.add([
      r.id.toString(),
      r.name,
      r.category ?? '',
      r.stock.toString(),
      r.lastUpdated?.toIso8601String() ?? '',
      r.status ?? ''
    ]);
  }
  final csv = const ListToCsvConverter().convert(fields);
  return csv;
}

Future<int> importItemsFromCsvString(AppDb db, String csv) async {
  final converter = const CsvToListConverter();
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
    final name = map['name'] ?? '';
    if (name.isEmpty) continue;
    final category = map['category'];
    final stock = int.tryParse(map['stock'] ?? '') ?? 0;
    final lastUpdated = (map['lastUpdated'] != null && map['lastUpdated']!.isNotEmpty)
        ? DateTime.tryParse(map['lastUpdated']!)
        : null;
    final status = map['status'];

    // Upsert logic: prefer id match, then name match, else insert
    final idStr = map['id'];
    int? id = idStr != null && idStr.isNotEmpty ? int.tryParse(idStr) : null;
    if (id != null) {
      final existing = await db.getItemById(id);
      if (existing != null) {
        final updated = existing.copyWith(
          name: name,
          category: Value(category),
          stock: stock,
          lastUpdated: Value(lastUpdated),
          status: Value(status),
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
      byName = all.firstWhere((r) => r.name == name);
    } catch (e) {
      byName = null;
    }
    if (byName != null) {
      final updated = byName.copyWith(
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
      category: Value(category),
      stock: Value(stock),
      lastUpdated: Value(lastUpdated),
      status: Value(status),
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
    ['id', 'lastName', 'firstName', 'middleName', 'role', 'contactNo', 'birthday', 'address', 'referrer', 'points', 'qr']
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
      r.qr ?? ''
    ]);
  }

  final csv = const ListToCsvConverter().convert(fields);
  return csv;
}

Future<int> importMembersFromCsvString(AppDb db, String csv) async {
  final converter = const CsvToListConverter();
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
    final lastName = map['lastName'] ?? '';
    final firstName = map['firstName'] ?? '';
    if (lastName.isEmpty && firstName.isEmpty) continue;
    // Upsert: prefer id match, then name match, else insert
    final idStr = map['id'];
    int? id = idStr != null && idStr.isNotEmpty ? int.tryParse(idStr) : null;
    if (id != null) {
      final existing = await db.getMemberById(id);
      if (existing != null) {
        final updated = existing.copyWith(
          lastName: Value(lastName.isEmpty ? null : lastName),
          firstName: Value(firstName.isEmpty ? null : firstName),
          middleName: Value(map['middleName']),
          role: Value(map['role']),
          contactNo: Value(map['contactNo']),
          birthday: Value(map['birthday']),
          address: Value(map['address']),
          referrer: Value(map['referrer']),
          points: int.tryParse(map['points'] ?? '') ?? 0,
          qr: Value(map['qr']),
        );
        await db.updateMemberData(updated);
        inserted++;
        continue;
      }
    }

    final all = await db.getAllMembers();
    Member? byName;
    try {
      byName = all.firstWhere((r) => (r.lastName ?? '') == lastName && (r.firstName ?? '') == firstName);
    } catch (e) {
      byName = null;
    }
    if (byName != null) {
      final updated = byName.copyWith(
  middleName: Value(map['middleName']),
  role: Value(map['role']),
  contactNo: Value(map['contactNo']),
  birthday: Value(map['birthday']),
  address: Value(map['address']),
  referrer: Value(map['referrer']),
  points: int.tryParse(map['points'] ?? '') ?? 0,
  qr: Value(map['qr']),
      );
      await db.updateMemberData(updated);
      inserted++;
      continue;
    }

    final companion = MembersCompanion.insert(
      lastName: Value(lastName.isEmpty ? null : lastName),
      firstName: Value(firstName.isEmpty ? null : firstName),
      middleName: Value(map['middleName']),
      role: Value(map['role']),
      contactNo: Value(map['contactNo']),
      birthday: Value(map['birthday']),
      address: Value(map['address']),
      referrer: Value(map['referrer']),
      points: Value(int.tryParse(map['points'] ?? '') ?? 0),
      qr: Value(map['qr']),
    );
    await db.insertMember(companion);
    inserted++;
  }
  return inserted;
}
