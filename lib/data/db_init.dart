// lib/data/db_init.dart

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:drift/native.dart';
import 'package:lzcas/db/app_db.dart';

/// Initialize a NativeDatabase stored in the app's private writable folder.
Future<AppDb> initDb() async {
  final appDir = await getApplicationSupportDirectory();
  final dbDir = Directory(p.join(appDir.path, 'data'));
  if (!await dbDir.exists()) await dbDir.create(recursive: true);
  final file = File(p.join(dbDir.path, 'app.db'));
  // Log the DB path so runtime uses are easy to trace.
  // ignore: avoid_print
  print('initDb: opening database at ${file.path}');

  final database = NativeDatabase(file);
  final appDb = AppDb(database);

  // Defensive: ensure required tables exist in case an existing DB file
  // lacks the newer schema (e.g., sales table). Creating tables with
  // IF NOT EXISTS prevents errors when queries run.
  try {
    await appDb.customStatement('''
      CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT,
        stock INTEGER NOT NULL DEFAULT 0,
        last_updated TEXT,
        status TEXT
      );

      CREATE TABLE IF NOT EXISTS members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        last_name TEXT,
        first_name TEXT,
        middle_name TEXT,
        role TEXT,
        contact_no TEXT,
        birthday TEXT,
        address TEXT,
        referrer TEXT,
        qr TEXT,
        level INTEGER NOT NULL DEFAULT 1
      );

      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        item_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price INTEGER NOT NULL DEFAULT 0,
        timestamp TEXT DEFAULT (CURRENT_TIMESTAMP)
      );
      
      CREATE TABLE IF NOT EXISTS member_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        member_id INTEGER NOT NULL,
        sale_id INTEGER,
        item_id INTEGER,
        item_name TEXT,
        quantity INTEGER DEFAULT 0,
        price INTEGER DEFAULT 0,
        timestamp TEXT DEFAULT (CURRENT_TIMESTAMP)
      );
    ''');
  } catch (e, st) {
    // ignore: avoid_print
    print('initDb: schema ensure failed: $e\n$st');
  }

  // Defensive migration: add level column to members if missing (for older DBs)
  try {
    await appDb.customStatement(
      'ALTER TABLE members ADD COLUMN level INTEGER NOT NULL DEFAULT 1;',
    );
  } catch (_) {
    // ignore: avoid_print
    // Column probably already exists — safe to continue.
  }

  // Defensive migration: add referrer_id to members if missing (nullable)
  try {
    await appDb.customStatement(
      'ALTER TABLE members ADD COLUMN referrer_id INTEGER;',
    );
  } catch (_) {
    // ignore: avoid_print
    // Column probably already exists or ALTER not applicable — safe to continue.
  }

  // Defensive migration: add sale_id to member_transactions if missing (nullable)
  try {
    await appDb.customStatement(
      'ALTER TABLE member_transactions ADD COLUMN sale_id INTEGER;',
    );
  } catch (_) {
    // ignore: avoid_print
    // Column probably already exists — safe to continue.
  }

  // Defensive migration: ensure reseller_levels table exists
  try {
    await appDb.customStatement(
      'CREATE TABLE IF NOT EXISTS reseller_levels ('
      'level INTEGER PRIMARY KEY,'
      'remittance_min INTEGER NOT NULL DEFAULT 0,'
      'remittance_max INTEGER NOT NULL DEFAULT 0,'
      'cash_advance INTEGER NOT NULL DEFAULT 0'
      ')',
    );
  } catch (_) {
    // ignore: avoid_print
  }

  return appDb;
}
