// lib/data/db_init.dart

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:drift/native.dart';
import 'package:lzcas/db/app_db.dart';

/// Initialize a NativeDatabase stored under the project's `lib/data` folder.
///
/// NOTE: Writing into the source tree is fine for local development but may
/// be read-only when the app is packaged/installed. This follows your
/// request to keep the DB physically under `lib/data`.
Future<AppDb> initDb() async {
  // Use current working directory (project root) and place DB under lib/data
  final cwd = Directory.current.path;
  final dbDir = Directory(p.join(cwd, 'lib', 'data'));
  if (!await dbDir.exists()) await dbDir.create(recursive: true);
  final file = File(p.join(dbDir.path, 'app.db'));
  // Log the DB path so runtime uses are easy to trace
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
        points INTEGER NOT NULL DEFAULT 0,
        qr TEXT
      );

      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        item_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price INTEGER NOT NULL DEFAULT 0,
        timestamp TEXT DEFAULT (CURRENT_TIMESTAMP)
      );
    ''');
  } catch (e, st) {
    // ignore: avoid_print
    print('initDb: schema ensure failed: $e\n$st');
  }

  return appDb;
}
