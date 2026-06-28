// lib/pages/cashier/cashier_dashboard.dart
// Cashier Dashboard — restricted to Cashier role only.
// Tabs:
//   1. Transaction — POS terminal for processing sales.
//   2. Members — Read-only member lookup.
//   3. Request Member Deletion — POST-based deletion request for Admin approval.
//   4. Request Borrow Stock — POST-based borrow stock request for review.
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
                        Icon(Icons.add_box_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Borrow Stock'),
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final borrows = await repository.fetchActiveBorrows();
      final members = await repository.fetchMembers();
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_borrows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_horiz_rounded,
              size: 48,
              color: widget.isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
            const SizedBox(height: 12),
            Text(
              'No Active Borrows',
              style: StockpileFonts.satoshi(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: widget.isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Borrow stock via the POS Terminal using the Borrow button.',
              textAlign: TextAlign.center,
              style: StockpileFonts.satoshi(
                fontSize: 13,
                color: widget.isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _borrows.length,
        itemBuilder: (context, index) {
          final b = _borrows[index];
          final memName = b.memberName ?? _memberName(b.memberId);
          final overdue = b.isOverdue && b.outstandingQuantity > 0;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: overdue
                    ? StockpileColors.error500.withAlpha(120)
                    : Colors.transparent,
                width: overdue ? 1.5 : 0,
              ),
            ),
            color: overdue ? StockpileColors.error50.withAlpha(80) : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: overdue
                        ? StockpileColors.error100
                        : StockpileColors.secondary100,
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      size: 18,
                      color: overdue
                          ? StockpileColors.error500
                          : StockpileColors.secondary700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.itemName,
                          style: StockpileFonts.satoshi(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: widget.isDark
                                ? StockpileColors.darkTextPrimary
                                : StockpileColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          memName,
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            color: widget.isDark
                                ? StockpileColors.darkTextMuted
                                : StockpileColors.mutedText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Borrowed: ${b.quantity}  ·  '
                          'Outstanding: ${b.outstandingQuantity}',
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            color: widget.isDark
                                ? StockpileColors.darkTextBody
                                : StockpileColors.bodyText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: overdue
                              ? StockpileColors.error500.withAlpha(30)
                              : Colors.blue.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          overdue ? 'Overdue' : 'Active',
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: overdue
                                ? StockpileColors.error500
                                : Colors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Due: ${b.dueDate.day}/${b.dueDate.month}/${b.dueDate.year}',
                        style: StockpileFonts.satoshi(
                          fontSize: 11,
                          color: overdue
                              ? StockpileColors.error500
                              : (widget.isDark
                                    ? StockpileColors.darkTextMuted
                                    : StockpileColors.mutedText),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
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
