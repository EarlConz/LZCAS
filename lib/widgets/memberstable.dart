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
  final Set<int> _selectedMemberIds = {};

  late final StreamSubscription<String> _changesSub;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _changesSub = repository.changes.listen((e) {
      if (e == 'member_added' ||
          e == 'member_imported' ||
          e == 'member_deleted' ||
          e == 'member_updated' ||
          e == 'item_updated') {
        _loadMembers();
      }
    });
  }

  Future<void> _loadMembers() async {
    final rows = await repository.fetchMembers();
    if (!mounted) return;
    setState(() {
      members = membersFromRows(rows);
      final currentIds = members
          .map((member) => member['id'])
          .whereType<int>()
          .toSet();
      _selectedMemberIds.removeWhere((id) => !currentIds.contains(id));
    });
  }

  void _setMemberSelected(int id, bool selected) {
    setState(() {
      if (selected) {
        _selectedMemberIds.add(id);
      } else {
        _selectedMemberIds.remove(id);
      }
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

  void _onAddMemberPressed() {
    showDialog(
      context: context,
      builder: (context) => AddMemberDialog(onMemberAdded: addMember),
    );
  }

  Future<void> _onExportCsvPressed(BuildContext safeContext) async {
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
        if (!mounted || !safeContext.mounted) return;
        ScaffoldMessenger.of(
          safeContext,
        ).showSnackBar(SnackBar(content: Text('Exported to ${loc.path}')));
      }
    } catch (e) {
      final dir = Directory.current.path;
      final savePath = p.join(dir, suggested);
      final file = File(savePath);
      await file.writeAsString(csv);
      if (!mounted || !safeContext.mounted) return;
      ScaffoldMessenger.of(
        safeContext,
      ).showSnackBar(SnackBar(content: Text('Exported to $savePath')));
    }
  }

  Future<void> _onImportCsvPressed(BuildContext localCtx) async {
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
    final headers = parsed.first.map((e) => e.toString()).toList();
    final rows = parsed
        .sublist(1)
        .map((r) => r.map((c) => c?.toString() ?? '').toList())
        .toList();
    if (!mounted || !localCtx.mounted) return;

    final expected = [
      'id',
      'lastname',
      'firstname',
      'middlename',
      'role',
      'phonenumber',
      'birthday',
      'address',
      'referrer',
      'points',
    ];
    final missing = findMissingHeaders(headers.cast<String>(), expected);
    if (missing.isNotEmpty) {
      if (!mounted || !localCtx.mounted) return;
      await showDialog<void>(
        context: localCtx,
        builder: (ctx) => AlertDialog(
          title: const Text('Invalid CSV'),
          content: Text('Missing headers: ${missing.join(', ')}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final existingRows = await repository.fetchMembers();
    final existingIds = <int>{};
    final existingNames = <String>{};
    for (final m in existingRows) {
      existingIds.add(m.id);
      existingNames.add(
        ('${m.firstName ?? ''}||${m.lastName ?? ''}').trim().toLowerCase(),
      );
    }

    bool fastExists(Map<String, String> map) {
      final idStr = (map['id'] ?? '').trim();
      if (idStr.isNotEmpty) {
        final id = int.tryParse(idStr);
        if (id != null && existingIds.contains(id)) return true;
      }
      final lastName = (map['lastName'] ?? '').trim();
      final firstName = (map['firstName'] ?? '').trim();
      if (lastName.isEmpty && firstName.isEmpty) return false;
      return existingNames.contains(
        ('$firstName||$lastName').trim().toLowerCase(),
      );
    }

    if (!mounted || !localCtx.mounted) return;
    final sel = await showImportPreviewDialogWithSelection(
      localCtx,
      headers,
      rows,
      exists: (m) async => fastExists(m),
    );
    if (sel == null || sel.isEmpty) return;

    final rowsToImport = sel.map((i) => rows[i]).toList();
    final inserted = await repository.importMembersFromRows(
      headers.cast<String>(),
      rowsToImport,
    );
    if (!mounted || !localCtx.mounted) return;
    await _loadMembers();
    if (!mounted || !localCtx.mounted) return;
    ScaffoldMessenger.of(localCtx).showSnackBar(
      SnackBar(
        content: Text(
          'Inserted $inserted new member${inserted == 1 ? '' : 's'}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 780;

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
          child: isDesktop
              ? Row(
                  children: [
                    Expanded(
                      child: SearchBarWidget(
                        onChanged: (value) =>
                            setState(() => searchTerm = value),
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
                      icon: Icon(
                        Icons.person_add,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      label: const Text(
                        "Add Member",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: Colors.blue[700],
                      onPressed: _onAddMemberPressed,
                    ),
                    const SizedBox(width: 8),
                    CustomElevatedButton(
                      icon: Icon(
                        Icons.upload_file,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      label: const Text(
                        'Export CSV',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: Colors.grey[700],
                      onPressed: () => _onExportCsvPressed(context),
                    ),
                    const SizedBox(width: 8),
                    CustomElevatedButton(
                      icon: Icon(
                        Icons.download,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      label: const Text(
                        'Import CSV',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: Colors.grey[700],
                      onPressed: () => _onImportCsvPressed(context),
                    ),
                  ],
                )
              : Column(
                  children: [
                    SearchBarWidget(
                      onChanged: (value) => setState(() => searchTerm = value),
                      hintText: "Search members...",
                      borderRadius: 12,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton.filled(
                          tooltip: 'Add Member',
                          icon: const Icon(Icons.person_add),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                          ),
                          onPressed: _onAddMemberPressed,
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Export CSV',
                          icon: const Icon(Icons.upload_file),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey[700],
                          ),
                          onPressed: () => _onExportCsvPressed(context),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Import CSV',
                          icon: const Icon(Icons.download),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey[700],
                          ),
                          onPressed: () => _onImportCsvPressed(context),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        Expanded(
          child: isDesktop
              ? _buildMembersTable(context, filteredMembers)
              : _buildMembersList(context, filteredMembers),
        ),
      ],
    );
  }

  Widget _buildMembersTable(
    BuildContext context,
    List<Map<String, dynamic>> filteredMembers,
  ) {
    return SizedBox(
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
            final reserved = 140.0;
            var available = constraints.maxHeight - reserved;
            if (available < 56) available = 56;
            final estimated = (available ~/ 56).clamp(1, 7);

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
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
                    DataColumn(label: Text('Points')),
                  ],
                  source: _MembersDataSource(
                    filteredMembers,
                    widget.onRowSelected,
                    _selectedMemberIds,
                    _setMemberSelected,
                    context,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMembersList(
    BuildContext context,
    List<Map<String, dynamic>> filteredMembers,
  ) {
    if (filteredMembers.isEmpty) {
      return const Center(child: Text('No members found'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      itemCount: filteredMembers.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final member = filteredMembers[index];
        return _MemberListCard(
          member: member,
          selected:
              (member['id'] as int?) != null &&
              _selectedMemberIds.contains(member['id'] as int),
          onTap: () => widget.onRowSelected(member),
        );
      },
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
  final Set<int> selectedMemberIds;
  final void Function(int id, bool selected) onSelectionChanged;
  final BuildContext _context;

  _MembersDataSource(
    this.members,
    this.onRowSelected,
    this.selectedMemberIds,
    this.onSelectionChanged,
    this._context,
  );

  @override
  DataRow getRow(int index) {
    if (index >= members.length) return const DataRow(cells: []);
    final member = members[index];
    final id = member['id'] as int?;
    final isEven = index % 2 == 0;
    return DataRow(
      selected: id != null && selectedMemberIds.contains(id),
      color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (isEven) {
          return Theme.of(_context).colorScheme.surfaceContainerHighest;
        }
        return null;
      }),
      onSelectChanged: id == null
          ? null
          : (selected) => onSelectionChanged(id, selected ?? false),
      cells: [
        DataCell(
          Text(member["lastName"] ?? ""),
          onTap: () => onRowSelected(member),
        ),
        DataCell(
          Text(member["firstName"] ?? ""),
          onTap: () => onRowSelected(member),
        ),
        DataCell(
          Text(member["middleName"] ?? ""),
          onTap: () => onRowSelected(member),
        ),
        DataCell(
          Text(member["role"] ?? ""),
          onTap: () => onRowSelected(member),
        ),
        DataCell(
          Text(member["contactNo"] ?? ""),
          onTap: () => onRowSelected(member),
        ),
        DataCell(
          Text(member["birthday"] ?? ""),
          onTap: () => onRowSelected(member),
        ),
        DataCell(
          Text(member["address"] ?? ""),
          onTap: () => onRowSelected(member),
        ),
        DataCell(
          Text((member["points"] ?? 0).toString()),
          onTap: () => onRowSelected(member),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => members.length;

  @override
  int get selectedRowCount => selectedMemberIds.length;
}

class _MemberListCard extends StatelessWidget {
  const _MemberListCard({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fullName =
        [member['firstName'], member['middleName'], member['lastName']]
            .where((part) => part != null && part.toString().trim().isNotEmpty)
            .join(' ');
    final contact = (member['contactNo'] ?? '').toString().trim();
    final address = (member['address'] ?? '').toString().trim();

    return Card(
      margin: EdgeInsets.zero,
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      fullName.isEmpty ? 'Unnamed Member' : fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MemberMetaPill(
                    icon: Icons.stars_outlined,
                    text: (member['points'] ?? 0).toString(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _MemberMetaPill(
                    icon: Icons.badge_outlined,
                    text: (member['role'] ?? 'Member').toString(),
                  ),
                  if (contact.isNotEmpty)
                    _MemberMetaPill(icon: Icons.phone_outlined, text: contact),
                ],
              ),
              if (address.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.home_outlined,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberMetaPill extends StatelessWidget {
  const _MemberMetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}
