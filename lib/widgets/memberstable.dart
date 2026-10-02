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
  bool _fetchingServer = false; // a fetch loop is currently running
  int _pendingNeeded = 0; // highest requested row count (coalesces requests)
  bool _didInitialPrefetch = false; // primed page 2 once after first load
  late final _MembersDataSource _membersSource;

  late final StreamSubscription<String> _changesSub;

  /// Search runs once typing pauses, not on every letter.
  Timer? _searchDebounce;

  /// A burst of member changes (an import, say) refreshes once.
  Timer? _changeDebounce;

  /// The phone's filter chips: how many in each, for the current search.
  ({int all, int resellers, int members})? _counts;
  bool _countsLoading = false;
  DateTime? _loadedAt;

  static bool _isMemberChange(String e) =>
      e == 'member_added' ||
      e == 'member_imported' ||
      e == 'member_deleted' ||
      e == 'member_updated';

  @override
  void initState() {
    super.initState();
    _MembersSnapshot.watch();
    final snap = _MembersSnapshot.take();
    _scrollController = ScrollController(initialScrollOffset: snap?.offset ?? 0);
    _scrollController.addListener(_onScroll);
    _membersSource = _MembersDataSource(
      _serverPage,
      () => _totalCount,
      widget.onRowSelected,
      _selectedMemberIds,
      _setMemberSelected,
    );
    if (snap != null) {
      // Back on the tab: show what was there at once. Only if a member
      // changed meanwhile is anything asked for, and then in place.
      _items.addAll(snap.items);
      _serverPage.addAll(snap.items);
      _currentPage = snap.page;
      _totalCount = snap.total;
      _hasMore = snap.hasMore;
      roleFilter = snap.role;
      _counts = snap.counts;
      _loadedAt = snap.at;
      _isInitialLoading = false;
      _pendingNeeded = _serverPage.length;
      if (snap.dirty) _refreshLoaded();
    } else {
      _loadMembers();
    }
    _changesSub = repository.changes.listen((e) {
      if (!_isMemberChange(e)) return;
      _changeDebounce?.cancel();
      _changeDebounce = Timer(const Duration(milliseconds: 800), _refreshLoaded);
    });
  }

  void _onSearchChanged(String value) {
    searchTerm = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadMembers();
    });
  }

  void _setRole(String? role) {
    setState(() => roleFilter = role);
    _loadMembers();
  }

  /// Re-read the rows already loaded, in one request, and swap them in
  /// place: the list keeps its scroll position and length.
  Future<void> _refreshLoaded() async {
    if (!mounted) return;
    final n = [_items.length, _serverPage.length, _pageSize].reduce((a, b) => a > b ? a : b);
    try {
      final res = await repository.fetchMembersPaginated(
        page: 1,
        pageSize: n,
        search: searchTerm.isNotEmpty ? searchTerm : null,
        roleFilter: (roleFilter != null && roleFilter!.isNotEmpty) ? roleFilter : null,
        sortColumn: 'last_name',
        sortAscending: true,
      );
      if (!mounted) return;
      final rows = membersFromRows(res.rows);
      setState(() {
        _items
          ..clear()
          ..addAll(rows);
        _serverPage
          ..clear()
          ..addAll(rows);
        _pendingNeeded = _serverPage.length;
        _currentPage = (rows.length / _pageSize).ceil().clamp(1, 1 << 30);
        _totalCount = res.totalCount;
        _hasMore = rows.length < res.totalCount;
        _counts = null;
        _loadedAt = DateTime.now();
        _error = null;
        final ids = rows.map((m) => m['id']).whereType<int>().toSet();
        _selectedMemberIds.removeWhere((id) => !ids.contains(id));
      });
      _membersSource.refresh();
    } catch (e) {
      debugPrint('[MembersTable] refresh failed: $e');
    }
  }

  Future<void> _loadCounts() async {
    if (_countsLoading) return;
    _countsLoading = true;
    final search = searchTerm.isNotEmpty ? searchTerm : null;
    try {
      final r = await Future.wait([
        repository.countMembers(search: search),
        repository.countMembers(search: search, roleFilter: 'Verified Reseller'),
        repository.countMembers(search: search, roleFilter: 'Member'),
      ]);
      if (mounted) setState(() => _counts = (all: r[0], resellers: r[1], members: r[2]));
    } catch (e) {
      debugPrint('[MembersTable] counts failed: $e');
    } finally {
      _countsLoading = false;
    }
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
        // The total comes with the first page only.
        withCount: page == 1,
        knownTotal: _totalCount,
      );
      if (!mounted) return;
      final newMembers = membersFromRows(result.rows);

      setState(() {
        if (page == 1) {
          _counts = null;
          _loadedAt = DateTime.now();
          _items.clear();
          _serverPage.clear();
          _serverPage.addAll(newMembers);
          _pendingNeeded = _serverPage.length;
          _didInitialPrefetch = false;
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

  /// Ensure `_serverPage` holds at least [neededCount] rows by loading
  /// consecutive server pages, then let the table repaint. Called from
  /// `onPageChanged` with the last row index the new table page needs.
  ///
  /// NOTE: PaginatedDataTable.onPageChanged reports the *first row index* of
  /// the page — NOT a page number — so we convert it to the server page(s) to
  /// fetch here rather than treating it as a page index.
  Future<void> _ensureLoadedThrough(int neededCount) async {
    if (neededCount > _pendingNeeded) _pendingNeeded = neededCount;
    // A running loop re-reads _pendingNeeded each iteration, so a fast
    // multi-page jump (or a background prefetch racing a navigation) never
    // drops a request.
    if (_fetchingServer) return;
    _fetchingServer = true;
    try {
      while (_serverPage.length < _pendingNeeded &&
          (_totalCount == 0 || _serverPage.length < _totalCount)) {
        final nextPage = (_serverPage.length ~/ _pageSize) + 1;
        final before = _serverPage.length;
        await _fetchServerPage(nextPage);
        if (!mounted) return;
        if (_serverPage.length <= before) break; // no progress — stop
      }
    } finally {
      _fetchingServer = false;
    }
  }

  /// Quietly load ONE page beyond what's loaded so the next forward step is
  /// instant. Fire-and-forget; ignored when a fetch is running or all rows
  /// are already loaded.
  void _prefetchNext() {
    final hasMore = _totalCount == 0 || _serverPage.length < _totalCount;
    if (hasMore) _ensureLoadedThrough(_serverPage.length + 1);
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
        withCount: false,
        knownTotal: _totalCount,
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
                buyerName: buyerName.isNotEmpty
                    ? buyerName
                    : 'Member #$memberId',
                packageId:
                    pkgId, // marks this as a package availment, not a product
              );
            }
          }

          _loadMembers();
          return memberId;
        }) ??
        0;
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
                            onChanged: _onSearchChanged,
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
                            onChanged: _setRole,
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
                  : _phoneHeader(context),
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

            // Desktop table is built → prime the second page once so the first
            // "next" is already loaded. (Runs here so the mobile list never
            // wastes a fetch into _serverPage.)
            if (!_didInitialPrefetch && !_isInitialLoading) {
              _didInitialPrefetch = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _prefetchNext();
              });
            }
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
                  // pageIndex is the FIRST row index of the new page; ensure we
                  // have loaded through the last visible row of that page, then
                  // quietly prime the following page.
                  onPageChanged: (pageIndex) => _ensureLoadedThrough(
                    pageIndex + estimated,
                  ).then((_) => _prefetchNext()),
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
    final q = searchTerm.trim();
    final groups = _letterGroups();
    final list = _items.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                q.isEmpty ? 'No members yet.' : 'No members match "$q".',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : ListView.builder(
            controller: _scrollController,
            // Room under the last row for the Add member button.
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
            itemCount: groups.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= groups.length) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final g = groups[i];
              return _MemberGroup(
                letter: g.letter,
                members: g.members,
                selectedIds: _selectedMemberIds,
                onTap: widget.onRowSelected,
              );
            },
          );

    return Stack(
      children: [
        Positioned.fill(child: list),
        Positioned(
          right: 4,
          bottom: 12,
          child: FloatingActionButton.extended(
            heroTag: null,
            onPressed: _onAddMemberPressed,
            backgroundColor: const Color(0xFFCC4900),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add member', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  /// Rows under their last name's first letter, in the order loaded (the
  /// server sorts by last name).
  List<({String letter, List<Map<String, dynamic>> members})> _letterGroups() {
    final groups = <({String letter, List<Map<String, dynamic>> members})>[];
    for (final m in _items) {
      final last = (m['lastName'] ?? '').toString().trim();
      final first = last.isEmpty ? '' : last[0].toUpperCase();
      final letter = RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
      if (groups.isEmpty || groups.last.letter != letter) {
        groups.add((letter: letter, members: [m]));
      } else {
        groups.last.members.add(m);
      }
    }
    return groups;
  }

  /// Phone: the search box, then All / Resellers / Members with counts.
  Widget _phoneHeader(BuildContext context) {
    final counts = _counts;
    if (counts == null && !_countsLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadCounts();
      });
    }
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    Widget chip(String label, String? value, int? n) {
      final on = roleFilter == value;
      final ink = theme.colorScheme.onSurface;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: on ? ink : theme.colorScheme.surface,
          shape: StadiumBorder(side: BorderSide(color: on ? ink : theme.dividerColor)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: on ? null : () => _setRole(value),
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  widthFactor: 1,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (n != null)
                          TextSpan(
                            text: '  $n',
                            style: TextStyle(color: on ? theme.colorScheme.surface : muted),
                          ),
                      ],
                    ),
                    style: TextStyle(fontSize: 14, color: on ? theme.colorScheme.surface : ink),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchBarWidget(
          onChanged: _onSearchChanged,
          hintText: 'Search name or contact number',
          borderRadius: 12,
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip('All', null, counts?.all),
              chip('Resellers', 'Verified Reseller', counts?.resellers),
              chip('Members', 'Member', counts?.members),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                searchTerm.trim().isEmpty
                    ? 'A to Z by last name'
                    : '$_totalCount match${_totalCount == 1 ? '' : 'es'}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted),
              ),
            ),
            if (_loadedAt != null)
              Text(
                'Updated ${_ago(_loadedAt!)}',
                style: TextStyle(fontSize: 12, color: muted),
              ),
          ],
        ),
      ],
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }

  @override
  void dispose() {
    // Keep the list for when this tab opens again (not mid-search: the
    // search box would come back empty over filtered rows).
    if (searchTerm.trim().isEmpty && _items.isNotEmpty) {
      _MembersSnapshot.save(
        items: List.of(_items),
        page: _currentPage,
        total: _totalCount,
        hasMore: _hasMore,
        role: roleFilter,
        counts: _counts,
        at: _loadedAt ?? DateTime.now(),
        offset: _scrollController.hasClients ? _scrollController.offset : 0,
      );
    }
    _searchDebounce?.cancel();
    _changeDebounce?.cancel();
    _scrollController.dispose();
    _changesSub.cancel();

    super.dispose();
  }
}

/// The members list as it was when its tab closed, so reopening it shows
/// rows at once. Dropped after 10 minutes, or for another signed-in
/// account; marked dirty by any member change meanwhile (the reopened list
/// then refreshes its rows in place).
class _MembersSnapshot {
  static ({
    List<Map<String, dynamic>> items,
    int page,
    int total,
    bool hasMore,
    String? role,
    ({int all, int resellers, int members})? counts,
    DateTime at,
    double offset,
    String? uid,
  })? _saved;
  static bool _dirty = false;
  static StreamSubscription<String>? _sub;

  static void watch() {
    _sub ??= repository.changes.listen((e) {
      if (MembersTableState._isMemberChange(e) || e.startsWith('package_')) {
        _dirty = true;
      }
    });
  }

  static void save({
    required List<Map<String, dynamic>> items,
    required int page,
    required int total,
    required bool hasMore,
    required String? role,
    required ({int all, int resellers, int members})? counts,
    required DateTime at,
    required double offset,
  }) {
    _saved = (
      items: items,
      page: page,
      total: total,
      hasMore: hasMore,
      role: role,
      counts: counts,
      at: at,
      offset: offset,
      uid: repository.supabase.auth.currentUser?.id,
    );
    _dirty = false;
  }

  /// The saved list, once, if still fresh for this account.
  static ({
    List<Map<String, dynamic>> items,
    int page,
    int total,
    bool hasMore,
    String? role,
    ({int all, int resellers, int members})? counts,
    DateTime at,
    double offset,
    bool dirty,
  })? take() {
    final s = _saved;
    _saved = null;
    if (s == null) return null;
    if (DateTime.now().difference(s.at) > const Duration(minutes: 10)) return null;
    if (s.uid != repository.supabase.auth.currentUser?.id) return null;
    return (
      items: s.items,
      page: s.page,
      total: s.total,
      hasMore: s.hasMore,
      role: s.role,
      counts: _dirty ? null : s.counts,
      at: s.at,
      offset: s.offset,
      dirty: _dirty,
    );
  }
}

/// One letter's members on a phone: the letter, then the rows in a card.
class _MemberGroup extends StatelessWidget {
  final String letter;
  final List<Map<String, dynamic>> members;
  final Set<int> selectedIds;
  final void Function(Map<String, dynamic>) onTap;

  const _MemberGroup({
    required this.letter,
    required this.members,
    required this.selectedIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.dividerColor.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(
            letter,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Material(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < members.length; i++) ...[
                if (i > 0) Divider(height: 1, color: line),
                _MemberRow(
                  member: members[i],
                  selected: selectedIds.contains(members[i]['id']),
                  onTap: () => onTap(members[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool selected;
  final VoidCallback onTap;

  const _MemberRow({required this.member, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    String s(String k) => (member[k] ?? '').toString().trim();
    final last = s('lastName'), first = s('firstName');
    final name = [last, first].where((p) => p.isNotEmpty).join(', ');
    final initials = [first, last].where((p) => p.isNotEmpty).map((p) => p[0].toUpperCase()).join();
    final reseller = s('role') == 'Verified Reseller';
    final pkg = s('packageName');
    final sub = [
      pkg.isEmpty ? 'No package' : '$pkg package',
      if (s('contactNo').isNotEmpty) s('contactNo'),
    ].join(' · ');
    const orangeText = Color(0xFFB24800);
    const cream = Color(0xFFFFF7DF);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? theme.colorScheme.primaryContainer : null,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: reseller
                  ? (dark ? orangeText.withAlpha(60) : cream)
                  : theme.colorScheme.surfaceContainerHighest,
              child: Text(
                initials.isEmpty ? '?' : initials,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: reseller && !dark ? orangeText : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Unnamed member' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (reseller) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: dark ? orangeText.withAlpha(60) : cream,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'Reseller',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: dark ? Colors.white : orangeText,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
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
      // Not fetched yet — show a shimmering skeleton row instead of raw text.
      return DataRow(
        cells: [
          skeletonCell(width: 90), // Last Name
          skeletonCell(width: 90), // First Name
          skeletonCell(width: 70), // Middle Name
          skeletonCell(width: 80), // Role
          skeletonCell(width: 100), // Contact No.
          skeletonCell(width: 80), // Birthday
          skeletonCell(width: 130), // Address
          skeletonCell(width: 32), // QR
        ],
      );
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

/// Small icon button that opens a dialog showing the member's QR code.
class _QrIconButton extends StatelessWidget {
  final Map<String, dynamic> member;

  const _QrIconButton({required this.member});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Show QR code',
      icon: Icon(Icons.qr_code, color: Theme.of(context).colorScheme.primary),
      onPressed: () => showMemberQrDialog(context, member),
    );
  }
}

/// The member's QR code in a dialog: from the table's QR column and the
/// phone's member screen.
void showMemberQrDialog(BuildContext context, Map<String, dynamic> member) {
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
