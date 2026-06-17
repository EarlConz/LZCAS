// moved from lib/data/app_db.dart

import 'package:drift/drift.dart';

part 'app_db.g.dart';

class Items extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get points => integer().withDefault(const Constant(0))();
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
  // New nullable integer foreign key to store the member id of the referrer.
  IntColumn get referrerId => integer().nullable()();
  IntColumn get points => integer().withDefault(const Constant(0))();
  TextColumn get qr => text().nullable()();
  // Verified reseller fields
  TextColumn get idType => text().nullable()();
  TextColumn get idNumber => text().nullable()();
  TextColumn get idImagePath => text().nullable()();
}

class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get itemId => integer()();
  IntColumn get buyerId => integer().nullable()();
  TextColumn get itemName => text()();
  IntColumn get quantity => integer()();
  IntColumn get points => integer().withDefault(const Constant(0))();
  IntColumn get price => integer().withDefault(const Constant(0))();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Items, Members, Sales])
class AppDb extends _$AppDb {
  AppDb(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    // When opening an existing DB with an older schema, apply safe ALTERs
    // to add newly introduced columns while preserving existing data.
    onUpgrade: (Migrator m, int from, int to) async {
      // Only run simple ALTER statements for the small, additive changes
      // we made (items.points, sales.points, members.referrer_id).
      if (from < 2) {
        try {
          await m.database.customStatement(
            'ALTER TABLE items ADD COLUMN points INTEGER DEFAULT 0',
          );
        } catch (e) {
          // ignore if column already exists or SQLite reports an error
        }
        try {
          await m.database.customStatement(
            'ALTER TABLE sales ADD COLUMN points INTEGER DEFAULT 0',
          );
        } catch (e) {
          // ignore
        }
        try {
          await m.database.customStatement(
            'ALTER TABLE members ADD COLUMN referrer_id INTEGER',
          );
        } catch (e) {
          // ignore
        }
        try {
          await m.database.customStatement(
            'ALTER TABLE members ADD COLUMN points INTEGER DEFAULT 0',
          );
        } catch (e) {
          // ignore
        }
      }
      // If upgrading from schema < 3, add buyerId to sales
      if (from < 3) {
        try {
          await m.database.customStatement(
            'ALTER TABLE sales ADD COLUMN buyer_id INTEGER',
          );
        } catch (e) {
          // ignore
        }
      }
      // If upgrading from schema < 4, add verified reseller ID columns
      if (from < 4) {
        try {
          await m.database.customStatement(
            'ALTER TABLE members ADD COLUMN id_type TEXT',
          );
        } catch (e) {
          // ignore
        }
        try {
          await m.database.customStatement(
            'ALTER TABLE members ADD COLUMN id_number TEXT',
          );
        } catch (e) {
          // ignore
        }
        try {
          await m.database.customStatement(
            'ALTER TABLE members ADD COLUMN id_image_path TEXT',
          );
        } catch (e) {
          // ignore
        }
      }
    },
  );

  // Items CRUD
  Future<int> insertItem(ItemsCompanion entry) => into(items).insert(entry);
  Future<List<Item>> getAllItems() => select(items).get();
  Future<Item?> getItemById(int id) =>
      (select(items)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<bool> updateItemData(Item item) => update(items).replace(item);
  Future<int> deleteItemById(int id) =>
      (delete(items)..where((t) => t.id.equals(id))).go();

  // Members CRUD
  Future<int> insertMember(MembersCompanion entry) =>
      into(members).insert(entry);
  Future<List<Member>> getAllMembers() => select(members).get();
  Future<Member?> getMemberById(int id) =>
      (select(members)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<bool> updateMemberData(Member member) =>
      update(members).replace(member);
  Future<int> deleteMemberById(int id) =>
      (delete(members)..where((t) => t.id.equals(id))).go();

  // Sales CRUD
  Future<int> insertSale(SalesCompanion entry) => into(sales).insert(entry);
  Future<List<Sale>> getAllSales() => select(sales).get();
  Future<List<Sale>> getSalesBetween(DateTime start, DateTime end) {
    return (select(
      sales,
    )..where((s) => s.timestamp.isBetweenValues(start, end))).get();
  }

  // Helper to get single sale by id
  Future<Sale?> getSaleById(int id) =>
      (select(sales)..where((t) => t.id.equals(id))).getSingleOrNull();
}

// This file is intentionally empty.
// The canonical Drift database implementation and generated part live in lib/data/app_db.dart and lib/data/app_db.g.dart.
// Keep this placeholder so code can import from `lib/db/db.dart` without accidentally pulling duplicate table definitions.
