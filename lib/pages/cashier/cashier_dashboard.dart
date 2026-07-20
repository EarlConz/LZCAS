// lib/pages/cashier/cashier_dashboard.dart
// Cashier Dashboard — restricted to Cashier role only.
// Tabs:
//   1. Transaction — POS terminal for processing sales.
//   2. Members — Read-only member lookup.
//   3. Request Member Deletion — POST-based deletion request for Admin approval.
//   4. My Requests — Track status of submitted requests.
// Cashier role CANNOT see: inventory CRUD, reports, admin panels, or user mgmt.

import 'package:flutter/material.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/memberstable.dart';
import 'package:lzcas/widgets/admin_members_page.dart';
import 'package:lzcas/widgets/transactionstable.dart';
import 'package:lzcas/dialogs/edit_member_dialog.dart';
import 'package:lzcas/db/db.dart';

class CashierDashboard extends StatefulWidget {
  const CashierDashboard({super.key});

  @override
  State<CashierDashboard> createState() => _CashierDashboardState();
}

class _CashierDashboardState extends State<CashierDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Defense-in-depth: only cashier role may render this dashboard.
    assertRoleOrThrow(context, {UserRole.cashier});

    final auth = context.watch<AuthState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cashier Terminal',
                          style: StockpileFonts.satoshi(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? StockpileColors.darkTextPrimary
                                : StockpileColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Welcome, ${auth.username} · Cashier',
                          style: StockpileFonts.satoshi(
                            fontSize: 14,
                            color: isDark
                                ? StockpileColors.darkTextMuted
                                : StockpileColors.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _LogoutButton(auth: auth),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Tab Bar ─────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? StockpileColors.darkInputBg
                    : StockpileColors.inputBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                indicator: BoxDecoration(
                  color: isDark ? StockpileColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: StockpileColors.primary900,
                unselectedLabelColor: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.point_of_sale_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Transaction'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_alt_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Members'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_remove_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Del. Request'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('My Requests'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Tab Content ─────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Transaction (POS)
                  const _TransactionTab(),

                  // Tab 2: Members (read-only)
                  const _MembersLookupTab(),

                  // Tab 3: Request Member Deletion
                  _RequestDeletionTab(isDark: isDark),

                  // Tab 4: My Requests
                  _MyRequestsTab(isDark: isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab 1: Transaction (POS) ───────────────────────────────────────────────

class _TransactionTab extends StatelessWidget {
  const _TransactionTab();

  @override
  Widget build(BuildContext context) {
    // Reuse the existing TransactionsTable or SellButton widget.
    // This provides the POS terminal layout.
    return const Padding(
      padding: EdgeInsets.all(16),
      child: TransactionPageBody(),
    );
  }
}

/// Wraps the existing TransactionsTable into a named widget.
class TransactionPageBody extends StatelessWidget {
  const TransactionPageBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const TransactionsTable();
  }
}

// ─── Tab 2: Members Lookup — SAME as Admin's members page ─────────────

class _MembersLookupTab extends StatelessWidget {
  const _MembersLookupTab();

  @override
  Widget build(BuildContext context) {
    return const AdminMembersPage();
  }
}

// ─── Tab 3: Request Member Deletion ─────────────────────────────────────────
// Uses Autocomplete<Member> dropdown with live search for member selection,
// matching the pattern established in add_member_dialog.dart / edit_member_dialog.dart.

class _RequestDeletionTab extends StatefulWidget {
  final bool isDark;
  const _RequestDeletionTab({required this.isDark});

  @override
  State<_RequestDeletionTab> createState() => _RequestDeletionTabState();
}

class _RequestDeletionTabState extends State<_RequestDeletionTab> {
  final _searchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _focusNode = FocusNode();
  List<Member> _members = [];
  Member? _selectedMember;
  bool _loadingMembers = true;
  bool _submitting = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _reasonCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      final members = await repository.fetchMembers();
      if (!mounted) return;
      setState(() {
        _members = members;
        _loadingMembers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _submitDeletionRequest() async {
    final member = _selectedMember;
    final reason = _reasonCtrl.text.trim();

    if (member == null || reason.isEmpty) {
      setState(
        () => _feedback = 'Please select a member and provide a reason.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _feedback = null;
    });

    try {
      final memberName = '${member.firstName ?? ''} ${member.lastName ?? ''}'
          .trim();
      await repository.submitMemberDeletionRequest(
        memberId: member.id!,
        memberName: memberName,
        reason: reason,
      );

      if (!mounted) return;
      _searchCtrl.clear();
      _reasonCtrl.clear();
      setState(() {
        _selectedMember = null;
        _feedback = 'Deletion request submitted for Admin approval.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _feedback = 'Failed to submit: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: StockpileColors.error50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: StockpileColors.error200.withAlpha(120),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: StockpileColors.error700,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This does NOT delete data directly. It sends a '
                      'deletion request for Admin approval.',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        color: StockpileColors.error700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Request Member Deletion',
              style: StockpileFonts.satoshi(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: widget.isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
            ),
            const SizedBox(height: 16),

            if (_feedback != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _feedback!.contains('submitted')
                      ? StockpileColors.successBg
                      : StockpileColors.dangerBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _feedback!,
                  style: TextStyle(
                    color: _feedback!.contains('submitted')
                        ? StockpileColors.success
                        : StockpileColors.danger,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            // ── Member Search Dropdown (Autocomplete) ──────────────
            if (_selectedMember != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: StockpileColors.primary50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: StockpileColors.primary200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_rounded,
                      size: 20,
                      color: StockpileColors.primary700,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_selectedMember!.firstName ?? ''} '
                                    '${_selectedMember!.lastName ?? ''}'
                                .trim(),
                            style: StockpileFonts.satoshi(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: StockpileColors.primary900,
                            ),
                          ),
                          Text(
                            'ID: ${_selectedMember!.id} · '
                            '${_selectedMember!.role ?? 'Member'}',
                            style: StockpileFonts.satoshi(
                              fontSize: 12,
                              color: StockpileColors.primary600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Change member',
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _selectedMember = null);
                      },
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),

            if (_selectedMember == null)
              Autocomplete<Member>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return [];
                  final query = textEditingValue.text.toLowerCase();
                  return _members.where((m) {
                    final name = '${m.firstName ?? ''} ${m.lastName ?? ''}'
                        .toLowerCase();
                    final idStr = m.id?.toString() ?? '';
                    return name.contains(query) || idStr.contains(query);
                  });
                },
                displayStringForOption: (m) =>
                    '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim(),
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: 'Search Member',
                      hintText: 'Type a name or ID to search...',
                      prefixIcon: const Icon(Icons.person_search_rounded),
                      border: border,
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(10),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: 220,
                          maxWidth: MediaQuery.of(context).size.width * 0.45,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final m = options.elementAt(index);
                            final name =
                                '${m.firstName ?? ''} ${m.lastName ?? ''}'
                                    .trim();
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: StockpileColors.primary100,
                                child: Text(
                                  '${m.firstName?.isNotEmpty == true ? m.firstName![0] : '?'}',
                                  style: StockpileFonts.satoshi(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: StockpileColors.primary900,
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'ID: ${m.id} · ${m.role ?? 'Member'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Text(
                                '#${m.id}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: widget.isDark
                                      ? StockpileColors.darkTextMuted
                                      : StockpileColors.mutedText,
                                ),
                              ),
                              onTap: () {
                                onSelected(m);
                                _searchCtrl.text = name;
                                setState(() => _selectedMember = m);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                onSelected: (m) {
                  final name = '${m.firstName ?? ''} ${m.lastName ?? ''}'
                      .trim();
                  _searchCtrl.text = name;
                  setState(() => _selectedMember = m);
                },
              ),

            if (_loadingMembers && _selectedMember == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Loading members…',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),

            const SizedBox(height: 12),

            // ── Reason for Deletion ────────────────────────────────
            TextFormField(
              controller: _reasonCtrl,
              enabled: !_submitting,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason for Deletion',
                hintText: 'Explain why this member should be removed',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Icon(Icons.edit_note_rounded),
                ),
                border: border,
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 20),

            // ── Submit Button ──────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _submitting ? 'Submitting…' : 'Submit Deletion Request',
                ),
                onPressed: _submitting ? null : _submitDeletionRequest,
                style: FilledButton.styleFrom(
                  backgroundColor: StockpileColors.error500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared Logout Button (uses confirmation) ───────────────────────────────

class _LogoutButton extends StatelessWidget {
  final AuthState auth;

  const _LogoutButton({required this.auth});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout_rounded),
      tooltip: 'Logout',
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Logout'),
            content: const Text('Are you sure you want to sign out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Logout'),
              ),
            ],
          ),
        );

        if (confirmed != true || !context.mounted) return;

        await auth.logout();

        if (!context.mounted) return;

        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
      },
    );
  }
}

// ─── Tab 5: My Requests ────────────────────────────────────────────────────

class _MyRequestsTab extends StatefulWidget {
  final bool isDark;
  const _MyRequestsTab({required this.isDark});

  @override
  State<_MyRequestsTab> createState() => _MyRequestsTabState();
}

class _MyRequestsTabState extends State<_MyRequestsTab> {
  List<PendingRequest> _requests = [];
  bool _loading = true;
  bool _loadingMore = false;
  String _statusFilter = 'all';
  String _typeFilter = 'all';
  bool _newestFirst = true;

  static const _pageSize = 25;
  int _visibleCount = _pageSize;
  int _currentPage = 0;
  bool _hasMore = true;

  static const _orange = Color(0xFFF59E0B);
  static const _emerald = Color(0xFF10B981);
  static const _rose = Color(0xFFEF4444);
  static const _slate = Color(0xFF64748B);
  static const _indigo = Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    _loading = true;
    if (mounted) setState(() {});
    try {
      final page = await repository.fetchRequestsPaginated(
        page: 1,
        pageSize: _pageSize,
        userIdFilter: repository.supabase.auth.currentUser?.id,
      );
      if (!mounted) return;
      setState(() {
        _requests = page.rows;
        _currentPage = 1;
        _hasMore = page.hasMore;
        _visibleCount = _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    setState(() {});
    try {
      final page = await repository.fetchRequestsPaginated(
        page: _currentPage + 1,
        pageSize: _pageSize,
        userIdFilter: repository.supabase.auth.currentUser?.id,
      );
      if (!mounted) return;
      setState(() {
        _requests.addAll(page.rows);
        _currentPage = page.page;
        _hasMore = page.hasMore;
        _visibleCount = _requests.length;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<PendingRequest> get _filteredRequests {
    return _requests.where((r) {
      if (_statusFilter != 'all' && r.status != _statusFilter) return false;
      if (_typeFilter != 'all' && r.requestType != _typeFilter) return false;
      return true;
    }).toList()..sort((a, b) {
      final aTime = a.createdAt ?? DateTime(2000);
      final bTime = b.createdAt ?? DateTime(2000);
      return _newestFirst ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
    });
  }

  int _countBy(String status) =>
      _requests.where((r) => r.status == status).length;

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // ── Stat pill (compact count card) ───────────────────────────────
  Widget _statPill(String label, int count, Color color, IconData icon) {
    final selected = _statusFilter == label.toLowerCase();
    final isDark = widget.isDark;
    final bg = selected
        ? color
        : (isDark ? Colors.white10 : Colors.grey.shade50);
    final fg = selected
        ? Colors.white
        : isDark
        ? Colors.white70
        : _slate;
    final borderColor = selected
        ? color
        : (isDark ? Colors.white12 : Colors.grey.shade200);

    return GestureDetector(
      onTap: () => setState(() => _statusFilter = label.toLowerCase()),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fg.withAlpha(200),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Type filter row ──────────────────────────────────────────────
  Widget _typeFilterRow() {
    final isDark = widget.isDark;
    final items = [
      _FilterSegment('All', 'all', Icons.layers_rounded, _requests.length),
      _FilterSegment('Delete', 'delete_member', Icons.person_remove_rounded, 0),
      _FilterSegment('Borrow', 'borrow', Icons.swap_horiz_rounded, 0),
    ];

    return Row(
      children: items.map((item) {
        final selected = _typeFilter == item.value;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _typeFilter = item.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark ? _indigo.withAlpha(40) : _indigo.withAlpha(20))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? _indigo
                      : (isDark ? Colors.white12 : Colors.grey.shade200),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 15, color: selected ? _indigo : _slate),
                  const SizedBox(width: 5),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? _indigo : _slate,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showReasonDialog(BuildContext context, String reason) {
    final isDark = widget.isDark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: primaryColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Request Reason',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
                height: 1,
              ),
              const SizedBox(height: 20),
              // Quote-style content
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withAlpha(8)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border(
                    left: BorderSide(
                      color: primaryColor.withAlpha(120),
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  reason,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                    height: 1.6,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Close button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.white.withAlpha(20)
                        : Colors.grey.shade100,
                    foregroundColor: isDark
                        ? Colors.white70
                        : const Color(0xFF475569),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Card builder ─────────────────────────────────────────────────
  Widget _buildCard(PendingRequest req) {
    final isDark = widget.isDark;
    final isPending = req.status == 'pending';
    final isApproved = req.status == 'approved';

    final statusColor = isPending ? _orange : (isApproved ? _emerald : _rose);
    final statusLabel = isPending
        ? 'Pending'
        : (isApproved ? 'Approved' : 'Rejected');
    final statusIcon = isPending
        ? Icons.hourglass_empty_rounded
        : (isApproved ? Icons.check_circle_rounded : Icons.cancel_rounded);
    final statusBg = isPending
        ? _orange.withAlpha(20)
        : (isApproved ? _emerald.withAlpha(20) : _rose.withAlpha(20));

    final isBorrow = req.requestType == 'borrow';
    final typeColor = isBorrow ? _orange : _rose;
    final typeIcon = isBorrow
        ? Icons.swap_horiz_rounded
        : Icons.person_remove_rounded;
    final title = isBorrow
        ? (req.itemName ?? 'Unknown')
        : (req.memberName ?? 'Unknown');
    final subtitle = isBorrow
        ? 'For ${req.memberName ?? 'Unknown'}  ·  ×${req.quantity ?? 0}${req.price != null && req.price! > 0 ? '  ·  ₱${req.price} each' : ''}'
        : 'Requested deletion';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
          width: 1,
        ),
      ),
      color: isDark ? Colors.grey.shade900 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Avatar + title + status
            Row(
              children: [
                // Leading avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: typeColor.withAlpha(isDark ? 30 : 20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(typeIcon, size: 20, color: typeColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1E293B),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : _slate,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withAlpha(60),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Reason — shown as an info icon button
            if (req.reason != null && req.reason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showReasonDialog(context, req.reason!),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _slate.withAlpha(isDark ? 30 : 15),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: _slate,
                  ),
                ),
              ),
            ],

            // Rejection reason
            if (req.status == 'rejected' &&
                req.rejectionReason != null &&
                req.rejectionReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _rose.withAlpha(isDark ? 20 : 15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _rose.withAlpha(40), width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.block_rounded, size: 15, color: _rose),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        req.rejectionReason!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _rose,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Timestamp
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 12,
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Text(
                  req.createdAt != null ? _formatDate(req.createdAt!) : '',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white24 : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final filtered = _filteredRequests;

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // ── Header ──────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'My Requests',
                                style: StockpileFonts.satoshi(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            // Sort toggle
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _newestFirst = !_newestFirst),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedRotation(
                                      turns: _newestFirst ? 0 : 0.5,
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      child: Icon(
                                        Icons.arrow_downward_rounded,
                                        size: 15,
                                        color: _slate,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _newestFirst ? 'Newest' : 'Oldest',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _slate,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Stats row
                        Row(
                          children: [
                            Expanded(
                              child: _statPill(
                                'All',
                                _requests.length,
                                _indigo,
                                Icons.inbox_rounded,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _statPill(
                                'Pending',
                                _countBy('pending'),
                                _orange,
                                Icons.hourglass_empty_rounded,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _statPill(
                                'Approved',
                                _countBy('approved'),
                                _emerald,
                                Icons.check_circle_rounded,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _statPill(
                                'Rejected',
                                _countBy('rejected'),
                                _rose,
                                Icons.cancel_rounded,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Type filter
                        _typeFilterRow(),
                        const SizedBox(height: 8),
                        // Result count
                        Text(
                          'Showing ${filtered.length} of ${_requests.length} request${_requests.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white24
                                : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Content ─────────────────────────────────────
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withAlpha(15)
                                  : Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _statusFilter != 'all' || _typeFilter != 'all'
                                  ? Icons.filter_list_off_rounded
                                  : Icons.inbox_rounded,
                              size: 40,
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade300,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _statusFilter != 'all' || _typeFilter != 'all'
                                ? 'No matching requests'
                                : 'No requests yet',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _statusFilter != 'all' || _typeFilter != 'all'
                                ? 'Try adjusting the filters above'
                                : 'Submitted requests\nwill appear here',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white.withAlpha(51)
                                  : Colors.grey.shade400,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _buildCard(filtered[i]),
                        childCount: filtered.take(_visibleCount).length,
                      ),
                    ),
                  ),
                // "Load More" button
                if (_visibleCount < filtered.length || _hasMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _loadingMore
                              ? null
                              : () {
                                  if (_visibleCount + _pageSize >
                                          _requests.length &&
                                      _hasMore) {
                                    _loadNextPage().then((_) {
                                      if (mounted)
                                        setState(
                                          () => _visibleCount += _pageSize,
                                        );
                                    });
                                  } else {
                                    setState(() => _visibleCount += _pageSize);
                                  }
                                },
                          child: _loadingMore
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  'Load More (${_visibleCount.clamp(0, filtered.length)} of ${filtered.length}${_hasMore ? "+" : ""})',
                                ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _FilterSegment {
  final String label;
  final String value;
  final IconData icon;
  final int count;
  const _FilterSegment(this.label, this.value, this.icon, this.count);
}
