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
  final String? buyerName;
  final String itemName;
  final int quantity;
  final int price;
  final DateTime? timestamp;
  final String? userId;

  const Sale({
    this.id,
    required this.itemId,
    this.buyerId,
    this.buyerName,
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
    buyerName: json['buyer_name'] as String?,
    itemName: json['item_name'] as String? ?? '',
    quantity: json['quantity'] as int? ?? 0,
    price: json['price'] as int? ?? 0,
    timestamp: json['timestamp'] != null
        ? DateTime.tryParse(json['timestamp'].toString())
        : null,
    userId: json['user_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    if (buyerId != null) 'buyer_id': buyerId,
    if (buyerName != null) 'buyer_name': buyerName,
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
    String? buyerName,
    String? itemName,
    int? quantity,
    int? price,
    DateTime? timestamp,
    String? userId,
  }) => Sale(
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    buyerId: buyerId ?? this.buyerId,
    buyerName: buyerName ?? this.buyerName,
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

/// Audit record for manual stock adjustments (add / reduce).
class StockMovement {
  final int? id;
  final String? userId;
  final int itemId;
  final String itemName;
  final int quantity;
  final String movementType; // 'stock_in' or 'stock_out'
  final String? reason;
  final DateTime? createdAt;

  const StockMovement({
    this.id,
    this.userId,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.movementType,
    this.reason,
    this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
    id: json['id'] as int?,
    userId: json['user_id'] as String?,
    itemId: json['item_id'] as int? ?? 0,
    itemName: json['item_name'] as String? ?? '',
    quantity: json['quantity'] as int? ?? 0,
    movementType: json['movement_type'] as String? ?? 'stock_in',
    reason: json['reason'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'].toString())
        : null,
  );

  Map<String, dynamic> toJson() => {
    if (userId != null) 'user_id': userId,
    'item_id': itemId,
    'item_name': itemName,
    'quantity': quantity,
    'movement_type': movementType,
    if (reason != null) 'reason': reason,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

/// A pending request for admin approval (inventory delete/reduce, or member delete).
class PendingRequest {
  final int? id;
  final String? userId;
  final int? itemId;
  final String? itemName;
  final int? memberId;
  final String? memberName;
  final String
  requestType; // 'delete', 'reduce_stock', 'delete_member', 'borrow'
  final int? quantity;
  final int? price; // for borrow: price per item
  final String? notes; // for borrow: optional notes
  final String? reason;
  final String? rejectionReason; // admin's reason when rejecting
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  const PendingRequest({
    this.id,
    this.userId,
    this.itemId,
    this.itemName,
    this.memberId,
    this.memberName,
    this.requestType = 'delete',
    this.quantity,
    this.price,
    this.notes,
    this.reason,
    this.rejectionReason,
    this.status = 'pending',
    this.reviewedBy,
    this.reviewedAt,
    this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isBorrowRequest => requestType == 'borrow';

  String get summary {
    if (requestType == 'delete') return 'Delete "$itemName"';
    if (requestType == 'reduce_stock') {
      return 'Reduce "$itemName" by ${quantity ?? 0}';
    }
    if (requestType == 'delete_member') {
      return 'Delete member "$memberName"';
    }
    if (requestType == 'borrow') {
      return 'Borrow "$itemName" (×${quantity ?? 0}) for "$memberName"';
    }
    return '$requestType: ${itemName ?? memberName ?? ''}';
  }

  factory PendingRequest.fromJson(Map<String, dynamic> json) => PendingRequest(
    id: json['id'] as int?,
    userId: json['user_id'] as String?,
    itemId: json['item_id'] as int?,
    itemName: json['item_name'] as String?,
    memberId: json['member_id'] as int?,
    memberName: json['member_name'] as String?,
    requestType: json['request_type'] as String? ?? 'delete',
    quantity: json['quantity'] as int?,
    price: json['price'] as int?,
    notes: json['notes'] as String?,
    reason: json['reason'] as String?,
    rejectionReason: json['rejection_reason'] as String?,
    status: json['status'] as String? ?? 'pending',
    reviewedBy: json['reviewed_by'] as String?,
    reviewedAt: json['reviewed_at'] != null
        ? DateTime.tryParse(json['reviewed_at'].toString())
        : null,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'].toString())
        : null,
  );

  Map<String, dynamic> toJson() => {
    if (userId != null) 'user_id': userId,
    if (itemId != null) 'item_id': itemId,
    if (itemName != null) 'item_name': itemName,
    if (memberId != null) 'member_id': memberId,
    if (memberName != null) 'member_name': memberName,
    'request_type': requestType,
    if (quantity != null) 'quantity': quantity,
    if (price != null) 'price': price,
    if (notes != null) 'notes': notes,
    if (reason != null) 'reason': reason,
    if (rejectionReason != null) 'rejection_reason': rejectionReason,
    'status': status,
    if (reviewedBy != null) 'reviewed_by': reviewedBy,
    if (reviewedAt != null) 'reviewed_at': reviewedAt!.toIso8601String(),
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };

  PendingRequest copyWith({
    int? id,
    String? userId,
    int? itemId,
    String? itemName,
    int? memberId,
    String? memberName,
    String? requestType,
    int? quantity,
    int? price,
    String? notes,
    String? reason,
    String? rejectionReason,
    String? status,
    String? reviewedBy,
    DateTime? reviewedAt,
    DateTime? createdAt,
  }) => PendingRequest(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    itemId: itemId ?? this.itemId,
    itemName: itemName ?? this.itemName,
    memberId: memberId ?? this.memberId,
    memberName: memberName ?? this.memberName,
    requestType: requestType ?? this.requestType,
    quantity: quantity ?? this.quantity,
    price: price ?? this.price,
    notes: notes ?? this.notes,
    reason: reason ?? this.reason,
    rejectionReason: rejectionReason ?? this.rejectionReason,
    status: status ?? this.status,
    reviewedBy: reviewedBy ?? this.reviewedBy,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    createdAt: createdAt ?? this.createdAt,
  );
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

/// A borrow record — items loaned to a reseller with a settlement deadline.
class Borrow {
  final int? id;
  final String? userId;
  final int memberId;
  final String? memberName;
  final int itemId;
  final String itemName;
  final int quantity;
  final int quantityReturned;
  final int quantityRemitted;
  final int price;
  final DateTime? borrowedAt;
  final DateTime dueDate;
  final String status;
  final String? notes;
  final DateTime? settledAt;

  const Borrow({
    this.id,
    this.userId,
    required this.memberId,
    this.memberName,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    this.quantityReturned = 0,
    this.quantityRemitted = 0,
    this.price = 0,
    this.borrowedAt,
    required this.dueDate,
    this.status = 'active',
    this.notes,
    this.settledAt,
  });

  /// Remaining items not yet returned or paid for.
  int get outstandingQuantity => quantity - quantityReturned - quantityRemitted;

  /// Whether the due date has passed and the borrow is not fully settled.
  bool get isOverdue =>
      dueDate.isBefore(DateTime.now()) &&
      status != 'returned' &&
      status != 'remitted';

  /// Whether the borrow is fully settled (all items returned or remitted).
  bool get isFullySettled => outstandingQuantity <= 0;

  /// Human-readable status badge label.
  String get statusLabel {
    if (status == 'overdue' || isOverdue) return 'Overdue';
    if (isFullySettled) {
      if (quantityReturned >= quantity) return 'Returned';
      if (quantityRemitted >= quantity) return 'Remitted';
      return 'Settled';
    }
    if (quantityReturned > 0 || quantityRemitted > 0) return 'Partial';
    return 'Active';
  }

  factory Borrow.fromJson(Map<String, dynamic> json) => Borrow(
    id: json['id'] as int?,
    userId: json['user_id'] as String?,
    memberId: json['member_id'] as int? ?? 0,
    memberName: json['member_name'] as String?,
    itemId: json['item_id'] as int? ?? 0,
    itemName: json['item_name'] as String? ?? '',
    quantity: json['quantity'] as int? ?? 0,
    quantityReturned: json['quantity_returned'] as int? ?? 0,
    quantityRemitted: json['quantity_remitted'] as int? ?? 0,
    price: json['price'] as int? ?? 0,
    borrowedAt: json['borrowed_at'] != null
        ? DateTime.tryParse(json['borrowed_at'].toString())
        : null,
    dueDate: json['due_date'] != null
        ? DateTime.parse(json['due_date'].toString())
        : DateTime.now().add(const Duration(days: 10)),
    status: json['status'] as String? ?? 'active',
    notes: json['notes'] as String?,
    settledAt: json['settled_at'] != null
        ? DateTime.tryParse(json['settled_at'].toString())
        : null,
  );

  Map<String, dynamic> toJson() => {
    if (userId != null) 'user_id': userId,
    'member_id': memberId,
    if (memberName != null) 'member_name': memberName,
    'item_id': itemId,
    'item_name': itemName,
    'quantity': quantity,
    'quantity_returned': quantityReturned,
    'quantity_remitted': quantityRemitted,
    'price': price,
    if (borrowedAt != null) 'borrowed_at': borrowedAt!.toIso8601String(),
    'due_date': dueDate.toIso8601String(),
    'status': status,
    if (notes != null) 'notes': notes,
    if (settledAt != null) 'settled_at': settledAt!.toIso8601String(),
  };

  Borrow copyWith({
    int? id,
    String? userId,
    int? memberId,
    int? itemId,
    String? itemName,
    int? quantity,
    int? quantityReturned,
    int? quantityRemitted,
    int? price,
    DateTime? borrowedAt,
    DateTime? dueDate,
    String? status,
    String? notes,
    DateTime? settledAt,
  }) => Borrow(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    memberId: memberId ?? this.memberId,
    itemId: itemId ?? this.itemId,
    itemName: itemName ?? this.itemName,
    quantity: quantity ?? this.quantity,
    quantityReturned: quantityReturned ?? this.quantityReturned,
    quantityRemitted: quantityRemitted ?? this.quantityRemitted,
    price: price ?? this.price,
    borrowedAt: borrowedAt ?? this.borrowedAt,
    dueDate: dueDate ?? this.dueDate,
    status: status ?? this.status,
    notes: notes ?? this.notes,
    settledAt: settledAt ?? this.settledAt,
  );
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
String statusFromStock(int stock, {int threshold = 50}) {
  if (stock <= 0) return 'Out of Stock';
  if (stock < threshold) return 'Low Stock';
  return 'Good';
}

/// Default configuration values used when no app_config row exists.
class AppConfigDefaults {
  static const lowStockThreshold = 50;
  static const borrowDurationDays = 10;
  static const overdueThresholdDays = 10;
  static const currencySymbol = '₱';
  static const borrowAutoApprove = false;
  static const notificationsEnabled = true;
  static const sessionTimeoutMinutes = 30;
}

/// A single key-value configuration entry persisted in app_config.
class AppConfigEntry {
  final String key;
  final String value;

  const AppConfigEntry({required this.key, required this.value});

  factory AppConfigEntry.fromJson(Map<String, dynamic> json) => AppConfigEntry(
    key: json['key'] as String? ?? '',
    value: json['value'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'key': key, 'value': value};
}
