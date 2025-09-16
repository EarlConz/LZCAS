import 'package:flutter_test/flutter_test.dart';
import 'package:lzcas/db/db.dart';

void main() {
  test('export/import items csv roundtrip', () async {
    final csv = await repository.exportItemsCsvString();
    expect(csv, isNotNull);

    // Add a dummy row via CSV import
    final now = DateTime.now().toIso8601String();
    final sample = 'id,name,category,stock,lastUpdated,status\n,Test Product,TestCat,42,$now,Good\n';
    final count = await repository.importItemsCsv(sample);
    // count should be >= 1
    expect(count, greaterThanOrEqualTo(1));

    // Export again and ensure the new name appears
    final csv2 = await repository.exportItemsCsvString();
    expect(csv2.contains('Test Product'), isTrue);
  });

  test('export/import members csv roundtrip', () async {
    final csv = await repository.exportMembersCsvString();
    expect(csv, isNotNull);

    final sample = 'id,lastName,firstName,middleName,role,contactNo,birthday,address,referrer,points,qr\n,Smith,John,,Member,1234567890,1990-01-01,Somewhere,,10,QR123\n';
    final count = await repository.importMembersCsv(sample);
    expect(count, greaterThanOrEqualTo(1));

    final csv2 = await repository.exportMembersCsvString();
    expect(csv2.contains('John'), isTrue);
  });
}
