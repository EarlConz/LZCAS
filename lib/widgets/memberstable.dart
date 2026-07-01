import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/widgets/search.dart';
import 'package:lzcas/widgets/custom_elevated_button.dart';
import 'package:lzcas/widgets/pagination_bar.dart';
import 'package:lzcas/dialogs/add_member_dialog.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
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

  static const _pageSize = 25;
  int _displayPage = 1;
  int _currentPage = 0;
  bool _hasMore = true;
  bool _loading = false;

  // ── Server-page state for desktop PaginatedDataTable ──────────────
  final List<Map<String, dynamic>> _serverPage = [];
  int _totalCount = 0;
  int _currentServerPage = 1;
  late final _MembersDataSource _membersSource;

  late final StreamSubscription<String> _changesSub;

  @override
  void initState() {
    super.initState();
    _membersSource = _MembersDataSource(
      _serverPage,
      () => _totalCount,
      () => _currentServerPage,
      _pageSize,
      widget.onRowSelected,
      _selectedMemberIds,
      _setMemberSelected,
    );
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
    await _fetchServerPage(1);
    if (mounted) {
      setState(() {
        members = List.of(_serverPage);
        _currentPage = 1;
        _hasMore = _totalCount > _pageSize;
        _displayPage = 1;
        final currentIds = members
            .map((member) => member['id'])
            .whereType<int>()
            .toSet();
        _selectedMemberIds.removeWhere((id) => !currentIds.contains(id));
      });
    }
  }

  /// Fetch a specific server page — updates desktop PaginatedDataTable.
  Future<void> _fetchServerPage(int serverPage) async {
    if (_loading) return;
    _loading = true;
    if (mounted) setState(() {});
    try {
      final page = await repository.fetchMembersPaginated(
        page: serverPage,
        pageSize: _pageSize,
        search: searchTerm.isNotEmpty ? searchTerm : null,
        roleFilter: (roleFilter != null && roleFilter!.isNotEmpty)
            ? roleFilter
            : null,
        sortColumn: 'last_name',
        sortAscending: true,
      );
      if (!mounted) return;
      _serverPage.clear();
      _serverPage.addAll(membersFromRows(page.rows));
      setState(() {
        _totalCount = page.totalCount;
        _currentServerPage = serverPage;
        _loading = false;
      });
      _membersSource.refresh();
    } catch (e) {
      debugPrint('MembersTable: failed to load page $serverPage: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    setState(() {});
    try {
      final page = await repository.fetchMembersPaginated(
        page: _currentPage + 1,
        pageSize: _pageSize,
        search: searchTerm.isNotEmpty ? searchTerm : null,
        roleFilter: (roleFilter != null && roleFilter!.isNotEmpty)
            ? roleFilter
            : null,
        sortColumn: 'last_name',
        sortAscending: true,
      );
      if (!mounted) return;
      setState(() {
        final newMembers = membersFromRows(page.rows);
        members.addAll(newMembers);
        _currentPage = page.page;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      debugPrint('MembersTable: failed to load more: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
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

    // Wrap addMember in its own try/catch — after hot reload the auth session
    // can briefly be null, which causes _uid to throw uncaught.
    int memberId;
    try {
      memberId = await repository.addMember(
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
        idImagePath: null, // set after upload
      );
    } catch (e) {
      debugPrint('[MembersTable] addMember failed: $e');
      if (mounted) {
        BotToast.showText(
          text: 'Failed to add member. Please restart the app.',
        );
      }
      return;
    }

    // Upload image to Supabase Storage for cross-device access.
    if (finalImagePath != null) {
      if (kIsWeb) {
        final created = await repository.getMemberById(memberId);
        if (created != null) {
          final updated = created.copyWith(idImagePath: finalImagePath);
          await repository.updateMember(updated);
        }
      } else {
        try {
          final srcFile = File(finalImagePath);
          if (await srcFile.exists()) {
            final bytes = await srcFile.readAsBytes();
            final ext = p.extension(finalImagePath).isNotEmpty
                ? p.extension(finalImagePath).substring(1)
                : 'jpg';
            final url = await repository.uploadMemberImage(
              memberId,
              bytes,
              ext,
            );
            if (url != null) {
              final created = await repository.getMemberById(memberId);
              if (created != null) {
                final updated = created.copyWith(idImagePath: url);
                await repository.updateMember(updated);
              }
            }
            await srcFile.delete();
          }
        } catch (e) {
          debugPrint(
            '[MembersTable] Image upload failed, keeping local path: $e',
          );
        }
      }
    }

    _loadMembers();

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: StockpileColors.primary900, width: 4),
        ),
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
    final row = await repository.getMemberById(id);
    if (row == null) return;

    // Determine the final idImagePath — if it's a new local file, upload
    // to Supabase Storage first so the image is accessible cross-device.
    final rawImagePath = updatedMember['idImagePath']?.toString();
    String? finalImagePath;
    if (rawImagePath != null && rawImagePath.isNotEmpty) {
      if (rawImagePath.startsWith('http://') ||
          rawImagePath.startsWith('https://') ||
          rawImagePath.startsWith('data:')) {
        finalImagePath = rawImagePath;
      } else if (!kIsWeb) {
        try {
          final srcFile = File(rawImagePath);
          if (await srcFile.exists()) {
            final bytes = await srcFile.readAsBytes();
            final ext = p.extension(rawImagePath).isNotEmpty
                ? p.extension(rawImagePath).substring(1)
                : 'jpg';
            final url = await repository.uploadMemberImage(id, bytes, ext);
            if (url != null) {
              finalImagePath = url;
              try {
                await srcFile.delete();
              } catch (_) {}
            } else {
              finalImagePath = row.idImagePath;
            }
          } else {
            finalImagePath = row.idImagePath;
          }
        } catch (e) {
          debugPrint('[MembersTable] Image upload failed: $e');
          finalImagePath = row.idImagePath;
        }
      } else {
        finalImagePath = rawImagePath;
      }
    }

    final hasId = (finalImagePath ?? '').isNotEmpty;
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
      idImagePath: finalImagePath,
    );
    await repository.updateMember(updated);
    _loadMembers();
  }

  Future<void> removeMember(Map<String, dynamic> member) async {
    final id = member['id'] as int?;
    if (id == null) return;
    await repository.deleteMemberById(id);
    _loadMembers();
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
                            onChanged: (value) => setState(() {
                              searchTerm = value;
                              _loadMembers();
                            }),
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
                            onChanged: (v) {
                              setState(() => roleFilter = v);
                              _loadMembers();
                            },
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
                          onChanged: (value) => setState(() {
                            searchTerm = value;
                            _loadMembers();
                          }),
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
                            onChanged: (v) {
                              setState(() => roleFilter = v);
                              _loadMembers();
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
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
    if (_loading && members.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (filteredMembers.isEmpty && !_loading) {
      return const Center(child: Text('No members found'));
    }

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
            final reserved = 200.0;
            var available = constraints.maxHeight - reserved;
            if (available < 62) available = 62;
            final estimated = (available ~/ 62).clamp(1, 20);
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
                  source: _membersSource,
                  onPageChanged: (pageIndex) => _fetchServerPage(pageIndex + 1),
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
    if (_loading && members.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (filteredMembers.isEmpty) {
      return const Center(child: Text('No members found'));
    }

    final totalPages = (filteredMembers.length / _pageSize).ceil();
    final start = (_displayPage - 1) * _pageSize;
    final pageItems = filteredMembers.skip(start).take(_pageSize).toList();

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            itemCount: pageItems.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final member = pageItems[index];
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
          ),
        ),
        if (totalPages > 1)
          PaginationBar(
            currentPage: _displayPage,
            totalPages: totalPages,
            compact: true,
            onPageChanged: (page) {
              final needed = page * _pageSize;
              if (needed > members.length && _hasMore && !_loading) {
                _loadNextPage().then((_) {
                  if (mounted) setState(() => _displayPage = page);
                });
              } else {
                setState(() => _displayPage = page);
              }
            },
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
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
  final List<Map<String, dynamic>> _items;
  final int Function() _getTotalCount;
  final int Function() _getPageNumber;
  final int _pageSize;
  final Function(Map<String, dynamic>) onRowSelected;
  final Set<int> selectedMemberIds;
  final void Function(int id, bool selected) onSelectionChanged;

  _MembersDataSource(
    this._items,
    this._getTotalCount,
    this._getPageNumber,
    this._pageSize,
    this.onRowSelected,
    this.selectedMemberIds,
    this.onSelectionChanged,
  );

  @override
  int get rowCount => _getTotalCount();

  @override
  DataRow getRow(int index) {
    final pageNumber = _getPageNumber();
    final pageStart = (pageNumber - 1) * _pageSize;
    final localIndex = index - pageStart;
    if (localIndex < 0 || localIndex >= _items.length) {
      return DataRow(cells: List.filled(9, const DataCell(Text(''))));
    }
    final member = _items[localIndex];
    final id = member['id'] as int?;
    final isEven = index % 2 == 0;
    return DataRow(
      selected: id != null && selectedMemberIds.contains(id),
      color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.blue.withAlpha(28);
        }
        if (states.contains(WidgetState.hovered)) {
          return Colors.blue.withAlpha(18);
        }
        if (isEven) {
          return Colors.grey.withAlpha(20);
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
  int get selectedRowCount => selectedMemberIds.length;

  /// Call after external data changes to refresh the table.
  void refresh() => notifyListeners();
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: StockpileColors.primary900, width: 4),
        ),
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
