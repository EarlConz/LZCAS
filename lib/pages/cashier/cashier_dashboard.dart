// lib/pages/cashier/cashier_dashboard.dart
// Cashier Dashboard — restricted to Cashier role only.
// Tabs:
//   1. Transaction — POS terminal for processing sales.
//   2. Members — Read-only member lookup.
//   3. Request Member Deletion — POST-based deletion request for Admin approval.
//   4. Request Borrow Stock — POST-based borrow stock request for review.
//   5. My Requests — Track status of submitted deletion and borrow requests.
// Cashier role CANNOT see: inventory CRUD, reports, admin panels, or user mgmt.

import 'package:flutter/material.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/memberstable.dart';
import 'package:lzcas/widgets/memberdetails.dart';
import 'package:lzcas/widgets/transactionstable.dart';
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
    _tabController = TabController(length: 5, vsync: this);
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
                        Icon(Icons.add_box_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Borrow Stock'),
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

                  // Tab 4: Request Borrow Stock
                  _BorrowStockTab(isDark: isDark),

                  // Tab 5: My Requests
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

// ─── Tab 2: Members Lookup (Read-Only) ─────────────────────────────────────

class _MembersLookupTab extends StatelessWidget {
  const _MembersLookupTab();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: MembersTable(
        onRowSelected: (member) => _showMemberDetail(context, member),
      ),
    );
  }

  static void _showMemberDetail(
    BuildContext context,
    Map<String, dynamic> member,
  ) {
    final fullName = [
      member['firstName'],
      member['middleName'],
      member['lastName'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');

    showAnimatedDialog(
      context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 700,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fullName.isEmpty ? 'Member Details' : fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: MemberDetailsCard(
                      member: member,
                      showHeader: false,
                      showCardStyling: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

// ─── Tab 4: Active Borrows (read-only) ─────────────────────────────────────

class _BorrowStockTab extends StatefulWidget {
  final bool isDark;
  const _BorrowStockTab({required this.isDark});

  @override
  State<_BorrowStockTab> createState() => _BorrowStockTabState();
}

class _BorrowStockTabState extends State<_BorrowStockTab> {
  List<Borrow> _borrows = [];
  List<Member> _members = [];
  bool _loading = true;
  String _settledFilter = 'all'; // all, returned, remitted

  static const _amber = Color(0xFFF59E0B);
  static const _emerald = Color(0xFF10B981);
  static const _rose = Color(0xFFEF4444);
  static const _slate = Color(0xFF64748B);
  static const _indigo = Color(0xFF6366F1);
  static const _purple = Color(0xFF8B5CF6);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final borrows = await repository.fetchBorrows();
      final members = await repository.fetchMembers();
      if (!mounted) return;
      // Sort: unsettled/active first, then latest to oldest within each group
      borrows.sort((a, b) {
        final aUnsettled = a.outstandingQuantity > 0 ? 0 : 1;
        final bUnsettled = b.outstandingQuantity > 0 ? 0 : 1;
        if (aUnsettled != bUnsettled) return aUnsettled.compareTo(bUnsettled);
        return (b.borrowedAt ?? DateTime(0)).compareTo(
          a.borrowedAt ?? DateTime(0),
        );
      });
      setState(() {
        _borrows = borrows;
        _members = members;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _memberName(int memberId) {
    final m = _members.cast<Member?>().firstWhere(
      (m) => m?.id == memberId,
      orElse: () => null,
    );
    if (m == null) return 'Member #$memberId';
    return '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim();
  }

  // ── Active / overdue ───────────────────────────────────────────
  List<Borrow> get _activeBorrows =>
      _borrows.where((b) => b.outstandingQuantity > 0).toList();

  int get _overdueCount => _activeBorrows.where((b) => b.isOverdue).length;

  int get _activeCount => _activeBorrows.length - _overdueCount;

  int get _totalOutstanding =>
      _activeBorrows.fold(0, (s, b) => s + b.outstandingQuantity);

  // ── Settled ────────────────────────────────────────────────────
  List<Borrow> get _allSettled =>
      _borrows.where((b) => b.outstandingQuantity <= 0).toList();

  List<Borrow> get _returnedOnly =>
      _allSettled.where((b) => b.quantityReturned >= b.quantity).toList();

  List<Borrow> get _remittedOnly =>
      _allSettled.where((b) => b.quantityRemitted >= b.quantity).toList();

  List<Borrow> get _filteredSettled {
    switch (_settledFilter) {
      case 'returned':
        return _returnedOnly;
      case 'remitted':
        return _remittedOnly;
      default:
        return _allSettled;
    }
  }

  int get _settledCount => _allSettled.length;
  int get _returnedCount => _returnedOnly.length;
  int get _remittedCount => _remittedOnly.length;

  String _formatDue(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.isNegative) return 'Overdue';
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Tomorrow';
    if (diff.inDays < 7) return '${diff.inDays}d left';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  // ── Stat pill ────────────────────────────────────────────────────
  Widget _statPill(String label, int count, Color color, IconData icon) {
    final isDark = widget.isDark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(isDark ? 25 : 15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(isDark ? 60 : 40)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color.withAlpha(200),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Card builder ─────────────────────────────────────────────────
  Widget _buildCard(Borrow b) {
    final isDark = widget.isDark;
    final isOverdue = b.isOverdue && b.outstandingQuantity > 0;
    final accentColor = isOverdue ? _rose : _amber;
    final memberName = b.memberName ?? _memberName(b.memberId);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOverdue
              ? _rose.withAlpha(isDark ? 50 : 30)
              : (isDark ? Colors.white10 : Colors.grey.shade200),
          width: isOverdue ? 1.5 : 1,
        ),
      ),
      color: isOverdue
          ? _rose.withAlpha(isDark ? 8 : 5)
          : (isDark ? Colors.grey.shade900 : Colors.white),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Avatar + item name + status
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(isDark ? 30 : 20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    size: 22,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.itemName,
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
                        memberName,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : _slate,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? _rose.withAlpha(isDark ? 25 : 15)
                        : _emerald.withAlpha(isDark ? 25 : 15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (isOverdue ? _rose : _emerald).withAlpha(
                        isDark ? 60 : 40,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOverdue
                            ? Icons.warning_rounded
                            : Icons.check_circle_rounded,
                        size: 13,
                        color: isOverdue ? _rose : _emerald,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOverdue ? 'Overdue' : 'Active',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isOverdue ? _rose : _emerald,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Progress / detail row
            const SizedBox(height: 14),
            Row(
              children: [
                // Borrowed
                _detailPill(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Borrowed',
                  value: '${b.quantity}',
                  color: _indigo,
                ),
                const SizedBox(width: 8),
                // Outstanding
                _detailPill(
                  icon: isOverdue
                      ? Icons.warning_rounded
                      : Icons.hourglass_empty_rounded,
                  label: 'Outstanding',
                  value: '${b.outstandingQuantity}',
                  color: isOverdue ? _rose : _amber,
                ),
                const Spacer(),
                // Due date
                Icon(
                  Icons.calendar_today_rounded,
                  size: 12,
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDue(b.dueDate),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w500,
                    color: isOverdue
                        ? _rose
                        : (isDark ? Colors.white38 : Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Settled card builder ──────────────────────────────────────
  Widget _buildSettledCard(Borrow b) {
    final isDark = widget.isDark;
    final isReturned = b.quantityReturned >= b.quantity;
    final accentColor = isReturned ? _emerald : _purple;
    final statusIcon = isReturned
        ? Icons.assignment_return_rounded
        : Icons.payments_rounded;
    final statusLabel = isReturned ? 'Returned' : 'Remitted';
    final settledQty = isReturned ? b.quantityReturned : b.quantityRemitted;
    final memberName = b.memberName ?? _memberName(b.memberId);
    final settledDate = b.settledAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accentColor.withAlpha(isDark ? 40 : 25)),
      ),
      color: accentColor.withAlpha(isDark ? 6 : 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor.withAlpha(isDark ? 25 : 15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(statusIcon, size: 18, color: accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.itemName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        memberName,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : _slate,
                        ),
                      ),
                      if (settledDate != null) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.circle,
                          size: 4,
                          color: isDark ? Colors.white24 : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${settledDate.day}/${settledDate.month}/${settledDate.year}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white24 : Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withAlpha(isDark ? 20 : 12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$settledQty',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: accentColor.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final isDark = widget.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 20 : 12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }

  // ── Settled filter chip ───────────────────────────────────────
  Widget _settledFilterChip({
    required String label,
    required int count,
    required String value,
    required Color color,
  }) {
    final isDark = widget.isDark;
    final selected = _settledFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _settledFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? color.withAlpha(isDark ? 30 : 20)
              : (isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color.withAlpha(isDark ? 80 : 60)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? color : (isDark ? Colors.white38 : _slate),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: selected
                    ? color.withAlpha(200)
                    : (isDark ? Colors.white24 : Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return RefreshIndicator(
      onRefresh: _loadData,
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Borrow Stock',
                                style: StockpileFonts.satoshi(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_borrows.length} total',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _slate,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Stats row
                        Row(
                          children: [
                            _statPill(
                              'Active',
                              _activeCount,
                              _emerald,
                              Icons.check_circle_rounded,
                            ),
                            const SizedBox(width: 8),
                            _statPill(
                              'Overdue',
                              _overdueCount,
                              _rose,
                              Icons.warning_rounded,
                            ),
                            const SizedBox(width: 8),
                            _statPill(
                              'Outstanding',
                              _totalOutstanding,
                              _amber,
                              Icons.hourglass_empty_rounded,
                            ),
                            const SizedBox(width: 8),
                            _statPill(
                              'Settled',
                              _settledCount,
                              _indigo,
                              Icons.task_alt_rounded,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Content ─────────────────────────────────────
                if (_borrows.isEmpty)
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
                              Icons.swap_horiz_rounded,
                              size: 40,
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade300,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Borrows',
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
                            'Borrow stock via the POS Terminal\nusing the Borrow button.',
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
                else ...[
                  // ── Active borrows ──────────────────────────
                  if (_activeBorrows.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white54 : _slate,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  if (_activeBorrows.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _buildCard(_activeBorrows[i]),
                          childCount: _activeBorrows.length,
                        ),
                      ),
                    ),

                  // ── Settled borrows ─────────────────────────
                  if (_allSettled.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Row(
                          children: [
                            Text(
                              'Settled',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white54 : _slate,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            // Filter chips
                            _settledFilterChip(
                              label: 'All',
                              count: _settledCount,
                              value: 'all',
                              color: _indigo,
                            ),
                            const SizedBox(width: 6),
                            _settledFilterChip(
                              label: 'Returned',
                              count: _returnedCount,
                              value: 'returned',
                              color: _emerald,
                            ),
                            const SizedBox(width: 6),
                            _settledFilterChip(
                              label: 'Remitted',
                              count: _remittedCount,
                              value: 'remitted',
                              color: _purple,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _buildSettledCard(_filteredSettled[i]),
                          childCount: _filteredSettled.length,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
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
  String _statusFilter = 'all';
  String _typeFilter = 'all';
  bool _newestFirst = true;

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
    try {
      final requests = await repository.fetchMyRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
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

  // ── Segmented status filter ──────────────────────────────────────
  Widget _segmentedFilter() {
    final isDark = widget.isDark;
    final items = [
      _FilterSegment('All', 'all', Icons.inbox_rounded, _requests.length),
      _FilterSegment(
        'Pending',
        'pending',
        Icons.hourglass_empty_rounded,
        _countBy('pending'),
      ),
      _FilterSegment(
        'Approved',
        'approved',
        Icons.check_circle_rounded,
        _countBy('approved'),
      ),
      _FilterSegment(
        'Rejected',
        'rejected',
        Icons.cancel_rounded,
        _countBy('rejected'),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: items.map((item) {
          final selected = _statusFilter == item.value;
          final bgColor = selected
              ? (isDark ? Colors.grey.shade800 : Colors.white)
              : Colors.transparent;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _statusFilter = item.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 30 : 10),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      item.icon,
                      size: 16,
                      color: selected ? _indigo : _slate,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.count}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? (isDark ? Colors.white : _indigo)
                            : _slate,
                      ),
                    ),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? (isDark ? Colors.white70 : _indigo.withAlpha(180))
                            : _slate.withAlpha(180),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
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

            // Reason section
            if (req.reason != null && req.reason!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withAlpha(15)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.format_quote_rounded,
                      size: 15,
                      color: _slate.withAlpha(150),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        req.reason!,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: isDark ? Colors.white54 : _slate,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
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
                                : 'Submitted deletion & borrow requests\nwill appear here',
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
                        childCount: filtered.length,
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
