import 'package:flutter/material.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/action_guard.dart';
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/widgets/search.dart';
import 'package:lzcas/widgets/custom_elevated_button.dart';
import 'package:lzcas/dialogs/add_member_dialog.dart';
import 'package:lzcas/db/db.dart';
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
  final Set<int> _selectedMemberIds = {};

  static const _pageSize = 25;

  // ── Mobile infinite-scroll state ──────────────────────────────────
  final List<Map<String, dynamic>> _items = [];
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isInitialLoading = true;
  String? _error;
  late final ScrollController _scrollController;

  // ── Server-page state for desktop PaginatedDataTable ──────────────
  final List<Map<String, dynamic>> _serverPage = [];
  int _totalCount = 0;
  late final _MembersDataSource _membersSource;

  late final StreamSubscription<String> _changesSub;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _membersSource = _MembersDataSource(
      _serverPage,
      () => _totalCount,
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

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  void _loadMembers() {
    _loadPage(1);
  }

  void _loadMore() {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    setState(() {});
    _loadPage(_currentPage + 1);
  }

  Future<void> _loadPage(int page) async {
    try {
      final result = await repository.fetchMembersPaginated(
        page: page,
        pageSize: _pageSize,
        search: searchTerm.isNotEmpty ? searchTerm : null,
        roleFilter: (roleFilter != null && roleFilter!.isNotEmpty)
            ? roleFilter
            : null,
        sortColumn: 'last_name',
        sortAscending: true,
      );
      if (!mounted) return;
      final newMembers = membersFromRows(result.rows);

      setState(() {
        if (page == 1) {
          _items.clear();
          _serverPage.clear();
          _serverPage.addAll(newMembers);
          final currentIds = newMembers
              .map((m) => m['id'])
              .whereType<int>()
              .toSet();
          _selectedMemberIds.removeWhere((id) => !currentIds.contains(id));
        }
        _items.addAll(newMembers);
        _currentPage = page;
        _totalCount = result.totalCount;
        _hasMore = result.hasMore;
        _isInitialLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
      if (page == 1) {
        _membersSource.refresh();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  /// Fetch a specific server page — updates desktop PaginatedDataTable.
  /// Accumulates pages into _serverPage; getRow reads _serverPage[index]
  /// directly, so table pages and server pages don't need to align.
  Future<void> _fetchServerPage(int serverPage) async {
    final neededEnd = serverPage * _pageSize;
    if (_serverPage.length >= neededEnd) return;
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
      final newItems = membersFromRows(page.rows);
      setState(() {
        _serverPage.addAll(newItems);
        _totalCount = page.totalCount;
        final currentIds = newItems
            .map((m) => m['id'])
            .whereType<int>()
            .toSet();
        _selectedMemberIds.removeWhere((id) => !currentIds.contains(id));
      });
      _membersSource.refresh();
    } catch (e) {
      if (!mounted) return;
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

  Future<int> addMember(Map<String, dynamic> newMember) async {
    // Guard against a double-click creating the member (and its login
    // account / package availment sale) twice.
    return await ActionGuard.run('add_member', () async {
      // Check username availability BEFORE creating the member.
    // This ensures nothing is written to the database if the username is taken.
    if (newMember['createAccount'] == true) {
      final username = newMember['username']?.toString() ?? '';
      if (username.isNotEmpty) {
        final available = await repository.isUsernameAvailable(username);
        if (!available) {
          // The username might be held by a soft-deleted member rather than
          // an active one — in that case offer to restore them instead of a
          // confusing "already taken" dead-end.
          final deleted = await repository.findDeletedMemberByUsername(
            username,
          );
          if (deleted != null && deleted.id != null) {
            if (!mounted) return 0;
            final doRestore = await _confirmRestoreDeletedMember(deleted);
            if (doRestore == true) {
              final ok = await repository.restoreMemberById(deleted.id!);
              if (ok) {
                if (mounted) {
                  showSuccessToast(
                    'Restored "${_memberDisplayName(deleted)}".',
                  );
                }
                _loadMembers();
                // Return the restored id so the add dialog closes; no new
                // member is created (we stop here).
                return deleted.id!;
              }
              if (mounted) showErrorToast('Failed to restore member.');
              return 0;
            }
            // Admin declined — they must pick a different username.
            if (mounted) {
              showErrorToast(
                'Username "$username" belongs to a deleted member. '
                'Choose a different username.',
              );
            }
            return 0;
          }
          if (mounted) showErrorToast('Username already taken');
          return 0; // Dialog stays open, nothing was created
        }
      }
    }

    // Reseller status is derived purely from package availment.
    final hasPackage = (newMember['packageId'] as int?) != null;
    final role = hasPackage ? 'Verified Reseller' : 'Member';

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
        packageId: newMember['packageId'] as int?,
      );
    } catch (e) {
      debugPrint('[MembersTable] addMember failed: $e');
      if (mounted) {
        showErrorToast('Failed to add member. Please restart the app.');
      }
      return 0;
    }

    // ── Create the login account FIRST (pre-checked above) ──────────
    // Do this before the package sale so that, if account creation fails
    // and the member is rolled back, no orphaned availment sale is left.
    if (newMember['createAccount'] == true) {
      final username = newMember['username']?.toString() ?? '';
      final password = newMember['password']?.toString() ?? '';
      if (username.isNotEmpty && password.isNotEmpty) {
        final acct = await repository.createMemberAuthAccount(
          memberId: memberId,
          username: username,
          password: password,
        );
        if (acct != null) {
          final err = acct['error']?.toString();
          if (err != null) {
            await repository.deleteMemberById(memberId);
            if (mounted) showErrorToast(err);
            return 0; // Rolled back — dialog stays open
          }
        }
        if (mounted && acct != null && acct['error'] == null) {
          showSuccessToast(
            'Account created!\nEmail: ${acct['email']}\nPassword: ${acct['password']}',
          );
        }
      }
    }

    // ── Auto-create sale transaction when a package is selected ──────
    final pkgId = newMember['packageId'] as int?;
    if (pkgId != null) {
      final pkg = await repository.getPackageById(pkgId);
      if (pkg != null) {
        final buyerName = [
          newMember['firstName'],
          newMember['lastName'],
        ].where((p) => p != null && p.toString().isNotEmpty).join(' ');
        await repository.addSale(
          itemId: 0, // sentinel — package sales use item 0
          itemName: pkg.name,
          quantity: 1,
          price: pkg.price,
          buyerId: memberId,
          buyerName: buyerName.isNotEmpty ? buyerName : 'Member #$memberId',
          packageId: pkgId, // marks this as a package availment, not a product
        );
      }
    }

      _loadMembers();
      return memberId;
    }) ?? 0;
  }

  String _memberDisplayName(Member m) {
    final n = [
      m.firstName,
      m.lastName,
    ].where((p) => p != null && p.trim().isNotEmpty).join(' ');
    return n.isEmpty ? 'Member #${m.id}' : n;
  }

  /// Ask the admin whether to restore a soft-deleted member whose username
  /// collided with a new-member entry. Returns true to restore.
  Future<bool?> _confirmRestoreDeletedMember(Member m) {
    final name = _memberDisplayName(m);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Username belongs to a deleted member'),
        content: Text(
          'That username belongs to "$name", a member who was deleted. '
          'You can restore that member instead of creating a new one — '
          'all of their records come back.\n\nRestore "$name"?',
        ),
        actions: [
          OverflowBar(
            spacing: 12,
            overflowSpacing: 8,
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Use a different username'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Restore Member'),
              ),
            ],
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

    // Reseller status is derived purely from package availment.
    final newPackageId = updatedMember['packageId'] is int
        ? updatedMember['packageId'] as int
        : null;
    final isReseller = newPackageId != null;
    final newRole = isReseller ? 'Verified Reseller' : 'Member';

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
      packageId: newPackageId,
    );
    await repository.updateMember(updated);

    // Keep the member's LOGIN role in sync with their reseller status so
    // gaining/losing a package updates the tabs they can see.
    await repository.syncMemberLoginRole(id, isReseller);

    // ── POS: create a sale when a package is newly assigned ──
    final newPkgId = updated.packageId;
    final oldPkgId = row.packageId;
    if (newPkgId != null && newPkgId != oldPkgId) {
      try {
        final packages = await repository.fetchPackages();
        final pkg = packages.firstWhere(
          (p) => p.id == newPkgId,
          orElse: () => Package(name: 'Unknown', price: 0),
        );
        final label = oldPkgId == null
            ? 'New Reseller Entry: ${pkg.name}'
            : 'Package Upgrade: ${pkg.name}';
        await repository.addSale(
          itemId: 0,
          itemName: label,
          quantity: 1,
          price: pkg.price,
          buyerId: id,
          buyerName: _memberDisplayName(updated),
          packageId: newPkgId,
          timestamp: DateTime.now(),
        );
      } catch (_) {
        // non-critical — don't fail the save if POS insert fails
      }
    }

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
                  ? _buildMembersTable(context)
                  : _buildMembersList(context),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMembersTable(BuildContext context) {
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

  Widget _buildMembersList(BuildContext context) {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Failed to load members.'),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadMembers, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No members found'));
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final member = _items[index];
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
    _scrollController.dispose();
    _changesSub.cancel();

    super.dispose();
  }
}

class _MembersDataSource extends DataTableSource {
  final List<Map<String, dynamic>> _items;
  final int Function() _getTotalCount;
  final Function(Map<String, dynamic>) onRowSelected;
  final Set<int> selectedMemberIds;
  final void Function(int id, bool selected) onSelectionChanged;

  _MembersDataSource(
    this._items,
    this._getTotalCount,
    this.onRowSelected,
    this.selectedMemberIds,
    this.onSelectionChanged,
  );

  @override
  int get rowCount => _getTotalCount();

  @override
  DataRow getRow(int index) {
    if (index >= _items.length) {
      return DataRow(cells: List.filled(8, const DataCell(Text('Loading…'))));
    }
    final member = _items[index];
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
                  (member["role"] ?? "").toString(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if ((member["role"] ?? '') == 'Verified Reseller')
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
                    _MemberMetaPill(icon: Icons.stars_outlined, text: ''),
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
            const Expanded(child: Text('Member QR Code')),
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
