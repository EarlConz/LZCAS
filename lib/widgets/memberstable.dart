import 'package:flutter/material.dart';
import 'package:lzcas/widgets/search.dart';
import 'package:lzcas/widgets/custom_elevated_button.dart';
import 'package:lzcas/dialogs/add_member_dialog.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'dart:typed_data';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:lzcas/db/db.dart';
import 'package:path/path.dart' as p;
import 'dart:async';
import 'package:csv/csv.dart';
import 'package:lzcas/dialogs/import_preview_dialog.dart';
import '../db/csv_header_utils.dart';

class MembersTable extends StatefulWidget {
  final Function(Map<String, dynamic>) onRowSelected;

  const MembersTable({super.key, required this.onRowSelected});

  @override
  MembersTableState createState() => MembersTableState();
}

class MembersTableState extends State<MembersTable> {
  String searchTerm = "";
  List<Map<String, dynamic>> members = [];

  late final StreamSubscription<String> _changesSub;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    // refresh when repository reports changes (imports/adds/deletes)
    // keep subscription so we can cancel on dispose
    _changesSub = repository.changes.listen((e) {
      if (e == 'member_added' ||
          e == 'member_imported' ||
          e == 'member_deleted' ||
          e == 'item_updated') {
        _loadMembers();
      }
    });
  }

  Future<void> _loadMembers() async {
    final rows = await repository.fetchMembers();
    setState(() {
      members = membersFromRows(rows);
    });
  }

  Future<void> addMember(Map<String, dynamic> newMember) async {
    await repository.addMember(
      lastName: newMember['lastName']?.toString(),
      firstName: newMember['firstName']?.toString(),
      middleName: newMember['middleName']?.toString(),
      role: newMember['role']?.toString(),
      contactNo: newMember['contactNo']?.toString(),
      birthday: newMember['birthday']?.toString(),
      address: newMember['address']?.toString(),
      referrer: newMember['referrer']?.toString(),
      points: (newMember['points'] ?? 0) is int
          ? newMember['points']
          : int.tryParse(newMember['points']?.toString() ?? '0') ?? 0,
    );
    await _loadMembers();
  }

  Future<void> updateMember(
    Map<String, dynamic> oldMember,
    Map<String, dynamic> updatedMember,
  ) async {
    // find by id if present
    final id = oldMember['id'] as int?;
    if (id == null) return;
    final row = (await repository.fetchMembers()).firstWhere((r) => r.id == id);
    final updated = row.copyWith(
      lastName: updatedMember['lastName'] != null
          ? Value(updatedMember['lastName'].toString())
          : const Value.absent(),
      firstName: updatedMember['firstName'] != null
          ? Value(updatedMember['firstName'].toString())
          : const Value.absent(),
      middleName: updatedMember['middleName'] != null
          ? Value(updatedMember['middleName'].toString())
          : const Value.absent(),
      role: updatedMember['role'] != null
          ? Value(updatedMember['role'].toString())
          : const Value.absent(),
      contactNo: updatedMember['contactNo'] != null
          ? Value(updatedMember['contactNo'].toString())
          : const Value.absent(),
      birthday: updatedMember['birthday'] != null
          ? Value(updatedMember['birthday'].toString())
          : const Value.absent(),
      address: updatedMember['address'] != null
          ? Value(updatedMember['address'].toString())
          : const Value.absent(),
      referrer: updatedMember['referrer'] != null
          ? Value(updatedMember['referrer'].toString())
          : const Value.absent(),
      points: updatedMember['points'] is int ? updatedMember['points'] : null,
    // QR field removed from UI; keep existing DB value unless updated via import.
    );
    await repository.db.updateMemberData(updated);
    await _loadMembers();
  }

  Future<void> removeMember(Map<String, dynamic> member) async {
    final id = member['id'] as int?;
    if (id == null) return;
    await repository.db.deleteMemberById(id);
    await _loadMembers();
  }

  @override
  Widget build(BuildContext context) {
    final filteredMembers = members.where((member) {
      final search = searchTerm.toLowerCase();
      return member.values.any(
        (value) => value.toString().toLowerCase().contains(search),
      );
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: SearchBarWidget(
                  onChanged: (value) {
                    setState(() {
                      searchTerm = value;
                    });
                  },
                  hintText: "Search members...",
                  borderRadius: 12,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CustomElevatedButton(
                icon: Icon(Icons.person_add, color: Theme.of(context).colorScheme.onPrimary),
                label: const Text(
                  "Add Member",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // stronger background color to be more visible
                // uses primary color from theme if not provided
                // we'll provide a darker blue for better contrast
                backgroundColor: Colors.blue[700],
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) =>
                        AddMemberDialog(onMemberAdded: addMember),
                  );
                },
              ),
              const SizedBox(width: 8),
              CustomElevatedButton(
                icon: Icon(Icons.upload_file, color: Theme.of(context).colorScheme.onPrimary),
                label: const Text(
                  'Export CSV',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: Colors.grey[700],
                onPressed: () async {
                  final csv = await repository.exportMembersCsvString();
                  final suggested =
                      'members_export_${DateTime.now().millisecondsSinceEpoch}.csv';
                  try {
                    final fs.FileSaveLocation? loc = await fs.getSaveLocation(
                      suggestedName: suggested,
                    );
                    if (loc != null) {
                      final xfile = fs.XFile.fromData(
                        Uint8List.fromList(csv.codeUnits),
                        mimeType: 'text/csv',
                        name: suggested,
                      );
                      await xfile.saveTo(loc.path);
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text('Exported to ${loc.path}')),
                      );
                      return;
                    }
                    return;
                  } catch (e) {
                    // fallback to writing in project root
                    final dir = Directory.current.path;
                    final savePath = p.join(dir, suggested);
                    final file = File(savePath);
                    await file.writeAsString(csv);
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('Exported to $savePath')),
                    );
                  }
                },
              ),
              const SizedBox(width: 8),
              CustomElevatedButton(
                icon: Icon(Icons.download, color: Theme.of(context).colorScheme.onPrimary),
                label: const Text(
                  'Import CSV',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: Colors.grey[700],
                onPressed: () async {
                  final files = await fs.openFiles(
                    acceptedTypeGroups: [
                      fs.XTypeGroup(label: 'CSV', extensions: ['csv']),
                    ],
                  );
                  if (files.isEmpty) return;
                  final xfile = files.first;
                  final content = await xfile.readAsString();
                  final conv = const CsvToListConverter();
                  final parsed = conv.convert(content);
                  if (parsed.isEmpty) return;
                  final headers = parsed.first
                      .map((e) => e.toString())
                      .toList();
                  final rows = parsed
                      .sublist(1)
                      .map((r) => r.map((c) => c?.toString() ?? '').toList())
                      .toList();
                  if (!mounted) return;
                  final expected = ['id', 'lastname', 'firstname', 'middlename', 'role', 'phonenumber', 'birthday', 'address', 'referrer', 'points'];
                  final missing = findMissingHeaders(headers.cast<String>(), expected);
                  if (missing.isNotEmpty) {
                    await showDialog<void>(
                      context: this.context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Invalid CSV'),
                        content: Text('This file does not look like a Members export. Missing headers: ${missing.join(', ')}'),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                      ),
                    );
                    return;
                  }
                  // ignore: use_build_context_synchronously
                  final confirm = await showImportPreviewDialog(
                    this.context,
                    headers,
                    rows,
                  );
                  if (confirm != true) return;
                  final count = await repository.importMembersCsv(content);
                  if (!mounted) return;
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text('Imported $count rows from ${xfile.name}'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: SizedBox(
            width: double.infinity,
              child: Theme(
              data: Theme.of(context).copyWith(
                cardTheme: CardThemeData(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                  color: Theme.of(context).cardColor,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // reserve some space for header/footer and controls, then estimate rows
                  final reserved = 140.0; // header + pagination controls approx
                  var available = constraints.maxHeight - reserved;
                  if (available < 56) available = 56; // at least one row height
                  var estimated = (available ~/ 56).clamp(1, 7);
                  return SingleChildScrollView(
                    child: PaginatedDataTable(
                      columnSpacing: 40,
                      rowsPerPage: estimated,
                      columns: const [
                        DataColumn(label: Text('Last Name')),
                        DataColumn(label: Text('First Name')),
                        DataColumn(label: Text('Middle Name')),
                        DataColumn(label: Text('Role')),
                        DataColumn(label: Text('Contact No.')),
                        DataColumn(label: Text('Birthday')),
                        DataColumn(label: Text('Address')),
                      ],
                      source: _MembersDataSource(
                        filteredMembers,
                        widget.onRowSelected,
                        context,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _changesSub.cancel();
    super.dispose();
  }
}

class _MembersDataSource extends DataTableSource {
  final List<Map<String, dynamic>> members;
  final Function(Map<String, dynamic>) onRowSelected;
  final BuildContext _context;

  _MembersDataSource(this.members, this.onRowSelected, this._context);

  @override
  DataRow getRow(int index) {
    if (index >= members.length) return const DataRow(cells: []);
    final member = members[index];
    final isEven = index % 2 == 0;
    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (isEven) return Theme.of(_context).colorScheme.surfaceContainerHighest;
        return null;
      }),
      onSelectChanged: (_) => onRowSelected(member),
      cells: [
        DataCell(Text(member["lastName"] ?? "")),
        DataCell(Text(member["firstName"] ?? "")),
        DataCell(Text(member["middleName"] ?? "")),
        DataCell(Text(member["role"] ?? "")),
        DataCell(Text(member["contactNo"] ?? "")),
        DataCell(Text(member["birthday"] ?? "")),
        DataCell(Text(member["address"] ?? "")),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => members.length;

  @override
  int get selectedRowCount => 0;
}
