// lib/db/db_repository.dart

import 'dart:async';

import 'package:drift/drift.dart';
import 'dart:math';
import 'app_db.dart';
import 'package:csv/csv.dart';
import 'csv_io.dart';

/// Repository that wraps AppDb and provides higher-level business operations
/// (imports, exports, atomic transactions, change notifications).
class DbRepository {
  final AppDb db;
  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  DbRepository(this.db);

  String _generateMemberQr() {
    final rnd = Random();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${rnd.nextInt(1 << 32).toRadixString(16)}';
  }

  Stream<String> get changes => _changes.stream;

  void notifyCloudRestored() {
    _changes.add('item_imported');
    _changes.add('member_imported');
    _changes.add('sale_imported');
    _changes.add('cloud_restored');
  }

  /// Import members from CSV string, return inserted count.
  Future<int> importMembersCsv(String csv) async {
    final converter = const CsvToListConverter(eol: '\n');
    final list = converter.convert(csv);
    if (list.isEmpty) return 0;
    final headers = list.first.map((e) => e.toString()).toList();
    final rows = list
        .sublist(1)
        .map((r) => r.map((c) => c?.toString() ?? '').toList())
        .toList();
    return await importMembersFromRows(headers, rows);
  }

  /// Migration helper to ensure existing sales.points and member.points follow
  /// the current business rule: sale.points == item.points * quantity and
  /// member.points == sum of their sales.points. This is idempotent and safe
  /// to run at startup; it updates rows in a transaction.
  /// -- DEPRECATED: points system removed. Method kept as no-op for compatibility.
  Future<void> ensurePointsConsistency() async {
    // Points system removed — no-op.
  }

  /// One-time fix: upgrade any member with an ID photo from "Member" to
  /// "Verified Reseller". Safe to run at startup — idempotent.
  Future<void> ensureVerifiedResellerConsistency() async {
    final all = await db.getAllMembers();
    for (final m in all) {
      final hasId = (m.idImagePath ?? '').isNotEmpty;
      if (hasId && m.role != 'Verified Reseller') {
        final updated = m.copyWith(role: const Value('Verified Reseller'));
        await db.updateMemberData(updated);
      }
    }
    if (all.any(
      (m) => (m.idImagePath ?? '').isNotEmpty && m.role != 'Verified Reseller',
    )) {
      _changes.add('member_updated');
    }
  }

  /// Bulk import helper that accepts parsed headers and rows (each row is a list of strings aligned to headers).
  /// Returns number of newly created members.
  Future<int> importMembersFromRows(
    List<String> headers,
    List<List<String>> rows,
  ) async {
    var inserted = 0;
    for (final row in rows) {
      final map = <String, String>{};
      for (var i = 0; i < headers.length && i < row.length; i++) {
        map[headers[i]] = row[i];
      }
      final lastName = (map['lastName'] ?? '').trim();
      final firstName = (map['firstName'] ?? '').trim();
      if (lastName.isEmpty && firstName.isEmpty) continue;

      final idStr = (map['id'] ?? '').trim();
      int? id = idStr.isNotEmpty ? int.tryParse(idStr) : null;

      // If id exists and member found, update and continue (no tx import)
      if (id != null) {
        final existing = await db.getMemberById(id);
        if (existing != null) {
          final updated = existing.copyWith(
            lastName: Value(lastName.isEmpty ? null : lastName),
            firstName: Value(firstName.isEmpty ? null : firstName),
            middleName: Value(
              (map['middleName'] ?? '').trim().isEmpty
                  ? null
                  : (map['middleName'] ?? '').trim(),
            ),
            role: Value(
              (map['role'] ?? '').trim().isEmpty
                  ? null
                  : (map['role'] ?? '').trim(),
            ),
            contactNo: Value(
              (map['contactNo'] ?? '').trim().isEmpty
                  ? null
                  : (map['contactNo'] ?? '').trim(),
            ),
            birthday: Value(
              (map['birthday'] ?? '').trim().isEmpty
                  ? null
                  : (map['birthday'] ?? '').trim(),
            ),
            address: Value(
              (map['address'] ?? '').trim().isEmpty
                  ? null
                  : (map['address'] ?? '').trim(),
            ),
            referrer: Value(
              (map['referrer'] ?? '').trim().isEmpty
                  ? null
                  : (map['referrer'] ?? '').trim(),
            ),
            level: int.tryParse((map['level'] ?? '').trim()) ?? 1,
          );
          await db.updateMemberData(updated);
          continue;
        }
      }

      // Name match
      final all = await db.getAllMembers();
      Member? byName;
      try {
        final targetLast = lastName.toLowerCase();
        final targetFirst = firstName.toLowerCase();
        byName = all.firstWhere(
          (r) =>
              (r.lastName ?? '').trim().toLowerCase() == targetLast &&
              (r.firstName ?? '').trim().toLowerCase() == targetFirst,
        );
      } catch (e) {
        byName = null;
      }
      if (byName != null) {
        final updated = byName.copyWith(
          middleName: Value(
            (map['middleName'] ?? '').trim().isEmpty
                ? null
                : (map['middleName'] ?? '').trim(),
          ),
          role: Value(
            (map['role'] ?? '').trim().isEmpty
                ? null
                : (map['role'] ?? '').trim(),
          ),
          contactNo: Value(
            (map['contactNo'] ?? '').trim().isEmpty
                ? null
                : (map['contactNo'] ?? '').trim(),
          ),
          birthday: Value(
            (map['birthday'] ?? '').trim().isEmpty
                ? null
                : (map['birthday'] ?? '').trim(),
          ),
          address: Value(
            (map['address'] ?? '').trim().isEmpty
                ? null
                : (map['address'] ?? '').trim(),
          ),
          referrer: Value(
            (map['referrer'] ?? '').trim().isEmpty
                ? null
                : (map['referrer'] ?? '').trim(),
          ),
          level: int.tryParse((map['level'] ?? '').trim()) ?? 1,
        );
        await db.updateMemberData(updated);
        continue;
      }

      final companion = MembersCompanion.insert(
        lastName: Value(lastName.isEmpty ? null : lastName),
        firstName: Value(firstName.isEmpty ? null : firstName),
        middleName: Value(
          (map['middleName'] ?? '').trim().isEmpty
              ? null
              : (map['middleName'] ?? '').trim(),
        ),
        role: Value(
          (map['role'] ?? '').trim().isEmpty
              ? null
              : (map['role'] ?? '').trim(),
        ),
        contactNo: Value(
          (map['contactNo'] ?? '').trim().isEmpty
              ? null
              : (map['contactNo'] ?? '').trim(),
        ),
        birthday: Value(
          (map['birthday'] ?? '').trim().isEmpty
              ? null
              : (map['birthday'] ?? '').trim(),
        ),
        address: Value(
          (map['address'] ?? '').trim().isEmpty
              ? null
              : (map['address'] ?? '').trim(),
        ),
        referrer: Value(
          (map['referrer'] ?? '').trim().isEmpty
              ? null
              : (map['referrer'] ?? '').trim(),
        ),
        level: Value(int.tryParse((map['level'] ?? '').trim()) ?? 1),
        qr: Value(_generateMemberQr()),
        idType: Value(
          (map['idType'] ?? '').trim().isEmpty
              ? null
              : (map['idType'] ?? '').trim(),
        ),
        idNumber: Value(
          (map['idNumber'] ?? '').trim().isEmpty
              ? null
              : (map['idNumber'] ?? '').trim(),
        ),
        idImagePath: Value(
          (map['idImagePath'] ?? '').trim().isEmpty
              ? null
              : (map['idImagePath'] ?? '').trim(),
        ),
      );

      final memberId = await db.insertMember(companion);

      // parse transactions field (if any) using shared parser to ensure
      // timestamp formats (ISO or epoch) are handled consistently
      final txRaw = (map['transactions'] ?? '').trim();
      final List<MemberTransactionEntry> entries = [];
      if (txRaw.isNotEmpty) {
        final parsed = parseMemberTransactionsColumn(txRaw);
        for (final p in parsed) {
          entries.add(
            MemberTransactionEntry(
              itemId: p['itemId'] as int? ?? 0,
              itemName: p['itemName'] as String? ?? '',
              quantity: p['quantity'] as int? ?? 0,
              price: p['price'] as int? ?? 0,
              timestamp: p['timestamp'] as DateTime?,
            ),
          );
        }
      }

      // If there are parsed transactions, commit them atomically. If commit fails, continue but log.
      if (entries.isNotEmpty) {
        final err = await commitMemberTransactions(
          memberId,
          entries,
          applyEffects: false,
        );
        if (err != null) {
          // Log the error and continue importing other members
          // ignore: avoid_print
          print('commitMemberTransactions failed for member $memberId: $err');
        }
      }

      inserted++;
    }

    if (inserted > 0) _changes.add('member_imported');
    return inserted;
  }

  /// Small DTO for parsed transaction entries coming from member CSV import.
  /// timestamp may be null to use current time.
  Future<String?> commitMemberTransactions(
    int memberId,
    List<MemberTransactionEntry> entries, {
    bool applyEffects = true,
  }) async {
    return await db.transaction(() async {
      final buyer = await db.getMemberById(memberId);
      if (buyer == null) return 'Member not found';

      final Map<int, Item> itemCache = {};
      for (final e in entries) {
        final itemId = e.itemId;
        Item? item;
        if (itemId != null && itemId > 0) {
          item = await db.getItemById(itemId);
        }
        if (item == null) {
          final all = await db.getAllItems();
          try {
            item = all.firstWhere(
              (it) =>
                  it.name.trim().toLowerCase() ==
                  e.itemName.trim().toLowerCase(),
            );
          } catch (_) {
            item = null;
          }
        }
        if (item == null) return 'Item ${e.itemName} not found';
        itemCache[item.id] = item;
        if (item.stock < e.quantity) {
          return 'Insufficient stock for ${item.name}';
        }
      }

      final now = DateTime.now();
      final existingSales = await db.getAllSales();

      for (final e in entries) {
        final item = itemCache.values.firstWhere(
          (it) =>
              it.name.trim().toLowerCase() == e.itemName.trim().toLowerCase(),
        );

        final duplicate = existingSales.any((s) {
          final sameCore =
              s.itemId == item.id &&
              s.itemName == e.itemName &&
              s.quantity == e.quantity &&
              s.price == e.price &&
              (s.buyerId == memberId);
          if (!sameCore) return false;
          if (e.timestamp != null) {
            return s.timestamp.toIso8601String() ==
                e.timestamp!.toIso8601String();
          }
          return true;
        });
        if (duplicate) continue;

        final saleComp = SalesCompanion.insert(
          itemId: item.id,
          buyerId: Value(memberId),
          itemName: e.itemName,
          quantity: e.quantity,
          price: Value(e.price),
          timestamp: Value(e.timestamp ?? now),
        );
        final insertedId = await db.insertSale(saleComp);

        if (applyEffects) {
          final updatedItem = item.copyWith(
            stock: item.stock - e.quantity,
            lastUpdated: Value(now),
          );
          await db.update(db.items).replace(updatedItem);
        }

        // write audit row into member_transactions table
        try {
          final tsVal = (e.timestamp ?? now).millisecondsSinceEpoch;
          await db.customInsert(
            'INSERT INTO member_transactions (member_id, sale_id, item_id, item_name, quantity, price, timestamp) VALUES (?,?,?,?,?,?,?)',
            variables: [
              Variable.withInt(memberId),
              Variable.withInt(insertedId),
              Variable.withInt(item.id),
              Variable.withString(e.itemName),
              Variable.withInt(e.quantity),
              Variable.withInt(e.price),
              Variable.withInt(tsVal),
            ],
          );
        } catch (_) {
          // ignore audit failures
        }
      }

      _changes.add('member_transactions_committed');
      _changes.add('sale_added');
      _changes.add('item_updated');
      return null;
    });
  }

  // Sales CSV helpers
  /// Export sales to CSV file and return the file path.
  Future<String> exportSalesCsv() => exportSalesToCsvFile(db);

  /// Return CSV content for sales as string (UI can show a save dialog).
  Future<String> exportSalesCsvString() => exportSalesToCsvString(db);

  /// Import sales from CSV string; returns number of rows inserted.
  Future<int> importSalesCsv(String csv) async {
    // Default import: treat sales as historical (do not apply stock).
    final count = await importSalesFromCsvString(db, csv, applyEffects: false);
    if (count > 0) {
      _changes.add('sale_imported');
    }
    return count;
  }

  // Sales helpers
  Future<int> addSale({
    required int itemId,
    required String itemName,
    required int quantity,
    int price = 0,
    DateTime? timestamp,
    int? buyerId,
  }) async {
    final companion = SalesCompanion.insert(
      itemId: itemId,
      buyerId: Value(buyerId),
      itemName: itemName,
      quantity: quantity,
      price: Value(price),
      timestamp: timestamp == null ? const Value.absent() : Value(timestamp),
    );
    final id = await db.insertSale(companion);
    // notify listeners that a sale was added
    _changes.add('sale_added');
    return id;
  }

  /// Update an item and notify listeners
  Future<bool> updateItem(Item item) async {
    final res = await db.updateItemData(item);
    _changes.add('item_updated');
    return res;
  }

  /// Update a member and notify listeners
  Future<bool> updateMember(Member member) async {
    final res = await db.updateMemberData(member);
    _changes.add('member_updated');
    return res;
  }

  /// Delete item helper
  Future<int> deleteItemById(int id) => db.deleteItemById(id);

  /// Add item helper
  Future<int> addItem({
    required String name,
    String? category,
    int stock = 0,
    DateTime? lastUpdated,
    String? status,
  }) async {
    final companion = ItemsCompanion.insert(
      name: name,
      category: Value(category == null || category.isEmpty ? null : category),
      stock: Value(stock),
      lastUpdated: Value(lastUpdated),
      status: Value(status == null || status.isEmpty ? null : status),
    );
    final id = await db.insertItem(companion);
    _changes.add('item_added');
    return id;
  }

  /// Import items CSV wrapper
  Future<int> importItemsCsv(String csv) async {
    final cnt = await importItemsFromCsvString(db, csv);
    if (cnt > 0) _changes.add('item_imported');
    return cnt;
  }

  // ── Reseller Level Management ──────────────────────────────────────

  /// Export items CSV content as string
  Future<String> exportItemsCsvString() => exportItemsToCsvString(db);

  /// Export items CSV to file and return path
  Future<String> exportItemsCsv() => exportItemsToCsvFile(db);

  /// Lookup a member by id.
  Future<Member?> getMemberById(int id) => db.getMemberById(id);

  /// Return all members (convenience wrapper)
  Future<List<Member>> fetchMembers() => db.getAllMembers();

  /// Return all items (convenience wrapper)
  Future<List<Item>> fetchItems() => db.getAllItems();

  /// Add a member with provided fields. Returns inserted id.
  Future<int> addMember({
    String? lastName,
    String? firstName,
    String? middleName,
    String? role,
    String? contactNo,
    String? birthday,
    String? address,
    String? referrer,
    int level = 1,
    String? idType,
    String? idNumber,
    String? idImagePath,
  }) async {
    final companion = MembersCompanion.insert(
      lastName: Value(lastName == null || lastName.isEmpty ? null : lastName),
      firstName: Value(
        firstName == null || firstName.isEmpty ? null : firstName,
      ),
      middleName: Value(
        middleName == null || middleName.isEmpty ? null : middleName,
      ),
      role: Value(role == null || role.isEmpty ? null : role),
      contactNo: Value(
        contactNo == null || contactNo.isEmpty ? null : contactNo,
      ),
      birthday: Value(birthday == null || birthday.isEmpty ? null : birthday),
      address: Value(address == null || address.isEmpty ? null : address),
      referrer: Value(referrer == null || referrer.isEmpty ? null : referrer),
      level: Value(level),
      qr: Value(_generateMemberQr()),
      idType: Value(idType == null || idType.isEmpty ? null : idType),
      idNumber: Value(idNumber == null || idNumber.isEmpty ? null : idNumber),
      idImagePath: Value(
        idImagePath == null || idImagePath.isEmpty ? null : idImagePath,
      ),
    );
    final id = await db.insertMember(companion);
    _changes.add('member_added');
    return id;
  }

  /// Verify a member as a reseller by setting their role to "Verified Reseller".
  /// Does nothing if the member doesn't exist or is already verified.
  Future<bool> verifyAsReseller(int memberId) async {
    final member = await db.getMemberById(memberId);
    if (member == null) return false;
    if (member.role == 'Verified Reseller') return true; // already verified

    final updated = member.copyWith(role: const Value('Verified Reseller'));
    await db.updateMemberData(updated);
    _changes.add('member_updated');
    _changes.add('member_verified');
    return true;
  }

  /// Export members CSV content as string
  Future<String> exportMembersCsvString() => exportMembersToCsvString(db);

  /// Export members CSV to file and return path
  Future<String> exportMembersCsv() => exportMembersToCsvFile(db);

  Future<List<Sale>> fetchSales() => db.getAllSales();

  Future<List<Sale>> fetchSalesBetween(DateTime start, DateTime end) =>
      db.getSalesBetween(start, end);

  /// Return sales where buyerId == memberId
  Future<List<Sale>> fetchSalesForMember(int memberId) async {
    final all = await db.getAllSales();
    return all.where((s) => s.buyerId == memberId).toList();
  }

  /// Return sales made by members who were referred by `referrerMemberId`.
  /// This resolves both numeric referrerId and legacy referrer string matching.
  Future<List<Sale>> fetchSalesForReferrer(int referrerMemberId) async {
    final allSales = await db.getAllSales();
    final List<Sale> out = [];
    final refMember = await db.getMemberById(referrerMemberId);
    final refName = refMember != null
        ? '${refMember.firstName ?? ''} ${refMember.lastName ?? ''}'
              .trim()
              .toLowerCase()
        : '';
    for (final s in allSales) {
      if (s.buyerId == null) continue;
      final buyer = await db.getMemberById(s.buyerId!);
      if (buyer == null) continue;
      if (buyer.referrerId != null && buyer.referrerId == referrerMemberId) {
        out.add(s);
        continue;
      }
      final refRaw = (buyer.referrer ?? '').toString();
      if (refRaw.isNotEmpty &&
          refName.isNotEmpty &&
          refRaw.toLowerCase() == refName) {
        out.add(s);
      }
    }
    return out;
  }

  /// Delete a sale by id and notify listeners. Restores item stock.
  Future<int> deleteSaleById(int id) async {
    final sale = await db.getSaleById(id);
    if (sale == null) return 0;

    try {
      final item = await db.getItemById(sale.itemId);
      if (item != null) {
        final updatedItem = item.copyWith(
          stock: (item.stock + sale.quantity).toInt(),
          lastUpdated: Value(DateTime.now()),
        );
        await db.update(db.items).replace(updatedItem);
      }

      final res = await (db.delete(
        db.sales,
      )..where((t) => t.id.equals(id))).go();
      if (res > 0) {
        _changes.add('sale_deleted');
      }
      return res;
    } catch (e) {
      // ignore: avoid_print
      print('deleteSaleById failed: $e');
      rethrow;
    }
  }

  /// Delete all sales that share the given [timestamp] and [buyerId] as a
  /// single transaction group. Restores stock for every item.
  /// Returns the number of rows deleted.
  Future<int> deleteSaleGroup(DateTime timestamp, {int? buyerId}) async {
    return await db.transaction(() async {
      final allSales = await db.getAllSales();
      final group = allSales.where((s) {
        final sameTime =
            s.timestamp.millisecondsSinceEpoch ==
            timestamp.millisecondsSinceEpoch;
        final buyerMatch = s.buyerId == buyerId;
        return sameTime && buyerMatch;
      }).toList();

      if (group.isEmpty) return 0;

      // Restore stock for each item
      final now = DateTime.now();
      for (final sale in group) {
        final item = await db.getItemById(sale.itemId);
        if (item != null) {
          final updated = item.copyWith(
            stock: item.stock + sale.quantity,
            lastUpdated: Value(now),
          );
          await db.update(db.items).replace(updated);
        }
      }

      // Delete all sales in the group
      int deleted = 0;
      for (final sale in group) {
        final res = await (db.delete(
          db.sales,
        )..where((t) => t.id.equals(sale.id))).go();
        deleted += res;
      }

      if (deleted > 0) _changes.add('sale_deleted');
      return deleted;
    });
  }

  /// Update a sale record and notify listeners.
  Future<bool> updateSale(Sale sale) async {
    final res = await db.update(db.sales).replace(sale);
    _changes.add('sale_updated');
    return res;
  }

  /// Clear all data from sales, items, and members tables.
  /// Emits delete notifications so UI can refresh.
  Future<void> clearAllData() async {
    try {
      await db.transaction(() async {
        await db.delete(db.sales).go();
        await db.delete(db.items).go();
        await db.delete(db.members).go();
        // Reset autoincrement sequences if present
        try {
          // Reset sequences for sales and items only. Preserve members sequence so
          // member IDs are not reused after delete/clear operations.
          await db.customStatement(
            "DELETE FROM sqlite_sequence WHERE name IN ('sales','items');",
          );
        } catch (_) {
          // ignore if sqlite_sequence doesn't exist or fails
        }
      });

      // Notify listeners so UI can reload
      _changes.add('sale_deleted');
      _changes.add('item_deleted');
      _changes.add('member_deleted');
      _changes.add('db_cleared');
    } catch (e) {
      // ignore: avoid_print
      print('clearAllData failed: $e');
      rethrow;
    }
  }

  /// Edit a grouped sale (all sales that share the same timestamp) atomically.
  /// Returns null on success or an error message string on validation failure.
  Future<String?> editSaleGroup({
    required DateTime timestamp,
    int? buyerId,
    required List<Sale> newLines,
  }) async {
    return await db.transaction(() async {
      final allSales = await db.getAllSales();
      final originals = allSales
          .where((s) => s.timestamp == timestamp)
          .toList();

      // Compute per-item quantity deltas
      final Map<int, int> origQty = {};
      for (final o in originals) {
        origQty[o.itemId] = (origQty[o.itemId] ?? 0) + o.quantity;
      }
      final Map<int, int> newQty = {};
      for (final n in newLines) {
        newQty[n.itemId] = (newQty[n.itemId] ?? 0) + n.quantity;
      }

      // Validate stock adjustments (do not apply yet)
      final now = DateTime.now();
      for (final itemId in {...origQty.keys, ...newQty.keys}) {
        final before = origQty[itemId] ?? 0;
        final after = newQty[itemId] ?? 0;
        final deltaQ = after - before;
        final item = await db.getItemById(itemId);
        if (item == null) return 'Item id=$itemId not found';
        if (deltaQ > 0 && item.stock < deltaQ) {
          return 'Insufficient stock for ${item.name}';
        }
      }

      // Apply stock adjustments
      for (final itemId in {...origQty.keys, ...newQty.keys}) {
        final before = origQty[itemId] ?? 0;
        final after = newQty[itemId] ?? 0;
        final deltaQ = after - before;
        final item = await db.getItemById(itemId);
        if (item == null) return 'Item id=$itemId not found';
        if (deltaQ > 0) {
          final updated = item.copyWith(
            stock: item.stock - deltaQ,
            lastUpdated: Value(now),
          );
          await db.update(db.items).replace(updated);
        } else if (deltaQ < 0) {
          final updated = item.copyWith(
            stock: item.stock + -deltaQ,
            lastUpdated: Value(now),
          );
          await db.update(db.items).replace(updated);
        }
      }

      // Remove original grouped sales
      await (db.delete(
        db.sales,
      )..where((s) => s.timestamp.equals(timestamp))).go();

      // Insert new sale rows with same timestamp and buyerId
      for (final n in newLines) {
        final companion = SalesCompanion.insert(
          itemId: n.itemId,
          buyerId: Value(buyerId),
          itemName: n.itemName,
          quantity: n.quantity,
          price: Value(n.price),
          timestamp: Value(timestamp),
        );
        await db.insertSale(companion);
      }

      return null;
    });
  }

  // ── Reseller Level Configuration ───────────────────────────────────

  /// Get all reseller level configurations. Seeds defaults if empty.
  Future<List<ResellerLevel>> fetchResellerLevels() async {
    final rows = await db.select(db.resellerLevels).get();
    if (rows.isEmpty) {
      await _seedDefaultLevels();
      return db.select(db.resellerLevels).get();
    }
    return rows;
  }

  /// Upsert a single level configuration row.
  Future<void> upsertResellerLevel({
    required int level,
    required int remittanceMin,
    required int remittanceMax,
    required int cashAdvance,
  }) async {
    await db
        .into(db.resellerLevels)
        .insert(
          ResellerLevelsCompanion.insert(
            level: Value(level),
            remittanceMin: Value(remittanceMin),
            remittanceMax: Value(remittanceMax),
            cashAdvance: Value(cashAdvance),
          ),
          mode: InsertMode.insertOrReplace,
        );
    _changes.add('reseller_levels_updated');
  }

  /// Set a member's reseller level (1-10).
  Future<bool> setMemberLevel(int memberId, int level) async {
    final member = await db.getMemberById(memberId);
    if (member == null) return false;
    final updated = member.copyWith(level: level.clamp(1, 10));
    await db.updateMemberData(updated);
    _changes.add('member_updated');
    return true;
  }

  /// Seed default level configurations (hardcoded values).
  Future<void> _seedDefaultLevels() async {
    final defaults = [
      (level: 1, remMin: 500, remMax: 500, ca: 0),
      (level: 2, remMin: 800, remMax: 1000, ca: 100),
      (level: 3, remMin: 1700, remMax: 2100, ca: 200),
      (level: 4, remMin: 3400, remMax: 4200, ca: 400),
      (level: 5, remMin: 6800, remMax: 8400, ca: 800),
      (level: 6, remMin: 13600, remMax: 16800, ca: 1600),
      (level: 7, remMin: 27200, remMax: 33600, ca: 3200),
      (level: 8, remMin: 54400, remMax: 67200, ca: 6400),
      (level: 9, remMin: 108800, remMax: 134400, ca: 12800),
      (level: 10, remMin: 217600, remMax: 268800, ca: 25600),
    ];
    for (final d in defaults) {
      await db
          .into(db.resellerLevels)
          .insert(
            ResellerLevelsCompanion.insert(
              level: Value(d.level),
              remittanceMin: Value(d.remMin),
              remittanceMax: Value(d.remMax),
              cashAdvance: Value(d.ca),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }
}

class MemberTransactionEntry {
  final int? itemId;
  final String itemName;
  final int quantity;
  final int price;
  final DateTime? timestamp;

  MemberTransactionEntry({
    this.itemId,
    required this.itemName,
    required this.quantity,
    required this.price,
    this.timestamp,
  });
}
