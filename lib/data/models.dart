// lib/data/models.dart
// Pure Dart model classes for the cloud-based LZCAS (Stockpile) app.
// All models use snake_case JSON keys matching Supabase column names.

/// Inventory item in the system.
class Item {
  final int? id;
  final String name;
  final String? category;
  final int stock;
  final DateTime? lastUpdated;
  final String? status;
  final String? userId; // Supabase auth.uid()

  const Item({
    this.id,
    required this.name,
    this.category,
    this.stock = 0,
    this.lastUpdated,
    this.status,
    this.userId,
  });

  factory Item.fromJson(Map<String, dynamic> json) => Item(
    id: json['id'] as int?,
    name: json['name'] as String? ?? '',
    category: json['category'] as String?,
    stock: json['stock'] as int? ?? 0,
    lastUpdated: json['last_updated'] != null
        ? DateTime.tryParse(json['last_updated'].toString())
        : null,
    status: json['status'] as String?,
    userId: json['user_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    if (category != null) 'category': category,
    'stock': stock,
    if (lastUpdated != null) 'last_updated': lastUpdated!.toIso8601String(),
    if (status != null) 'status': status,
    if (userId != null) 'user_id': userId,
  };

  Item copyWith({
    int? id,
    String? name,
    String? category,
    int? stock,
    DateTime? lastUpdated,
    String? status,
    String? userId,
  }) => Item(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    stock: stock ?? this.stock,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    status: status ?? this.status,
    userId: userId ?? this.userId,
  );
}

/// A member (customer / reseller / supplier) in the system.
class Member {
  final int? id;
  final String? lastName;
  final String? firstName;
  final String? middleName;
  final String? role;
  final String? contactNo;
  final String? birthday;
  final String? address;
  final String? referrer;
  final int? referrerId;
  final String? qr;
  final String? idType;
  final String? idNumber;
  final String? idImagePath;
  final int level;
  final String? userId;

  const Member({
    this.id,
    this.lastName,
    this.firstName,
    this.middleName,
    this.role,
    this.contactNo,
    this.birthday,
    this.address,
    this.referrer,
    this.referrerId,
    this.qr,
    this.idType,
    this.idNumber,
    this.idImagePath,
    this.level = 1,
    this.userId,
  });

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: json['id'] as int?,
    lastName: json['last_name'] as String?,
    firstName: json['first_name'] as String?,
    middleName: json['middle_name'] as String?,
    role: json['role'] as String?,
    contactNo: json['contact_no'] as String?,
    birthday: json['birthday'] as String?,
    address: json['address'] as String?,
    referrer: json['referrer'] as String?,
    referrerId: json['referrer_id'] as int?,
    qr: json['qr'] as String?,
    idType: json['id_type'] as String?,
    idNumber: json['id_number'] as String?,
    idImagePath: json['id_image_path'] as String?,
    level: json['level'] as int? ?? 1,
    userId: json['user_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    if (lastName != null) 'last_name': lastName,
    if (firstName != null) 'first_name': firstName,
    if (middleName != null) 'middle_name': middleName,
    if (role != null) 'role': role,
    if (contactNo != null) 'contact_no': contactNo,
    if (birthday != null) 'birthday': birthday,
    if (address != null) 'address': address,
    if (referrer != null) 'referrer': referrer,
    if (referrerId != null) 'referrer_id': referrerId,
    if (qr != null) 'qr': qr,
    if (idType != null) 'id_type': idType,
    if (idNumber != null) 'id_number': idNumber,
    if (idImagePath != null) 'id_image_path': idImagePath,
    'level': level,
    if (userId != null) 'user_id': userId,
  };

  Member copyWith({
    int? id,
    String? lastName,
    String? firstName,
    String? middleName,
    String? role,
    String? contactNo,
    String? birthday,
    String? address,
    String? referrer,
    int? referrerId,
    String? qr,
    String? idType,
    String? idNumber,
    String? idImagePath,
    int? level,
    String? userId,
  }) => Member(
    id: id ?? this.id,
    lastName: lastName ?? this.lastName,
    firstName: firstName ?? this.firstName,
    middleName: middleName ?? this.middleName,
    role: role ?? this.role,
    contactNo: contactNo ?? this.contactNo,
    birthday: birthday ?? this.birthday,
    address: address ?? this.address,
    referrer: referrer ?? this.referrer,
    referrerId: referrerId ?? this.referrerId,
    qr: qr ?? this.qr,
    idType: idType ?? this.idType,
    idNumber: idNumber ?? this.idNumber,
    idImagePath: idImagePath ?? this.idImagePath,
    level: level ?? this.level,
    userId: userId ?? this.userId,
  );
}

/// A sale / transaction record.
class Sale {
  final int? id;
  final int itemId;
  final int? buyerId;
  final String itemName;
  final int quantity;
  final int price;
  final DateTime? timestamp;
  final String? userId;

  const Sale({
    this.id,
    required this.itemId,
    this.buyerId,
    required this.itemName,
    required this.quantity,
    this.price = 0,
    this.timestamp,
    this.userId,
  });

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
    id: json['id'] as int?,
    itemId: json['item_id'] as int? ?? 0,
    buyerId: json['buyer_id'] as int?,
    itemName: json['item_name'] as String? ?? '',
    quantity: json['quantity'] as int? ?? 0,
    price: json['price'] as int? ?? 0,
    timestamp: json['timestamp'] != null
        ? DateTime.tryParse(json['timestamp'].toString())
        : null,
    userId: json['user_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'item_id': itemId,
    if (buyerId != null) 'buyer_id': buyerId,
    'item_name': itemName,
    'quantity': quantity,
    'price': price,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
    if (userId != null) 'user_id': userId,
  };

  Sale copyWith({
    int? id,
    int? itemId,
    int? buyerId,
    String? itemName,
    int? quantity,
    int? price,
    DateTime? timestamp,
    String? userId,
  }) => Sale(
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    buyerId: buyerId ?? this.buyerId,
    itemName: itemName ?? this.itemName,
    quantity: quantity ?? this.quantity,
    price: price ?? this.price,
    timestamp: timestamp ?? this.timestamp,
    userId: userId ?? this.userId,
  );
}

/// Reseller level configuration (1-10).
class ResellerLevel {
  final int level;
  final int remittanceMin;
  final int remittanceMax;
  final int cashAdvance;
  final String? userId;

  const ResellerLevel({
    required this.level,
    this.remittanceMin = 0,
    this.remittanceMax = 0,
    this.cashAdvance = 0,
    this.userId,
  });

  factory ResellerLevel.fromJson(Map<String, dynamic> json) => ResellerLevel(
    level: json['level'] as int? ?? 1,
    remittanceMin: json['remittance_min'] as int? ?? 0,
    remittanceMax: json['remittance_max'] as int? ?? 0,
    cashAdvance: json['cash_advance'] as int? ?? 0,
    userId: json['user_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'level': level,
    'remittance_min': remittanceMin,
    'remittance_max': remittanceMax,
    'cash_advance': cashAdvance,
    if (userId != null) 'user_id': userId,
  };
}

/// Audit row for member transactions (member_transactions table).
class MemberTransaction {
  final int? id;
  final int memberId;
  final int? saleId;
  final int? itemId;
  final String? itemName;
  final int quantity;
  final int price;
  final DateTime? timestamp;
  final String? userId;

  const MemberTransaction({
    this.id,
    required this.memberId,
    this.saleId,
    this.itemId,
    this.itemName,
    this.quantity = 0,
    this.price = 0,
    this.timestamp,
    this.userId,
  });

  factory MemberTransaction.fromJson(Map<String, dynamic> json) =>
      MemberTransaction(
        id: json['id'] as int?,
        memberId: json['member_id'] as int? ?? 0,
        saleId: json['sale_id'] as int?,
        itemId: json['item_id'] as int?,
        itemName: json['item_name'] as String?,
        quantity: json['quantity'] as int? ?? 0,
        price: json['price'] as int? ?? 0,
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'].toString())
            : null,
        userId: json['user_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'member_id': memberId,
    if (saleId != null) 'sale_id': saleId,
    if (itemId != null) 'item_id': itemId,
    if (itemName != null) 'item_name': itemName,
    'quantity': quantity,
    'price': price,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
    if (userId != null) 'user_id': userId,
  };
}

/// User profile linked to Supabase Auth.
class UserProfile {
  final String id; // matches auth.users.id (UUID)
  final String username;
  final String role; // admin, inventory, cashier
  final DateTime? createdAt;

  const UserProfile({
    required this.id,
    required this.username,
    this.role = 'cashier',
    this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String? ?? '',
    username: json['username'] as String? ?? '',
    role: json['role'] as String? ?? 'cashier',
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'].toString())
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'role': role,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

/// Small DTO for parsed transaction entries (used in member CSV import).
class MemberTransactionEntry {
  final int? itemId;
  final String itemName;
  final int quantity;
  final int price;
  final DateTime? timestamp;

  const MemberTransactionEntry({
    this.itemId,
    required this.itemName,
    required this.quantity,
    required this.price,
    this.timestamp,
  });
}

// ── Helper Functions ──────────────────────────────────────────────────────

/// Convert a list of [Item]s to a list of maps for UI consumption.
List<Map<String, dynamic>> inventoryItemsFromRows(List<Item> rows) {
  return rows
      .map(
        (r) => {
          'id': r.id,
          'name': r.name,
          'category': r.category ?? '',
          'stock': r.stock,
          'lastUpdated': r.lastUpdated?.toIso8601String() ?? '',
          'status': r.status ?? statusFromStock(r.stock),
        },
      )
      .toList();
}

/// Convert a list of [Member]s to a list of maps for UI consumption.
List<Map<String, dynamic>> membersFromRows(List<Member> rows) {
  return rows
      .map(
        (m) => {
          'id': m.id,
          'firstName': m.firstName ?? '',
          'lastName': m.lastName ?? '',
          'middleName': m.middleName ?? '',
          'role': m.role ?? '',
          'contactNo': m.contactNo ?? '',
          'birthday': m.birthday ?? '',
          'address': m.address ?? '',
          'referrer': m.referrer ?? '',
          'referrerId': m.referrerId,
          'level': m.level,
          'qr': m.qr ?? '',
          'idType': m.idType ?? '',
          'idNumber': m.idNumber ?? '',
          'idImagePath': m.idImagePath ?? '',
        },
      )
      .toList();
}

/// Returns a status label based on stock quantity.
String statusFromStock(int stock) {
  if (stock <= 0) return 'Out of Stock';
  if (stock < 50) return 'Low Stock';
  return 'Good';
}
