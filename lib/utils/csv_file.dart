// lib/utils/csv_file.dart
//
// Saves an exported CSV and opens it, for the Export buttons on the staff
// tables (Inventory, Members, Transactions): into Downloads on a PC, then
// opened with the default app so it lands in Excel or Sheets.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Writes [csv] as `<prefix>_<yyyyMMdd_HHmmss>.csv` and opens it. Returns
/// the file's path, for the "Exported to …" message.
Future<String> saveAndOpenCsv(String csv, String prefix) async {
  // Downloads on desktop; app documents as a fallback (e.g. Android).
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {}
  dir ??= await getApplicationDocumentsDirectory();

  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  final ts = '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  final file = File(p.join(dir.path, '${prefix}_$ts.csv'));
  await file.writeAsString(csv);

  // Open with the system default app so it lands in Excel/Sheets.
  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', file.path], runInShell: true);
  } else if (Platform.isMacOS) {
    await Process.run('open', [file.path]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [file.path]);
  }
  return file.path;
}
