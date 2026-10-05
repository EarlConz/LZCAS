import 'package:flutter/material.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/action_guard.dart';
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/utils/csv_file.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/dialogs/add_member_dialog.dart';
import 'package:lzcas/db/db.dart';
import 'dart:async';
import 'package:lzcas/utils/phone_formatter.dart';
import 'package:lzcas/widgets/staff_table.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
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

  /// A to Z by last name, or Z to A (the Member header).
  bool _sortAscending = true;

  static const _pageSize = 25;

  // ── The loaded rows: the table and the phone list both scroll these ──
  final List<Map<String, dynamic>> _items = [];
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isInitialLoading = true;
  String? _error;
  late final ScrollController _scrollController;
  int _totalCount = 0;

  late final StreamSubscription<String> _changesSub;

  /// Search runs once typing pauses, not on every letter.
  Timer? _searchDebounce;

  /// A burst of member changes (an import, say) refreshes once.
  Timer? _changeDebounce;

  DateTime? _loadedAt;
  bool _exporting = false;

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
    if (snap != null) {
      // Back on the tab: show what was there at once. Only if a member
      // changed meanwhile is anything asked for, and then in place.
      _items.addAll(snap.items);
      _currentPage = snap.page;
      _totalCount = snap.total;
      _hasMore = snap.hasMore;
      _loadedAt = snap.at;
      _isInitialLoading = false;
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

  /// Re-read the rows already loaded, in one request, and swap them in
  /// place: the list keeps its scroll position and length.
  Future<void> _refreshLoaded() async {
    if (!mounted) return;
    final n = _items.length > _pageSize ? _items.length : _pageSize;
    try {
      final res = await repository.fetchMembersPaginated(
        page: 1,
        pageSize: n,
        search: searchTerm.isNotEmpty ? searchTerm : null,
        sortColumn: 'last_name',
        sortAscending: _sortAscending,
      );
      if (!mounted) return;
      final rows = membersFromRows(res.rows);
      setState(() {
        _items
          ..clear()
          ..addAll(rows);
        _currentPage = (rows.length / _pageSize).ceil().clamp(1, 1 << 30);
        _totalCount = res.totalCount;
        _hasMore = rows.length < res.totalCount;
        _loadedAt = DateTime.now();
        _error = null;
      });
    } catch (e) {
      debugPrint('[MembersTable] refresh failed: $e');
    }
  }

  /// Every member (not only the rows loaded) as a CSV, opened in Excel.
  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final csv = await repository.exportMembersCsv();
      final path = await saveAndOpenCsv(csv, 'members');
      showSuccessToast('Exported to $path');
    } catch (e) {
      showErrorToast('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
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
        sortColumn: 'last_name',
        sortAscending: _sortAscending,
        // The total comes with the first page only.
        withCount: page == 1,
        knownTotal: _totalCount,
      );
      if (!mounted) return;
      final newMembers = membersFromRows(result.rows);

      setState(() {
        if (page == 1) {
          _loadedAt = DateTime.now();
          _items.clear();
        }
        _items.addAll(newMembers);
        _currentPage = page;
        _totalCount = result.totalCount;
        _hasMore = result.hasMore;
        _isInitialLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _toggleSort() {
    setState(() => _sortAscending = !_sortAscending);
    _loadMembers();
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

  /// Saves an edit. True once it is saved; the "Member updated" toast is
  /// shown here, after the save, never before it (a refused save used to
  /// read as a success).
  Future<bool> updateMember(
    Map<String, dynamic> oldMember,
    Map<String, dynamic> updatedMember,
  ) async {
    final id = oldMember['id'] as int?;
    if (id == null) return false;
    final row = await repository.getMemberById(id);
    if (row == null) return false;

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
    try {
      await repository.updateMember(updated);
      // copyWith and toJson both skip a null referrer, so clearing one
      // needs its own write.
      if (updatedMember['referrerId'] == null && row.referrerId != null) {
        await repository.clearMemberReferrer(id);
      }
    } on PostgrestException catch (e) {
      // v67 refuses a referrer from the member's own downline.
      showErrorToast(
        e.message.contains('downline') || e.message.contains('own referrer')
            ? e.message
            : 'Could not save the member. Please try again.',
      );
      _loadMembers();
      return false;
    }
    showSuccessToast('Member updated');

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
    return true;
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
        if (constraints.maxWidth < kStaffTableBreakpoint) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(appSpacing),
                child: _phoneHeader(context),
              ),
              Expanded(child: _buildMembersList(context)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaffTableTop(
              caption: _caption(),
              searchWidth: 360,
              search: StaffSearchField(
                hint: 'Name, number or member ID',
                initialValue: searchTerm,
                onChanged: _onSearchChanged,
              ),
              actions: [
                StaffButton(
                  label: _exporting ? 'Exporting…' : 'Export',
                  icon: Icons.file_download_outlined,
                  primary: false,
                  onPressed: _exporting ? null : _export,
                ),
                StaffButton(
                  label: 'Add member',
                  icon: Icons.person_add_alt_1_rounded,
                  onPressed: _onAddMemberPressed,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(child: _buildMembersTable(context)),
          ],
        );
      },
    );
  }

  /// "1,284 members", or how many match the search.
  String _caption() {
    if (_isInitialLoading) return 'Members';
    if (searchTerm.trim().isNotEmpty) {
      return '${staffCount(_totalCount)} match${_totalCount == 1 ? '' : 'es'}';
    }
    return '${staffCount(_totalCount)} member${_totalCount == 1 ? '' : 's'}';
  }

  /// Wide screens: Member · Package · Contact · Referred by · Login · ⋯
  /// (redesign 2026-10-04). Middle name, birthday and address are on the
  /// member's own screen; the QR code is in ⋯.
  Widget _buildMembersTable(BuildContext context) {
    final s = StaffTableStyle.of(context);
    final q = searchTerm.trim();
    return StaffTable(
      controller: _scrollController,
      loading: _isInitialLoading,
      error: _error,
      onRetry: _loadMembers,
      loadingMore: _hasMore && _items.isNotEmpty,
      onLoadMore: _loadMore,
      emptyText: q.isEmpty ? 'No members yet.' : 'No members match "$q".',
      footer: staffShowing(_items.length, _totalCount),
      itemCount: _items.length,
      onRowTap: (i) => widget.onRowSelected(_items[i]),
      columns: [
        StaffColumn('Member', flex: 23, onSort: _toggleSort, sortAscending: _sortAscending),
        const StaffColumn('Package', flex: 12),
        const StaffColumn('Contact', flex: 11),
        const StaffColumn('Referred by', flex: 14),
        const StaffColumn('Login', width: 130),
        const StaffColumn('', width: 48),
      ],
      cells: (context, i) => _memberCells(context, s, _items[i]),
    );
  }

  List<Widget> _memberCells(BuildContext context, StaffTableStyle s, Map<String, dynamic> m) {
    String v(String k) => (m[k] ?? '').toString().trim();
    final last = v('lastName'), first = v('firstName');
    final name = [last, first].where((p) => p.isNotEmpty).join(', ');
    final initials = [first, last].where((p) => p.isNotEmpty).map((p) => p[0].toUpperCase()).join();
    final pkg = v('packageName');
    final contact = v('contactNo');
    final referrer = v('referrer');
    final hasLogin = v('email').isNotEmpty || v('user_id').isNotEmpty;

    return [
      Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: s.chipOnBg,
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w800, color: s.chipOnText),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Unnamed member' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w700, color: s.text),
                ),
                Text('ID ${m['id'] ?? '—'}', style: StockpileFonts.satoshi(fontSize: 13, color: s.muted)),
              ],
            ),
          ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: pkg.isEmpty
            ? Text('No package', style: StockpileFonts.satoshi(fontSize: 15, color: s.muted))
            : StaffPill('$pkg package', tone: StaffTone.orange),
      ),
      Text(
        contact.isEmpty ? '—' : formatPhilippinePhone(contact),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: StockpileFonts.satoshi(fontSize: 16, color: s.text),
      ),
      Text(
        referrer.isEmpty ? '—' : referrer,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: StockpileFonts.satoshi(fontSize: 16, color: s.body),
      ),
      hasLogin
          ? Row(
              children: [
                Icon(Icons.check_rounded, size: 18, color: s.success),
                const SizedBox(width: 6),
                Text('Has login', style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w600, color: s.success)),
              ],
            )
          : Text('No login', style: StockpileFonts.satoshi(fontSize: 15, color: s.muted)),
      StaffMoreButton(
        tooltip: 'More for ${name.isEmpty ? 'this member' : name}',
        items: [
          StaffMenuItem('Open member', Icons.open_in_new_rounded, () => widget.onRowSelected(m)),
          StaffMenuItem('Show QR code', Icons.qr_code_rounded, () => showMemberQrDialog(context, m)),
        ],
      ),
    ];
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
                onTap: widget.onRowSelected,
              );
            },
          );

    // Hidden while the keyboard is up (typing a search): it would ride up
    // over the rows. Kept clear of the screen edge and the system bar.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(child: list),
        if (!keyboard)
          Positioned(
            right: 16,
            bottom: 16 + safeBottom,
            child: StaffFab(
              label: 'Add member',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: _onAddMemberPressed,
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

  /// Phone: what the list holds and the search box.
  Widget _phoneHeader(BuildContext context) {
    final s = StaffTableStyle.of(context);
    return StaffPhoneTop(
      caption: searchTerm.trim().isEmpty ? '${_caption()} · A to Z' : _caption(),
      captionTrailing: _loadedAt == null
          ? null
          : Text('Updated ${_ago(_loadedAt!)}', style: StockpileFonts.satoshi(fontSize: 13, color: s.muted)),
      search: StaffSearchField(
        hint: 'Name, number or member ID',
        height: 48,
        initialValue: searchTerm,
        onChanged: _onSearchChanged,
      ),
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
    required DateTime at,
    required double offset,
  }) {
    _saved = (
      items: items,
      page: page,
      total: total,
      hasMore: hasMore,
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
  final void Function(Map<String, dynamic>) onTap;

  const _MemberGroup({
    required this.letter,
    required this.members,
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
  final VoidCallback onTap;

  const _MemberRow({required this.member, required this.onTap});

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
      if (s('contactNo').isNotEmpty) formatPhilippinePhone(s('contactNo')),
    ].join(' · ');
    const orangeText = Color(0xFFB24800);
    const cream = Color(0xFFFFF7DF);

    return InkWell(
      onTap: onTap,
      child: Container(
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

/// The member's QR code in a dialog: from a row's ⋯ menu and the phone's
/// member screen.
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
