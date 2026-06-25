// lib/pages/cashier/cashier_dashboard.dart
// Cashier Dashboard with four tab modules:
//   1. Transaction — POS terminal for processing sales.
//   2. Members — Read-only member lookup.
//   3. Request Member Deletion — POST-based deletion request for Admin approval.
//   4. Request Borrow Stock — POST-based borrow stock request for review.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/memberstable.dart';
import 'package:lzcas/widgets/transactionstable.dart';

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

  static void _noOpMemberSelect(Map<String, dynamic> _) {
    // Read-only mode — no action on member row selection.
  }

  @override
  Widget build(BuildContext context) {
    // Reuse existing MembersTable in read-only mode.
    // The cashier role does not have edit/delete permissions.
    return const Padding(
      padding: EdgeInsets.all(16),
      child: MembersTable(onRowSelected: _noOpMemberSelect),
    );
  }
}

// ─── Tab 3: Request Member Deletion ─────────────────────────────────────────

class _RequestDeletionTab extends StatefulWidget {
  final bool isDark;
  const _RequestDeletionTab({required this.isDark});

  @override
  State<_RequestDeletionTab> createState() => _RequestDeletionTabState();
}

class _RequestDeletionTabState extends State<_RequestDeletionTab> {
  final _memberIdCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;
  String? _feedback;

  @override
  void dispose() {
    _memberIdCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitDeletionRequest() async {
    final memberId = _memberIdCtrl.text.trim();
    final reason = _reasonCtrl.text.trim();

    if (memberId.isEmpty || reason.isEmpty) {
      setState(() => _feedback = 'Please fill in all fields.');
      return;
    }

    setState(() {
      _submitting = true;
      _feedback = null;
    });

    try {
      // Refresh CSRF token before sending the state-changing request.
      final auth = context.read<AuthState>();
      await auth.refreshCsrfToken();

      // POST request to initiate deletion request for admin approval.
      // final client = context.read<ApiClient>();
      // await client.post('/api/cashier/delete-member-request', data: {
      //   'memberId': int.tryParse(memberId),
      //   'reason': reason,
      // });

      // Simulate API delay
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;
      _memberIdCtrl.clear();
      _reasonCtrl.clear();
      setState(() {
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

            TextFormField(
              controller: _memberIdCtrl,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Member ID',
                hintText: 'Enter the member ID to delete',
                prefixIcon: Icon(Icons.person_search_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reasonCtrl,
              enabled: !_submitting,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason for Deletion',
                hintText: 'Explain why this member should be removed',
                alignLabelWithHint: true,
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Icon(Icons.edit_note_rounded),
                ),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

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

// ─── Tab 4: Request Borrow Stock ────────────────────────────────────────────

class _BorrowStockTab extends StatefulWidget {
  final bool isDark;
  const _BorrowStockTab({required this.isDark});

  @override
  State<_BorrowStockTab> createState() => _BorrowStockTabState();
}

class _BorrowStockTabState extends State<_BorrowStockTab> {
  final _itemNameCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;
  String? _feedback;

  @override
  void dispose() {
    _itemNameCtrl.dispose();
    _quantityCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitBorrowRequest() async {
    final itemName = _itemNameCtrl.text.trim();
    final quantity = _quantityCtrl.text.trim();
    final reason = _reasonCtrl.text.trim();

    if (itemName.isEmpty || quantity.isEmpty || reason.isEmpty) {
      setState(() => _feedback = 'Please fill in all fields.');
      return;
    }

    if (int.tryParse(quantity) == null || int.parse(quantity) <= 0) {
      setState(() => _feedback = 'Quantity must be a positive number.');
      return;
    }

    setState(() {
      _submitting = true;
      _feedback = null;
    });

    try {
      // Refresh CSRF token before sending the state-changing request.
      final auth = context.read<AuthState>();
      await auth.refreshCsrfToken();

      // POST request to submit borrow stock request.
      // final client = context.read<ApiClient>();
      // await client.post('/api/cashier/borrow-stock-request', data: {
      //   'itemName': itemName,
      //   'quantity': int.parse(quantity),
      //   'reason': reason,
      // });

      // Simulate API delay
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;
      _itemNameCtrl.clear();
      _quantityCtrl.clear();
      _reasonCtrl.clear();
      setState(() {
        _feedback = 'Borrow stock request submitted for review.';
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
                color: StockpileColors.secondary50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: StockpileColors.secondary200.withAlpha(120),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: StockpileColors.secondary700,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Submit a request to borrow stock from the inventory. '
                      'This will be reviewed by the Admin or Inventory team.',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        color: StockpileColors.secondary700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Request Borrow Stock',
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

            TextFormField(
              controller: _itemNameCtrl,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Item Name',
                hintText: 'e.g., Office Chair',
                prefixIcon: Icon(Icons.inventory_2_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantityCtrl,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                hintText: 'Number of units to borrow',
                prefixIcon: Icon(Icons.numbers_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reasonCtrl,
              enabled: !_submitting,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason for Borrowing',
                hintText: 'Explain why you need to borrow this item',
                alignLabelWithHint: true,
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Icon(Icons.edit_note_rounded),
                ),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

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
                  _submitting ? 'Submitting…' : 'Submit Borrow Request',
                ),
                onPressed: _submitting ? null : _submitBorrowRequest,
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
