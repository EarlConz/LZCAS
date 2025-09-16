// Minimal seed data and helper mappers used by UI components.
import 'package:lzcas/db/app_db.dart' show Item, Member;

final List<Map<String, dynamic>> inventoryItemsSeed = [
  // keep this small; developers can modify
  {
    'name': 'Sample Item A',
    'category': 'General',
    'stock': 100,
    'status': 'Good',
  },
  {
    'name': 'Sample Item B',
    'category': 'General',
    'stock': 10,
    'status': 'Low Stock',
  },
];

final List<Map<String, dynamic>> membersdataSeed = [
  {
    'firstName': 'John',
    'lastName': 'Doe',
    'role': 'Customer',
    'points': 0,
  }
];

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
