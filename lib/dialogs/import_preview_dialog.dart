import 'package:flutter/material.dart';

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
                      columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
                      rows: displayRows
                          .map((r) => DataRow(cells: r.map((c) => DataCell(Text(c))).toList()))
                          .toList(),
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
