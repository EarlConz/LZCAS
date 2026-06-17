// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_db.dart';

// ignore_for_file: type=lint
class $ItemsTable extends Items with TableInfo<$ItemsTable, Item> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pointsMeta = const VerificationMeta('points');
  @override
  late final GeneratedColumn<int> points = GeneratedColumn<int>(
    'points',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stockMeta = const VerificationMeta('stock');
  @override
  late final GeneratedColumn<int> stock = GeneratedColumn<int>(
    'stock',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastUpdatedMeta = const VerificationMeta(
    'lastUpdated',
  );
  @override
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
    'last_updated',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    points,
    category,
    stock,
    lastUpdated,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'items';
  @override
  VerificationContext validateIntegrity(
    Insertable<Item> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('points')) {
      context.handle(
        _pointsMeta,
        points.isAcceptableOrUnknown(data['points']!, _pointsMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('stock')) {
      context.handle(
        _stockMeta,
        stock.isAcceptableOrUnknown(data['stock']!, _stockMeta),
      );
    }
    if (data.containsKey('last_updated')) {
      context.handle(
        _lastUpdatedMeta,
        lastUpdated.isAcceptableOrUnknown(
          data['last_updated']!,
          _lastUpdatedMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Item map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Item(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      points: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}points'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      stock: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stock'],
      )!,
      lastUpdated: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_updated'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
    );
  }

  @override
  $ItemsTable createAlias(String alias) {
    return $ItemsTable(attachedDatabase, alias);
  }
}

class Item extends DataClass implements Insertable<Item> {
  final int id;
  final String name;
  final int points;
  final String? category;
  final int stock;
  final DateTime? lastUpdated;
  final String? status;
  const Item({
    required this.id,
    required this.name,
    required this.points,
    this.category,
    required this.stock,
    this.lastUpdated,
    this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['points'] = Variable<int>(points);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    map['stock'] = Variable<int>(stock);
    if (!nullToAbsent || lastUpdated != null) {
      map['last_updated'] = Variable<DateTime>(lastUpdated);
    }
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    return map;
  }

  ItemsCompanion toCompanion(bool nullToAbsent) {
    return ItemsCompanion(
      id: Value(id),
      name: Value(name),
      points: Value(points),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      stock: Value(stock),
      lastUpdated: lastUpdated == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUpdated),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
    );
  }

  factory Item.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Item(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      points: serializer.fromJson<int>(json['points']),
      category: serializer.fromJson<String?>(json['category']),
      stock: serializer.fromJson<int>(json['stock']),
      lastUpdated: serializer.fromJson<DateTime?>(json['lastUpdated']),
      status: serializer.fromJson<String?>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'points': serializer.toJson<int>(points),
      'category': serializer.toJson<String?>(category),
      'stock': serializer.toJson<int>(stock),
      'lastUpdated': serializer.toJson<DateTime?>(lastUpdated),
      'status': serializer.toJson<String?>(status),
    };
  }

  Item copyWith({
    int? id,
    String? name,
    int? points,
    Value<String?> category = const Value.absent(),
    int? stock,
    Value<DateTime?> lastUpdated = const Value.absent(),
    Value<String?> status = const Value.absent(),
  }) => Item(
    id: id ?? this.id,
    name: name ?? this.name,
    points: points ?? this.points,
    category: category.present ? category.value : this.category,
    stock: stock ?? this.stock,
    lastUpdated: lastUpdated.present ? lastUpdated.value : this.lastUpdated,
    status: status.present ? status.value : this.status,
  );
  Item copyWithCompanion(ItemsCompanion data) {
    return Item(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      points: data.points.present ? data.points.value : this.points,
      category: data.category.present ? data.category.value : this.category,
      stock: data.stock.present ? data.stock.value : this.stock,
      lastUpdated: data.lastUpdated.present
          ? data.lastUpdated.value
          : this.lastUpdated,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Item(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('points: $points, ')
          ..write('category: $category, ')
          ..write('stock: $stock, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, points, category, stock, lastUpdated, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Item &&
          other.id == this.id &&
          other.name == this.name &&
          other.points == this.points &&
          other.category == this.category &&
          other.stock == this.stock &&
          other.lastUpdated == this.lastUpdated &&
          other.status == this.status);
}

class ItemsCompanion extends UpdateCompanion<Item> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> points;
  final Value<String?> category;
  final Value<int> stock;
  final Value<DateTime?> lastUpdated;
  final Value<String?> status;
  const ItemsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.points = const Value.absent(),
    this.category = const Value.absent(),
    this.stock = const Value.absent(),
    this.lastUpdated = const Value.absent(),
    this.status = const Value.absent(),
  });
  ItemsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.points = const Value.absent(),
    this.category = const Value.absent(),
    this.stock = const Value.absent(),
    this.lastUpdated = const Value.absent(),
    this.status = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Item> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? points,
    Expression<String>? category,
    Expression<int>? stock,
    Expression<DateTime>? lastUpdated,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (points != null) 'points': points,
      if (category != null) 'category': category,
      if (stock != null) 'stock': stock,
      if (lastUpdated != null) 'last_updated': lastUpdated,
      if (status != null) 'status': status,
    });
  }

  ItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? points,
    Value<String?>? category,
    Value<int>? stock,
    Value<DateTime?>? lastUpdated,
    Value<String?>? status,
  }) {
    return ItemsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      points: points ?? this.points,
      category: category ?? this.category,
      stock: stock ?? this.stock,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (points.present) {
      map['points'] = Variable<int>(points.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (stock.present) {
      map['stock'] = Variable<int>(stock.value);
    }
    if (lastUpdated.present) {
      map['last_updated'] = Variable<DateTime>(lastUpdated.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('points: $points, ')
          ..write('category: $category, ')
          ..write('stock: $stock, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $MembersTable extends Members with TableInfo<$MembersTable, Member> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _middleNameMeta = const VerificationMeta(
    'middleName',
  );
  @override
  late final GeneratedColumn<String> middleName = GeneratedColumn<String>(
    'middle_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contactNoMeta = const VerificationMeta(
    'contactNo',
  );
  @override
  late final GeneratedColumn<String> contactNo = GeneratedColumn<String>(
    'contact_no',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _birthdayMeta = const VerificationMeta(
    'birthday',
  );
  @override
  late final GeneratedColumn<String> birthday = GeneratedColumn<String>(
    'birthday',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referrerMeta = const VerificationMeta(
    'referrer',
  );
  @override
  late final GeneratedColumn<String> referrer = GeneratedColumn<String>(
    'referrer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referrerIdMeta = const VerificationMeta(
    'referrerId',
  );
  @override
  late final GeneratedColumn<int> referrerId = GeneratedColumn<int>(
    'referrer_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pointsMeta = const VerificationMeta('points');
  @override
  late final GeneratedColumn<int> points = GeneratedColumn<int>(
    'points',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _qrMeta = const VerificationMeta('qr');
  @override
  late final GeneratedColumn<String> qr = GeneratedColumn<String>(
    'qr',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idTypeMeta = const VerificationMeta('idType');
  @override
  late final GeneratedColumn<String> idType = GeneratedColumn<String>(
    'id_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idNumberMeta = const VerificationMeta(
    'idNumber',
  );
  @override
  late final GeneratedColumn<String> idNumber = GeneratedColumn<String>(
    'id_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idImagePathMeta = const VerificationMeta(
    'idImagePath',
  );
  @override
  late final GeneratedColumn<String> idImagePath = GeneratedColumn<String>(
    'id_image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    lastName,
    firstName,
    middleName,
    role,
    contactNo,
    birthday,
    address,
    referrer,
    referrerId,
    points,
    qr,
    idType,
    idNumber,
    idImagePath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'members';
  @override
  VerificationContext validateIntegrity(
    Insertable<Member> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    }
    if (data.containsKey('middle_name')) {
      context.handle(
        _middleNameMeta,
        middleName.isAcceptableOrUnknown(data['middle_name']!, _middleNameMeta),
      );
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    }
    if (data.containsKey('contact_no')) {
      context.handle(
        _contactNoMeta,
        contactNo.isAcceptableOrUnknown(data['contact_no']!, _contactNoMeta),
      );
    }
    if (data.containsKey('birthday')) {
      context.handle(
        _birthdayMeta,
        birthday.isAcceptableOrUnknown(data['birthday']!, _birthdayMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('referrer')) {
      context.handle(
        _referrerMeta,
        referrer.isAcceptableOrUnknown(data['referrer']!, _referrerMeta),
      );
    }
    if (data.containsKey('referrer_id')) {
      context.handle(
        _referrerIdMeta,
        referrerId.isAcceptableOrUnknown(data['referrer_id']!, _referrerIdMeta),
      );
    }
    if (data.containsKey('points')) {
      context.handle(
        _pointsMeta,
        points.isAcceptableOrUnknown(data['points']!, _pointsMeta),
      );
    }
    if (data.containsKey('qr')) {
      context.handle(_qrMeta, qr.isAcceptableOrUnknown(data['qr']!, _qrMeta));
    }
    if (data.containsKey('id_type')) {
      context.handle(
        _idTypeMeta,
        idType.isAcceptableOrUnknown(data['id_type']!, _idTypeMeta),
      );
    }
    if (data.containsKey('id_number')) {
      context.handle(
        _idNumberMeta,
        idNumber.isAcceptableOrUnknown(data['id_number']!, _idNumberMeta),
      );
    }
    if (data.containsKey('id_image_path')) {
      context.handle(
        _idImagePathMeta,
        idImagePath.isAcceptableOrUnknown(
          data['id_image_path']!,
          _idImagePathMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Member map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Member(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      ),
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      ),
      middleName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}middle_name'],
      ),
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      ),
      contactNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_no'],
      ),
      birthday: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}birthday'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      referrer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}referrer'],
      ),
      referrerId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}referrer_id'],
      ),
      points: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}points'],
      )!,
      qr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}qr'],
      ),
      idType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id_type'],
      ),
      idNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id_number'],
      ),
      idImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id_image_path'],
      ),
    );
  }

  @override
  $MembersTable createAlias(String alias) {
    return $MembersTable(attachedDatabase, alias);
  }
}

class Member extends DataClass implements Insertable<Member> {
  final int id;
  final String? lastName;
  final String? firstName;
  final String? middleName;
  final String? role;
  final String? contactNo;
  final String? birthday;
  final String? address;
  final String? referrer;
  final int? referrerId;
  final int points;
  final String? qr;
  final String? idType;
  final String? idNumber;
  final String? idImagePath;
  const Member({
    required this.id,
    this.lastName,
    this.firstName,
    this.middleName,
    this.role,
    this.contactNo,
    this.birthday,
    this.address,
    this.referrer,
    this.referrerId,
    required this.points,
    this.qr,
    this.idType,
    this.idNumber,
    this.idImagePath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || lastName != null) {
      map['last_name'] = Variable<String>(lastName);
    }
    if (!nullToAbsent || firstName != null) {
      map['first_name'] = Variable<String>(firstName);
    }
    if (!nullToAbsent || middleName != null) {
      map['middle_name'] = Variable<String>(middleName);
    }
    if (!nullToAbsent || role != null) {
      map['role'] = Variable<String>(role);
    }
    if (!nullToAbsent || contactNo != null) {
      map['contact_no'] = Variable<String>(contactNo);
    }
    if (!nullToAbsent || birthday != null) {
      map['birthday'] = Variable<String>(birthday);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || referrer != null) {
      map['referrer'] = Variable<String>(referrer);
    }
    if (!nullToAbsent || referrerId != null) {
      map['referrer_id'] = Variable<int>(referrerId);
    }
    map['points'] = Variable<int>(points);
    if (!nullToAbsent || qr != null) {
      map['qr'] = Variable<String>(qr);
    }
    if (!nullToAbsent || idType != null) {
      map['id_type'] = Variable<String>(idType);
    }
    if (!nullToAbsent || idNumber != null) {
      map['id_number'] = Variable<String>(idNumber);
    }
    if (!nullToAbsent || idImagePath != null) {
      map['id_image_path'] = Variable<String>(idImagePath);
    }
    return map;
  }

  MembersCompanion toCompanion(bool nullToAbsent) {
    return MembersCompanion(
      id: Value(id),
      lastName: lastName == null && nullToAbsent
          ? const Value.absent()
          : Value(lastName),
      firstName: firstName == null && nullToAbsent
          ? const Value.absent()
          : Value(firstName),
      middleName: middleName == null && nullToAbsent
          ? const Value.absent()
          : Value(middleName),
      role: role == null && nullToAbsent ? const Value.absent() : Value(role),
      contactNo: contactNo == null && nullToAbsent
          ? const Value.absent()
          : Value(contactNo),
      birthday: birthday == null && nullToAbsent
          ? const Value.absent()
          : Value(birthday),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      referrer: referrer == null && nullToAbsent
          ? const Value.absent()
          : Value(referrer),
      referrerId: referrerId == null && nullToAbsent
          ? const Value.absent()
          : Value(referrerId),
      points: Value(points),
      qr: qr == null && nullToAbsent ? const Value.absent() : Value(qr),
      idType: idType == null && nullToAbsent
          ? const Value.absent()
          : Value(idType),
      idNumber: idNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(idNumber),
      idImagePath: idImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(idImagePath),
    );
  }

  factory Member.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Member(
      id: serializer.fromJson<int>(json['id']),
      lastName: serializer.fromJson<String?>(json['lastName']),
      firstName: serializer.fromJson<String?>(json['firstName']),
      middleName: serializer.fromJson<String?>(json['middleName']),
      role: serializer.fromJson<String?>(json['role']),
      contactNo: serializer.fromJson<String?>(json['contactNo']),
      birthday: serializer.fromJson<String?>(json['birthday']),
      address: serializer.fromJson<String?>(json['address']),
      referrer: serializer.fromJson<String?>(json['referrer']),
      referrerId: serializer.fromJson<int?>(json['referrerId']),
      points: serializer.fromJson<int>(json['points']),
      qr: serializer.fromJson<String?>(json['qr']),
      idType: serializer.fromJson<String?>(json['idType']),
      idNumber: serializer.fromJson<String?>(json['idNumber']),
      idImagePath: serializer.fromJson<String?>(json['idImagePath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lastName': serializer.toJson<String?>(lastName),
      'firstName': serializer.toJson<String?>(firstName),
      'middleName': serializer.toJson<String?>(middleName),
      'role': serializer.toJson<String?>(role),
      'contactNo': serializer.toJson<String?>(contactNo),
      'birthday': serializer.toJson<String?>(birthday),
      'address': serializer.toJson<String?>(address),
      'referrer': serializer.toJson<String?>(referrer),
      'referrerId': serializer.toJson<int?>(referrerId),
      'points': serializer.toJson<int>(points),
      'qr': serializer.toJson<String?>(qr),
      'idType': serializer.toJson<String?>(idType),
      'idNumber': serializer.toJson<String?>(idNumber),
      'idImagePath': serializer.toJson<String?>(idImagePath),
    };
  }

  Member copyWith({
    int? id,
    Value<String?> lastName = const Value.absent(),
    Value<String?> firstName = const Value.absent(),
    Value<String?> middleName = const Value.absent(),
    Value<String?> role = const Value.absent(),
    Value<String?> contactNo = const Value.absent(),
    Value<String?> birthday = const Value.absent(),
    Value<String?> address = const Value.absent(),
    Value<String?> referrer = const Value.absent(),
    Value<int?> referrerId = const Value.absent(),
    int? points,
    Value<String?> qr = const Value.absent(),
    Value<String?> idType = const Value.absent(),
    Value<String?> idNumber = const Value.absent(),
    Value<String?> idImagePath = const Value.absent(),
  }) => Member(
    id: id ?? this.id,
    lastName: lastName.present ? lastName.value : this.lastName,
    firstName: firstName.present ? firstName.value : this.firstName,
    middleName: middleName.present ? middleName.value : this.middleName,
    role: role.present ? role.value : this.role,
    contactNo: contactNo.present ? contactNo.value : this.contactNo,
    birthday: birthday.present ? birthday.value : this.birthday,
    address: address.present ? address.value : this.address,
    referrer: referrer.present ? referrer.value : this.referrer,
    referrerId: referrerId.present ? referrerId.value : this.referrerId,
    points: points ?? this.points,
    qr: qr.present ? qr.value : this.qr,
    idType: idType.present ? idType.value : this.idType,
    idNumber: idNumber.present ? idNumber.value : this.idNumber,
    idImagePath: idImagePath.present ? idImagePath.value : this.idImagePath,
  );
  Member copyWithCompanion(MembersCompanion data) {
    return Member(
      id: data.id.present ? data.id.value : this.id,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      middleName: data.middleName.present
          ? data.middleName.value
          : this.middleName,
      role: data.role.present ? data.role.value : this.role,
      contactNo: data.contactNo.present ? data.contactNo.value : this.contactNo,
      birthday: data.birthday.present ? data.birthday.value : this.birthday,
      address: data.address.present ? data.address.value : this.address,
      referrer: data.referrer.present ? data.referrer.value : this.referrer,
      referrerId: data.referrerId.present
          ? data.referrerId.value
          : this.referrerId,
      points: data.points.present ? data.points.value : this.points,
      qr: data.qr.present ? data.qr.value : this.qr,
      idType: data.idType.present ? data.idType.value : this.idType,
      idNumber: data.idNumber.present ? data.idNumber.value : this.idNumber,
      idImagePath: data.idImagePath.present
          ? data.idImagePath.value
          : this.idImagePath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Member(')
          ..write('id: $id, ')
          ..write('lastName: $lastName, ')
          ..write('firstName: $firstName, ')
          ..write('middleName: $middleName, ')
          ..write('role: $role, ')
          ..write('contactNo: $contactNo, ')
          ..write('birthday: $birthday, ')
          ..write('address: $address, ')
          ..write('referrer: $referrer, ')
          ..write('referrerId: $referrerId, ')
          ..write('points: $points, ')
          ..write('qr: $qr, ')
          ..write('idType: $idType, ')
          ..write('idNumber: $idNumber, ')
          ..write('idImagePath: $idImagePath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    lastName,
    firstName,
    middleName,
    role,
    contactNo,
    birthday,
    address,
    referrer,
    referrerId,
    points,
    qr,
    idType,
    idNumber,
    idImagePath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Member &&
          other.id == this.id &&
          other.lastName == this.lastName &&
          other.firstName == this.firstName &&
          other.middleName == this.middleName &&
          other.role == this.role &&
          other.contactNo == this.contactNo &&
          other.birthday == this.birthday &&
          other.address == this.address &&
          other.referrer == this.referrer &&
          other.referrerId == this.referrerId &&
          other.points == this.points &&
          other.qr == this.qr &&
          other.idType == this.idType &&
          other.idNumber == this.idNumber &&
          other.idImagePath == this.idImagePath);
}

class MembersCompanion extends UpdateCompanion<Member> {
  final Value<int> id;
  final Value<String?> lastName;
  final Value<String?> firstName;
  final Value<String?> middleName;
  final Value<String?> role;
  final Value<String?> contactNo;
  final Value<String?> birthday;
  final Value<String?> address;
  final Value<String?> referrer;
  final Value<int?> referrerId;
  final Value<int> points;
  final Value<String?> qr;
  final Value<String?> idType;
  final Value<String?> idNumber;
  final Value<String?> idImagePath;
  const MembersCompanion({
    this.id = const Value.absent(),
    this.lastName = const Value.absent(),
    this.firstName = const Value.absent(),
    this.middleName = const Value.absent(),
    this.role = const Value.absent(),
    this.contactNo = const Value.absent(),
    this.birthday = const Value.absent(),
    this.address = const Value.absent(),
    this.referrer = const Value.absent(),
    this.referrerId = const Value.absent(),
    this.points = const Value.absent(),
    this.qr = const Value.absent(),
    this.idType = const Value.absent(),
    this.idNumber = const Value.absent(),
    this.idImagePath = const Value.absent(),
  });
  MembersCompanion.insert({
    this.id = const Value.absent(),
    this.lastName = const Value.absent(),
    this.firstName = const Value.absent(),
    this.middleName = const Value.absent(),
    this.role = const Value.absent(),
    this.contactNo = const Value.absent(),
    this.birthday = const Value.absent(),
    this.address = const Value.absent(),
    this.referrer = const Value.absent(),
    this.referrerId = const Value.absent(),
    this.points = const Value.absent(),
    this.qr = const Value.absent(),
    this.idType = const Value.absent(),
    this.idNumber = const Value.absent(),
    this.idImagePath = const Value.absent(),
  });
  static Insertable<Member> custom({
    Expression<int>? id,
    Expression<String>? lastName,
    Expression<String>? firstName,
    Expression<String>? middleName,
    Expression<String>? role,
    Expression<String>? contactNo,
    Expression<String>? birthday,
    Expression<String>? address,
    Expression<String>? referrer,
    Expression<int>? referrerId,
    Expression<int>? points,
    Expression<String>? qr,
    Expression<String>? idType,
    Expression<String>? idNumber,
    Expression<String>? idImagePath,
  }) {
    return RawValuesInsertable({
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
      if (points != null) 'points': points,
      if (qr != null) 'qr': qr,
      if (idType != null) 'id_type': idType,
      if (idNumber != null) 'id_number': idNumber,
      if (idImagePath != null) 'id_image_path': idImagePath,
    });
  }

  MembersCompanion copyWith({
    Value<int>? id,
    Value<String?>? lastName,
    Value<String?>? firstName,
    Value<String?>? middleName,
    Value<String?>? role,
    Value<String?>? contactNo,
    Value<String?>? birthday,
    Value<String?>? address,
    Value<String?>? referrer,
    Value<int?>? referrerId,
    Value<int>? points,
    Value<String?>? qr,
    Value<String?>? idType,
    Value<String?>? idNumber,
    Value<String?>? idImagePath,
  }) {
    return MembersCompanion(
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
      points: points ?? this.points,
      qr: qr ?? this.qr,
      idType: idType ?? this.idType,
      idNumber: idNumber ?? this.idNumber,
      idImagePath: idImagePath ?? this.idImagePath,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (middleName.present) {
      map['middle_name'] = Variable<String>(middleName.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (contactNo.present) {
      map['contact_no'] = Variable<String>(contactNo.value);
    }
    if (birthday.present) {
      map['birthday'] = Variable<String>(birthday.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (referrer.present) {
      map['referrer'] = Variable<String>(referrer.value);
    }
    if (referrerId.present) {
      map['referrer_id'] = Variable<int>(referrerId.value);
    }
    if (points.present) {
      map['points'] = Variable<int>(points.value);
    }
    if (qr.present) {
      map['qr'] = Variable<String>(qr.value);
    }
    if (idType.present) {
      map['id_type'] = Variable<String>(idType.value);
    }
    if (idNumber.present) {
      map['id_number'] = Variable<String>(idNumber.value);
    }
    if (idImagePath.present) {
      map['id_image_path'] = Variable<String>(idImagePath.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembersCompanion(')
          ..write('id: $id, ')
          ..write('lastName: $lastName, ')
          ..write('firstName: $firstName, ')
          ..write('middleName: $middleName, ')
          ..write('role: $role, ')
          ..write('contactNo: $contactNo, ')
          ..write('birthday: $birthday, ')
          ..write('address: $address, ')
          ..write('referrer: $referrer, ')
          ..write('referrerId: $referrerId, ')
          ..write('points: $points, ')
          ..write('qr: $qr, ')
          ..write('idType: $idType, ')
          ..write('idNumber: $idNumber, ')
          ..write('idImagePath: $idImagePath')
          ..write(')'))
        .toString();
  }
}

class $SalesTable extends Sales with TableInfo<$SalesTable, Sale> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<int> itemId = GeneratedColumn<int>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _buyerIdMeta = const VerificationMeta(
    'buyerId',
  );
  @override
  late final GeneratedColumn<int> buyerId = GeneratedColumn<int>(
    'buyer_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _itemNameMeta = const VerificationMeta(
    'itemName',
  );
  @override
  late final GeneratedColumn<String> itemName = GeneratedColumn<String>(
    'item_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pointsMeta = const VerificationMeta('points');
  @override
  late final GeneratedColumn<int> points = GeneratedColumn<int>(
    'points',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<int> price = GeneratedColumn<int>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    itemId,
    buyerId,
    itemName,
    quantity,
    points,
    price,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sales';
  @override
  VerificationContext validateIntegrity(
    Insertable<Sale> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('buyer_id')) {
      context.handle(
        _buyerIdMeta,
        buyerId.isAcceptableOrUnknown(data['buyer_id']!, _buyerIdMeta),
      );
    }
    if (data.containsKey('item_name')) {
      context.handle(
        _itemNameMeta,
        itemName.isAcceptableOrUnknown(data['item_name']!, _itemNameMeta),
      );
    } else if (isInserting) {
      context.missing(_itemNameMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('points')) {
      context.handle(
        _pointsMeta,
        points.isAcceptableOrUnknown(data['points']!, _pointsMeta),
      );
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Sale map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Sale(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}item_id'],
      )!,
      buyerId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}buyer_id'],
      ),
      itemName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_name'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      points: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}points'],
      )!,
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $SalesTable createAlias(String alias) {
    return $SalesTable(attachedDatabase, alias);
  }
}

class Sale extends DataClass implements Insertable<Sale> {
  final int id;
  final int itemId;
  final int? buyerId;
  final String itemName;
  final int quantity;
  final int points;
  final int price;
  final DateTime timestamp;
  const Sale({
    required this.id,
    required this.itemId,
    this.buyerId,
    required this.itemName,
    required this.quantity,
    required this.points,
    required this.price,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['item_id'] = Variable<int>(itemId);
    if (!nullToAbsent || buyerId != null) {
      map['buyer_id'] = Variable<int>(buyerId);
    }
    map['item_name'] = Variable<String>(itemName);
    map['quantity'] = Variable<int>(quantity);
    map['points'] = Variable<int>(points);
    map['price'] = Variable<int>(price);
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  SalesCompanion toCompanion(bool nullToAbsent) {
    return SalesCompanion(
      id: Value(id),
      itemId: Value(itemId),
      buyerId: buyerId == null && nullToAbsent
          ? const Value.absent()
          : Value(buyerId),
      itemName: Value(itemName),
      quantity: Value(quantity),
      points: Value(points),
      price: Value(price),
      timestamp: Value(timestamp),
    );
  }

  factory Sale.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Sale(
      id: serializer.fromJson<int>(json['id']),
      itemId: serializer.fromJson<int>(json['itemId']),
      buyerId: serializer.fromJson<int?>(json['buyerId']),
      itemName: serializer.fromJson<String>(json['itemName']),
      quantity: serializer.fromJson<int>(json['quantity']),
      points: serializer.fromJson<int>(json['points']),
      price: serializer.fromJson<int>(json['price']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'itemId': serializer.toJson<int>(itemId),
      'buyerId': serializer.toJson<int?>(buyerId),
      'itemName': serializer.toJson<String>(itemName),
      'quantity': serializer.toJson<int>(quantity),
      'points': serializer.toJson<int>(points),
      'price': serializer.toJson<int>(price),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  Sale copyWith({
    int? id,
    int? itemId,
    Value<int?> buyerId = const Value.absent(),
    String? itemName,
    int? quantity,
    int? points,
    int? price,
    DateTime? timestamp,
  }) => Sale(
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    buyerId: buyerId.present ? buyerId.value : this.buyerId,
    itemName: itemName ?? this.itemName,
    quantity: quantity ?? this.quantity,
    points: points ?? this.points,
    price: price ?? this.price,
    timestamp: timestamp ?? this.timestamp,
  );
  Sale copyWithCompanion(SalesCompanion data) {
    return Sale(
      id: data.id.present ? data.id.value : this.id,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      buyerId: data.buyerId.present ? data.buyerId.value : this.buyerId,
      itemName: data.itemName.present ? data.itemName.value : this.itemName,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      points: data.points.present ? data.points.value : this.points,
      price: data.price.present ? data.price.value : this.price,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Sale(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('buyerId: $buyerId, ')
          ..write('itemName: $itemName, ')
          ..write('quantity: $quantity, ')
          ..write('points: $points, ')
          ..write('price: $price, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    itemId,
    buyerId,
    itemName,
    quantity,
    points,
    price,
    timestamp,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Sale &&
          other.id == this.id &&
          other.itemId == this.itemId &&
          other.buyerId == this.buyerId &&
          other.itemName == this.itemName &&
          other.quantity == this.quantity &&
          other.points == this.points &&
          other.price == this.price &&
          other.timestamp == this.timestamp);
}

class SalesCompanion extends UpdateCompanion<Sale> {
  final Value<int> id;
  final Value<int> itemId;
  final Value<int?> buyerId;
  final Value<String> itemName;
  final Value<int> quantity;
  final Value<int> points;
  final Value<int> price;
  final Value<DateTime> timestamp;
  const SalesCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.buyerId = const Value.absent(),
    this.itemName = const Value.absent(),
    this.quantity = const Value.absent(),
    this.points = const Value.absent(),
    this.price = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  SalesCompanion.insert({
    this.id = const Value.absent(),
    required int itemId,
    this.buyerId = const Value.absent(),
    required String itemName,
    required int quantity,
    this.points = const Value.absent(),
    this.price = const Value.absent(),
    this.timestamp = const Value.absent(),
  }) : itemId = Value(itemId),
       itemName = Value(itemName),
       quantity = Value(quantity);
  static Insertable<Sale> custom({
    Expression<int>? id,
    Expression<int>? itemId,
    Expression<int>? buyerId,
    Expression<String>? itemName,
    Expression<int>? quantity,
    Expression<int>? points,
    Expression<int>? price,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (buyerId != null) 'buyer_id': buyerId,
      if (itemName != null) 'item_name': itemName,
      if (quantity != null) 'quantity': quantity,
      if (points != null) 'points': points,
      if (price != null) 'price': price,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  SalesCompanion copyWith({
    Value<int>? id,
    Value<int>? itemId,
    Value<int?>? buyerId,
    Value<String>? itemName,
    Value<int>? quantity,
    Value<int>? points,
    Value<int>? price,
    Value<DateTime>? timestamp,
  }) {
    return SalesCompanion(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      buyerId: buyerId ?? this.buyerId,
      itemName: itemName ?? this.itemName,
      quantity: quantity ?? this.quantity,
      points: points ?? this.points,
      price: price ?? this.price,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<int>(itemId.value);
    }
    if (buyerId.present) {
      map['buyer_id'] = Variable<int>(buyerId.value);
    }
    if (itemName.present) {
      map['item_name'] = Variable<String>(itemName.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (points.present) {
      map['points'] = Variable<int>(points.value);
    }
    if (price.present) {
      map['price'] = Variable<int>(price.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SalesCompanion(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('buyerId: $buyerId, ')
          ..write('itemName: $itemName, ')
          ..write('quantity: $quantity, ')
          ..write('points: $points, ')
          ..write('price: $price, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $ItemsTable items = $ItemsTable(this);
  late final $MembersTable members = $MembersTable(this);
  late final $SalesTable sales = $SalesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [items, members, sales];
}

typedef $$ItemsTableCreateCompanionBuilder =
    ItemsCompanion Function({
      Value<int> id,
      required String name,
      Value<int> points,
      Value<String?> category,
      Value<int> stock,
      Value<DateTime?> lastUpdated,
      Value<String?> status,
    });
typedef $$ItemsTableUpdateCompanionBuilder =
    ItemsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> points,
      Value<String?> category,
      Value<int> stock,
      Value<DateTime?> lastUpdated,
      Value<String?> status,
    });

class $$ItemsTableFilterComposer extends Composer<_$AppDb, $ItemsTable> {
  $$ItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get points => $composableBuilder(
    column: $table.points,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stock => $composableBuilder(
    column: $table.stock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ItemsTableOrderingComposer extends Composer<_$AppDb, $ItemsTable> {
  $$ItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get points => $composableBuilder(
    column: $table.points,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stock => $composableBuilder(
    column: $table.stock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ItemsTableAnnotationComposer extends Composer<_$AppDb, $ItemsTable> {
  $$ItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get points =>
      $composableBuilder(column: $table.points, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<int> get stock =>
      $composableBuilder(column: $table.stock, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$ItemsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $ItemsTable,
          Item,
          $$ItemsTableFilterComposer,
          $$ItemsTableOrderingComposer,
          $$ItemsTableAnnotationComposer,
          $$ItemsTableCreateCompanionBuilder,
          $$ItemsTableUpdateCompanionBuilder,
          (Item, BaseReferences<_$AppDb, $ItemsTable, Item>),
          Item,
          PrefetchHooks Function()
        > {
  $$ItemsTableTableManager(_$AppDb db, $ItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> points = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<int> stock = const Value.absent(),
                Value<DateTime?> lastUpdated = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => ItemsCompanion(
                id: id,
                name: name,
                points: points,
                category: category,
                stock: stock,
                lastUpdated: lastUpdated,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<int> points = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<int> stock = const Value.absent(),
                Value<DateTime?> lastUpdated = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => ItemsCompanion.insert(
                id: id,
                name: name,
                points: points,
                category: category,
                stock: stock,
                lastUpdated: lastUpdated,
                status: status,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $ItemsTable,
      Item,
      $$ItemsTableFilterComposer,
      $$ItemsTableOrderingComposer,
      $$ItemsTableAnnotationComposer,
      $$ItemsTableCreateCompanionBuilder,
      $$ItemsTableUpdateCompanionBuilder,
      (Item, BaseReferences<_$AppDb, $ItemsTable, Item>),
      Item,
      PrefetchHooks Function()
    >;
typedef $$MembersTableCreateCompanionBuilder =
    MembersCompanion Function({
      Value<int> id,
      Value<String?> lastName,
      Value<String?> firstName,
      Value<String?> middleName,
      Value<String?> role,
      Value<String?> contactNo,
      Value<String?> birthday,
      Value<String?> address,
      Value<String?> referrer,
      Value<int?> referrerId,
      Value<int> points,
      Value<String?> qr,
      Value<String?> idType,
      Value<String?> idNumber,
      Value<String?> idImagePath,
    });
typedef $$MembersTableUpdateCompanionBuilder =
    MembersCompanion Function({
      Value<int> id,
      Value<String?> lastName,
      Value<String?> firstName,
      Value<String?> middleName,
      Value<String?> role,
      Value<String?> contactNo,
      Value<String?> birthday,
      Value<String?> address,
      Value<String?> referrer,
      Value<int?> referrerId,
      Value<int> points,
      Value<String?> qr,
      Value<String?> idType,
      Value<String?> idNumber,
      Value<String?> idImagePath,
    });

class $$MembersTableFilterComposer extends Composer<_$AppDb, $MembersTable> {
  $$MembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get middleName => $composableBuilder(
    column: $table.middleName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactNo => $composableBuilder(
    column: $table.contactNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get birthday => $composableBuilder(
    column: $table.birthday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referrer => $composableBuilder(
    column: $table.referrer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get referrerId => $composableBuilder(
    column: $table.referrerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get points => $composableBuilder(
    column: $table.points,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get qr => $composableBuilder(
    column: $table.qr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idType => $composableBuilder(
    column: $table.idType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idNumber => $composableBuilder(
    column: $table.idNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idImagePath => $composableBuilder(
    column: $table.idImagePath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MembersTableOrderingComposer extends Composer<_$AppDb, $MembersTable> {
  $$MembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get middleName => $composableBuilder(
    column: $table.middleName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactNo => $composableBuilder(
    column: $table.contactNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get birthday => $composableBuilder(
    column: $table.birthday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referrer => $composableBuilder(
    column: $table.referrer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get referrerId => $composableBuilder(
    column: $table.referrerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get points => $composableBuilder(
    column: $table.points,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get qr => $composableBuilder(
    column: $table.qr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idType => $composableBuilder(
    column: $table.idType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idNumber => $composableBuilder(
    column: $table.idNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idImagePath => $composableBuilder(
    column: $table.idImagePath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MembersTableAnnotationComposer
    extends Composer<_$AppDb, $MembersTable> {
  $$MembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get middleName => $composableBuilder(
    column: $table.middleName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get contactNo =>
      $composableBuilder(column: $table.contactNo, builder: (column) => column);

  GeneratedColumn<String> get birthday =>
      $composableBuilder(column: $table.birthday, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get referrer =>
      $composableBuilder(column: $table.referrer, builder: (column) => column);

  GeneratedColumn<int> get referrerId => $composableBuilder(
    column: $table.referrerId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get points =>
      $composableBuilder(column: $table.points, builder: (column) => column);

  GeneratedColumn<String> get qr =>
      $composableBuilder(column: $table.qr, builder: (column) => column);

  GeneratedColumn<String> get idType =>
      $composableBuilder(column: $table.idType, builder: (column) => column);

  GeneratedColumn<String> get idNumber =>
      $composableBuilder(column: $table.idNumber, builder: (column) => column);

  GeneratedColumn<String> get idImagePath => $composableBuilder(
    column: $table.idImagePath,
    builder: (column) => column,
  );
}

class $$MembersTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $MembersTable,
          Member,
          $$MembersTableFilterComposer,
          $$MembersTableOrderingComposer,
          $$MembersTableAnnotationComposer,
          $$MembersTableCreateCompanionBuilder,
          $$MembersTableUpdateCompanionBuilder,
          (Member, BaseReferences<_$AppDb, $MembersTable, Member>),
          Member,
          PrefetchHooks Function()
        > {
  $$MembersTableTableManager(_$AppDb db, $MembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> lastName = const Value.absent(),
                Value<String?> firstName = const Value.absent(),
                Value<String?> middleName = const Value.absent(),
                Value<String?> role = const Value.absent(),
                Value<String?> contactNo = const Value.absent(),
                Value<String?> birthday = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> referrer = const Value.absent(),
                Value<int?> referrerId = const Value.absent(),
                Value<int> points = const Value.absent(),
                Value<String?> qr = const Value.absent(),
                Value<String?> idType = const Value.absent(),
                Value<String?> idNumber = const Value.absent(),
                Value<String?> idImagePath = const Value.absent(),
              }) => MembersCompanion(
                id: id,
                lastName: lastName,
                firstName: firstName,
                middleName: middleName,
                role: role,
                contactNo: contactNo,
                birthday: birthday,
                address: address,
                referrer: referrer,
                referrerId: referrerId,
                points: points,
                qr: qr,
                idType: idType,
                idNumber: idNumber,
                idImagePath: idImagePath,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> lastName = const Value.absent(),
                Value<String?> firstName = const Value.absent(),
                Value<String?> middleName = const Value.absent(),
                Value<String?> role = const Value.absent(),
                Value<String?> contactNo = const Value.absent(),
                Value<String?> birthday = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> referrer = const Value.absent(),
                Value<int?> referrerId = const Value.absent(),
                Value<int> points = const Value.absent(),
                Value<String?> qr = const Value.absent(),
                Value<String?> idType = const Value.absent(),
                Value<String?> idNumber = const Value.absent(),
                Value<String?> idImagePath = const Value.absent(),
              }) => MembersCompanion.insert(
                id: id,
                lastName: lastName,
                firstName: firstName,
                middleName: middleName,
                role: role,
                contactNo: contactNo,
                birthday: birthday,
                address: address,
                referrer: referrer,
                referrerId: referrerId,
                points: points,
                qr: qr,
                idType: idType,
                idNumber: idNumber,
                idImagePath: idImagePath,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MembersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $MembersTable,
      Member,
      $$MembersTableFilterComposer,
      $$MembersTableOrderingComposer,
      $$MembersTableAnnotationComposer,
      $$MembersTableCreateCompanionBuilder,
      $$MembersTableUpdateCompanionBuilder,
      (Member, BaseReferences<_$AppDb, $MembersTable, Member>),
      Member,
      PrefetchHooks Function()
    >;
typedef $$SalesTableCreateCompanionBuilder =
    SalesCompanion Function({
      Value<int> id,
      required int itemId,
      Value<int?> buyerId,
      required String itemName,
      required int quantity,
      Value<int> points,
      Value<int> price,
      Value<DateTime> timestamp,
    });
typedef $$SalesTableUpdateCompanionBuilder =
    SalesCompanion Function({
      Value<int> id,
      Value<int> itemId,
      Value<int?> buyerId,
      Value<String> itemName,
      Value<int> quantity,
      Value<int> points,
      Value<int> price,
      Value<DateTime> timestamp,
    });

class $$SalesTableFilterComposer extends Composer<_$AppDb, $SalesTable> {
  $$SalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get buyerId => $composableBuilder(
    column: $table.buyerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemName => $composableBuilder(
    column: $table.itemName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get points => $composableBuilder(
    column: $table.points,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SalesTableOrderingComposer extends Composer<_$AppDb, $SalesTable> {
  $$SalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get buyerId => $composableBuilder(
    column: $table.buyerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemName => $composableBuilder(
    column: $table.itemName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get points => $composableBuilder(
    column: $table.points,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SalesTableAnnotationComposer extends Composer<_$AppDb, $SalesTable> {
  $$SalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<int> get buyerId =>
      $composableBuilder(column: $table.buyerId, builder: (column) => column);

  GeneratedColumn<String> get itemName =>
      $composableBuilder(column: $table.itemName, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get points =>
      $composableBuilder(column: $table.points, builder: (column) => column);

  GeneratedColumn<int> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $$SalesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $SalesTable,
          Sale,
          $$SalesTableFilterComposer,
          $$SalesTableOrderingComposer,
          $$SalesTableAnnotationComposer,
          $$SalesTableCreateCompanionBuilder,
          $$SalesTableUpdateCompanionBuilder,
          (Sale, BaseReferences<_$AppDb, $SalesTable, Sale>),
          Sale,
          PrefetchHooks Function()
        > {
  $$SalesTableTableManager(_$AppDb db, $SalesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SalesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> itemId = const Value.absent(),
                Value<int?> buyerId = const Value.absent(),
                Value<String> itemName = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                Value<int> points = const Value.absent(),
                Value<int> price = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
              }) => SalesCompanion(
                id: id,
                itemId: itemId,
                buyerId: buyerId,
                itemName: itemName,
                quantity: quantity,
                points: points,
                price: price,
                timestamp: timestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int itemId,
                Value<int?> buyerId = const Value.absent(),
                required String itemName,
                required int quantity,
                Value<int> points = const Value.absent(),
                Value<int> price = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
              }) => SalesCompanion.insert(
                id: id,
                itemId: itemId,
                buyerId: buyerId,
                itemName: itemName,
                quantity: quantity,
                points: points,
                price: price,
                timestamp: timestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SalesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $SalesTable,
      Sale,
      $$SalesTableFilterComposer,
      $$SalesTableOrderingComposer,
      $$SalesTableAnnotationComposer,
      $$SalesTableCreateCompanionBuilder,
      $$SalesTableUpdateCompanionBuilder,
      (Sale, BaseReferences<_$AppDb, $SalesTable, Sale>),
      Sale,
      PrefetchHooks Function()
    >;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db, _db.items);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db, _db.members);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db, _db.sales);
}
