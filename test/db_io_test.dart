import 'package:flutter_test/flutter_test.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/data/db_init.dart';
import 'package:lzcas/main.dart' as app_main;

void main() {
  test('export/import items csv roundtrip', () async {
    // Ensure repository is initialized (same as app startup)
    try {
      // Accessing will throw if not initialized
      final _ = app_main.repository;
    } catch (_) {
      final db = await initDb();
      app_main.repository = DbRepository(db);
    }
    final csv = await app_main.repository.exportItemsCsvString();
    expect(csv, isNotNull);

    // Add a dummy row via CSV import
    final now = DateTime.now().toIso8601String();
    final sample = 'id,name,category,stock,lastUpdated,status\n,Test Product,TestCat,42,$now,Good\n';
  await app_main.repository.importItemsCsv(sample);

  // Query for the imported product by name
  final items = await app_main.repository.fetchItems();
  final found = items.any((i) => i.name == 'Test Product');
  expect(found, isTrue);
  });

  test('export/import members csv roundtrip', () async {
    // Ensure repository initialized
    try {
      final _ = app_main.repository;
    } catch (_) {
      final db = await initDb();
      app_main.repository = DbRepository(db);
    }
    final csv = await app_main.repository.exportMembersCsvString();
    expect(csv, isNotNull);

  final sample = 'id,lastName,firstName,middleName,role,contactNo,birthday,address,referrer,points\n,Smith,John,,Member,1234567890,1990-01-01,Somewhere,,10\n';
    await app_main.repository.importMembersCsv(sample);
    final members = await app_main.repository.fetchMembers();
    final foundMember = members.any((m) => (m.firstName ?? '') == 'John' && (m.lastName ?? '') == 'Smith');
    expect(foundMember, isTrue);
  });
}
