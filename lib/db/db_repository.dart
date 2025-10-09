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
  final StreamController<String> _changes = StreamController<String>.broadcast();

  DbRepository(this.db);

  String _generateMemberQr() {
    final rnd = Random();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${rnd.nextInt(1 << 32).toRadixString(16)}';
  }

  Stream<String> get changes => _changes.stream;

  /// Import members from CSV string, return inserted count.
  Future<int> importMembersCsv(String csv) async {
    final converter = const CsvToListConverter(eol: '\n');
    final list = converter.convert(csv);
    if (list.isEmpty) return 0;
    final headers = list.first.map((e) => e.toString()).toList();
    final rows = list.sublist(1).map((r) => r.map((c) => c?.toString() ?? '').toList()).toList();
    return await importMembersFromRows(headers, rows);
  }

  /// Migration helper to ensure existing sales.points and member.points follow
  /// the current business rule: sale.points == item.points * quantity and
  /// member.points == sum of their sales.points. This is idempotent and safe
  /// to run at startup; it updates rows in a transaction.
  Future<void> ensurePointsConsistency() async {
    await db.transaction(() async {
      // Read sales using a raw select so we can handle cases where the
      // timestamp column is stored as an ISO string (legacy) or as an
      // integer milliseconds value. Using generated mappers (db.getAllSales)
      // may fail if the stored format doesn't match Drift's expectation.
      final rows = await db.customSelect('SELECT id, item_id, buyer_id, quantity, points FROM sales').get();
      final Map<int, int> memberTotals = {};
      for (final row in rows) {
        final saleId = row.read<int>('id');
        final itemId = row.read<int>('item_id');
        final buyerId = row.read<int?>('buyer_id');
        final quantity = row.read<int>('quantity');
        final existingPoints = row.read<int>('points');

        final item = await db.getItemById(itemId);
        final computed = item != null ? (item.points * quantity).toInt() : existingPoints;

        if (computed != existingPoints) {
          try {
            await db.customStatement('UPDATE sales SET points = $computed WHERE id = $saleId');
          } catch (_) {
            // ignore update failures
          }
        }

        if (buyerId != null) {
          memberTotals[buyerId] = (memberTotals[buyerId] ?? 0) + computed;
        }
      }

      // Update members to match computed totals. Leave members not present as-is.
      for (final entry in memberTotals.entries) {
        final m = await db.getMemberById(entry.key);
        if (m != null && m.points != entry.value) {
          final updated = m.copyWith(points: entry.value);
          await db.update(db.members).replace(updated);
        }
      }
    });
    _changes.add('points_migrated');
  }

  /// Bulk import helper that accepts parsed headers and rows (each row is a list of strings aligned to headers).
  /// Returns number of newly created members.
  Future<int> importMembersFromRows(List<String> headers, List<List<String>> rows) async {
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
            middleName: Value((map['middleName'] ?? '').trim().isEmpty ? null : (map['middleName'] ?? '').trim()),
            role: Value((map['role'] ?? '').trim().isEmpty ? null : (map['role'] ?? '').trim()),
            contactNo: Value((map['contactNo'] ?? '').trim().isEmpty ? null : (map['contactNo'] ?? '').trim()),
            birthday: Value((map['birthday'] ?? '').trim().isEmpty ? null : (map['birthday'] ?? '').trim()),
            address: Value((map['address'] ?? '').trim().isEmpty ? null : (map['address'] ?? '').trim()),
            referrer: Value((map['referrer'] ?? '').trim().isEmpty ? null : (map['referrer'] ?? '').trim()),
            points: int.tryParse((map['points'] ?? '').trim()) ?? 0,
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
        byName = all.firstWhere((r) => (r.lastName ?? '').trim().toLowerCase() == targetLast && (r.firstName ?? '').trim().toLowerCase() == targetFirst);
      } catch (e) {
        byName = null;
      }
      if (byName != null) {
        final updated = byName.copyWith(
          middleName: Value((map['middleName'] ?? '').trim().isEmpty ? null : (map['middleName'] ?? '').trim()),
          role: Value((map['role'] ?? '').trim().isEmpty ? null : (map['role'] ?? '').trim()),
          contactNo: Value((map['contactNo'] ?? '').trim().isEmpty ? null : (map['contactNo'] ?? '').trim()),
          birthday: Value((map['birthday'] ?? '').trim().isEmpty ? null : (map['birthday'] ?? '').trim()),
          address: Value((map['address'] ?? '').trim().isEmpty ? null : (map['address'] ?? '').trim()),
          referrer: Value((map['referrer'] ?? '').trim().isEmpty ? null : (map['referrer'] ?? '').trim()),
          points: int.tryParse((map['points'] ?? '').trim()) ?? 0,
        );
        await db.updateMemberData(updated);
        continue;
      }

      final companion = MembersCompanion.insert(
        lastName: Value(lastName.isEmpty ? null : lastName),
        firstName: Value(firstName.isEmpty ? null : firstName),
        middleName: Value((map['middleName'] ?? '').trim().isEmpty ? null : (map['middleName'] ?? '').trim()),
        role: Value((map['role'] ?? '').trim().isEmpty ? null : (map['role'] ?? '').trim()),
        contactNo: Value((map['contactNo'] ?? '').trim().isEmpty ? null : (map['contactNo'] ?? '').trim()),
        birthday: Value((map['birthday'] ?? '').trim().isEmpty ? null : (map['birthday'] ?? '').trim()),
        address: Value((map['address'] ?? '').trim().isEmpty ? null : (map['address'] ?? '').trim()),
        referrer: Value((map['referrer'] ?? '').trim().isEmpty ? null : (map['referrer'] ?? '').trim()),
        points: Value(int.tryParse((map['points'] ?? '').trim()) ?? 0),
        qr: Value(_generateMemberQr()),
      );

      final memberId = await db.insertMember(companion);

      // NOTE: Do not auto-award referrer points when importing members via CSV.
      // Awarding points on import can lead to accidental double-awards if the
      // same data is re-imported. The interactive addMember() path still
      // awards referrer points for members added through the UI.

      // parse transactions field (if any) using shared parser to ensure
      // timestamp formats (ISO or epoch) are handled consistently
      final txRaw = (map['transactions'] ?? '').trim();
      final List<MemberTransactionEntry> entries = [];
      if (txRaw.isNotEmpty) {
        final parsed = parseMemberTransactionsColumn(txRaw);
        for (final p in parsed) {
          entries.add(MemberTransactionEntry(
            itemId: p['itemId'] as int? ?? 0,
            itemName: p['itemName'] as String? ?? '',
            quantity: p['quantity'] as int? ?? 0,
            price: p['price'] as int? ?? 0,
            points: p['points'] as int? ?? 0,
            timestamp: p['timestamp'] as DateTime?,
          ));
        }
      }

      // If there are parsed transactions, commit them atomically. If commit fails, continue but log.
      if (entries.isNotEmpty) {
        final err = await commitMemberTransactions(memberId, entries, applyEffects: false);
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
  /// itemId is optional; itemName should be provided.
  /// timestamp may be null to use current time.
  Future<String?> commitMemberTransactions(int memberId, List<MemberTransactionEntry> entries, {bool applyEffects = true}) async {
    return await db.transaction(() async {
      // Validate member exists
      final buyer = await db.getMemberById(memberId);
      if (buyer == null) return 'Member not found';

      // Validate all items and stock first
      final Map<int, Item> itemCache = {};
      for (final e in entries) {
        final itemId = e.itemId;
        Item? item;
        if (itemId != null && itemId > 0) {
          item = await db.getItemById(itemId);
        }
        if (item == null) {
          // try to find by name
          final all = await db.getAllItems();
          try {
            item = all.firstWhere((it) => it.name.trim().toLowerCase() == e.itemName.trim().toLowerCase());
          } catch (_) {
            item = null;
          }
        }
        if (item == null) return 'Item ${e.itemName} not found';
        itemCache[item.id] = item;
        if (item.stock < e.quantity) return 'Insufficient stock for ${item.name}';
      }

  final now = DateTime.now();
      // Load existing sales once to avoid inserting duplicates
      final existingSales = await db.getAllSales();

      // Apply each transaction: insert sale and adjust stock and audit
      for (final e in entries) {
        final item = itemCache.values.firstWhere((it) => it.name.trim().toLowerCase() == e.itemName.trim().toLowerCase());

        // Compute points based on product's configured points per unit
        final computedPoints = (item.points * e.quantity).toInt();
        // Avoid duplicate inserts: check existing by core fields + timestamp
        final duplicate = existingSales.any((s) {
          final sameCore = s.itemId == item.id && s.itemName == e.itemName && s.quantity == e.quantity && s.price == e.price && (s.buyerId == memberId);
          if (!sameCore) return false;
          if (e.timestamp != null) return s.timestamp.toIso8601String() == e.timestamp!.toIso8601String();
          return true;
        });
        if (duplicate) continue;

        final saleComp = SalesCompanion.insert(
          itemId: item.id,
          buyerId: Value(memberId),
          itemName: e.itemName,
          quantity: e.quantity,
          price: Value(e.price),
          points: Value(computedPoints),
          timestamp: Value(e.timestamp ?? now),
        );
        final insertedId = await db.insertSale(saleComp);

        // decrement stock only when applyEffects is true. When importing
        // historical transactions via CSV we skip mutating stock here to
        // avoid double-decrementing.
        if (applyEffects) {
          final updatedItem = item.copyWith(stock: item.stock - e.quantity, lastUpdated: Value(now));
          await db.update(db.items).replace(updatedItem);
        }

        // write audit row into member_transactions table (raw SQL using variables)
        try {
          final tsVal = (e.timestamp ?? now).millisecondsSinceEpoch;
          await db.customInsert(
            'INSERT INTO member_transactions (member_id, sale_id, item_id, item_name, quantity, price, points, timestamp) VALUES (?,?,?,?,?,?,?,?)',
            variables: [
              Variable.withInt(memberId),
              Variable.withInt(insertedId),
              Variable.withInt(item.id),
              Variable.withString(e.itemName),
              Variable.withInt(e.quantity),
              Variable.withInt(e.price),
              Variable.withInt(e.points),
              Variable.withInt(tsVal),
            ],
          );
        } catch (_) {
          // ignore audit failures
        }

  // totalPoints intentionally not accumulated here; points are
  // recomputed centrally by ensurePointsConsistency().
  // add to existingSales so subsequent duplicate checks catch it
  // (we can't get the inserted id easily here, but fields are sufficient)
  // create a minimal Sale-like map by adding a synthetic entry via existingSales.add is not possible because it's typed; instead rely on duplicate checks that inspect DB on next import if necessary
      }
      // NOTE: Do NOT directly award points to the buyer here. Points are
      // maintained as the sum of sale.points per business rule. The repository
      //-level import methods will call `ensurePointsConsistency()` after
      //imports to recompute member.points from sales (avoids double-awards).

      // notify listeners about created transactions and item updates
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
    // Default import: treat sales as historical (do not apply stock/points).
    final count = await importSalesFromCsvString(db, csv, applyEffects: false);
    if (count > 0) {
      // Recompute points from sales (safe idempotent operation) and notify.
      await ensurePointsConsistency();
      _changes.add('sale_imported');
    }
    return count;
  }

  // Sales helpers
  Future<int> addSale({required int itemId, required String itemName, required int quantity, int price = 0, int points = 0, DateTime? timestamp, int? buyerId}) async {
    final companion = SalesCompanion.insert(
      itemId: itemId,
      buyerId: Value(buyerId),
      itemName: itemName,
      quantity: quantity,
      price: Value(price),
      points: Value(points),
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
  Future<int> addItem({required String name, int points = 0, String? category, int stock = 0, DateTime? lastUpdated, String? status}) async {
    final companion = ItemsCompanion.insert(
      name: name,
      points: Value(points),
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

  /// Redeem points helper (simple wrapper) - subtract points from member if possible
  Future<bool> redeemPoints({required int memberId, required int points}) async {
    final m = await db.getMemberById(memberId);
    if (m == null) return false;
    if (m.points < points) return false;
    final updated = m.copyWith(points: m.points - points);
    await db.update(db.members).replace(updated);
    _changes.add('member_updated');
    return true;
  }

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
  Future<int> addMember({String? lastName, String? firstName, String? middleName, String? role, String? contactNo, String? birthday, String? address, String? referrer, int points = 0}) async {
    final companion = MembersCompanion.insert(
      lastName: Value(lastName == null || lastName.isEmpty ? null : lastName),
      firstName: Value(firstName == null || firstName.isEmpty ? null : firstName),
      middleName: Value(middleName == null || middleName.isEmpty ? null : middleName),
      role: Value(role == null || role.isEmpty ? null : role),
      contactNo: Value(contactNo == null || contactNo.isEmpty ? null : contactNo),
      birthday: Value(birthday == null || birthday.isEmpty ? null : birthday),
      address: Value(address == null || address.isEmpty ? null : address),
      referrer: Value(referrer == null || referrer.isEmpty ? null : referrer),
      points: Value(points),
      qr: Value(_generateMemberQr()),
    );
    final id = await db.insertMember(companion);

    // If a referrer string was provided, try to resolve it to a member and award 15 points.
    if (referrer != null && referrer.trim().isNotEmpty) {
      try {
        final refStr = referrer.trim();
        Member? refMember;
        final parsed = int.tryParse(refStr);
        if (parsed != null) {
          // numeric referrer was provided
          if (parsed != id) {
            refMember = await db.getMemberById(parsed);
          }
        } else {
          // try to match by full name (first + last)
          final all = await db.getAllMembers();
          try {
            final target = refStr.toLowerCase();
            refMember = all.firstWhere((m) {
              final name = ('${m.firstName ?? ''} ${m.lastName ?? ''}').trim().toLowerCase();
              return name == target;
            });
            if (refMember.id == id) refMember = null; // don't award to self
          } catch (_) {
            refMember = null;
          }
        }

        if (refMember != null) {
          final updated = refMember.copyWith(points: refMember.points + 15);
          await db.update(db.members).replace(updated);
          _changes.add('member_updated');
          _changes.add('member_points_awarded');
        }
      } catch (_) {
        // Don't fail member creation if awarding points fails; just continue.
      }
    }

    _changes.add('member_added');
    return id;
  }

  /// Export members CSV content as string
  Future<String> exportMembersCsvString() => exportMembersToCsvString(db);

  /// Export members CSV to file and return path
  Future<String> exportMembersCsv() => exportMembersToCsvFile(db);

  Future<List<Sale>> fetchSales() => db.getAllSales();

  Future<List<Sale>> fetchSalesBetween(DateTime start, DateTime end) => db.getSalesBetween(start, end);

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
    final refName = refMember != null ? '${refMember.firstName ?? ''} ${refMember.lastName ?? ''}'.trim().toLowerCase() : '';
    for (final s in allSales) {
      if (s.buyerId == null) continue;
      final buyer = await db.getMemberById(s.buyerId!);
      if (buyer == null) continue;
      if (buyer.referrerId != null && buyer.referrerId == referrerMemberId) {
        out.add(s);
        continue;
      }
      final refRaw = (buyer.referrer ?? '').toString();
      if (refRaw.isNotEmpty && refName.isNotEmpty && refRaw.toLowerCase() == refName) {
        out.add(s);
      }
    }
    return out;
  }

  /// Delete a sale by id and notify listeners.
  Future<int> deleteSaleById(int id) async {
    // Load the sale so we can restore stock and adjust referrer points.
    final sale = await db.getSaleById(id);
    if (sale == null) return 0;

    // Resolve item and restore stock
    try {
      final item = await db.getItemById(sale.itemId);
      if (item != null) {
        final updatedItem = item.copyWith(stock: (item.stock + sale.quantity).toInt(), lastUpdated: Value(DateTime.now()));
        await db.update(db.items).replace(updatedItem);
      }

      // If sale had a buyer, try to deduct the awarded points from the buyer (reverse the points awarded previously)
      if (sale.buyerId != null) {
        final buyer = await db.getMemberById(sale.buyerId!);
        if (buyer != null) {
          // Compute points to reverse from the current item config (ensure consistent calculation)
          final itemForSale = await db.getItemById(sale.itemId);
          final pointsToReverse = itemForSale != null ? (itemForSale.points * sale.quantity).toInt() : sale.points;
          if (pointsToReverse > 0) {
            // Require the buyer to have enough points to reverse the award.
            if (buyer.points < pointsToReverse) {
              // indicate failure to caller (no deletion performed)
              return -1;
            }
            final updatedBuyer = buyer.copyWith(points: (buyer.points - pointsToReverse).toInt());
            await db.update(db.members).replace(updatedBuyer);
          }
        }
      }

      // Now delete the sale (do NOT attempt to renumber primary keys) - primary keys must remain stable.
      final res = await (db.delete(db.sales)..where((t) => t.id.equals(id))).go();
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
          await db.customStatement("DELETE FROM sqlite_sequence WHERE name IN ('sales','items');");
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
  /// newLines should contain Sale objects representing the desired final state.
  /// Returns null on success or an error message string on validation failure.
  Future<String?> editSaleGroup({required DateTime timestamp, int? buyerId, required List<Sale> newLines}) async {
    return await db.transaction(() async {
      // Load originals in the transaction
      final allSales = await db.getAllSales();
      final originals = allSales.where((s) => s.timestamp == timestamp).toList();

      // Recompute points using current item.points * quantity to ensure consistent business rule
      int originalPoints = 0;
      for (final o in originals) {
        final it = await db.getItemById(o.itemId);
        originalPoints += it != null ? (it.points * o.quantity).toInt() : o.points;
      }
      int newPoints = 0;
      for (final n in newLines) {
        final it = await db.getItemById(n.itemId);
        newPoints += it != null ? (it.points * n.quantity).toInt() : n.points;
      }
      final int delta = newPoints - originalPoints;
      final int? originalBuyerId = originals.isNotEmpty ? originals.first.buyerId : null;

      // If deducting points from the buyer (delta < 0), ensure buyer has enough points
      if (delta < 0 && buyerId != null) {
        final buyer = await db.getMemberById(buyerId);
        if (buyer != null) {
          final needed = -delta;
          if (buyer.points < needed) {
            return '${buyer.firstName ?? ''} ${buyer.lastName ?? ''} has only ${buyer.points} points but you are trying to deduct $needed points.';
          }
        }
      }

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
        final deltaQ = after - before; // positive means we need more stock (decrease store stock)
        final item = await db.getItemById(itemId);
        if (item == null) return 'Item id=$itemId not found';
        if (deltaQ > 0 && item.stock < deltaQ) return 'Insufficient stock for ${item.name}';
      }

      // Apply stock adjustments
      for (final itemId in {...origQty.keys, ...newQty.keys}) {
        final before = origQty[itemId] ?? 0;
        final after = newQty[itemId] ?? 0;
        final deltaQ = after - before;
        final item = await db.getItemById(itemId);
        if (item == null) return 'Item id=$itemId not found';
        if (deltaQ > 0) {
          final updated = item.copyWith(stock: item.stock - deltaQ, lastUpdated: Value(now));
          await db.update(db.items).replace(updated);
        } else if (deltaQ < 0) {
          final updated = item.copyWith(stock: item.stock + -deltaQ, lastUpdated: Value(now));
          await db.update(db.items).replace(updated);
        }
      }

      // Remove original grouped sales
      await (db.delete(db.sales)..where((s) => s.timestamp.equals(timestamp))).go();

      // Insert new sale rows with same timestamp and buyerId
      for (final n in newLines) {
        final companion = SalesCompanion.insert(
          itemId: n.itemId,
          buyerId: Value(buyerId),
          itemName: n.itemName,
          quantity: n.quantity,
          price: Value(n.price),
          points: Value(n.points),
          timestamp: Value(timestamp),
        );
        await db.insertSale(companion);
      }

      // Apply buyer point adjustments
      if (buyerId == originalBuyerId) {
        if (delta != 0 && buyerId != null) {
          final buyer = await db.getMemberById(buyerId);
          if (buyer != null) {
            if (delta > 0) {
              final updatedBuyer = buyer.copyWith(points: buyer.points + delta);
              await db.update(db.members).replace(updatedBuyer);
            } else if (delta < 0) {
              // Deduct points from buyer
              if (buyer.points < -delta) return 'Failed to deduct points from buyer.';
              final updatedBuyer = buyer.copyWith(points: buyer.points + delta); // delta negative
              await db.update(db.members).replace(updatedBuyer);
            }
          }
        }
      } else {
        // Buyer changed: reverse originalPoints from original buyer (if any), then add newPoints to new buyer (if any)
        if (originalBuyerId != null && originalPoints > 0) {
          final originalBuyer = await db.getMemberById(originalBuyerId);
          if (originalBuyer != null) {
            if (originalBuyer.points < originalPoints) return 'Cannot reverse points from original buyer (${originalBuyer.firstName} ${originalBuyer.lastName}) — insufficient points.';
            final updated = originalBuyer.copyWith(points: originalBuyer.points - originalPoints);
            await db.update(db.members).replace(updated);
          }
        }

        if (buyerId != null && newPoints > 0) {
          final newBuyer = await db.getMemberById(buyerId);
          if (newBuyer != null) {
            final updated = newBuyer.copyWith(points: newBuyer.points + newPoints);
            await db.update(db.members).replace(updated);
          }
        }
      }

      // success
      return null;
    });
  }
}

class MemberTransactionEntry {
  final int? itemId;
  final String itemName;
  final int quantity;
  final int price;
  final int points;
  final DateTime? timestamp;

  MemberTransactionEntry({this.itemId, required this.itemName, required this.quantity, required this.price, required this.points, this.timestamp});
}
