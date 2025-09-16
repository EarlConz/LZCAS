// moved from lib/data/app_db.dart

import 'package:drift/drift.dart';

part 'app_db.g.dart';

class Items extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get category => text().nullable()();
  IntColumn get stock => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUpdated => dateTime().nullable()();
  TextColumn get status => text().nullable()();
}

class Members extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get lastName => text().nullable()();
  TextColumn get firstName => text().nullable()();
  TextColumn get middleName => text().nullable()();
  TextColumn get role => text().nullable()();
  TextColumn get contactNo => text().nullable()();
  TextColumn get birthday => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get referrer => text().nullable()();
  IntColumn get points => integer().withDefault(const Constant(0))();
  TextColumn get qr => text().nullable()();
}

class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get itemId => integer()();
  TextColumn get itemName => text()();
  IntColumn get quantity => integer()();
  IntColumn get price => integer().withDefault(const Constant(0))();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Items, Members, Sales])
class AppDb extends _$AppDb {
  AppDb(super.e);

  @override
  int get schemaVersion => 1;

  // Items CRUD
  Future<int> insertItem(ItemsCompanion entry) => into(items).insert(entry);
  Future<List<Item>> getAllItems() => select(items).get();
  Future<Item?> getItemById(int id) => (select(items)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<bool> updateItemData(Item item) => update(items).replace(item);
  Future<int> deleteItemById(int id) => (delete(items)..where((t) => t.id.equals(id))).go();

  // Members CRUD
  Future<int> insertMember(MembersCompanion entry) => into(members).insert(entry);
  Future<List<Member>> getAllMembers() => select(members).get();
  Future<Member?> getMemberById(int id) => (select(members)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<bool> updateMemberData(Member member) => update(members).replace(member);
  Future<int> deleteMemberById(int id) => (delete(members)..where((t) => t.id.equals(id))).go();

  // Sales CRUD
  Future<int> insertSale(SalesCompanion entry) => into(sales).insert(entry);
  Future<List<Sale>> getAllSales() => select(sales).get();
  Future<List<Sale>> getSalesBetween(DateTime start, DateTime end) {
    return (select(sales)..where((s) => s.timestamp.isBetweenValues(start, end))).get();
  }
}
// This file is intentionally empty.
// The canonical Drift database implementation and generated part live in lib/data/app_db.dart and lib/data/app_db.g.dart.
// Keep this placeholder so code can import from `lib/db/db.dart` without accidentally pulling duplicate table definitions.
