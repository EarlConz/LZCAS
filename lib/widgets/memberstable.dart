import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/widgets/search.dart';
import 'package:lzcas/widgets/custom_elevated_button.dart';
import 'package:lzcas/dialogs/add_member_dialog.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:lzcas/db/db.dart';
import 'package:path/path.dart' as p;
import 'dart:async';
import '../theme.dart';
import 'memberqr.dart';

class MembersTable extends StatefulWidget {
  final Function(Map<String, dynamic>) onRowSelected;

  const MembersTable({super.key, required this.onRowSelected});

  @override
  MembersTableState createState() => MembersTableState();
}

class MembersTableState extends State<MembersTable> {
  String searchTerm = "";
  String? roleFilter;
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
    // Handle renaming the ID image from temp name to member-id-based name
    final rawImagePath = newMember['idImagePath']?.toString();
    String? finalImagePath = rawImagePath;

    // Auto-verify if an ID photo was uploaded
    final hasId = (newMember['idImagePath']?.toString() ?? '').isNotEmpty;
    final role = hasId
        ? 'Verified Reseller'
        : (newMember['role']?.toString() ?? 'Member');

    final memberId = await repository.addMember(
      lastName: newMember['lastName']?.toString(),
      firstName: newMember['firstName']?.toString(),
      middleName: newMember['middleName']?.toString(),
      role: role,
      contactNo: newMember['contactNo']?.toString(),
      birthday: newMember['birthday']?.toString(),
      address: newMember['address']?.toString(),
      referrer: newMember['referrer']?.toString(),
      referrerId: newMember['referrerId'] as int?,
      level: int.tryParse(newMember['level']?.toString() ?? '1') ?? 1,
      idType: newMember['idType']?.toString(),
      idNumber: newMember['idNumber']?.toString(),
      idImagePath: null, // set after renaming
    );

    // Rename temp image file to member ID (skip on web — data URLs don't need renaming)
    if (finalImagePath != null && !kIsWeb) {
      try {
        final srcFile = File(finalImagePath);
        if (await srcFile.exists()) {
          final parent = srcFile.parent;
          final ext = p.extension(finalImagePath).isNotEmpty
              ? p.extension(finalImagePath)
              : '.jpg';
          final renamed = p.join(parent.path, '$memberId$ext');
          final bytes = await srcFile.readAsBytes();
          await File(renamed).writeAsBytes(bytes);
          await srcFile.delete();
          finalImagePath = renamed;

          // Update the DB path
          final created = await repository.getMemberById(memberId);
          if (created != null) {
            final updated = created.copyWith(idImagePath: finalImagePath);
            await repository.updateMember(updated);
          }
        }
      } catch (_) {
        // Keep original path if rename fails
      }
    }

    await _loadMembers();

    // Show QR code dialog for the newly created member
    if (!mounted) return;
    final created = await repository.getMemberById(memberId);
    if (created != null && mounted) {
      _showMemberQrDialog(created);
    }
  }

  void _showMemberQrDialog(Member member) {
    final fullName =
        '${member.firstName ?? ''} ${member.middleName ?? ''} ${member.lastName ?? ''}'
            .trim();
    showAnimatedDialog(
      context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.qr_code, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 10),
            const Text('Member QR Code'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fullName,
              style: Theme.of(
                ctx,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            MemberQr(
              lastName: member.lastName ?? '',
              firstName: member.firstName ?? '',
              middleName: member.middleName ?? '',
              contactNo: member.contactNo ?? '',
              birthday: member.birthday ?? '',
              address: member.address ?? '',
              referrer: member.referrer ?? '',
              qrToken: member.qr,
              size: 240,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> updateMember(
    Map<String, dynamic> oldMember,
    Map<String, dynamic> updatedMember,
  ) async {
    final id = oldMember['id'] as int?;
    if (id == null) return;
    final row = (await repository.fetchMembers()).firstWhere((r) => r.id == id);

    // Auto-verify if an ID photo is present
    final newIdImagePath =
        updatedMember['idImagePath']?.toString() ?? row.idImagePath;
    final hasId = (newIdImagePath ?? '').isNotEmpty;
    final newRole = hasId ? 'Verified Reseller' : (row.role ?? 'Member');

    final updated = row.copyWith(
      lastName: updatedMember['lastName']?.toString(),
      firstName: updatedMember['firstName']?.toString(),
      middleName: updatedMember['middleName']?.toString(),
      role: newRole,
      contactNo: updatedMember['contactNo']?.toString(),
      birthday: updatedMember['birthday']?.toString(),
      address: updatedMember['address']?.toString(),
      referrer: updatedMember['referrer']?.toString(),
      referrerId: updatedMember['referrerId'] is int
          ? updatedMember['referrerId'] as int
          : null,
      level: updatedMember['level'] is int
          ? updatedMember['level'] as int
          : null,
      idType: updatedMember['idType']?.toString(),
      idNumber: updatedMember['idNumber']?.toString(),
      idImagePath: updatedMember['idImagePath']?.toString(),
    );
    await repository.updateMember(updated);
    await _loadMembers();
  }

  Future<void> removeMember(Map<String, dynamic> member) async {
    final id = member['id'] as int?;
    if (id == null) return;
    await repository.deleteMemberById(id);
    await _loadMembers();
  }

  void _onAddMemberPressed() {
    showAnimatedDialog(
      context,
      builder: (context) => AddMemberDialog(onMemberAdded: addMember),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredMembers = members.where((member) {
      final search = searchTerm.toLowerCase();
      final matchesSearch =
          search.isEmpty ||
          member.values.any(
            (value) => value.toString().toLowerCase().contains(search),
          );
      final matchesRole =
          roleFilter == null ||
          (member['role']?.toString() ?? '') == roleFilter;
      return matchesSearch && matchesRole;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 900;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(appSpacing),
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
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String?>(
                            value: roleFilter,
                            decoration: const InputDecoration(
                              labelText: 'Role',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(value: null, child: Text('All')),
                              DropdownMenuItem(
                                value: 'Verified Reseller',
                                child: Text('Verified Reseller'),
                              ),
                              DropdownMenuItem(
                                value: 'Member',
                                child: Text('Member'),
                              ),
                            ],
                            onChanged: (v) => setState(() => roleFilter = v),
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
                      ],
                    )
                  : Column(
                      children: [
                        SearchBarWidget(
                          onChanged: (value) =>
                              setState(() => searchTerm = value),
                          hintText: "Search members...",
                          borderRadius: 12,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: DropdownButtonFormField<String?>(
                            value: roleFilter,
                            decoration: const InputDecoration(
                              labelText: 'Filter by Role',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(value: null, child: Text('All')),
                              DropdownMenuItem(
                                value: 'Verified Reseller',
                                child: Text('Verified Reseller'),
                              ),
                              DropdownMenuItem(
                                value: 'Member',
                                child: Text('Member'),
                              ),
                            ],
                            onChanged: (v) => setState(() => roleFilter = v),
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
      },
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
              borderRadius: BorderRadius.circular(appRadius),
              side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
            ),
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // headingRowHeight(52) + internalPad(~62) + footer(~56) + card ≈ 200
            final reserved = 200.0;
            var available = constraints.maxHeight - reserved;
            if (available < 62) available = 62;
            final estimated = (available ~/ 62).clamp(1, 7);
            final tableWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : (constraints.minWidth.isFinite && constraints.minWidth > 0
                      ? constraints.minWidth
                      : MediaQuery.sizeOf(context).width);

            return ClipRect(
              child: SizedBox(
                width: tableWidth,
                child: PaginatedDataTable(
                  horizontalMargin: constraints.maxWidth < 1100 ? 12 : 20,
                  columnSpacing: constraints.maxWidth < 1100 ? 18 : 32,
                  rowsPerPage: estimated,
                  headingRowHeight: 52,
                  dataRowMinHeight: 56,
                  dataRowMaxHeight: 62,
                  showCheckboxColumn: true,
                  columns: const [
                    DataColumn(label: Text('Last Name')),
                    DataColumn(label: Text('First Name')),
                    DataColumn(label: Text('Middle Name')),
                    DataColumn(label: Text('Role')),
                    DataColumn(label: Text('Contact No.')),
                    DataColumn(label: Text('Birthday')),
                    DataColumn(label: Text('Address')),
                    DataColumn(label: Text('Level')),
                    DataColumn(label: Text('QR')),
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
        return StaggeredItem(
          index: index,
          child: _MemberListCard(
            member: member,
            selected:
                (member['id'] as int?) != null &&
                _selectedMemberIds.contains(member['id'] as int),
            onTap: () => widget.onRowSelected(member),
          ),
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
        if (states.contains(WidgetState.selected)) {
          return Theme.of(_context).colorScheme.primary.withAlpha(28);
        }
        if (states.contains(WidgetState.hovered)) {
          return Theme.of(_context).colorScheme.primary.withAlpha(18);
        }
        if (isEven) {
          return Theme.of(
            _context,
          ).colorScheme.surfaceContainerHighest.withAlpha(90);
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  (member['idImagePath']?.toString() ?? '').isNotEmpty
                      ? 'Verified Reseller'
                      : (member["role"] ?? ""),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if ((member['idImagePath']?.toString() ?? '').isNotEmpty ||
                  (member["role"] ?? '') == 'Verified Reseller')
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.verified_user,
                    size: 16,
                    color: Colors.green.shade700,
                  ),
                ),
            ],
          ),
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
          Text(
            (member['role'] ?? '') == 'Verified Reseller'
                ? (member['level'] ?? 1).toString()
                : '—',
          ),
          onTap: () => onRowSelected(member),
        ),
        DataCell(_QrIconButton(member: member)),
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
                  if ((member['role'] ?? '') == 'Verified Reseller')
                    _MemberMetaPill(
                      icon: Icons.stars_outlined,
                      text: (member['level'] ?? 1).toString(),
                    ),
                  const SizedBox(width: 4),
                  _QrIconButton(member: member),
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

/// Small icon button that opens a dialog showing the member's QR code.
class _QrIconButton extends StatelessWidget {
  final Map<String, dynamic> member;

  const _QrIconButton({required this.member});

  void _showQrDialog(BuildContext context) {
    final fullName = [
      member['firstName'],
      member['middleName'],
      member['lastName'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');

    showAnimatedDialog(
      context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.qr_code, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 10),
            const Text('Member QR Code'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fullName,
              style: Theme.of(
                ctx,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            MemberQr(
              lastName: (member['lastName'] ?? '').toString(),
              firstName: (member['firstName'] ?? '').toString(),
              middleName: (member['middleName'] ?? '').toString(),
              contactNo: (member['contactNo'] ?? '').toString(),
              birthday: (member['birthday'] ?? '').toString(),
              address: (member['address'] ?? '').toString(),
              referrer: (member['referrer'] ?? '').toString(),
              qrToken: (member['qr'] ?? '').toString(),
              size: 240,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Show QR code',
      icon: Icon(Icons.qr_code, color: Theme.of(context).colorScheme.primary),
      onPressed: () => _showQrDialog(context),
    );
  }
}
