// lib/pages/admin/admin_dashboard.dart
// Admin Dashboard — full unrestricted access to ALL application features.
// The admin role passes every role assertion and can access every tab
// from every dashboard (admin, inventory, and cashier).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/widgets/inventorytable.dart' as inventory;
import 'package:lzcas/widgets/stockpile_topbar.dart';
import 'package:lzcas/widgets/transactionstable.dart';
import 'package:lzcas/widgets/memberstable.dart';
import 'package:lzcas/widgets/memberdetails.dart';
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

class _UserManagementTabState extends State<_UserManagementTab>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _passwordCtrls = List.generate(1, (_) => TextEditingController());
  final _confirmPasswordCtrl = TextEditingController();
  UserRole _selectedRole = UserRole.cashier;
  bool _creating = false;
  String? _createError;
  String? _successMessage;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  List<Map<String, dynamic>> _users = [];
  bool _usersLoading = false;
  String _userSearchTerm = '';
  String? _userRoleFilter;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    for (final c in _passwordCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    final username = _nameCtrl.text.trim();
    final password = _passwordCtrls[0].text;
    final confirm = _confirmPasswordCtrl.text;

    if (password != confirm) {
      setState(() => _createError = 'Passwords do not match.');
      return;
    }
    // Supabase Auth requires email format — auto-generate from username
    final email = '$username@lzcas.local';

    setState(() {
      _creating = true;
      _createError = null;
    });

    try {
      final auth = context.read<AuthState>();

      final ok = await auth.createUser(
        email: email,
        password: password,
        role: _selectedRole,
        username: username,
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
      _passwordCtrls[0].clear();
      _confirmPasswordCtrl.clear();

      setState(() => _successMessage = 'User created successfully.');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _successMessage = null);
      });
      _fetchUsers();
    } catch (e) {
      setState(() => _createError = e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _fetchUsers() async {
    setState(() => _usersLoading = true);
    try {
      final auth = context.read<AuthState>();
      final users = await auth.fetchUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _usersLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _usersLoading = false);
    }
  }

  Future<void> _deleteUser(String userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Delete "$username"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final auth = context.read<AuthState>();
      final ok = await auth.deleteUser(userId);
      if (!mounted) return;
      if (ok) {
        setState(() => _successMessage = 'User deleted.');
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _successMessage = null);
        });
        _fetchUsers();
      } else {
        setState(
          () => _createError = auth.error.isNotEmpty
              ? auth.error
              : 'Failed to delete user.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _createError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? StockpileColors.darkInputBg
                      : StockpileColors.inputBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TabBar(
                  controller: _tabController,
                  padding: const EdgeInsets.all(5),
                  labelStyle: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  indicator: BoxDecoration(
                    color: isDark ? surfaceColor : Colors.white,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.white.withAlpha(10)
                            : Colors.black.withAlpha(15),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: isDark
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.primary900,
                  unselectedLabelColor: isDark
                      ? StockpileColors.darkTextMuted
                      : StockpileColors.mutedText,
                  dividerColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                  tabs: const [
                    Tab(
                      height: 44,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_add_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Create'),
                        ],
                      ),
                    ),
                    Tab(
                      height: 44,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_alt_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Users'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: TabBarView(
                  key: ValueKey(_tabController.index),
                  controller: _tabController,
                  children: [
                    SingleChildScrollView(
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
                                style: const TextStyle(
                                  color: StockpileColors.danger,
                                ),
                              ),
                            ),

                          Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _nameCtrl,
                                  enabled: !_creating,
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  decoration: const InputDecoration(
                                    labelText: 'Username',
                                    prefixIcon: Icon(
                                      Icons.person_outline_rounded,
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'Username is required'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _passwordCtrls[0],
                                  enabled: !_creating,
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  obscureText: !_passwordVisible,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                    ),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _passwordVisible
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                      onPressed: () => setState(
                                        () => _passwordVisible =
                                            !_passwordVisible,
                                      ),
                                    ),
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Password is required'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _confirmPasswordCtrl,
                                  enabled: !_creating,
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  obscureText: !_confirmPasswordVisible,
                                  decoration: InputDecoration(
                                    labelText: 'Confirm Password',
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                    ),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _confirmPasswordVisible
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                      onPressed: () => setState(
                                        () => _confirmPasswordVisible =
                                            !_confirmPasswordVisible,
                                      ),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Confirm password is required';
                                    }
                                    if (v != _passwordCtrls[0].text) {
                                      return 'Passwords do not match';
                                    }
                                    return null;
                                  },
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
                                        (r) => DropdownMenuItem(
                                          value: r,
                                          child: Text(r.displayName),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null)
                                      setState(() => _selectedRole = v);
                                  },
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.badge_outlined),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ScaleTap(
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
                                label: Text(
                                  _creating ? 'Creating…' : 'Create User',
                                ),
                                onPressed: _creating ? null : _createUser,
                              ),
                            ),
                          ),
                          // ── End of Create tab ──────────────────────────
                        ],
                      ),
                    ),
                    // ── Users tab ─────────────────────────────────────
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Existing Users',
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
                            'View and manage registered accounts.',
                            style: StockpileFonts.satoshi(
                              fontSize: 13,
                              color: isDark
                                  ? StockpileColors.darkTextMuted
                                  : StockpileColors.mutedText,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: const InputDecoration(
                                    hintText: 'Search by username…',
                                    prefixIcon: Icon(Icons.search, size: 20),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  onChanged: (v) =>
                                      setState(() => _userSearchTerm = v),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 160,
                                child: DropdownButtonFormField<String?>(
                                  value: _userRoleFilter,
                                  decoration: const InputDecoration(
                                    labelText: 'Role',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: null,
                                      child: Text('All'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'admin',
                                      child: Text('Admin'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'inventory',
                                      child: Text('Inventory'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'cashier',
                                      child: Text('Cashier'),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _userRoleFilter = v),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_usersLoading)
                            const SkeletonList(count: 4)
                          else
                            ..._buildUserList(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // ── Success notification bubble (top-right) ──────────────
        if (_successMessage != null)
          Positioned(
            top: 16,
            right: 16,
            child: SlideDownFromTop(
              key: ValueKey(_successMessage),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF166534),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _successMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => setState(() => _successMessage = null),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildUserList(BuildContext context) {
    final filtered = _users.where((u) {
      final matchesSearch =
          _userSearchTerm.isEmpty ||
          (u['username']?.toString() ?? '').toLowerCase().contains(
            _userSearchTerm.toLowerCase(),
          );
      final matchesRole =
          _userRoleFilter == null || u['role']?.toString() == _userRoleFilter;
      return matchesSearch && matchesRole;
    }).toList();

    if (filtered.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No users found.')),
        ),
      ];
    }

    return [
      Card(
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filtered.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 16, endIndent: 16),
          itemBuilder: (_, i) {
            final u = filtered[i];
            final role = u['role']?.toString() ?? '';
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: _roleColor(role).withAlpha(30),
                child: Icon(_roleIcon(role), color: _roleColor(role), size: 20),
              ),
              title: Text(
                u['username']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                u['email']?.toString().isNotEmpty == true
                    ? u['email'].toString()
                    : '${u['username']}@lzcas.local',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _roleColor(role).withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      role.isNotEmpty
                          ? role[0].toUpperCase() + role.substring(1)
                          : '',
                      style: TextStyle(
                        color: _roleColor(role),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    tooltip: 'Delete user',
                    onPressed: () => _deleteUser(
                      u['id']?.toString() ?? '',
                      u['username']?.toString() ?? '',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ];
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.green.shade700;
      case 'inventory':
        return Colors.blue.shade700;
      case 'cashier':
        return Colors.grey.shade700;
      default:
        return Colors.grey;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'inventory':
        return Icons.inventory_2;
      case 'cashier':
        return Icons.point_of_sale;
      default:
        return Icons.person;
    }
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

// ─── Admin · Pending Requests — review deletion/reduction requests ─────────

class _AdminDeleteRequestTab extends StatefulWidget {
  const _AdminDeleteRequestTab();

  @override
  State<_AdminDeleteRequestTab> createState() => _AdminDeleteRequestTabState();
}

class _AdminDeleteRequestTabState extends State<_AdminDeleteRequestTab> {
  List<PendingRequest> _pendingRequests = [];
  bool _loading = true;
  StreamSubscription<String>? _changeSub;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _changeSub = repository.changes.listen((event) {
      if (event == 'pending_request_added' ||
          event == 'pending_request_approved' ||
          event == 'pending_request_rejected') {
        _loadRequests();
      }
    });
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    try {
      final requests = await repository.fetchPendingRequests();
      if (!mounted) return;
      setState(() {
        _pendingRequests = requests;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _approve(PendingRequest req) async {
    if (req.id == null) return;
    final ok = await repository.approveRequest(req.id!);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${req.summary} — approved')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve ${req.summary}')),
      );
    }
    _loadRequests();
  }

  Future<void> _reject(PendingRequest req) async {
    if (req.id == null) return;
    final ok = await repository.rejectRequest(req.id!);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${req.summary} — rejected')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject ${req.summary}')),
      );
    }
    _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pendingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pending_actions_rounded,
              size: 48,
              color: StockpileColors.success,
            ),
            const SizedBox(height: 12),
            Text(
              'No Pending Requests',
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
              'Deletion and stock reduction requests submitted by inventory '
              'staff will appear here for your review and approval.',
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
        final req = _pendingRequests[index];
        final isDelete = req.requestType == 'delete';
        final icon = isDelete
            ? Icons.delete_forever_rounded
            : Icons.arrow_downward_rounded;
        final iconColor = isDelete
            ? StockpileColors.error500
            : Colors.orange.shade700;

        String subtitle = req.itemName;
        if (req.requestType == 'reduce_stock' && req.quantity != null) {
          subtitle = 'Reduce "${req.itemName}" by ${req.quantity}';
          if (req.reason != null && req.reason!.isNotEmpty) {
            subtitle += ' — ${req.reason}';
          }
        }
        if (req.createdAt != null) {
          subtitle += '\nSubmitted ${_formatDate(req.createdAt!)}';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isDelete
                  ? StockpileColors.error100
                  : Colors.orange.shade100,
              child: Icon(icon, color: iconColor),
            ),
            title: Text(
              isDelete ? 'Delete "${req.itemName}"' : 'Reduce Stock',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(subtitle),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.check_circle_outline,
                    color: StockpileColors.success,
                  ),
                  tooltip: 'Approve',
                  onPressed: () => _approve(req),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.cancel_outlined,
                    color: StockpileColors.error500,
                  ),
                  tooltip: 'Reject',
                  onPressed: () => _reject(req),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
