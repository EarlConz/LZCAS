// lib/pages/branch/branch_cashier_dashboard.dart
// Branch Cashier Dashboard — a restricted staff role.
// Two tabs only:
//   1. POS Terminal   — process sales (reuses the existing TransactionsTable).
//   2. Stocks on Hand — READ-ONLY current stock with Good/Low/Out status.
// Branch cashier CANNOT see: members, inventory CRUD, reports, admin, users.
// (The narrow surface is enforced here in the UI; at the DB level the role is
//  treated as staff — see migration_v28_branch_cashier_role.sql.)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/transactionstable.dart';
import 'package:lzcas/db/db.dart';

class BranchCashierDashboard extends StatefulWidget {
  const BranchCashierDashboard({super.key});

  @override
  State<BranchCashierDashboard> createState() => _BranchCashierDashboardState();
}

class _BranchCashierDashboardState extends State<BranchCashierDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Defense-in-depth: only branch cashier role may render this dashboard.
    assertRoleOrThrow(context, {UserRole.branchCashier});

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
                          'Branch Terminal',
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
                          'Welcome, ${auth.username} · Branch Cashier',
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
                labelColor: StockpileColors.primary900,
                unselectedLabelColor: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
                indicator: BoxDecoration(
                  color: isDark ? StockpileColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.point_of_sale_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('POS Terminal'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Stocks on Hand'),
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
                children: const [
                  // Tab 1: POS terminal (reused)
                  Padding(padding: EdgeInsets.all(16), child: TransactionsTable()),
                  // Tab 2: Stocks on Hand (read-only)
                  _StocksOnHandView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Logout ─────────────────────────────────────────────────────────────────

class _LogoutButton extends StatelessWidget {
  final AuthState auth;
  const _LogoutButton({required this.auth});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Log out',
      icon: const Icon(Icons.logout_rounded),
      onPressed: () async {
        await auth.logout();
        if (!context.mounted) return;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
      },
    );
  }
}

// ─── Stocks on Hand (read-only) ─────────────────────────────────────────────

class _StocksOnHandView extends StatefulWidget {
  const _StocksOnHandView();

  @override
  State<_StocksOnHandView> createState() => _StocksOnHandViewState();
}

class _StocksOnHandViewState extends State<_StocksOnHandView> {
  late Future<_StockData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_StockData> _load() async {
    // All products, plus the below-threshold set (status = stock_status) so we
    // can show accurate Good/Low/Out flags without any write capability.
    final all = await repository.fetchItems();
    final low = await repository.fetchLowStockItems();
    final statusById = {for (final it in low) it.id: it.status ?? ''};
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return _StockData(all, statusById);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StockData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data;
        if (data == null || data.items.isEmpty) {
          return const Center(child: Text('No products found.'));
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: data.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final it = data.items[i];
              final status = it.stock <= 0
                  ? 'Out of Stock'
                  : (data.statusById[it.id] ?? 'Good');
              final color = status == 'Out of Stock'
                  ? Colors.red
                  : (status == 'Low Stock' ? Colors.orange : Colors.green);
              return ListTile(
                dense: true,
                title: Text(
                  it.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(it.category ?? 'Uncategorized'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${it.stock}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: color,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      status,
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _StockData {
  final List<Item> items;
  final Map<int?, String> statusById;
  const _StockData(this.items, this.statusById);
}
