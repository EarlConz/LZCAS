// lib/pages/admin/admin_dashboard.dart
// Admin Dashboard — full unrestricted access to ALL application features.
// The admin role passes every role assertion and can access every tab
// from every dashboard (admin, inventory, and cashier).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/inventorytable.dart' as inventory;
import 'package:lzcas/widgets/stockpile_topbar.dart';
import 'package:lzcas/widgets/transactionstable.dart';
import 'package:lzcas/widgets/memberstable.dart';
import 'package:lzcas/widgets/inventory_reports_view.dart';
import 'package:lzcas/pages/dashboardpage.dart';
import 'package:lzcas/data/supabase_config.dart';
import 'package:lzcas/db/db.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _pageTitles = [
    'Dashboard',
    'User Management',
    'Inventory · Stock',
    'Inventory · Reports',
    'POS Terminal',
    'Members',
    'Deletion Requests',
    'Borrow Stock',
    'Settings',
    'Help & Support',
  ];

  List<Widget> _buildPages() => const [
    // 0: Dashboard — recovered from original DashboardPage
    _AdminDashboardPage(),
    // 1: Users — user provisioning
    _UserManagementTab(),
    // 2: Inventory — full CRUD via InventoryTable
    _AdminInventoryTab(),
    // 3: Reports — In/Out/Borrow read-only
    _AdminReportsTab(),
    // 4: POS Terminal — shared with Cashier via TransactionsTable
    _AdminPosTab(),
    // 5: Members — recovered full MembersTable
    _AdminMembersPage(),
    // 6: Deletion Requests
    _AdminDeleteRequestTab(),
    // 7: Borrow Stock
    _AdminBorrowStockTab(),
    // 8: Settings — Global Config moved here
    _AdminSettingsTab(),
    // 9: Help & Support
    _AdminHelpTab(),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  void _toggleSidebar() {
    if (_scaffoldKey.currentState!.isDrawerOpen) {
      _scaffoldKey.currentState!.closeDrawer();
    } else {
      _scaffoldKey.currentState!.openDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Defense-in-depth: only admins may render this dashboard.
    assertRoleOrThrow(context, {UserRole.admin});

    final auth = context.watch<AuthState>();
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final pages = _buildPages();

    final sidebar = _AdminSidebar(
      selectedIndex: _selectedIndex,
      auth: auth,
      onItemSelected: (i) {
        if (!isDesktop) Navigator.pop(context);
        _onItemTapped(i);
      },
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: isDesktop ? null : sidebar,
      body: Row(
        children: [
          // Desktop sidebar
          if (isDesktop) SizedBox(width: 260, child: sidebar),
          if (isDesktop) const VerticalDivider(width: 1),

          // Main content area
          Expanded(
            child: Column(
              children: [
                // ── Top Bar ────────────────────────────────────────────
                StockpileTopBar(
                  pageTitle: _pageTitles[_selectedIndex],
                  showMenu: !isDesktop,
                  onMenuTap: _toggleSidebar,
                  onAddNewItem: () {
                    // Admin can add products from any page; default to
                    // opening the add-product dialog.
                  },
                ),
                // ── Page Content ───────────────────────────────────────
                Expanded(child: pages[_selectedIndex]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dashboard — recovered from original DashboardPage ─────────────────────

class _AdminDashboardPage extends StatelessWidget {
  const _AdminDashboardPage();

  @override
  Widget build(BuildContext context) {
    return const DashboardPage();
  }
}

// ─── User Management Tab ────────────────────────────────────────────────────

class _UserManagementTab extends StatefulWidget {
  const _UserManagementTab();

  @override
  State<_UserManagementTab> createState() => _UserManagementTabState();
}

class _UserManagementTabState extends State<_UserManagementTab> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrls = List.generate(1, (_) => TextEditingController());
  UserRole _selectedRole = UserRole.cashier;
  bool _creating = false;
  String? _createError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    for (final c in _passwordCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _createUser() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrls[0].text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _createError = 'All fields are required.');
      return;
    }

    setState(() {
      _creating = true;
      _createError = null;
    });

    try {
      final auth = context.read<AuthState>();

      // Create the user via Supabase Auth (online)
      final ok = await auth.createUser(
        email: email,
        password: password,
        role: _selectedRole,
      );

      if (!ok) {
        setState(
          () => _createError = auth.error.isNotEmpty
              ? auth.error
              : 'Failed to create user.',
        );
        return;
      }

      if (!mounted) return;
      _nameCtrl.clear();
      _emailCtrl.clear();
      _passwordCtrls[0].clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User created successfully.')),
      );
    } catch (e) {
      setState(() => _createError = e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create New User',
            style: StockpileFonts.satoshi(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Provision a new account. Users cannot self-register.',
            style: StockpileFonts.satoshi(
              fontSize: 13,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
          const SizedBox(height: 20),

          if (_createError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: StockpileColors.dangerBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _createError!,
                style: const TextStyle(color: StockpileColors.danger),
              ),
            ),

          TextFormField(
            controller: _nameCtrl,
            enabled: !_creating,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(Icons.person_outline_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailCtrl,
            enabled: !_creating,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email / Username',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordCtrls[0],
            enabled: !_creating,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Temporary Password',
              prefixIcon: Icon(Icons.lock_outline_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Role selector
          Text(
            'Role',
            style: StockpileFonts.satoshi(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<UserRole>(
            initialValue: _selectedRole,
            items: UserRole.values
                .map(
                  (r) => DropdownMenuItem(value: r, child: Text(r.displayName)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedRole = v);
            },
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_add_rounded),
              label: Text(_creating ? 'Creating…' : 'Create User'),
              onPressed: _creating ? null : _createUser,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Admin · Settings Tab — Global Config relocated from top nav ───────────

class _AdminSettingsTab extends StatefulWidget {
  const _AdminSettingsTab();

  @override
  State<_AdminSettingsTab> createState() => _AdminSettingsTabState();
}

class _AdminSettingsTabState extends State<_AdminSettingsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _settingsTabController;
  bool _syncing = false;
  bool _restoring = false;
  List<ResellerLevel> _levels = [];
  bool _levelsLoading = true;
  final Map<int, TextEditingController> _remMinCtls = {};
  final Map<int, TextEditingController> _remMaxCtls = {};
  final Map<int, TextEditingController> _cashAdvCtls = {};

  @override
  void initState() {
    super.initState();
    _settingsTabController = TabController(length: 3, vsync: this);
    _loadLevels();
  }

  @override
  void dispose() {
    _settingsTabController.dispose();
    for (final c in [
      ..._remMinCtls.values,
      ..._remMaxCtls.values,
      ..._cashAdvCtls.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLevels() async {
    final rows = await repository.fetchResellerLevels();
    for (final c in [
      ..._remMinCtls.values,
      ..._remMaxCtls.values,
      ..._cashAdvCtls.values,
    ]) {
      c.dispose();
    }
    _remMinCtls.clear();
    _remMaxCtls.clear();
    _cashAdvCtls.clear();
    for (final r in rows) {
      _remMinCtls[r.level] = TextEditingController(
        text: r.remittanceMin.toString(),
      );
      _remMaxCtls[r.level] = TextEditingController(
        text: r.remittanceMax.toString(),
      );
      _cashAdvCtls[r.level] = TextEditingController(
        text: r.cashAdvance.toString(),
      );
    }
    setState(() {
      _levels = rows;
      _levelsLoading = false;
    });
  }

  Future<void> _saveLevels() async {
    for (final lvl in _levels) {
      await repository.upsertResellerLevel(
        level: lvl.level,
        remittanceMin: int.tryParse(_remMinCtls[lvl.level]?.text ?? '0') ?? 0,
        remittanceMax: int.tryParse(_remMaxCtls[lvl.level]?.text ?? '0') ?? 0,
        cashAdvance: int.tryParse(_cashAdvCtls[lvl.level]?.text ?? '0') ?? 0,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Reseller levels saved')));
  }

  // ── Cloud Sync ────────────────────────────────────────────────────────

  Future<void> _syncToCloud() async {
    if (!SupabaseConfig.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supabase is not configured for this run'),
        ),
      );
      return;
    }

    final items = await repository.fetchItems();
    final members = await repository.fetchMembers();
    final sales = await repository.fetchSales();
    final isEmpty = items.isEmpty && members.isEmpty && sales.isEmpty;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync to Cloud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will overwrite the cloud snapshot with your local data.',
            ),
            const SizedBox(height: 12),
            Text('• ${items.length} items'),
            Text('• ${members.length} members'),
            Text('• ${sales.length} sales'),
            if (isEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error.withAlpha(80),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your local database is empty. Syncing now '
                        'will DELETE all cloud data.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: isEmpty
                ? ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEmpty ? 'Sync Anyway' : 'Sync'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _syncing = true);
    try {
      // Data is already in the cloud — no sync needed.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All data is already stored in Supabase.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _restoreFromCloud() async {
    if (!SupabaseConfig.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supabase is not configured for this run'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from cloud'),
        content: const Text(
          'This will replace your local inventory, members, and transactions '
          'with the current Supabase snapshot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _restoring = true);
    try {
      // Data is already cloud-based — no restore needed.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data is already cloud-based. No restore needed.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to restore from Supabase: $e')),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _clearDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear database'),
        content: const Text(
          'This will permanently delete all records from the local database.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await repository.clearAllData();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Local database cleared')));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Settings header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            children: [
              Text(
                'Settings',
                style: StockpileFonts.satoshi(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Tab bar: General | Cloud Sync | Reseller Levels
        TabBar(
          controller: _settingsTabController,
          labelColor: StockpileColors.primary900,
          unselectedLabelColor: isDark
              ? StockpileColors.darkTextMuted
              : StockpileColors.mutedText,
          indicatorColor: StockpileColors.primary900,
          tabs: const [
            Tab(text: 'General'),
            Tab(text: 'Cloud Sync'),
            Tab(text: 'Reseller Levels'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _settingsTabController,
            children: [
              // ── General Tab ─────────────────────────────────────────
              _buildGeneralTab(isDark),
              // ── Cloud Sync Tab ──────────────────────────────────────
              _buildCloudSyncTab(isDark),
              // ── Reseller Levels Tab ─────────────────────────────────
              _buildResellerLevelsTab(isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGeneralTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Global Configuration',
            style: StockpileFonts.satoshi(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          const SizedBox(height: 16),
          _ConfigTile(
            icon: Icons.palette_outlined,
            title: 'Dark Mode',
            subtitle: 'Toggle between light and dark appearance',
            trailing: Switch(
              value: isDark,
              onChanged: (_) {
                // The theme toggle is handled at the app level
              },
            ),
          ),
          _ConfigTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Configure system alerts and email notifications',
            trailing: Switch(value: true, onChanged: (_) {}),
          ),
          _ConfigTile(
            icon: Icons.security_rounded,
            title: 'Session Timeout',
            subtitle: 'Auto-logout after period of inactivity',
            trailing: const Text('30 min'),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudSyncTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supabase Cloud Sync',
            style: StockpileFonts.satoshi(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            SupabaseConfig.isConfigured
                ? 'Connected to ${SupabaseConfig.url}'
                : 'Supabase not configured',
            style: StockpileFonts.satoshi(
              fontSize: 13,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _syncing || _restoring ? null : _syncToCloud,
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_syncing ? 'Syncing...' : 'Sync to Cloud'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _syncing || _restoring ? null : _restoreFromCloud,
              icon: _restoring
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_restoring ? 'Restoring...' : 'Restore from Cloud'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: StockpileColors.error500,
                foregroundColor: Colors.white,
              ),
              onPressed: _clearDatabase,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Clear Local Database'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResellerLevelsTab(bool isDark) {
    if (_levelsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _levels.length,
            itemBuilder: (context, index) {
              final lvl = _levels[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Level ${lvl.level}',
                        style: StockpileFonts.satoshi(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? StockpileColors.darkTextPrimary
                              : StockpileColors.darkText,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _remMinCtls[lvl.level],
                        decoration: const InputDecoration(
                          labelText: 'Remittance Min',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _remMaxCtls[lvl.level],
                        decoration: const InputDecoration(
                          labelText: 'Remittance Max',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _cashAdvCtls[lvl.level],
                        decoration: const InputDecoration(
                          labelText: 'Cash Advance',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveLevels,
              icon: const Icon(Icons.save_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Save Reseller Levels'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Admin · Help & Support Tab ─────────────────────────────────────────────

class _AdminHelpTab extends StatelessWidget {
  const _AdminHelpTab();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.help_outline_rounded,
              size: 64,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
            const SizedBox(height: 16),
            Text(
              'Help & Support',
              style: StockpileFonts.satoshi(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Contact support@lzcas.app for assistance.',
              style: StockpileFonts.satoshi(
                fontSize: 16,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Admin Sidebar (styled after StockpileSidebar from UI Changes) ─────────

class _AdminSidebar extends StatelessWidget {
  final int selectedIndex;
  final AuthState auth;
  final ValueChanged<int> onItemSelected;

  const _AdminSidebar({
    required this.selectedIndex,
    required this.auth,
    required this.onItemSelected,
  });

  static const _navItems = <_NavItem>[
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.person_add_alt_rounded, 'Users'),
    _NavItem(Icons.inventory_2_rounded, 'Inventory'),
    _NavItem(Icons.history_rounded, 'Reports'),
    _NavItem(Icons.point_of_sale_rounded, 'POS Terminal'),
    _NavItem(Icons.people_alt_rounded, 'Members'),
    _NavItem(Icons.person_remove_rounded, 'Del. Requests'),
    _NavItem(Icons.add_box_rounded, 'Borrow Stock'),
  ];

  static const _bottomItems = <_NavItem>[
    _NavItem(Icons.settings_rounded, 'Settings'),
    _NavItem(Icons.help_outline_rounded, 'Help & Support'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final activeBg = isDark
        ? StockpileColors.darkSidebarActive
        : StockpileColors.sidebarActive;

    return Drawer(
      width: 260,
      backgroundColor: surface,
      elevation: 0,
      child: Column(
        children: [
          // ── Brand ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: StockpileColors.primary900,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'LZCAS · Admin',
                  style: StockpileFonts.satoshi(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? StockpileColors.darkTextPrimary
                        : StockpileColors.darkText,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // ── Navigation Items ─────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                ...List.generate(_navItems.length, (i) {
                  return _AdminSidebarTile(
                    item: _navItems[i],
                    isSelected: selectedIndex == i,
                    activeBg: activeBg,
                    isDark: isDark,
                    onTap: () => onItemSelected(i),
                  );
                }),
                const SizedBox(height: 12),
                Divider(
                  color: isDark
                      ? StockpileColors.darkDivider
                      : StockpileColors.divider,
                  indent: 12,
                  endIndent: 12,
                ),
                const SizedBox(height: 12),
                // Settings → index 8
                _AdminSidebarTile(
                  item: _bottomItems[0],
                  isSelected: selectedIndex == 8,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () => onItemSelected(8),
                ),
                // Help & Support → index 9
                _AdminSidebarTile(
                  item: _bottomItems[1],
                  isSelected: selectedIndex == 9,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () => onItemSelected(9),
                ),
              ],
            ),
          ),

          // ── User Profile Card ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? StockpileColors.darkInputBg
                    : StockpileColors.inputBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: StockpileColors.primary900,
                    child: Text(
                      auth.username.isNotEmpty
                          ? auth.username[0].toUpperCase()
                          : 'A',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          auth.username.isNotEmpty ? auth.username : 'Admin',
                          style: StockpileFonts.satoshi(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? StockpileColors.darkTextPrimary
                                : StockpileColors.darkText,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Admin',
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? StockpileColors.darkTextMuted
                                : StockpileColors.mutedText,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Logout button in profile card
                  IconButton(
                    icon: Icon(
                      Icons.logout_rounded,
                      size: 20,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                    onPressed: () => _confirmLogout(context, auth),
                    tooltip: 'Logout',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, AuthState auth) async {
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
  }
}

// ─── Sidebar Tile ───────────────────────────────────────────────────────────

class _AdminSidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final Color activeBg;
  final bool isDark;
  final VoidCallback onTap;

  const _AdminSidebarTile({
    required this.item,
    required this.isSelected,
    required this.activeBg,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected
        ? StockpileColors.primary900
        : isDark
        ? StockpileColors.darkTextBody
        : StockpileColors.bodyText;

    final bgColor = isSelected ? activeBg : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 20, color: textColor),
              const SizedBox(width: 12),
              Text(
                item.label,
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared Widgets ─────────────────────────────────────────────────────────

class _ConfigTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _ConfigTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isDark
                ? StockpileColors.darkTextBody
                : StockpileColors.bodyText,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: StockpileFonts.satoshi(
                    fontSize: 12,
                    color: isDark
                        ? StockpileColors.darkTextMuted
                        : StockpileColors.mutedText,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

// ─── Admin · Inventory Tab (directly uses InventoryTable) ──────────────────

class _AdminInventoryTab extends StatelessWidget {
  const _AdminInventoryTab();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: inventory.InventoryTable(),
    );
  }
}

// ─── Admin · Reports Tab ────────────────────────────────────────────────────

class _AdminReportsTab extends StatelessWidget {
  const _AdminReportsTab();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: InventoryReportsView(),
    );
  }
}

// ─── Admin · POS Tab — shared TransactionsTable with Cashier ───────────────

class _AdminPosTab extends StatelessWidget {
  const _AdminPosTab();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: TransactionsTable(),
    );
  }
}

// ─── Admin · Members Tab — recovered full MembersTable ──────────────────────

class _AdminMembersPage extends StatelessWidget {
  const _AdminMembersPage();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: MembersTable(onRowSelected: _noOpMemberSelect),
    );
  }

  static void _noOpMemberSelect(Map<String, dynamic> _) {}
}

// ─── Admin · Delete Request Management — review requests from Cashiers ─────

class _AdminDeleteRequestTab extends StatefulWidget {
  const _AdminDeleteRequestTab();

  @override
  State<_AdminDeleteRequestTab> createState() => _AdminDeleteRequestTabState();
}

class _AdminDeleteRequestTabState extends State<_AdminDeleteRequestTab> {
  // Placeholder list — in production, fetch from API/repository.
  final List<Map<String, String>> _pendingRequests = [];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_pendingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_remove_rounded,
              size: 48,
              color: StockpileColors.error500,
            ),
            const SizedBox(height: 12),
            Text(
              'No Pending Deletion Requests',
              style: StockpileFonts.satoshi(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Member deletion requests submitted by cashiers will appear here '
              'for your review and approval.',
              textAlign: TextAlign.center,
              style: StockpileFonts.satoshi(
                fontSize: 13,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingRequests.length,
      itemBuilder: (context, index) {
        final request = _pendingRequests[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: StockpileColors.error100,
              child: const Icon(
                Icons.person_remove_rounded,
                color: StockpileColors.error500,
              ),
            ),
            title: Text(request['memberName'] ?? 'Unknown'),
            subtitle: Text(request['reason'] ?? ''),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.check_circle_outline,
                    color: StockpileColors.success,
                  ),
                  tooltip: 'Approve',
                  onPressed: () {
                    // TODO: approve deletion
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.cancel_outlined,
                    color: StockpileColors.error500,
                  ),
                  tooltip: 'Reject',
                  onPressed: () {
                    // TODO: reject deletion
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Admin · Borrow Stock Management ────────────────────────────────────────

class _AdminBorrowStockTab extends StatefulWidget {
  const _AdminBorrowStockTab();

  @override
  State<_AdminBorrowStockTab> createState() => _AdminBorrowStockTabState();
}

class _AdminBorrowStockTabState extends State<_AdminBorrowStockTab> {
  List<Borrow> _borrows = [];
  List<Member> _members = [];
  bool _loading = true;
  String _filter = 'all'; // all, active, overdue, settled

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

  List<Borrow> get _filtered {
    final now = DateTime.now();
    switch (_filter) {
      case 'active':
        return _borrows.where((b) {
          final isOverdue =
              b.dueDate.isBefore(now) &&
              b.status != 'returned' &&
              b.status != 'remitted';
          return b.outstandingQuantity > 0 && !isOverdue;
        }).toList();
      case 'overdue':
        return _borrows.where((b) {
          return b.dueDate.isBefore(now) &&
              b.status != 'returned' &&
              b.status != 'remitted' &&
              b.outstandingQuantity > 0;
        }).toList();
      case 'settled':
        return _borrows.where((b) => b.outstandingQuantity <= 0).toList();
      default:
        return _borrows;
    }
  }

  int get _activeCount =>
      _borrows.where((b) => b.outstandingQuantity > 0 && !b.isOverdue).length;
  int get _overdueCount =>
      _borrows.where((b) => b.isOverdue && b.outstandingQuantity > 0).length;
  int get _settledCount =>
      _borrows.where((b) => b.outstandingQuantity <= 0).length;

  Color _statusColor(String status, bool isOverdue, bool isDark) {
    if (isOverdue) return StockpileColors.error500;
    switch (status) {
      case 'returned':
        return StockpileColors.success;
      case 'remitted':
        return Colors.purple;
      case 'partially_settled':
        return Colors.orange;
      default:
        return isDark ? StockpileColors.darkTextBody : StockpileColors.bodyText;
    }
  }

  String _statusLabel(Borrow b) {
    if (b.outstandingQuantity <= 0) {
      if (b.quantityReturned >= b.quantity) return 'Returned';
      if (b.quantityRemitted >= b.quantity) return 'Remitted';
      return 'Settled';
    }
    if (b.isOverdue) return 'Overdue';
    if (b.quantityReturned > 0 || b.quantityRemitted > 0) return 'Partial';
    return 'Active';
  }

  Future<void> _returnItem(Borrow b) async {
    final qtyCtrl = TextEditingController(
      text: b.outstandingQuantity.toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Return Borrowed Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${b.itemName} — ${_memberName(b.memberId)}'),
            const SizedBox(height: 4),
            Text(
              'Borrowed: ${b.quantity}  |  '
              'Outstanding: ${b.outstandingQuantity}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Quantity to return',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final q = int.tryParse(qtyCtrl.text) ?? 0;
              Navigator.pop(ctx, q);
            },
            child: const Text('Return'),
          ),
        ],
      ),
    );

    if (result == null || result <= 0) return;
    await repository.returnBorrowedItem(b.id!, result);
    _loadData();
  }

  Future<void> _remitItem(Borrow b) async {
    final qtyCtrl = TextEditingController(
      text: b.outstandingQuantity.toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remit Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${b.itemName} — ${_memberName(b.memberId)}'),
            const SizedBox(height: 4),
            Text(
              'Borrowed: ${b.quantity}  |  '
              'Outstanding: ${b.outstandingQuantity}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Quantity to remit',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.purple),
            onPressed: () {
              final q = int.tryParse(qtyCtrl.text) ?? 0;
              Navigator.pop(ctx, q);
            },
            child: const Text('Remit'),
          ),
        ],
      ),
    );

    if (result == null || result <= 0) return;
    await repository.remitBorrowedItem(b.id!, result);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Overdue alert banner
        if (_overdueCount > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: StockpileColors.error50,
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: StockpileColors.error700,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '⚠️ $_overdueCount overdue borrow(s) — '
                    'resellers have not settled within 10 days.',
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: StockpileColors.error700,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Summary cards
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _SummaryChip(
                label: 'All',
                count: _borrows.length,
                isSelected: _filter == 'all',
                color: isDark
                    ? StockpileColors.darkTextBody
                    : StockpileColors.bodyText,
                onTap: () => setState(() => _filter = 'all'),
              ),
              const SizedBox(width: 8),
              _SummaryChip(
                label: 'Active',
                count: _activeCount,
                isSelected: _filter == 'active',
                color: Colors.blue,
                onTap: () => setState(() => _filter = 'active'),
              ),
              const SizedBox(width: 8),
              _SummaryChip(
                label: 'Overdue',
                count: _overdueCount,
                isSelected: _filter == 'overdue',
                color: StockpileColors.error500,
                onTap: () => setState(() => _filter = 'overdue'),
              ),
              const SizedBox(width: 8),
              _SummaryChip(
                label: 'Settled',
                count: _settledCount,
                isSelected: _filter == 'settled',
                color: StockpileColors.success,
                onTap: () => setState(() => _filter = 'settled'),
              ),
            ],
          ),
        ),

        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.swap_horiz_rounded,
                        size: 48,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _filter == 'all'
                            ? 'No borrow records yet'
                            : 'No ${_filter} borrows',
                        style: StockpileFonts.satoshi(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
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
                          color: isDark
                              ? StockpileColors.darkTextMuted
                              : StockpileColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final b = _filtered[index];
                      final memName = _memberName(b.memberId);
                      final statusLbl = _statusLabel(b);
                      final overdue = b.isOverdue && b.outstandingQuantity > 0;
                      final statusCol = _statusColor(b.status, overdue, isDark);

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
                        color: overdue
                            ? StockpileColors.error50.withAlpha(80)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header row
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: statusCol.withAlpha(30),
                                    child: Icon(
                                      Icons.swap_horiz_rounded,
                                      size: 18,
                                      color: statusCol,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          b.itemName,
                                          style: StockpileFonts.satoshi(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? StockpileColors
                                                      .darkTextPrimary
                                                : StockpileColors.darkText,
                                          ),
                                        ),
                                        Text(
                                          memName,
                                          style: StockpileFonts.satoshi(
                                            fontSize: 12,
                                            color: isDark
                                                ? StockpileColors.darkTextMuted
                                                : StockpileColors.mutedText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Status badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusCol.withAlpha(30),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      statusLbl,
                                      style: StockpileFonts.satoshi(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: statusCol,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 10),

                              // Quantity details
                              Row(
                                children: [
                                  _QtyBadge(
                                    label: 'Borrowed',
                                    value: b.quantity,
                                    isDark: isDark,
                                  ),
                                  const SizedBox(width: 8),
                                  _QtyBadge(
                                    label: 'Returned',
                                    value: b.quantityReturned,
                                    isDark: isDark,
                                    color: StockpileColors.success,
                                  ),
                                  const SizedBox(width: 8),
                                  _QtyBadge(
                                    label: 'Remitted',
                                    value: b.quantityRemitted,
                                    isDark: isDark,
                                    color: Colors.purple,
                                  ),
                                  const SizedBox(width: 8),
                                  _QtyBadge(
                                    label: 'Outstanding',
                                    value: b.outstandingQuantity,
                                    isDark: isDark,
                                    color: b.outstandingQuantity > 0
                                        ? StockpileColors.error500
                                        : StockpileColors.success,
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),

                              // Date info
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 14,
                                    color: isDark
                                        ? StockpileColors.darkTextMuted
                                        : StockpileColors.mutedText,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Due: ${b.dueDate.day}/${b.dueDate.month}/${b.dueDate.year}',
                                    style: StockpileFonts.satoshi(
                                      fontSize: 12,
                                      color: overdue
                                          ? StockpileColors.error500
                                          : isDark
                                          ? StockpileColors.darkTextMuted
                                          : StockpileColors.mutedText,
                                      fontWeight: overdue
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                  if (overdue) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '(${DateTime.now().difference(b.dueDate).inDays}d late)',
                                      style: StockpileFonts.satoshi(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: StockpileColors.error500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                              // Notes
                              if (b.notes != null && b.notes!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  b.notes!,
                                  style: StockpileFonts.satoshi(
                                    fontSize: 12,
                                    color: isDark
                                        ? StockpileColors.darkTextMuted
                                        : StockpileColors.mutedText,
                                  ),
                                ),
                              ],

                              // Action buttons (only if outstanding)
                              if (b.outstandingQuantity > 0) ...[
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      icon: const Icon(
                                        Icons.assignment_return_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Return'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            StockpileColors.success,
                                      ),
                                      onPressed: () => _returnItem(b),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.icon(
                                      icon: const Icon(
                                        Icons.payments_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Remit'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.purple,
                                      ),
                                      onPressed: () => _remitItem(b),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _SummaryChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withAlpha(25)
                : (isDark
                      ? StockpileColors.darkSurface
                      : StockpileColors.surface),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? color.withAlpha(120)
                  : StockpileColors.divider,
            ),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: StockpileFonts.satoshi(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isSelected
                      ? color
                      : (isDark
                            ? StockpileColors.darkTextBody
                            : StockpileColors.bodyText),
                ),
              ),
              Text(
                label,
                style: StockpileFonts.satoshi(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? color
                      : (isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QtyBadge extends StatelessWidget {
  final String label;
  final int value;
  final bool isDark;
  final Color? color;

  const _QtyBadge({
    required this.label,
    required this.value,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        (isDark ? StockpileColors.darkTextBody : StockpileColors.bodyText);
    return Column(
      children: [
        Text(
          '$value',
          style: StockpileFonts.satoshi(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: c,
          ),
        ),
        Text(
          label,
          style: StockpileFonts.satoshi(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: isDark
                ? StockpileColors.darkTextMuted
                : StockpileColors.mutedText,
          ),
        ),
      ],
    );
  }
}

// ─── Nav Item Model ─────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem(this.icon, this.label);
}
