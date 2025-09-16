// lib/db/db_repository.dart (moved from lib/data)

import 'package:drift/drift.dart';
import 'app_db.dart';
import 'csv_io.dart';
import 'dart:async';

class DbRepository {
  final AppDb db;
  // A simple broadcast stream to notify listeners about changes (items/sales).
  final StreamController<String> _changes = StreamController<String>.broadcast();

  DbRepository(this.db);

  Stream<String> get changes => _changes.stream;

  // Items helpers
  Future<List<Item>> fetchItems() => db.getAllItems();
  
  // Update an item record and emit a change notification.
  Future<bool> updateItem(Item item) async {
    final res = await db.updateItemData(item);
    _changes.add('item_updated');
    return res;
  }
  Future<int> addItem({required String name, String? category, int stock = 0, DateTime? lastUpdated, String? status}) {
    final companion = ItemsCompanion.insert(
      name: name,
      category: Value(category),
      stock: Value(stock),
      lastUpdated: Value(lastUpdated),
      status: Value(status),
    );
  final future = db.insertItem(companion);
  future.then((_) => _changes.add('item_added'));
  return future;
  }

  /// Delete an item by id and notify listeners.
  Future<int> deleteItemById(int id) async {
    final res = await db.deleteItemById(id);
    _changes.add('item_deleted');
    return res;
  }

  /// Export items to CSV file under lib/data/exports and return the file path.
  Future<String> exportItemsCsv() => exportItemsToCsvFile(db);

  /// Return CSV content for items as string (UI can show a save dialog).
  Future<String> exportItemsCsvString() => exportItemsToCsvString(db);

  /// Import items from a CSV string; returns number of rows inserted.
  Future<int> importItemsCsv(String csv) async {
    final count = await importItemsFromCsvString(db, csv);
    if (count > 0) _changes.add('item_imported');
    return count;
  }

  Future<void> seedItemsFromList(List<Map<String, dynamic>> list) async {
    final existing = await db.getAllItems();
    if (existing.isNotEmpty) return; // already seeded
    for (final m in list) {
      await addItem(
        name: m['name']?.toString() ?? '',
        category: m['category']?.toString(),
        stock: (m['stock'] ?? 0) is int ? m['stock'] : int.tryParse(m['stock']?.toString() ?? '0') ?? 0,
        lastUpdated: null,
        status: m['status']?.toString(),
      );
    }
  }

  // Members helpers
  Future<List<Member>> fetchMembers() => db.getAllMembers();
  Future<int> addMember({String? lastName, String? firstName, String? middleName, String? role, String? contactNo, String? birthday, String? address, String? referrer, int points = 0, String? qr}) {
    final companion = MembersCompanion.insert(
      lastName: Value(lastName),
      firstName: Value(firstName),
      middleName: Value(middleName),
      role: Value(role),
      contactNo: Value(contactNo),
      birthday: Value(birthday),
      address: Value(address),
      referrer: Value(referrer),
      points: Value(points),
      qr: Value(qr),
    );
  final future = db.insertMember(companion);
  future.then((_) => _changes.add('member_added'));
  return future;
  }

  /// Export members to CSV file and return path.
  Future<String> exportMembersCsv() => exportMembersToCsvFile(db);

  /// Return CSV content for members as string (UI can show a save dialog).
  Future<String> exportMembersCsvString() => exportMembersToCsvString(db);

  /// Import members from CSV string, return inserted count.
  Future<int> importMembersCsv(String csv) async {
    final count = await importMembersFromCsvString(db, csv);
    if (count > 0) _changes.add('member_imported');
    return count;
  }

  Future<void> seedMembersFromList(List<Map<String, dynamic>> list) async {
    final existing = await db.getAllMembers();
    if (existing.isNotEmpty) return;
    for (final m in list) {
      await addMember(
        lastName: m['lastName']?.toString(),
        firstName: m['firstName']?.toString(),
        middleName: m['middleName']?.toString(),
        role: m['role']?.toString(),
        contactNo: m['contactNo']?.toString(),
        birthday: m['birthday']?.toString(),
        address: m['address']?.toString(),
        referrer: m['referrer']?.toString(),
        points: (m['points'] ?? 0) is int ? m['points'] : int.tryParse(m['points']?.toString() ?? '0') ?? 0,
        qr: m['qr']?.toString(),
      );
    }
  }

  // Sales helpers
  Future<int> addSale({required int itemId, required String itemName, required int quantity, int price = 0}) {
    final companion = SalesCompanion.insert(
      itemId: itemId,
      itemName: itemName,
      quantity: quantity,
      price: Value(price),
    );
  final id = db.insertSale(companion);
  // notify listeners that a sale was added
  _changes.add('sale_added');
  return id;
  }

  Future<List<Sale>> fetchSales() => db.getAllSales();

  Future<List<Sale>> fetchSalesBetween(DateTime start, DateTime end) => db.getSalesBetween(start, end);
}
