// Helper mappers and utilities used by UI components.
// NOTE: in-memory seed lists were removed. Use CSV import helpers on the repository
// (e.g. `repository.importItemsCsv(...)`) or an external seed script if initial data is needed.
import 'package:lzcas/db/app_db.dart' show Item, Member;

// Seed lists removed: this module now only exposes helper mappers and utilities.

List<Map<String, dynamic>> inventoryItemsFromRows(List<Item> rows) {
  return rows.map((r) => {
        'id': r.id,
        'name': r.name,
        'category': r.category ?? '',
        'stock': r.stock,
        'lastUpdated': r.lastUpdated?.toString() ?? '',
        'status': r.status ?? statusFromStock(r.stock),
      }).toList();
}

List<Map<String, dynamic>> membersFromRows(List<Member> rows) {
  return rows.map((m) => {
        'id': m.id,
        'firstName': m.firstName ?? '',
        'lastName': m.lastName ?? '',
        'middleName': m.middleName ?? '',
        'role': m.role ?? '',
        'contactNo': m.contactNo ?? '',
        'birthday': m.birthday ?? '',
        'address': m.address ?? '',
        'referrer': m.referrer ?? '',
        'points': m.points,
        'qr': m.qr ?? '',
      }).toList();
}

String statusFromStock(int stock) {
  if (stock <= 0) return 'Out of Stock';
  if (stock < 50) return 'Low Stock';
  return 'Good';
}
