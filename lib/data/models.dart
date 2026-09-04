// lib/data/models.dart
// Pure Dart model classes for the cloud-based LZCAS (Stockpile) app.
// All models use snake_case JSON keys matching Supabase column names.

import '../utils/app_clock.dart';

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
  final String? email;
  final String? userId;
  final int? packageId;
  final String? packageName; // joined via Supabase FK -> packages(name)

  /// Soft-delete flag: deleted members are hidden from lists but stay in
  /// the referral tree so previously earned bonuses are never deducted.
  final bool isDeleted;

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
    this.email,
    this.userId,
    this.packageId,
    this.packageName,
    this.isDeleted = false,
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
    email: json['email'] as String?,
    userId: json['user_id'] as String?,
    packageId: json['package_id'] as int?,
    packageName: _extractPackageName(json['packages']),
    isDeleted: json['is_deleted'] as bool? ?? false,
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
    if (email != null) 'email': email,
    if (userId != null) 'user_id': userId,
    // Always sent (even when null) so clearing a package — which demotes a
    // Verified Reseller back to Member — actually persists. Every other key
    // above is omit-when-null so a partial update never wipes an unrelated
    // field; package_id is deliberately different because null is meaningful.
    'package_id': packageId,
  };

  /// Sentinel so [copyWith] can distinguish "leave packageId unchanged" from
  /// "explicitly clear the package". A plain `packageId ?? this.packageId`
  /// can't express clearing, which silently blocked reseller → member demotion.
  static const Object _unsetPackage = Object();

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
    String? email,
    String? userId,
    Object? packageId = _unsetPackage,
    String? packageName,
    bool? isDeleted,
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
    email: email ?? this.email,
    userId: userId ?? this.userId,
    packageId: identical(packageId, _unsetPackage)
        ? this.packageId
        : packageId as int?,
    packageName: packageName ?? this.packageName,
    isDeleted: isDeleted ?? this.isDeleted,
  );
}

/// A package / membership tier with referral bonuses and rates.
class Package {
  final int? id;
  final String name;
  final int price;
  final int directReferralBonus;
  final int indirectReferralBonus;
  final int chairmansBonus;

  /// Bonus paid to the referrer when a direct downline upgrades their package.
  /// Looked up from the *referrer's* current package at upgrade time.
  final int upgradeReferralBonus;

  final int groupSalesDirect;
  final int groupSalesIndirect;

  /// Numeric tier rank for upgrade validation. Higher = better tier.
  /// E.g.: Starter=10, Pro=15, Ambassador=20.
  final int hierarchyRank;

  final DateTime? createdAt;

  const Package({
    this.id,
    required this.name,
    this.price = 0,
    this.directReferralBonus = 0,
    this.indirectReferralBonus = 0,
    this.chairmansBonus = 0,
    this.upgradeReferralBonus = 0,
    this.groupSalesDirect = 0,
    this.groupSalesIndirect = 0,
    this.hierarchyRank = 0,
    this.createdAt,
  });

  factory Package.fromJson(Map<String, dynamic> json) => Package(
    id: json['id'] as int?,
    name: json['name'] as String? ?? '',
    price: json['price'] as int? ?? 0,
    directReferralBonus: json['direct_referral_bonus'] as int? ?? 0,
    indirectReferralBonus: json['indirect_referral_bonus'] as int? ?? 0,
    chairmansBonus: json['chairmans_bonus'] as int? ?? 0,
    upgradeReferralBonus: json['upgrade_referral_bonus'] as int? ?? 0,
    groupSalesDirect: json['group_sales_direct'] as int? ?? 0,
    groupSalesIndirect: json['group_sales_indirect'] as int? ?? 0,
    hierarchyRank: json['hierarchy_rank'] as int? ?? 0,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'].toString())
        : null,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'direct_referral_bonus': directReferralBonus,
    'indirect_referral_bonus': indirectReferralBonus,
    'chairmans_bonus': chairmansBonus,
    'upgrade_referral_bonus': upgradeReferralBonus,
    'group_sales_direct': groupSalesDirect,
    'group_sales_indirect': groupSalesIndirect,
    'hierarchy_rank': hierarchyRank,
  };

  Package copyWith({
    int? id,
    String? name,
    int? price,
    int? directReferralBonus,
    int? indirectReferralBonus,
    int? chairmansBonus,
    int? upgradeReferralBonus,
    int? groupSalesDirect,
    int? groupSalesIndirect,
    int? hierarchyRank,
  }) => Package(
    id: id ?? this.id,
    name: name ?? this.name,
    price: price ?? this.price,
    directReferralBonus: directReferralBonus ?? this.directReferralBonus,
    indirectReferralBonus: indirectReferralBonus ?? this.indirectReferralBonus,
    chairmansBonus: chairmansBonus ?? this.chairmansBonus,
    upgradeReferralBonus: upgradeReferralBonus ?? this.upgradeReferralBonus,
    groupSalesDirect: groupSalesDirect ?? this.groupSalesDirect,
    groupSalesIndirect: groupSalesIndirect ?? this.groupSalesIndirect,
    hierarchyRank: hierarchyRank ?? this.hierarchyRank,
    createdAt: createdAt,
  );
}

/// A point-in-time record of a member's computed earnings and balance.
/// Earnings are computed live (and can decrease), so history is captured
/// as snapshots with deltas whenever the computed values change.
class EarningsSnapshot {
  final int? id;
  final int memberId;
  final int totalEarnings;
  final int balance;
  final int earningsDelta;
  final int balanceDelta;

  // Component snapshot — where total_earnings comes from. Diffing two
  // consecutive snapshots attributes a change to its source(s).
  // (balance's only source is the direct referral bonus)
  final int indirectBonus;
  final int groupSales; // deprecated — replaced by passiveIncome
  final int passiveIncome; // 5/item direct + 3/item indirect
  final int repeatPurchase;
  final int chairmanBonus;

  /// Upgrade referral bonus earned when direct downlines upgrade.
  final int upgradeBonus;

  /// Why this snapshot moved, when the cause is known. Snapshots otherwise
  /// record only deltas, which is why a decrease used to be guessed at (and
  /// mislabelled "Withdrawal"). Written by `admin_adjust_member_funds` (v35);
  /// null for the ordinary snapshots the member's own dashboard records.
  final String? note;

  final DateTime? recordedAt;

  const EarningsSnapshot({
    this.id,
    required this.memberId,
    this.totalEarnings = 0,
    this.balance = 0,
    this.earningsDelta = 0,
    this.balanceDelta = 0,
    this.indirectBonus = 0,
    this.groupSales = 0,
    this.passiveIncome = 0,
    this.repeatPurchase = 0,
    this.chairmanBonus = 0,
    this.upgradeBonus = 0,
    this.note,
    this.recordedAt,
  });

  /// True for rows recorded before component tracking existed — their
  /// components are all zero despite a nonzero total, so a component
  /// diff against them would mislead.
  bool get isLegacy =>
      totalEarnings != 0 &&
      indirectBonus == 0 &&
      groupSales == 0 &&
      passiveIncome == 0 &&
      repeatPurchase == 0 &&
      chairmanBonus == 0 &&
      upgradeBonus == 0;

  factory EarningsSnapshot.fromJson(Map<String, dynamic> json) =>
      EarningsSnapshot(
        id: json['id'] as int?,
        memberId: json['member_id'] as int? ?? 0,
        totalEarnings: json['total_earnings'] as int? ?? 0,
        balance: json['balance'] as int? ?? 0,
        earningsDelta: json['earnings_delta'] as int? ?? 0,
        balanceDelta: json['balance_delta'] as int? ?? 0,
        indirectBonus: json['indirect_bonus'] as int? ?? 0,
        groupSales: json['group_sales'] as int? ?? 0,
        passiveIncome: json['passive_income'] as int? ?? 0,
        repeatPurchase: json['repeat_purchase'] as int? ?? 0,
        chairmanBonus: json['chairman_bonus'] as int? ?? 0,
        upgradeBonus: json['upgrade_bonus'] as int? ?? 0,
        note: (json['note'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['note'] as String).trim(),
        recordedAt: json['recorded_at'] != null
            ? DateTime.tryParse(json['recorded_at'].toString())
            : null,
      );

  Map<String, dynamic> toJson() => {
    'member_id': memberId,
    'total_earnings': totalEarnings,
    'balance': balance,
    'earnings_delta': earningsDelta,
    'balance_delta': balanceDelta,
    'indirect_bonus': indirectBonus,
    'group_sales': groupSales,
    'passive_income': passiveIncome,
    'repeat_purchase': repeatPurchase,
    'chairman_bonus': chairmanBonus,
    'upgrade_bonus': upgradeBonus,
  };
}

/// A product category, used for low-stock thresholds and grouping.
class Category {
  final int? id;
  final String name;

  /// Per-category low-stock threshold. Null means "not set" — the global
  /// app_config threshold is used as a fallback (for uncategorized items).
  final int? lowStockThreshold;

  const Category({this.id, required this.name, this.lowStockThreshold});

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as int?,
    name: json['name'] as String? ?? '',
    lowStockThreshold: json['low_stock_threshold'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (lowStockThreshold != null) 'low_stock_threshold': lowStockThreshold,
  };

  Category copyWith({int? id, String? name, int? lowStockThreshold}) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
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

  /// Set when this sale is a package availment, not a product sale.
  final int? packageId;

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
    this.packageId,
  });

  /// Package availments are not products and are excluded from
  /// product metrics (revenue, category breakdown, top products).
  bool get isPackage => packageId != null;

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
    packageId: json['package_id'] as int?,
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
    if (packageId != null) 'package_id': packageId,
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
    int? packageId,
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
    packageId: packageId ?? this.packageId,
  );
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
  final String requestType; // 'delete', 'reduce_stock', 'delete_member'
  final int? quantity;
  final int? price;
  final String? notes;
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

  String get summary {
    if (requestType == 'delete') return 'Delete "$itemName"';
    if (requestType == 'reduce_stock') {
      return 'Reduce "$itemName" by ${quantity ?? 0}';
    }
    if (requestType == 'delete_member') {
      return 'Delete member "$memberName"';
    }
    // Legacy: historical rows from the retired borrow mechanic still
    // exist in pending_requests and must render in request history.
    if (requestType == 'borrow') {
      return 'Borrow "$itemName" (×${quantity ?? 0}) for "$memberName" (legacy)';
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

/// A withdrawal request submitted by a member against their Total Earnings
/// or Balance pool. Admins approve or reject each request.
class WithdrawalRequest {
  final String? id; // UUID
  final int memberId;
  final String sourceBucket; // 'total_earnings' or 'balance'
  final int requestedAmount;
  final String status; // 'pending', 'approved', 'rejected'
  final String? rejectionReason;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  const WithdrawalRequest({
    this.id,
    required this.memberId,
    required this.sourceBucket,
    required this.requestedAmount,
    this.status = 'pending',
    this.rejectionReason,
    this.reviewedBy,
    this.reviewedAt,
    this.createdAt,
  });

  bool get isPending => status == 'pending';

  String get sourceLabel =>
      sourceBucket == 'total_earnings' ? 'Total Earnings' : 'Balance';

  factory WithdrawalRequest.fromJson(Map<String, dynamic> json) =>
      WithdrawalRequest(
        id: json['id'] as String?,
        memberId: json['member_id'] as int? ?? 0,
        sourceBucket: json['source_bucket'] as String? ?? 'total_earnings',
        requestedAmount: json['requested_amount'] as int? ?? 0,
        status: json['status'] as String? ?? 'pending',
        rejectionReason: json['rejection_reason'] as String?,
        reviewedBy: json['reviewed_by'] as String?,
        reviewedAt: json['reviewed_at'] != null
            ? DateTime.tryParse(json['reviewed_at'].toString())
            : null,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'].toString())
            : null,
      );

  Map<String, dynamic> toJson() => {
    'member_id': memberId,
    'source_bucket': sourceBucket,
    'requested_amount': requestedAmount,
    'status': status,
    if (rejectionReason != null) 'rejection_reason': rejectionReason,
    if (reviewedBy != null) 'reviewed_by': reviewedBy,
    if (reviewedAt != null) 'reviewed_at': reviewedAt!.toIso8601String(),
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };

  WithdrawalRequest copyWith({
    String? id,
    int? memberId,
    String? sourceBucket,
    int? requestedAmount,
    String? status,
    String? rejectionReason,
    String? reviewedBy,
    DateTime? reviewedAt,
    DateTime? createdAt,
  }) => WithdrawalRequest(
    id: id ?? this.id,
    memberId: memberId ?? this.memberId,
    sourceBucket: sourceBucket ?? this.sourceBucket,
    requestedAmount: requestedAmount ?? this.requestedAmount,
    status: status ?? this.status,
    rejectionReason: rejectionReason ?? this.rejectionReason,
    reviewedBy: reviewedBy ?? this.reviewedBy,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    createdAt: createdAt ?? this.createdAt,
  );
}

/// User profile linked to Supabase Auth.
class UserProfile {
  final String id; // matches auth.users.id (UUID)
  final String username;
  final String?
  email; // auth.users.email — populated via handle_new_user trigger
  final String
  role; // admin, inventory, cashier, branch_cashier, member, reseller
  final int? memberId; // links to members.id for member/reseller roles
  final bool mobileEnabled; // admin-granted mobile login (branch_cashier only)

  /// Saved physical location (cashier / branch cashier only). Set from the
  /// Cashier Location Settings screen; read by the member's Nearest Cashiers
  /// map. Null means "not set yet".
  final double? latitude;
  final double? longitude;
  final String? address;

  /// When the cashier/branch location was last set (null = never set).
  /// Deliberately not called `updatedAt` — it tracks the location only, not
  /// the profile row.
  final DateTime? locationUpdatedAt;
  final DateTime? createdAt;

  const UserProfile({
    required this.id,
    required this.username,
    this.email,
    this.role = 'cashier',
    this.memberId,
    this.mobileEnabled = false,
    this.latitude,
    this.longitude,
    this.address,
    this.locationUpdatedAt,
    this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String? ?? '',
    username: json['username'] as String? ?? '',
    email: json['email'] as String?,
    role: json['role'] as String? ?? 'cashier',
    memberId: json['member_id'] as int?,
    mobileEnabled: json['mobile_enabled'] == true,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    address: json['address'] as String?,
    locationUpdatedAt: json['location_updated_at'] != null
        ? DateTime.tryParse(json['location_updated_at'].toString())
        : null,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'].toString())
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'role': role,
    'mobile_enabled': mobileEnabled,
    if (email != null) 'email': email,
    if (memberId != null) 'member_id': memberId,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (address != null) 'address': address,
    if (locationUpdatedAt != null)
      'location_updated_at': locationUpdatedAt!.toIso8601String(),
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

/// A cashier (or branch cashier) with a saved physical location.
///
/// Used by the member-facing "Nearest Cashiers" map. Distance is computed
/// client-side with `Geolocator.distanceBetween()` and never persisted.
class CashierLocation {
  final String id; // profiles.id (UUID)
  final String name; // profiles.username — shown as the branch/cashier name
  final String role; // 'cashier' or 'branch_cashier'
  final double latitude;
  final double longitude;
  final String? address;

  /// When this location was last set (null when the row predates this field).
  final DateTime? locationUpdatedAt;

  const CashierLocation({
    required this.id,
    required this.name,
    required this.role,
    required this.latitude,
    required this.longitude,
    this.address,
    this.locationUpdatedAt,
  });

  bool get isBranchCashier => role == 'branch_cashier';

  String get roleLabel => isBranchCashier ? 'Branch Cashier' : 'Cashier';

  factory CashierLocation.fromJson(Map<String, dynamic> json) =>
      CashierLocation(
        id: json['id'] as String? ?? '',
        name: json['username'] as String? ?? 'Unknown',
        role: json['role'] as String? ?? 'cashier',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        address: json['address'] as String?,
        locationUpdatedAt: json['location_updated_at'] != null
            ? DateTime.tryParse(json['location_updated_at'].toString())
            : null,
      );
}

/// One on-hand inventory line for a located cashier / branch cashier,
/// exposed to members by the "Nearest Cashiers" discovery screen.
///
/// For a branch cashier this is a `branch_stock` row (read through the
/// SECURITY DEFINER `member_branch_stock` RPC); for a regular
/// (central-stock) cashier the app derives these from the shared `items`
/// catalog, in which case [ownerId] is empty.
class CashierStockLine {
  final String ownerId; // profiles.id of the branch cashier ('' for central)
  final int? itemId;
  final String name;
  final String? category;
  final int quantity;
  final String? status;

  const CashierStockLine({
    required this.ownerId,
    this.itemId,
    required this.name,
    this.category,
    this.quantity = 0,
    this.status,
  });

  /// A line is only "in stock" when its on-hand quantity is positive.
  bool get inStock => quantity > 0;

  factory CashierStockLine.fromJson(Map<String, dynamic> json) =>
      CashierStockLine(
        ownerId: json['owner_id'] as String? ?? '',
        itemId: (json['item_id'] as num?)?.toInt(),
        name: json['item_name'] as String? ?? '',
        category: json['category'] as String?,
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        status: json['status'] as String?,
      );
}

/// A located cashier / branch cashier plus its live stock availability —
/// the unit the member "Nearest Cashiers" screen ranks by distance and
/// filters to its Top 3 stocked locations.
class CashierWithStock {
  final CashierLocation location;
  final bool hasStock;

  /// On-hand inventory (quantity carried in each line) for the inspection
  /// sheet. Branch cashiers carry their own allocation; regular cashiers
  /// carry the shared central catalog.
  final List<CashierStockLine> stock;

  const CashierWithStock({
    required this.location,
    required this.hasStock,
    this.stock = const [],
  });
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

/// Which wallet a ledger row pays into, and how it is labelled in the UI.
///
/// Mirrors how `get_member_earnings` buckets the same rows, so an itemised
/// list always reconciles to the totals shown on the dashboard.
enum EarningsBucket {
  directReferral('Direct Referral', isBalance: true, wire: 'direct_referral'),
  indirectReferral('Indirect Referral', wire: 'indirect_referral'),
  groupSales('Group Sales', wire: 'group_sales'),
  chairmanBonus("Chairman's Bonus", wire: 'chairman_bonus'),
  upgradeBonus('Upgrade Bonus', wire: 'upgrade_bonus'),
  other('Other');

  const EarningsBucket(this.label, {this.isBalance = false, this.wire});

  final String label;

  /// Direct Referral pays the Balance wallet; every other bucket feeds
  /// Total Earnings. Matches v24's split.
  final bool isBalance;

  /// Key the `admin_adjust_member_funds` RPC (v35) accepts for this bucket.
  /// Null for [other], which is not a real bucket and cannot be adjusted.
  final String? wire;

  /// The buckets an admin may adjust — every one except [other].
  static List<EarningsBucket> get adjustable =>
      values.where((b) => b.wire != null).toList(growable: false);

  /// Classify a `member_transactions.item_name`. Order matters: "Indirect
  /// Referral" must be tested before "Direct Referral" would ever match, and
  /// Group Sales rows are named "Group Sales (Direct)" / "(Indirect)".
  static EarningsBucket fromItemName(String raw) {
    final n = raw.toLowerCase();
    if (n.startsWith('group sales')) return EarningsBucket.groupSales;
    if (n.startsWith('indirect referral')) {
      return EarningsBucket.indirectReferral;
    }
    if (n.startsWith('direct referral')) return EarningsBucket.directReferral;
    if (n.startsWith('chairman bonus')) return EarningsBucket.chairmanBonus;
    if (n.startsWith('upgrade bonus')) return EarningsBucket.upgradeBonus;
    return EarningsBucket.other;
  }
}

/// One earning event from the frozen ledger (`member_transactions`), with its
/// source resolved to a human-readable name.
///
/// [sourceName] is the person the credit came from — the referred member for
/// referral/chairman rows, the buyer for group-sales rows. Null when the
/// ledger row carries no link (Upgrade Bonus rows don't record which downline
/// upgraded), in which case the UI shows the raw label only.
class EarningsSource {
  final EarningsBucket bucket;
  final String rawLabel;
  final String? sourceName;
  final String? detail;
  final int amount;
  final DateTime? timestamp;

  /// True when an admin posted this row through `admin_adjust_member_funds`
  /// rather than it being earned. Such a row has no counterparty — its label
  /// carries the admin's reason instead of a person's name.
  final bool isAdjustment;

  const EarningsSource({
    required this.bucket,
    required this.rawLabel,
    required this.amount,
    this.sourceName,
    this.detail,
    this.timestamp,
    this.isAdjustment = false,
  });
}

/// Who an announcement is addressed to. The three values are mutually
/// exclusive: [members] means plain members only, so a reseller does not
/// receive one sent to "members".
/// Who an announcement reaches.
///
/// The split is staff vs customers: [branches] addresses branch cashier
/// accounts, [members] addresses members AND resellers together. There is
/// deliberately no reseller-only option — see migration v38, which widened
/// the old 'resellers' audience into [members].
enum AnnouncementAudience {
  all('all', 'Everyone'),
  branches('branches', 'Branches only'),
  members('members', 'Members only');

  const AnnouncementAudience(this.wire, this.label);

  final String wire;
  final String label;

  static AnnouncementAudience fromWire(String? raw) =>
      values.firstWhere((a) => a.wire == raw, orElse: () => all);
}

/// An admin-posted notice shown to members.
class Announcement {
  final int id;
  final String title;
  final String body;
  final AnnouncementAudience audience;
  final DateTime? publishedAt;

  /// When it stops being current. Null means it stays up until archived.
  final DateTime? endsAt;

  /// Set when an admin takes it out of circulation. Announcements are never
  /// deleted — a member may have saved one.
  final DateTime? archivedAt;

  /// Whether THIS member has starred it. Populated by the repository from
  /// the member's saved list, not by the announcements query.
  final bool saved;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.audience = AnnouncementAudience.all,
    this.publishedAt,
    this.endsAt,
    this.archivedAt,
    this.saved = false,
  });

  bool get isArchived => archivedAt != null;

  /// Still in its window. An announcement with no end date is current
  /// forever; one with an end date stops on the dot.
  ///
  /// Defaults to [AppClock], not `DateTime.now()`: this has to give the same
  /// answer the RLS policy and every server-side query give, and those use
  /// the database's clock. A device three weeks fast otherwise reads a live
  /// announcement as ended — labelled "Ended" for staff, and filtered out of
  /// existence for members.
  bool isCurrent([DateTime? now]) {
    if (isArchived) return false;
    final at = now ?? AppClock.now();
    if (publishedAt != null && publishedAt!.isAfter(at)) return false;
    return endsAt == null || endsAt!.isAfter(at);
  }

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    id: json['id'] as int? ?? 0,
    title: (json['title'] ?? '').toString(),
    body: (json['body'] ?? '').toString(),
    audience: AnnouncementAudience.fromWire(json['audience'] as String?),
    publishedAt: DateTime.tryParse((json['published_at'] ?? '').toString()),
    endsAt: DateTime.tryParse((json['ends_at'] ?? '').toString()),
    archivedAt: DateTime.tryParse((json['archived_at'] ?? '').toString()),
  );

  Announcement copyWith({bool? saved}) => Announcement(
    id: id,
    title: title,
    body: body,
    audience: audience,
    publishedAt: publishedAt,
    endsAt: endsAt,
    archivedAt: archivedAt,
    saved: saved ?? this.saved,
  );
}

/// A birthday greeting for one member in one year.
///
/// Not a database row — it is computed from `members.birthday` when the
/// member opens the app, which is why the feature needs no scheduler and
/// sends nothing. [year] is what identifies it when saved.
class BirthdayGreeting {
  /// The year this greeting belongs to — normally the current year, but the
  /// PREVIOUS year when the window straddles New Year (a 20 December
  /// birthday viewed on 5 January is still last year's greeting).
  final int year;

  /// The actual date the birthday fell on, for display.
  final DateTime occurredOn;

  /// Whole days since the birthday. 0 on the day itself.
  final int daysSince;

  final bool saved;

  const BirthdayGreeting({
    required this.year,
    required this.occurredOn,
    required this.daysSince,
    this.saved = false,
  });

  bool get isToday => daysSince == 0;

  BirthdayGreeting copyWith({bool? saved}) => BirthdayGreeting(
    year: year,
    occurredOn: occurredOn,
    daysSince: daysSince,
    saved: saved ?? this.saved,
  );
}

/// One entry from the admin fund-adjustment audit trail (`fund_adjustments`).
///
/// The money itself lives in `member_transactions`; this is the paperwork —
/// who changed what, when, and why. Readable by admins only.
class FundAdjustment {
  final int? id;
  final int memberId;
  final EarningsBucket bucket;
  final int amount; // signed: negative deducts
  final String reason;
  final int balanceBefore; // of this bucket, not the wallet
  final int balanceAfter;
  final DateTime? createdAt;

  const FundAdjustment({
    this.id,
    required this.memberId,
    required this.bucket,
    required this.amount,
    required this.reason,
    this.balanceBefore = 0,
    this.balanceAfter = 0,
    this.createdAt,
  });

  bool get isDeduction => amount < 0;

  factory FundAdjustment.fromJson(Map<String, dynamic> json) {
    final wire = (json['bucket'] ?? '').toString();
    return FundAdjustment(
      id: json['id'] as int?,
      memberId: json['member_id'] as int? ?? 0,
      bucket: EarningsBucket.values.firstWhere(
        (b) => b.wire == wire,
        orElse: () => EarningsBucket.other,
      ),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      reason: (json['reason'] ?? '').toString(),
      balanceBefore: (json['balance_before'] as num?)?.toInt() ?? 0,
      balanceAfter: (json['balance_after'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
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
          'qr': m.qr ?? '',
          'email': m.email ?? '',
          'user_id': m.userId ?? '',
          'packageId': m.packageId,
          'packageName': m.packageName ?? '',
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

/// Extract a package name from a PostgREST FK join result.
/// Handles: null, single map {name: "..."}, or array [{name: "..."}].
String? _extractPackageName(dynamic packages) {
  if (packages == null) return null;
  if (packages is List) {
    if (packages.isEmpty) return null;
    return (packages.first as Map<String, dynamic>)['name'] as String?;
  }
  if (packages is Map<String, dynamic>) {
    return packages['name'] as String?;
  }
  return null;
}

/// Default configuration values used when no app_config row exists.
class AppConfigDefaults {
  static const lowStockThreshold = 50;
  static const currencySymbol = '₱';
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
