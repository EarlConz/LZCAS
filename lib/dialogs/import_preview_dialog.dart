// ...existing code...
import 'package:flutter/material.dart';
import '../utils/formatters.dart';

DateTime? _parseMaybeTimestamp(String s) {
  if (s.trim().isEmpty) return null;
  // Try parse as int (milliseconds or microseconds)
  final numStr = s.trim();
  final intVal = int.tryParse(numStr);
  if (intVal != null) {
    // Heuristic: if value looks like microseconds (too big), treat accordingly
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (intVal > nowMs * 100) {
      return DateTime.fromMillisecondsSinceEpoch(intVal ~/ 1000);
    }
    return DateTime.fromMillisecondsSinceEpoch(intVal);
  }
  // Fallback to ISO parsing
  final dt = DateTime.tryParse(s.trim());
  return dt;
}

Future<bool?> showImportPreviewDialog(
  BuildContext context,
  List<String> headers,
  List<List<String>> rows, {
  int previewRows = 10,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final displayRows = rows.take(previewRows).toList();
      return AlertDialog(
        title: const Text('Import preview'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Constrain the table height and make it vertically scrollable so large
                // previews don't cause RenderFlex overflows.
                SizedBox(
                  height: 320,
                  child: SingleChildScrollView(
            child: DataTable(
              columns: [for (final h in headers) DataColumn(label: Text(h))],
              rows: [for (final r in displayRows) DataRow(cells: [for (final c in r) DataCell(Text(c))])],
            ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('${rows.length} total rows — showing ${displayRows.length} rows'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
        ],
      );
    },
  );
}

/// Show an import preview that allows selecting which rows to import.
/// Returns a list of selected row indices (relative to `rows`) or null if cancelled.
Future<List<int>?> showImportPreviewDialogWithSelection(
  BuildContext context,
  List<String> headers,
  List<List<String>> rows, {
  int previewRows = 20,
  /// Optional async checker that returns true when a row already exists in the DB.
  Future<bool> Function(Map<String, String> row)? exists,
}) async {
  // Precompute existence flags and reason strings for all rows (caller can supply an efficient checker).
  final existsFlags = <bool>[];
  final reasons = <String>[]; // empty string when not existing
  for (final r in rows) {
    final map = <String, String>{};
    for (var i = 0; i < headers.length && i < r.length; i++) {
      map[headers[i]] = r[i];
    }
    if (exists != null) {
      try {
        final e = await exists(map);
        existsFlags.add(e);
        if (e) {
          // The exists checker may not give a reason; infer a simple reason by ID or name presence.
          final idStr = (map['id'] ?? '').trim();
          if (idStr.isNotEmpty) {
            reasons.add('existing (id)');
          } else {
            reasons.add('existing (name)');
          }
        } else {
          reasons.add('');
        }
      } catch (_) {
        existsFlags.add(false);
        reasons.add('');
      }
    } else {
      existsFlags.add(false);
      reasons.add('');
    }
  }

  // Selected state: default checked only when not existing
  final selected = List<bool>.generate(rows.length, (i) => !existsFlags[i]);

  // ignore: use_build_context_synchronously
  return showDialog<List<int>>(context: context, builder: (ctx) {
  // When only previewing a slice we must keep the selected[] array indexed
  // against the original rows list. Build an index map for the displayed
  // rows so UI controls refer to the correct original indices.
  final displayCount = rows.length < previewRows ? rows.length : previewRows;
  final displayIndices = List<int>.generate(displayCount, (i) => i);
  return StatefulBuilder(builder: (ctx2, setState) {
    final selectedCount = selected.where((s) => s).length;
    return AlertDialog(
        title: const Text('Import preview'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ElevatedButton(onPressed: () { setState(() { for (var i = 0; i < selected.length; i++) { if (!existsFlags[i]) selected[i] = true; } }); }, child: const Text('Select all')),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: () { setState(() { for (var i = 0; i < selected.length; i++) { selected[i] = false; } }); }, child: const Text('Deselect all')),
                  const SizedBox(width: 12),
                  Text('$selectedCount selected'),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 360,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      const DataColumn(label: Text('Import')),
                      for (final h in headers) DataColumn(label: Text(h)),
                      const DataColumn(label: Text('Reason')),
                    ],
                      rows: List.generate(displayIndices.length, (rowPos) {
                      final globalIndex = displayIndices[rowPos];
                      final r = rows[globalIndex];
                      final cells = <DataCell>[];
                      cells.add(DataCell(Checkbox(
                        value: selected[globalIndex],
                        onChanged: (v) {
                          setState(() {
                            selected[globalIndex] = v ?? false;
                          });
                        },
                      )));
                              // Format timestamp-like columns for readability
                              final formattedCells = <DataCell>[];
                              for (var i = 0; i < r.length; i++) {
                                final h = headers.length > i ? headers[i].toString().toLowerCase() : '';
                                final raw = r[i];
                                if (h.contains('time') || h.contains('date') || h.contains('timestamp') || h.contains('createdat') || h.contains('lastupdated')) {
                                  final dt = _parseMaybeTimestamp(raw.toString());
                                  formattedCells.add(DataCell(Text(formatDisplayDate(dt))));
                                } else {
                                  formattedCells.add(DataCell(Text(raw)));
                                }
                              }
                              cells.addAll(formattedCells);
                      final reason = reasons[globalIndex];
                      cells.add(DataCell(reason.isEmpty ? const SizedBox.shrink() : Chip(label: Text(reason))));
                      return DataRow(cells: cells);
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('${rows.length} total rows — showing ${displayIndices.length} rows — $selectedCount selected'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          ElevatedButton(onPressed: () {
            final selIndices = <int>[];
            for (var i = 0; i < selected.length; i++) {
              if (selected[i]) {
                selIndices.add(i);
              }
            }
            // capture indices before async gaps and pop with the captured value
            Navigator.pop(ctx, selIndices);
          }, child: const Text('Import selected')),
        ],
      );
    });
  });
}
