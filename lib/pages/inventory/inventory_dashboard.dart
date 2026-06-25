// lib/pages/inventory/inventory_dashboard.dart
// Inventory Dashboard with two navigation tabs:
//   1. Inventory CRUD — manage items, stock levels, product details.
//   2. In/Out/Borrow Reports — read-only logs of inventory history.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/inventorytable.dart';

class InventoryDashboard extends StatefulWidget {
  const InventoryDashboard({super.key});

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard>
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
                          'Inventory Management',
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
                          'Welcome, ${auth.username} · Inventory Team',
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
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? StockpileColors.darkInputBg
                    : StockpileColors.inputBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
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
                        Icon(Icons.inventory_2_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Inventory'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('In / Out / Borrow Reports'),
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
                  // Tab 1: Inventory CRUD
                  const _InventoryCrudTab(),

                  // Tab 2: In/Out/Borrow Reports (read-only)
                  _InventoryReportsTab(isDark: isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab 1: Inventory CRUD ──────────────────────────────────────────────────

class _InventoryCrudTab extends StatelessWidget {
  const _InventoryCrudTab();

  @override
  Widget build(BuildContext context) {
    // Reuse the existing InventoryTable widget which provides full CRUD
    // capabilities: view items, edit stock, add products, etc.
    return const Padding(padding: EdgeInsets.all(16), child: InventoryTable());
  }
}

// ─── Tab 2: In/Out/Borrow Reports (read-only) ───────────────────────────────

class _InventoryReportsTab extends StatefulWidget {
  final bool isDark;
  const _InventoryReportsTab({required this.isDark});

  @override
  State<_InventoryReportsTab> createState() => _InventoryReportsTabState();
}

class _InventoryReportsTabState extends State<_InventoryReportsTab> {
  // Mock report data — in production, fetch from repository/API.
  final List<Map<String, dynamic>> _movements = [];

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  Future<void> _loadMovements() async {
    // TODO: Replace with actual data from repository.fetchSales() or a
    // dedicated stock movement log.
    setState(() {
      // Populate with placeholder data for the UI wireframe.
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          Row(
            children: [
              Expanded(
                child: _ReportStatCard(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Stock In',
                  value: '—',
                  color: StockpileColors.success,
                  isDark: widget.isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ReportStatCard(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Stock Out',
                  value: '—',
                  color: StockpileColors.error500,
                  isDark: widget.isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ReportStatCard(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Borrowed',
                  value: '—',
                  color: StockpileColors.secondary500,
                  isDark: widget.isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Read-only movement log
          Text(
            'Movement History',
            style: StockpileFonts.satoshi(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: widget.isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          const SizedBox(height: 12),

          if (_movements.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? StockpileColors.darkSurface
                    : StockpileColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.isDark
                      ? StockpileColors.darkDivider
                      : StockpileColors.divider,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 48,
                    color: widget.isDark
                        ? StockpileColors.darkTextMuted
                        : StockpileColors.mutedText,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No movements recorded yet.',
                    style: StockpileFonts.satoshi(
                      fontSize: 15,
                      color: widget.isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stock in, out, and borrow activity will appear here.',
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      color: widget.isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_movements.length, (i) {
              final m = _movements[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: StockpileColors.primary100,
                  child: Icon(
                    Icons.swap_vert_rounded,
                    color: StockpileColors.primary700,
                  ),
                ),
                title: Text(m['item'] ?? ''),
                subtitle: Text(
                  '${m['type']} · ${m['qty']} units · ${m['date']}',
                ),
                trailing: Text(m['user'] ?? ''),
              );
            }),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ─────────────────────────────────────────────────────────

class _ReportStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _ReportStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: StockpileFonts.satoshi(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          Text(
            label,
            style: StockpileFonts.satoshi(
              fontSize: 11,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
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
