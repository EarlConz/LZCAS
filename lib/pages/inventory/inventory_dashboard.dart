// lib/pages/inventory/inventory_dashboard.dart
// Inventory Dashboard — restricted to Inventory role only.
// Tabs:
//   1. Inventory — Full CRUD for items, stock levels, product details.
//   2. In/Out/Borrow Reports — Read-only logs of inventory activity.
//   3. My Requests — Track submitted deletion & reduction requests.
// Inventory role CANNOT see: cashier tabs, admin tabs, member management,
// POS transactions, or borrow requests.

import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:lzcas/auth/auth.dart";
import "package:lzcas/router/route_guard.dart";
import "package:lzcas/theme.dart";
import "package:lzcas/utils/fonts.dart";
import "package:lzcas/widgets/inventorytable.dart";
import "package:lzcas/widgets/inventory_reports_view.dart";
import "package:lzcas/widgets/my_requests_tab.dart";

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
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Defense-in-depth: only inventory + admin roles may render this dashboard.
    assertRoleOrThrow(context, {UserRole.inventory});

    final auth = context.watch<AuthState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // -- Header --------------------------------------------------
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Inventory Management",
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
                          "Welcome, ${auth.username} � Inventory Team",
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

            // -- Tab Bar � Only Inventory + Reports ----------------------
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
                        Text("Inventory"),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_rounded, size: 18),
                        SizedBox(width: 6),
                        Text("In / Out / Borrow Reports"),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_rounded, size: 18),
                        SizedBox(width: 6),
                        Text("My Requests"),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // -- Tab Content ---------------------------------------------
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Inventory CRUD
                  const _InventoryCrudTab(),

                  // Tab 2: In/Out/Borrow Reports (read-only)
                  _InventoryReportsTab(isDark: isDark),

                  // Tab 3: My Requests — track deletion & reduction requests
                  MyRequestsTab(
                    isDark: isDark,
                    typeFilters: const [
                      FilterSegment('All', 'all', Icons.layers_rounded),
                      FilterSegment('Delete', 'delete', Icons.delete_rounded),
                      FilterSegment(
                        'Reduce',
                        'reduce_stock',
                        Icons.remove_circle_rounded,
                      ),
                    ],
                    emptyMessage:
                        'Submitted deletion & stock reduction requests\nwill appear here',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Tab 1: Inventory CRUD --------------------------------------------------

class _InventoryCrudTab extends StatelessWidget {
  const _InventoryCrudTab();

  @override
  Widget build(BuildContext context) {
    return const Padding(padding: EdgeInsets.all(16), child: InventoryTable());
  }
}

// --- Tab 2: In/Out/Borrow Reports (read-only, shared widget) ---------------

class _InventoryReportsTab extends StatelessWidget {
  final bool isDark;
  const _InventoryReportsTab({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: InventoryReportsView(),
    );
  }
}

// --- Shared Logout Button (uses confirmation) -------------------------------

class _LogoutButton extends StatelessWidget {
  final AuthState auth;

  const _LogoutButton({required this.auth});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout_rounded),
      tooltip: "Logout",
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Logout"),
            content: const Text("Are you sure you want to sign out?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Logout"),
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
