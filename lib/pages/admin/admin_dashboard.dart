// lib/pages/admin/admin_dashboard.dart
// Admin Dashboard — full unrestricted access to ALL application features.
// The admin role passes every role assertion and can access every tab
// from every dashboard (admin, inventory, and cashier).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/widgets/inventorytable.dart' as inventory;
import 'package:lzcas/widgets/stockpile_topbar.dart';
import 'package:lzcas/widgets/transactionstable.dart';
import 'package:lzcas/widgets/memberstable.dart';
import 'package:lzcas/widgets/memberdetails.dart';
import 'package:lzcas/widgets/inventory_reports_view.dart';
import 'package:lzcas/pages/dashboardpage.dart';
import 'package:lzcas/dialogs/edit_member_dialog.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/services/notification_service.dart';
import 'package:lzcas/services/config_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  bool _sidebarHovered = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _sidebarExpandedWidth = 260.0;
  static const _sidebarCompactWidth = 68.0;
  static const _sidebarAnimDuration = Duration(milliseconds: 200);
  static const _sidebarAnimCurve = Curves.easeOut;

  static const _pageTitles = [
    'Dashboard',
    'User Management',
    'Inventory · Stock',
    'Inventory · Reports',
    'POS Terminal',
    'Members',
    'Requests',
    'Borrow Stock',
    'Settings',
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
    final notifService = context.watch<NotificationService>();
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pages = _buildPages();

    final sharedSidebarArgs = (
      selectedIndex: _selectedIndex,
      auth: auth,
      pendingCount: notifService.pendingCount,
      onItemSelected: (int i) {
        if (!isDesktop) Navigator.pop(context);
        if (i == 6) notifService.markPendingSeen(); // Requests tab
        _onItemTapped(i);
      },
    );

    final mobileDrawer = _AdminSidebar(
      selectedIndex: sharedSidebarArgs.selectedIndex,
      auth: sharedSidebarArgs.auth,
      pendingCount: sharedSidebarArgs.pendingCount,
      onItemSelected: sharedSidebarArgs.onItemSelected,
      useDrawer: true,
    );

    final desktopSidebar = _AdminSidebar(
      selectedIndex: sharedSidebarArgs.selectedIndex,
      auth: sharedSidebarArgs.auth,
      pendingCount: sharedSidebarArgs.pendingCount,
      onItemSelected: sharedSidebarArgs.onItemSelected,
      useDrawer: false,
      expanded: _sidebarHovered,
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: isDesktop ? null : mobileDrawer,
      body: Row(
        children: [
          // Desktop sidebar — hover to expand, collapses to icons
          if (isDesktop)
            MouseRegion(
              onEnter: (_) => setState(() => _sidebarHovered = true),
              onExit: (_) => setState(() => _sidebarHovered = false),
              child: AnimatedContainer(
                duration: _sidebarAnimDuration,
                curve: _sidebarAnimCurve,
                width: _sidebarHovered
                    ? _sidebarExpandedWidth
                    : _sidebarCompactWidth,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: isDark
                      ? StockpileColors.darkSurface
                      : StockpileColors.surface,
                ),
                child: desktopSidebar,
              ),
            ),
          if (isDesktop) const VerticalDivider(width: 1),

          // Main content area
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  // ── Top Bar ────────────────────────────────────────────
                  StockpileTopBar(
                    pageTitle: _pageTitles[_selectedIndex],
                    showMenu: !isDesktop,
                    onMenuTap: _toggleSidebar,
                    onNavigateToTab: (i) => setState(() => _selectedIndex = i),
                  ),
                  // ── Page Content ───────────────────────────────────────
                  Expanded(child: pages[_selectedIndex]),
                ],
              ),
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

  Future<void> _editUser(
    String userId,
    String username,
    String role,
    String email,
  ) async {
    final result = await showDialog<_EditUserResult>(
      context: context,
      builder: (ctx) => _EditUserDialog(
        userId: userId,
        username: username,
        role: role,
        email: email,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final auth = context.read<AuthState>();
      final newRole = result.role.isNotEmpty
          ? UserRole.fromString(result.role)
          : null;
      final ok = await auth.updateUser(
        userId: userId,
        password: result.password.isNotEmpty ? result.password : null,
        role: newRole,
        username: result.username.isNotEmpty ? result.username : null,
        email: result.email.isNotEmpty ? result.email : null,
      );
      if (!mounted) return;
      if (ok) {
        setState(() => _successMessage = 'User updated.');
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _successMessage = null);
        });
        _fetchUsers();
      } else {
        setState(
          () => _createError = auth.error.isNotEmpty
              ? auth.error
              : 'Failed to update user.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _createError = e.toString());
    }
  }

  Future<void> _viewUserPassword(String userId, String username) async {
    final password = await repository.fetchUserPassword(userId);

    if (!mounted) return;

    if (password == null || password.isEmpty) {
      // No password stored — offer to reset
      final shouldReset = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No Password Stored'),
          content: Text(
            'No password record exists for "$username". '
            'This account may have been created before password tracking '
            'was enabled. Would you like to reset their password now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset Password'),
            ),
          ],
        ),
      );

      if (shouldReset == true && mounted) {
        _editUser(userId, username, '', '');
      }
      return;
    }

    await _showPasswordDialog(username, password);
  }

  Future<void> _showPasswordDialog(String username, String password) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    var obscured = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.vpn_key_rounded, color: Colors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Password for $username',
                  style: StockpileFonts.satoshi(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        obscured ? '••••••••••••' : password,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          letterSpacing: obscured ? 4 : 1,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        obscured ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscured = !obscured),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy to Clipboard'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: password));
                    BotToast.showText(text: 'Password copied!');
                  },
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
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
                                      .where(
                                        (r) =>
                                            r != UserRole.member &&
                                            r != UserRole.reseller,
                                      )
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
                          // ── Users card wrapper ──────────────────────
                          Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? StockpileColors.darkSurface
                                  : StockpileColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? StockpileColors.darkDivider
                                    : StockpileColors.divider,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Card header ────────────────────────
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    16,
                                    20,
                                    0,
                                  ),
                                  child: Row(
                                    children: [
                                      Builder(
                                        builder: (_) {
                                          final count = _filteredUsers.length;
                                          return Text(
                                            _usersLoading
                                                ? 'Loading users…'
                                                : '$count ${count == 1 ? 'user' : 'users'}',
                                            style: StockpileFonts.satoshi(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? StockpileColors
                                                        .darkTextMuted
                                                  : StockpileColors.mutedText,
                                            ),
                                          );
                                        },
                                      ),
                                      const Spacer(),
                                      if (_usersLoading)
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // ── User list ─────────────────────────
                                Builder(
                                  builder: (_) {
                                    final users = _filteredUsers;
                                    if (_usersLoading) {
                                      return const SkeletonList(count: 4);
                                    }
                                    if (users.isEmpty) {
                                      return _buildEmptyState(context);
                                    }
                                    return Column(
                                      children: _buildUserRows(context, users),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
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

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((u) {
      final role = u['role']?.toString() ?? '';
      // Members and resellers have their own dedicated management page
      if (role == 'member' || role == 'reseller') return false;
      final matchesSearch =
          _userSearchTerm.isEmpty ||
          (u['username']?.toString() ?? '').toLowerCase().contains(
            _userSearchTerm.toLowerCase(),
          );
      final matchesRole = _userRoleFilter == null || role == _userRoleFilter;
      return matchesSearch && matchesRole;
    }).toList();
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 48,
              color: isDark
                  ? StockpileColors.darkTextMuted.withAlpha(80)
                  : StockpileColors.mutedText.withAlpha(80),
            ),
            const SizedBox(height: 12),
            Text(
              'No users found',
              style: StockpileFonts.satoshi(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try adjusting your search or role filter.',
              style: StockpileFonts.satoshi(
                fontSize: 13,
                color: isDark
                    ? StockpileColors.darkTextMuted.withAlpha(150)
                    : StockpileColors.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildUserRows(
    BuildContext context,
    List<Map<String, dynamic>> users,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return List.generate(users.length, (i) {
      final u = users[i];
      final role = u['role']?.toString() ?? '';
      final username = u['username']?.toString() ?? '';
      final email = u['email']?.toString() ?? '';
      final createdAt = u['created_at']?.toString() ?? '';
      final isLast = i == users.length - 1;

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                // ── Left accent bar ────────────────────────────
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _roleColor(role),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 14),

                // ── Avatar with initials ───────────────────────
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _roleColor(role).withAlpha(30),
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: _roleColor(role),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // ── Name + meta ────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: StockpileFonts.satoshi(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? StockpileColors.darkTextPrimary
                              : StockpileColors.darkText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (email.isNotEmpty) ...[
                            Icon(
                              Icons.email_outlined,
                              size: 12,
                              color: isDark
                                  ? StockpileColors.darkTextMuted
                                  : StockpileColors.mutedText,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? StockpileColors.darkTextMuted
                                      : StockpileColors.mutedText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (createdAt.isNotEmpty) ...[
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 11,
                              color: isDark
                                  ? StockpileColors.darkTextMuted.withAlpha(150)
                                  : StockpileColors.mutedText,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? StockpileColors.darkTextMuted.withAlpha(
                                        150,
                                      )
                                    : StockpileColors.mutedText,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Role badge ────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _roleColor(role).withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    role.isNotEmpty
                        ? role[0].toUpperCase() + role.substring(1)
                        : '',
                    style: TextStyle(
                      color: _roleColor(role),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                const SizedBox(width: 4),

                // ── View Password ───────────────────────────
                ScaleTap(
                  child: IconButton(
                    tooltip: 'View password',
                    onPressed: () =>
                        _viewUserPassword(u['id']?.toString() ?? '', username),
                    icon: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey.shade600,
                      child: const Icon(
                        Icons.visibility_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),

                const SizedBox(width: 4),

                // ── Edit ──────────────────────────────────────
                ScaleTap(
                  child: IconButton(
                    tooltip: 'Edit user',
                    onPressed: () => _editUser(
                      u['id']?.toString() ?? '',
                      username,
                      role,
                      email,
                    ),
                    icon: const CircleAvatar(
                      radius: 16,
                      backgroundColor: StockpileColors.primary900,
                      child: Icon(
                        Icons.edit_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),

                const SizedBox(width: 4),

                // ── Delete ────────────────────────────────────
                ScaleTap(
                  child: IconButton(
                    tooltip: 'Delete user',
                    onPressed: () =>
                        _deleteUser(u['id']?.toString() ?? '', username),
                    icon: const CircleAvatar(
                      radius: 16,
                      backgroundColor: StockpileColors.danger,
                      child: Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!isLast)
            Divider(
              height: 1,
              indent: 20,
              endIndent: 20,
              color: isDark
                  ? StockpileColors.darkDivider
                  : StockpileColors.divider,
            ),
        ],
      );
    });
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.green.shade700;
      case 'inventory':
        return Colors.blue.shade700;
      case 'cashier':
        return Colors.amber.shade700;
      default:
        return Colors.grey;
    }
  }
}

// ─── Edit User Result ──────────────────────────────────────────────────────

class _EditUserResult {
  final String password;
  final String role;
  final String username;
  final String email;

  const _EditUserResult({
    required this.password,
    required this.role,
    required this.username,
    required this.email,
  });
}

// ─── Edit User Dialog ──────────────────────────────────────────────────────

class _EditUserDialog extends StatefulWidget {
  final String userId;
  final String username;
  final String role;
  final String email;

  const _EditUserDialog({
    required this.userId,
    required this.username,
    required this.role,
    required this.email,
  });

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _emailCtrl;
  late String _role;
  bool _passwordVisible = false;
  String? _error;
  bool _changePassword = false;

  Color get _roleColor {
    switch (widget.role) {
      case 'admin':
        return Colors.green.shade700;
      case 'inventory':
        return Colors.blue.shade700;
      case 'cashier':
        return Colors.amber.shade700;
      default:
        return Colors.grey;
    }
  }

  Color _colorForRole(String role) {
    switch (role) {
      case 'admin':
        return Colors.green.shade700;
      case 'inventory':
        return Colors.blue.shade700;
      case 'cashier':
        return Colors.amber.shade700;
      default:
        return Colors.grey;
    }
  }

  @override
  void initState() {
    super.initState();
    _passwordCtrl = TextEditingController();
    _usernameCtrl = TextEditingController(text: widget.username);
    _emailCtrl = TextEditingController(text: widget.email);
    _role = widget.role;
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark
          ? StockpileColors.darkSurface
          : StockpileColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        decoration: BoxDecoration(
          color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _roleColor.withAlpha(30),
              child: Text(
                widget.username.isNotEmpty
                    ? widget.username[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: _roleColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Edit User',
                    style: StockpileFonts.satoshi(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? StockpileColors.darkTextPrimary
                          : StockpileColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.username,
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: StockpileColors.dangerBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: StockpileColors.danger,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: StockpileColors.danger,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Username ───────────────────────────
              TextFormField(
                controller: _usernameCtrl,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                ),
                decoration: _inputDeco('Username', Icons.person_outline),
              ),
              const SizedBox(height: 10),

              // ── Email ──────────────────────────────
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                ),
                decoration: _inputDeco('Email', Icons.email_outlined),
              ),
              const SizedBox(height: 10),

              // ── Role ───────────────────────────────
              DropdownButtonFormField<String>(
                value: _role,
                items: UserRole.values
                    .where(
                      (r) => r != UserRole.member && r != UserRole.reseller,
                    )
                    .map(
                      (r) => DropdownMenuItem(
                        value: r.name,
                        child: Row(
                          children: [
                            _RoleDot(color: _colorForRole(r.name)),
                            const SizedBox(width: 8),
                            Text(r.displayName),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _role = v!),
                decoration: _inputDeco('Role', Icons.badge_outlined),
              ),

              const SizedBox(height: 18),

              // ── Password ───────────────────────────
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? StockpileColors.darkDivider
                        : StockpileColors.divider,
                  ),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      secondary: Icon(
                        _changePassword
                            ? Icons.lock_open_rounded
                            : Icons.lock_rounded,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                        size: 20,
                      ),
                      title: Text(
                        'Change password',
                        style: StockpileFonts.satoshi(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? StockpileColors.darkTextPrimary
                              : StockpileColors.darkText,
                        ),
                      ),
                      subtitle: Text(
                        'Set a new password for this user.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? StockpileColors.darkTextMuted
                              : StockpileColors.mutedText,
                        ),
                      ),
                      value: _changePassword,
                      onChanged: (v) => setState(() => _changePassword = v),
                    ),
                    if (_changePassword)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: TextFormField(
                          controller: _passwordCtrl,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          obscureText: !_passwordVisible,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? StockpileColors.darkTextPrimary
                                : StockpileColors.darkText,
                          ),
                          decoration: InputDecoration(
                            labelText: 'New password',
                            hintText: 'Minimum 6 characters',
                            prefixIcon: const Icon(
                              Icons.vpn_key_outlined,
                              size: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            filled: true,
                            fillColor: isDark
                                ? StockpileColors.darkSurface
                                : StockpileColors.surface,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _passwordVisible = !_passwordVisible,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _roleColor,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.save_rounded, size: 18),
          label: const Text('Save Changes'),
          onPressed: _save,
        ),
      ],
    );
  }

  void _save() {
    final password = _passwordCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (username.isEmpty) {
      setState(() => _error = 'Username cannot be empty.');
      return;
    }

    if (_changePassword && password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    Navigator.pop(
      context,
      _EditUserResult(
        password: _changePassword ? password : '',
        role: _role,
        username: username,
        email: email,
      ),
    );
  }
}

// ─── Role Dot Widget ───────────────────────────────────────────────────────

class _RoleDot extends StatelessWidget {
  final Color color;
  const _RoleDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ─── Admin · Settings Tab — Global Config relocated from top nav ───────────

class _AdminSettingsTab extends StatefulWidget {
  const _AdminSettingsTab();

  @override
  State<_AdminSettingsTab> createState() => _AdminSettingsTabState();
}

class _AdminSettingsTabState extends State<_AdminSettingsTab> {
  // General config state
  bool _configLoading = true;
  final _lowStockCtrl = TextEditingController();
  final _borrowDaysCtrl = TextEditingController();
  final _overdueDaysCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController();
  bool _notificationsOn = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _lowStockCtrl.dispose();
    _borrowDaysCtrl.dispose();
    _overdueDaysCtrl.dispose();
    _currencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await repository.fetchAppConfig();
    if (!mounted) return;
    setState(() {
      _lowStockCtrl.text = config['low_stock_threshold'] ?? '50';
      _borrowDaysCtrl.text = config['borrow_duration_days'] ?? '10';
      _overdueDaysCtrl.text = config['overdue_threshold_days'] ?? '10';
      _currencyCtrl.text = config['currency_symbol'] ?? '₱';
      _notificationsOn = config['notifications_enabled'] != 'false';
      _configLoading = false;
    });
  }

  Future<void> _saveConfig() async {
    await repository.updateAppConfig('low_stock_threshold', _lowStockCtrl.text);
    await repository.updateAppConfig(
      'borrow_duration_days',
      _borrowDaysCtrl.text,
    );
    await repository.updateAppConfig(
      'overdue_threshold_days',
      _overdueDaysCtrl.text,
    );
    await repository.updateAppConfig('currency_symbol', _currencyCtrl.text);
    await repository.updateAppConfig(
      'notifications_enabled',
      _notificationsOn ? 'true' : 'false',
    );
    if (!mounted) return;
    // Refresh in-memory config so the rest of the app picks up changes
    context.read<ConfigService>().refresh();
    BotToast.showText(text: 'Settings saved');
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
        const Divider(height: 24),
        Expanded(child: _buildGeneralTab(isDark)),
      ],
    );
  }

  Widget _buildGeneralTab(bool isDark) {
    if (_configLoading) {
      return const Center(child: CircularProgressIndicator());
    }

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
            icon: Icons.inventory_2_rounded,
            title: 'Low Stock Threshold',
            subtitle: 'Alert when stock falls below this number',
            trailing: SizedBox(
              width: 70,
              child: TextField(
                controller: _lowStockCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          _ConfigTile(
            icon: Icons.calendar_today_rounded,
            title: 'Borrow Duration (days)',
            subtitle: 'Default due date for new borrows',
            trailing: SizedBox(
              width: 70,
              child: TextField(
                controller: _borrowDaysCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          _ConfigTile(
            icon: Icons.warning_amber_rounded,
            title: 'Overdue Threshold (days)',
            subtitle: 'Days before a borrow is marked overdue',
            trailing: SizedBox(
              width: 70,
              child: TextField(
                controller: _overdueDaysCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          _ConfigTile(
            icon: Icons.attach_money_rounded,
            title: 'Currency Symbol',
            subtitle: 'Symbol used for price display',
            trailing: SizedBox(
              width: 70,
              child: TextField(
                controller: _currencyCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          _ConfigTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Enable in-app notification alerts',
            trailing: Switch(
              value: _notificationsOn,
              onChanged: (v) => setState(() => _notificationsOn = v),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save Settings'),
              onPressed: _saveConfig,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Admin Sidebar (styled after StockpileSidebar from UI Changes) ─────────

class _AdminSidebar extends StatelessWidget {
  final int selectedIndex;
  final AuthState auth;
  final ValueChanged<int> onItemSelected;
  final int pendingCount;

  /// When true wraps the content in a [Drawer] (for Scaffold.drawer on mobile).
  /// When false uses a plain Container (for inline desktop sidebar).
  final bool useDrawer;

  /// When true shows full sidebar with text; when false shows icons only.
  final bool expanded;

  const _AdminSidebar({
    required this.selectedIndex,
    required this.auth,
    required this.onItemSelected,
    this.pendingCount = 0,
    this.useDrawer = true,
    this.expanded = true,
  });

  static const _navItems = <_NavItem>[
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.person_add_alt_rounded, 'Users'),
    _NavItem(Icons.inventory_2_rounded, 'Inventory'),
    _NavItem(Icons.history_rounded, 'Reports'),
    _NavItem(Icons.point_of_sale_rounded, 'POS Terminal'),
    _NavItem(Icons.people_alt_rounded, 'Members'),
    _NavItem(Icons.person_remove_rounded, 'Requests'),
    _NavItem(Icons.add_box_rounded, 'Borrow Stock'),
  ];

  static const _bottomItems = <_NavItem>[
    _NavItem(Icons.settings_rounded, 'Settings'),
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

    Widget buildContent(bool wide) => Column(
      children: [
        // ── Brand ────────────────────────────────────────────────────
        if (wide)
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
                Flexible(
                  child: Text(
                    'LZCAS · Admin',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: StockpileFonts.satoshi(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? StockpileColors.darkTextPrimary
                          : StockpileColors.darkText,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 28, bottom: 24),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: StockpileColors.primary900,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),

        // ── Navigation Items ─────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              ...List.generate(_navItems.length, (i) {
                final tile = _AdminSidebarTile(
                  item: _navItems[i],
                  isSelected: selectedIndex == i,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () => onItemSelected(i),
                  expanded: wide,
                );
                // Show badge on Requests item (index 6)
                if (i == 6 && pendingCount > 0) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      tile,
                      Positioned(
                        top: 6,
                        right: wide ? 6 : 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: StockpileColors.primary900,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$pendingCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return tile;
              }),
              const SizedBox(height: 8),
              Divider(
                color: isDark
                    ? StockpileColors.darkDivider
                    : StockpileColors.divider,
                indent: 12,
                endIndent: 12,
              ),
              const SizedBox(height: 8),
              // Settings → index 8
              _AdminSidebarTile(
                item: _bottomItems[0],
                isSelected: selectedIndex == 8,
                activeBg: activeBg,
                isDark: isDark,
                onTap: () => onItemSelected(8),
                expanded: wide,
              ),
            ],
          ),
        ),

        // ── User Profile Card ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _confirmLogout(context, auth),
            child: Container(
              padding: wide
                  ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
                  : const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? StockpileColors.darkInputBg
                    : StockpileColors.inputBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: wide
                  ? Row(
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
                                auth.username.isNotEmpty
                                    ? auth.username
                                    : 'Admin',
                                maxLines: 1,
                                overflow: TextOverflow.clip,
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
                    )
                  : Center(
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: StockpileColors.primary900,
                        child: Text(
                          auth.username.isNotEmpty
                              ? auth.username[0].toUpperCase()
                              : 'A',
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );

    if (useDrawer) {
      return Drawer(
        width: 260,
        backgroundColor: surface,
        elevation: 0,
        child: LayoutBuilder(
          builder: (_, constraints) => buildContent(constraints.maxWidth > 150),
        ),
      );
    }
    return SizedBox.expand(
      child: Container(
        color: surface,
        child: LayoutBuilder(
          builder: (_, constraints) => buildContent(constraints.maxWidth > 150),
        ),
      ),
    );
  }
}

void _confirmLogout(BuildContext context, AuthState auth) async {
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

  Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
}

// ─── Sidebar Tile ───────────────────────────────────────────────────────────

class _AdminSidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final Color activeBg;
  final bool isDark;
  final VoidCallback onTap;
  final bool expanded;

  const _AdminSidebarTile({
    required this.item,
    required this.isSelected,
    required this.activeBg,
    required this.isDark,
    required this.onTap,
    this.expanded = true,
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: expanded
              ? Row(
                  children: [
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 44,
                      child: Center(
                        child: Icon(item.icon, size: 20, color: textColor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: StockpileFonts.satoshi(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                )
              : Tooltip(
                  message: item.label,
                  child: Center(
                    child: SizedBox(
                      width: 44,
                      child: Center(
                        child: Icon(item.icon, size: 20, color: textColor),
                      ),
                    ),
                  ),
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

class _AdminMembersPage extends StatefulWidget {
  const _AdminMembersPage();

  @override
  State<_AdminMembersPage> createState() => _AdminMembersPageState();
}

class _AdminMembersPageState extends State<_AdminMembersPage> {
  final _tableKey = GlobalKey<MembersTableState>();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: MembersTable(
        key: _tableKey,
        onRowSelected: (member) => _showMemberDetail(context, member),
      ),
    );
  }

  void _showMemberDetail(BuildContext context, Map<String, dynamic> member) {
    final fullName = [
      member['firstName'],
      member['middleName'],
      member['lastName'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');
    final initials = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'M';
    final isReseller =
        (member['role']?.toString() ?? '') == 'Verified Reseller';
    final email = (member['email']?.toString() ?? '').trim();
    final hasAccount = email.isNotEmpty;

    showAnimatedDialog(
      context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final surface = isDark
            ? StockpileColors.darkSurface
            : StockpileColors.surface;
        final textColor = isDark
            ? StockpileColors.darkTextPrimary
            : StockpileColors.darkText;
        final muted = isDark
            ? StockpileColors.darkTextMuted
            : StockpileColors.mutedText;
        final divider = isDark
            ? StockpileColors.darkDivider
            : StockpileColors.divider;

        return Dialog(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Close button (top-right) ────────────────
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),

                // ── Scrollable content ──────────────────────
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      children: [
                        // ── Avatar header ──────────────────
                        _ModalAvatarHeader(
                          initials: initials,
                          fullName: fullName.isEmpty
                              ? 'Unnamed Member'
                              : fullName,
                          memberId: member['id']?.toString() ?? '—',
                          isReseller: isReseller,
                          email: email,
                          hasAccount: hasAccount,
                          isDark: isDark,
                          textColor: textColor,
                          muted: muted,
                        ),
                        const SizedBox(height: 20),

                        // ── Personal Info card ─────────────
                        _ModalInfoCard(
                          isDark: isDark,
                          textColor: textColor,
                          muted: muted,
                          surface: surface,
                          divider: divider,
                          title: 'Personal Info',
                          icon: Icons.person_outline_rounded,
                          children: [
                            _ModalInfoRow(
                              icon: Icons.cake_outlined,
                              label: 'Birthday',
                              value: member['birthday'],
                              muted: muted,
                              textColor: textColor,
                              isDark: isDark,
                            ),
                            _ModalInfoRow(
                              icon: Icons.home_outlined,
                              label: 'Address',
                              value: member['address'],
                              muted: muted,
                              textColor: textColor,
                              isDark: isDark,
                            ),
                            _ModalInfoRow(
                              icon: Icons.phone_outlined,
                              label: 'Contact',
                              value: member['contactNo'],
                              muted: muted,
                              textColor: textColor,
                              isDark: isDark,
                              isLast: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ── Referral card ──────────────────
                        _ModalInfoCard(
                          isDark: isDark,
                          textColor: textColor,
                          muted: muted,
                          surface: surface,
                          divider: divider,
                          title: 'Referral',
                          icon: Icons.group_outlined,
                          children: [
                            _ModalInfoRow(
                              icon: Icons.person_add_outlined,
                              label: 'Referred by',
                              value:
                                  (member['referrer']?.toString() ?? '')
                                      .isNotEmpty
                                  ? member['referrer']
                                  : 'None',
                              muted: muted,
                              textColor: textColor,
                              isDark: isDark,
                              italic: (member['referrer']?.toString() ?? '')
                                  .isEmpty,
                            ),
                            _ModalInfoRow(
                              icon: Icons.people_outline,
                              label: 'Referral count',
                              value: 'Loading…',
                              muted: muted,
                              textColor: textColor,
                              isDark: isDark,
                              isLast: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ── ID Verification card ────────────
                        if ((member['idImagePath']?.toString() ?? '')
                            .isNotEmpty)
                          _ModalInfoCard(
                            isDark: isDark,
                            textColor: textColor,
                            muted: muted,
                            surface: surface,
                            divider: divider,
                            title: 'ID Verification',
                            icon: Icons.verified_user,
                            children: [
                              _ModalInfoRow(
                                icon: Icons.credit_card_outlined,
                                label: 'ID Type',
                                value: member['idType'],
                                muted: muted,
                                textColor: textColor,
                                isDark: isDark,
                              ),
                              if ((member['idNumber']?.toString() ?? '')
                                  .isNotEmpty)
                                _ModalInfoRow(
                                  icon: Icons.numbers_outlined,
                                  label: 'ID Number',
                                  value: member['idNumber'],
                                  muted: muted,
                                  textColor: textColor,
                                  isDark: isDark,
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: GestureDetector(
                                  onTap: () {
                                    final path = member['idImagePath']
                                        ?.toString();
                                    if (path != null && path.isNotEmpty) {
                                      _showIdImagePreview(ctx, path);
                                    }
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: buildIdImage(
                                      ctx,
                                      member['idImagePath'].toString(),
                                      height: 140,
                                      width: double.infinity,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                          ),

                        // ── Action buttons ─────────────────
                        const SizedBox(height: 20),

                        // Create account button (only if no account)
                        if (!hasAccount)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _showCreateAccountDialog(ctx, member),
                                icon: const Icon(
                                  Icons.person_add_rounded,
                                  size: 18,
                                ),
                                label: const Text('Create Login Account'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // View Password button (only if member HAS an account)
                        if (hasAccount)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _viewMemberPassword(ctx, member, fullName),
                                icon: const Icon(
                                  Icons.vpn_key_rounded,
                                  size: 18,
                                  color: Colors.amber,
                                ),
                                label: const Text('View Password'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.amber.shade800,
                                  side: BorderSide(
                                    color: Colors.amber.shade300,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _showTransactionHistory(ctx, member),
                                icon: const Icon(
                                  Icons.receipt_long_outlined,
                                  size: 18,
                                ),
                                label: const Text('View History'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _openEditDialog(member);
                                },
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('Edit Member'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () =>
                                _confirmDeleteMemberDialog(ctx, member),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Delete Member'),
                            style: TextButton.styleFrom(
                              foregroundColor: StockpileColors.danger,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTransactionHistory(BuildContext ctx, Map<String, dynamic> member) {
    final fullName = [
      member['firstName'],
      member['middleName'],
      member['lastName'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');
    final memberId = (member['id'] ?? 0) as int;

    showDialog<void>(
      context: ctx,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final size = MediaQuery.of(dialogContext).size;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: EdgeInsets.symmetric(
            horizontal: size.width < 480 ? 12 : 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: size.height * 0.85,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                size.width < 480 ? 12 : 18,
                16,
                size.width < 480 ? 12 : 18,
                18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName.isEmpty ? 'Member History' : fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Transaction history',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: FutureBuilder<List<Sale>>(
                      future: repository.fetchSalesForMember(memberId),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final sales = snap.data ?? [];
                        if (sales.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.receipt_long_outlined,
                                    size: 48,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withAlpha(80),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No transactions yet',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: sales.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final s = sales[index];
                            final time = s.timestamp;
                            final timeStr = time != null
                                ? '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}'
                                : '—';
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.itemName,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        Text(
                                          '$timeStr  ·  Qty: ${s.quantity}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '₱${s.price}',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showIdImagePreview(BuildContext ctx, String imagePath) {
    showAnimatedDialog(
      ctx,
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(c).size.height * 0.8,
            maxWidth: MediaQuery.of(c).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: InteractiveViewer(
                  child: buildIdImage(c, imagePath, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteMemberDialog(
    BuildContext ctx,
    Map<String, dynamic> member,
  ) {
    showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Member'),
        content: Text(
          'Permanently delete ${member['firstName'] ?? 'this member'}? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(c, true);
              _deleteMember(member);
              Navigator.pop(ctx); // close the member detail modal
            },
            style: FilledButton.styleFrom(
              backgroundColor: StockpileColors.danger,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _openEditDialog(Map<String, dynamic> member) {
    showAnimatedDialog(
      context,
      builder: (context) => EditMemberDialog(
        member: member,
        onMemberUpdated: (updatedMember) {
          _tableKey.currentState?.updateMember(member, updatedMember);
        },
      ),
    );
  }

  void _deleteMember(Map<String, dynamic> member) {
    _tableKey.currentState?.removeMember(member);
    showSuccessToast('Member deleted.');
  }

  void _showCreateAccountDialog(BuildContext ctx, Map<String, dynamic> member) {
    final memberId = (member['id'] ?? 0) as int;
    final name = [
      member['firstName'],
      member['lastName'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.person_add_rounded, color: StockpileColors.primary900),
            const SizedBox(width: 10),
            const Text('Create Login Account'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create a login account for $name so they can '
                'access the member portal.',
                style: Theme.of(c).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: usernameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordCtrl,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outlined),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(c);
              final result = await repository.createMemberAuthAccount(
                memberId: memberId,
                username: usernameCtrl.text.trim(),
                password: passwordCtrl.text,
              );
              if (!ctx.mounted) return;
              if (result != null) {
                final err = result['error']?.toString();
                if (err != null) {
                  showErrorToast(err);
                } else {
                  member['email'] = result['email'];
                  showSuccessToast(
                    'Account created!\nEmail: ${result['email']}\nPassword: ${result['password']}',
                  );
                  // Reopen modal with updated data so "Has account" shows
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _showMemberDetail(context, member);
                  }
                }
              } else {
                showErrorToast('Failed to create account.');
              }
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _viewMemberPassword(
    BuildContext ctx,
    Map<String, dynamic> member,
    String fullName,
  ) async {
    final memberId = (member['id'] ?? 0) as int;
    final password = await repository.fetchMemberPassword(memberId);

    if (!ctx.mounted) return;

    if (password == null || password.isEmpty) {
      await showDialog<void>(
        context: ctx,
        builder: (c) => AlertDialog(
          title: const Text('No Password Stored'),
          content: Text(
            'No password record exists for $fullName. '
            'The account was created before password tracking was enabled. '
            'Use Edit Member to update or recreate the account.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    _showMemberPasswordDialog(ctx, fullName, password);
  }

  void _showMemberPasswordDialog(
    BuildContext ctx,
    String name,
    String password,
  ) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    var obscured = true;

    showDialog<void>(
      context: ctx,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.vpn_key_rounded, color: Colors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Password for $name',
                  style: StockpileFonts.satoshi(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        obscured ? '••••••••••••' : password,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          letterSpacing: obscured ? 4 : 1,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        obscured ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscured = !obscured),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy to Clipboard'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: password));
                    BotToast.showText(text: 'Password copied!');
                  },
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Member detail modal widgets ───────────────────────────────────────────

class _ModalAvatarHeader extends StatelessWidget {
  const _ModalAvatarHeader({
    required this.initials,
    required this.fullName,
    required this.memberId,
    required this.isReseller,
    required this.email,
    required this.hasAccount,
    required this.isDark,
    required this.textColor,
    required this.muted,
  });

  final String initials;
  final String fullName;
  final String memberId;
  final bool isReseller;
  final String email;
  final bool hasAccount;
  final bool isDark;
  final Color textColor;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: divider),
      ),
      child: Row(
        children: [
          // ── Gradient avatar ────────────────────────────
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [StockpileColors.primary900, Color(0xFF3B1F7E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: StockpileColors.primary900.withAlpha(60),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: StockpileFonts.satoshi(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // ── Name + badges ──────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  style: StockpileFonts.satoshi(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // Member ID badge
                    _InfoBadge(
                      icon: Icons.fingerprint,
                      label: '#$memberId',
                      bgColor: textColor.withAlpha(12),
                      textColor: muted,
                      iconColor: muted,
                    ),
                    // Role badge
                    if (isReseller) ...[
                      _InfoBadge(
                        icon: Icons.verified,
                        label: 'Verified Reseller',
                        bgColor: StockpileColors.successBg,
                        textColor: StockpileColors.success,
                        iconColor: StockpileColors.success,
                      ),
                    ] else
                      _InfoBadge(
                        icon: Icons.person_outline,
                        label: 'Member',
                        bgColor: textColor.withAlpha(12),
                        textColor: muted,
                        iconColor: muted,
                      ),
                    // Account status badge
                    _InfoBadge(
                      icon: hasAccount
                          ? Icons.check_circle
                          : Icons.cancel_outlined,
                      label: hasAccount ? 'Has account' : 'No account',
                      bgColor: hasAccount
                          ? StockpileColors.successBg
                          : textColor.withAlpha(10),
                      textColor: hasAccount ? StockpileColors.success : muted,
                      iconColor: hasAccount ? StockpileColors.success : muted,
                    ),
                  ],
                ),
                // Email row
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.email_outlined, size: 14, color: muted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          email,
                          style: StockpileFonts.satoshi(
                            fontSize: 13,
                            color: muted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModalInfoCard extends StatelessWidget {
  const _ModalInfoCard({
    required this.isDark,
    required this.textColor,
    required this.muted,
    required this.surface,
    required this.divider,
    required this.title,
    required this.icon,
    required this.children,
  });

  final bool isDark;
  final Color textColor;
  final Color muted;
  final Color surface;
  final Color divider;
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: muted),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ModalInfoRow extends StatelessWidget {
  const _ModalInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.muted,
    required this.textColor,
    required this.isDark,
    this.italic = false,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final Object? value;
  final Color muted;
  final Color textColor;
  final bool isDark;
  final bool italic;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final text = value == null || value.toString().trim().isEmpty
        ? 'Not set'
        : value.toString();

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: muted),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: StockpileFonts.satoshi(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.textColor,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color bgColor;
  final Color textColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: StockpileFonts.satoshi(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
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
  List<PendingRequest> _historyRequests = [];
  Map<String, String> _profiles = {};
  Map<String, String> _roles = {};
  bool _showHistory = false;
  String _historyFilter = 'all'; // all, approved, rejected
  String _historyTypeFilter = 'all'; // all, delete, reduce
  bool _loading = true;
  bool _loadingMore = false;
  static const _pageSize = 25;
  int _pendingVisibleCount = _pageSize;
  int _pendingPage = 0;
  bool _pendingHasMore = true;
  int _historyVisibleCount = _pageSize;
  int _historyPage = 0;
  bool _historyHasMore = true;
  final Map<int, bool> _memberBorrowStatus = {};
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

  Future<void> _loadProfiles() async {
    final profiles = await repository.fetchProfilesMap();
    final rolesData = await repository.supabase
        .from('profiles')
        .select('id, role');
    final roles = <String, String>{};
    for (final r in (rolesData as List)) {
      roles[r['id'] as String] = r['role'] as String? ?? 'cashier';
    }
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _roles = roles;
    });
  }

  Future<void> _loadRequests() async {
    _loading = true;
    if (mounted) setState(() {});
    try {
      final page = await repository.fetchRequestsPaginated(
        page: 1,
        pageSize: _pageSize,
        statusFilter: 'pending',
      );
      final profiles = await repository.fetchProfilesMap();

      // Pre-check borrow status for member-deletion requests
      final Map<int, bool> borrowStatus = {};
      for (final req in page.rows) {
        if (req.requestType == 'delete_member' && req.memberId != null) {
          final hasBorrows = await repository.hasActiveBorrowsForMember(
            req.memberId!,
          );
          borrowStatus[req.memberId!] = hasBorrows;
        }
      }

      if (!mounted) return;
      setState(() {
        _pendingRequests = page.rows;
        _pendingPage = 1;
        _pendingHasMore = page.hasMore;
        _pendingVisibleCount = _pageSize;
        _profiles = profiles;
        _memberBorrowStatus
          ..clear()
          ..addAll(borrowStatus);
        _loading = false;
      });
      _loadProfiles();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadPendingNextPage() async {
    if (_loadingMore || !_pendingHasMore) return;
    _loadingMore = true;
    setState(() {});
    try {
      final page = await repository.fetchRequestsPaginated(
        page: _pendingPage + 1,
        pageSize: _pageSize,
        statusFilter: 'pending',
      );
      if (!mounted) return;
      setState(() {
        _pendingRequests.addAll(page.rows);
        _pendingPage = page.page;
        _pendingHasMore = page.hasMore;
        _pendingVisibleCount = _pendingRequests.length;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadHistory() async {
    _loading = true;
    if (mounted) setState(() {});
    try {
      final page = await repository.fetchRequestsPaginated(
        page: 1,
        pageSize: _pageSize,
        statusFilter: 'history',
      );
      final profiles = await repository.fetchProfilesMap();
      if (!mounted) return;
      setState(() {
        _historyRequests = page.rows;
        _historyPage = 1;
        _historyHasMore = page.hasMore;
        _historyVisibleCount = _pageSize;
        _profiles = profiles;
        _loading = false;
      });
      _loadProfiles();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadHistoryNextPage() async {
    if (_loadingMore || !_historyHasMore) return;
    _loadingMore = true;
    setState(() {});
    try {
      final page = await repository.fetchRequestsPaginated(
        page: _historyPage + 1,
        pageSize: _pageSize,
        statusFilter: 'history',
      );
      if (!mounted) return;
      setState(() {
        _historyRequests.addAll(page.rows);
        _historyPage = page.page;
        _historyHasMore = page.hasMore;
        _historyVisibleCount = _historyRequests.length;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _showReasonDialog(BuildContext context, String reason) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
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
                      color: colorScheme.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: colorScheme.primary,
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
                      color: colorScheme.primary.withAlpha(120),
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

  Widget _buildModernRequestCard({
    required bool isDark,
    required Color accentColor,
    required IconData icon,
    required String title,
    required String body,
    String? detail,
    Color? detailColor,
    String? notes,
    String? reason,
    required String submitter,
    required String timeAgo,
    required List<_ActionButton> actions,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
          width: 1,
        ),
      ),
      color: isDark ? Colors.grey.shade900 : Colors.white,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left color accent bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: icon + title
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accentColor.withAlpha(isDark ? 30 : 20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, size: 18, color: accentColor),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Body
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF334155),
                      ),
                    ),
                    // Detail
                    if (detail != null && detail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              detailColor ??
                              (isDark
                                  ? Colors.white54
                                  : const Color(0xFF64748B)),
                        ),
                      ),
                    ],
                    // Notes
                    if (notes != null && notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.notes_rounded,
                            size: 14,
                            color: isDark
                                ? Colors.white38
                                : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              notes,
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: isDark
                                    ? Colors.white54
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Reason
                    if (reason != null && reason.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _showReasonDialog(context, reason),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withAlpha(isDark ? 15 : 10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 13,
                                color: accentColor,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'View reason',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Divider(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      height: 1,
                    ),
                    const SizedBox(height: 10),
                    // Footer: submitter + time + actions
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                size: 13,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '$submitter · $timeAgo',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.grey.shade500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Action buttons
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: actions.map((a) {
                            return Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Material(
                                color: a.color.withAlpha(isDark ? 25 : 15),
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: a.onTap,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    child: Icon(
                                      a.icon,
                                      size: 20,
                                      color: a.onTap != null
                                          ? a.color
                                          : a.color.withAlpha(120),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(PendingRequest req) async {
    if (req.id == null) return;

    // Pre-check: if this is a delete request, verify no active borrows exist
    if (req.requestType == 'delete') {
      final hasBorrows = await repository.hasActiveBorrows(req.itemId!);
      if (!mounted) return;
      if (hasBorrows) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cannot approve deletion'),
            content: Text(
              '"${req.itemName}" has unsettled borrows. '
              'All borrowed items must be returned or paid for '
              'before this product can be deleted.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }

    // Pre-check: if this is a member deletion, verify no active borrows
    if (req.requestType == 'delete_member' && req.memberId != null) {
      final hasBorrows = await repository.hasActiveBorrowsForMember(
        req.memberId!,
      );
      if (!mounted) return;
      if (hasBorrows) {
        final borrows = await repository.fetchActiveBorrowsForMember(
          req.memberId!,
        );
        if (!mounted) return;
        await _showBorrowsModal(req.memberName ?? 'Member', borrows);
        return;
      }
    }

    // Pre-check: if this is a borrow request, verify stock is sufficient
    if (req.requestType == 'borrow' && req.itemId != null) {
      final item = await repository.getItemById(req.itemId!);
      if (!mounted) return;
      if (item == null) {
        BotToast.showText(text: 'Item no longer exists');
        _loadRequests();
        return;
      }
      final needed = req.quantity ?? 0;
      if (item.stock < needed) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cannot approve borrow'),
            content: Text(
              'Insufficient stock for "${req.itemName}". '
              'Current stock: ${item.stock}, requested: $needed.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }

    final err = await repository.approveRequest(req.id!);
    if (!mounted) return;
    if (err == null) {
      BotToast.showText(text: '${req.summary} — approved');
    } else {
      BotToast.showText(text: 'Failed to approve ${req.summary}: $err');
    }
    _loadRequests();
  }

  Future<void> _reject(PendingRequest req) async {
    if (req.id == null) return;

    // Show rejection reason dialog
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(req.summary, style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Rejection reason',
                hintText: 'Explain why this request is being rejected',
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
            style: FilledButton.styleFrom(
              backgroundColor: StockpileColors.error500,
            ),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                BotToast.showText(text: 'Please provide a rejection reason');
                return;
              }
              Navigator.pop(ctx, reasonController.text.trim());
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (!mounted || reason == null) return;

    final ok = await repository.rejectRequest(req.id!, rejectionReason: reason);
    if (!mounted) return;
    if (ok) {
      BotToast.showText(text: '${req.summary} — rejected');
    } else {
      BotToast.showText(text: 'Failed to reject ${req.summary}');
    }
    _loadRequests();
  }

  /// Shows a modal listing the member's active borrows.
  Future<void> _showBorrowsModal(
    String memberName,
    List<Borrow> borrows,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final totalOutstanding = borrows.fold<int>(
      0,
      (s, b) => s + b.outstandingQuantity,
    );
    final overdueCount = borrows.where((b) => b.isOverdue).length;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: cs.surface,
        titlePadding: EdgeInsets.zero,
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ───────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50.withAlpha(isDark ? 30 : 200),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.person_remove_rounded,
                            color: Colors.purple.shade700,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Member Deletion Blocked',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.purple.shade700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                memberName,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? StockpileColors.darkTextPrimary
                                      : StockpileColors.darkText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Summary Bar ──────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color:
                      (overdueCount > 0
                              ? StockpileColors.error500
                              : StockpileColors.success)
                          .withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        (overdueCount > 0
                                ? StockpileColors.error500
                                : StockpileColors.success)
                            .withAlpha(60),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      overdueCount > 0
                          ? Icons.warning_amber_rounded
                          : Icons.inventory_2_outlined,
                      size: 20,
                      color: overdueCount > 0
                          ? StockpileColors.error500
                          : StockpileColors.success,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$totalOutstanding outstanding items across ${borrows.length} borrow${borrows.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? StockpileColors.darkTextBody
                            : StockpileColors.bodyText,
                      ),
                    ),
                    if (overdueCount > 0) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: StockpileColors.error500.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$overdueCount overdue',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: StockpileColors.error500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Borrow List ──────────────────────────────────
              Flexible(
                child: borrows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No unsettled borrows found.',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? StockpileColors.darkTextMuted
                                  : StockpileColors.mutedText,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        itemCount: borrows.length,
                        itemBuilder: (_, i) {
                          final b = borrows[i];
                          final isOverdue = b.isOverdue;
                          final statusColor = isOverdue
                              ? StockpileColors.error500
                              : b.outstandingQuantity < b.quantity
                              ? Colors.amber.shade700
                              : Colors.teal.shade600;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? StockpileColors.darkSurface
                                  : StockpileColors.tableHead,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: statusColor.withAlpha(50),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        isOverdue
                                            ? Icons.schedule_rounded
                                            : b.outstandingQuantity < b.quantity
                                            ? Icons.sync_rounded
                                            : Icons.check_circle_outline,
                                        size: 18,
                                        color: statusColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          b.itemName,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? StockpileColors
                                                      .darkTextPrimary
                                                : StockpileColors.darkText,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withAlpha(25),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          b.statusLabel.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: statusColor,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _BorrowStat(
                                        icon: Icons.inventory_2_outlined,
                                        label: 'Total',
                                        value: '${b.quantity}',
                                      ),
                                      const SizedBox(width: 16),
                                      _BorrowStat(
                                        icon: Icons.assignment_return_outlined,
                                        label: 'Outstanding',
                                        value: '${b.outstandingQuantity}',
                                        valueColor: b.outstandingQuantity > 0
                                            ? statusColor
                                            : null,
                                      ),
                                      const Spacer(),
                                      Text(
                                        'Due ${_formatDate(b.dueDate)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: isOverdue
                                              ? StockpileColors.error500
                                              : isDark
                                              ? StockpileColors.darkTextMuted
                                              : StockpileColors.mutedText,
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
              ),

              // ── Footer ───────────────────────────────────────
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Close'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tiny stat pill used in borrow details modal.
  Widget _BorrowStat({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: isDark
              ? StockpileColors.darkTextMuted
              : StockpileColors.mutedText,
        ),
        const SizedBox(width: 4),
        Text(
          '$label ',
          style: TextStyle(
            fontSize: 12,
            color: isDark
                ? StockpileColors.darkTextMuted
                : StockpileColors.mutedText,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color:
                valueColor ??
                (isDark
                    ? StockpileColors.darkTextBody
                    : StockpileColors.bodyText),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show history view
    if (_showHistory) {
      if (_historyRequests.isEmpty) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  _ToggleChip(
                    label: 'Pending',
                    count: _pendingRequests.length,
                    isSelected: false,
                    onTap: () => setState(() {
                      _showHistory = false;
                      _loading = true;
                      _loadRequests();
                    }),
                  ),
                  const SizedBox(width: 8),
                  _ToggleChip(label: 'History', isSelected: true, onTap: () {}),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 48,
                      color: StockpileColors.success,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No history yet',
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
                      'Approved and rejected requests will appear here.',
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
              ),
            ),
          ],
        );
      }
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _ToggleChip(
                  label: 'Pending',
                  count: _pendingRequests.length,
                  isSelected: false,
                  onTap: () => setState(() {
                    _showHistory = false;
                    _loading = true;
                    _loadRequests();
                  }),
                ),
                const SizedBox(width: 8),
                _ToggleChip(label: 'History', isSelected: true, onTap: () {}),
              ],
            ),
          ),
          _buildHistoryFilterRow(),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadHistory,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: _filteredHistory
                          .take(_historyVisibleCount)
                          .length,
                      itemBuilder: (context, index) => _buildHistoryCard(
                        _filteredHistory[index],
                        isDark,
                        theme,
                      ),
                    ),
                  ),
                ),
                if (_historyVisibleCount < _filteredHistory.length ||
                    _historyHasMore)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _loadingMore
                            ? null
                            : () {
                                if (_historyVisibleCount + _pageSize >
                                        _historyRequests.length &&
                                    _historyHasMore) {
                                  _loadHistoryNextPage().then((_) {
                                    if (mounted)
                                      setState(
                                        () => _historyVisibleCount += _pageSize,
                                      );
                                  });
                                } else {
                                  setState(
                                    () => _historyVisibleCount += _pageSize,
                                  );
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
                                'Load More (${_historyVisibleCount.clamp(0, _filteredHistory.length)} of ${_filteredHistory.length}${_historyHasMore ? "+" : ""})',
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    // Pending view
    if (_pendingRequests.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _ToggleChip(
                  label: 'Pending',
                  count: 0,
                  isSelected: true,
                  onTap: () {},
                ),
                const SizedBox(width: 8),
                _ToggleChip(
                  label: 'History',
                  isSelected: false,
                  onTap: () => setState(() {
                    _showHistory = true;
                    _loading = true;
                    _loadHistory();
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
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
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Toggle row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _ToggleChip(
                label: 'Pending',
                count: _pendingRequests.length,
                isSelected: true,
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _ToggleChip(
                label: 'History',
                isSelected: false,
                onTap: () => setState(() {
                  _showHistory = true;
                  _loading = true;
                  _loadHistory();
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: _pendingRequests.take(_pendingVisibleCount).length,
            itemBuilder: (context, index) {
              final req = _pendingRequests[index];
              final isMemberDelete = req.requestType == 'delete_member';
              final isDelete = req.requestType == 'delete';
              final isBorrow = req.requestType == 'borrow';
              final icon = isMemberDelete
                  ? Icons.person_remove_rounded
                  : isDelete
                  ? Icons.delete_forever_rounded
                  : isBorrow
                  ? Icons.swap_horiz_rounded
                  : Icons.arrow_downward_rounded;

              if (isMemberDelete) {
                final hasBorrows = _memberBorrowStatus[req.memberId] ?? false;
                final submitter = _profiles[req.userId] ?? 'Unknown';
                final role = _roles[req.userId] ?? '';
                final submitterLabel = role.isNotEmpty
                    ? '$submitter ($role)'
                    : submitter;

                return _buildModernRequestCard(
                  isDark: isDark,
                  accentColor: Colors.purple.shade600,
                  icon: icon,
                  title: 'Delete Member Request',
                  body: req.memberName ?? 'Unknown',
                  detail: hasBorrows
                      ? '⚠ This member has unsettled borrows'
                      : null,
                  detailColor: Colors.red,
                  reason: req.reason,
                  submitter: submitterLabel,
                  timeAgo: req.createdAt != null
                      ? _formatDate(req.createdAt!)
                      : '',
                  actions: [
                    if (hasBorrows)
                      _ActionButton(
                        icon: Icons.info_outline_rounded,
                        color: Colors.blue.shade600,
                        tooltip: 'View unsettled borrows',
                        onTap: () async {
                          final borrows = await repository
                              .fetchActiveBorrowsForMember(req.memberId!);
                          if (!mounted) return;
                          await _showBorrowsModal(
                            req.memberName ?? 'Member',
                            borrows,
                          );
                        },
                      ),
                    _ActionButton(
                      icon: Icons.check_circle_outline,
                      color: hasBorrows
                          ? Colors.grey.shade400
                          : StockpileColors.success,
                      tooltip: hasBorrows
                          ? 'Cannot approve — unsettled borrows'
                          : 'Approve',
                      onTap: hasBorrows ? null : () => _approve(req),
                    ),
                    _ActionButton(
                      icon: Icons.cancel_outlined,
                      color: StockpileColors.error500,
                      tooltip: 'Reject',
                      onTap: () => _reject(req),
                    ),
                  ],
                );
              }

              if (isBorrow) {
                final submitter = _profiles[req.userId] ?? 'Unknown';
                final role = _roles[req.userId] ?? '';
                final submitterLabel = role.isNotEmpty
                    ? '$submitter ($role)'
                    : submitter;

                final detailParts = <String>[
                  'For ${req.memberName ?? 'Unknown'}',
                  '×${req.quantity ?? 0}',
                ];
                if (req.price != null && req.price! > 0) {
                  detailParts.add('₱${req.price} each');
                }
                final notes = req.notes;

                return _buildModernRequestCard(
                  isDark: isDark,
                  accentColor: Colors.orange.shade600,
                  icon: icon,
                  title: 'Borrow Request',
                  body: req.itemName ?? 'Unknown item',
                  detail: detailParts.join(' · '),
                  notes: notes != null && notes.isNotEmpty ? notes : null,
                  reason: req.reason,
                  submitter: submitterLabel,
                  timeAgo: req.createdAt != null
                      ? _formatDate(req.createdAt!)
                      : '',
                  actions: [
                    _ActionButton(
                      icon: Icons.check_circle_outline,
                      color: StockpileColors.success,
                      tooltip: 'Approve borrow',
                      onTap: () => _approve(req),
                    ),
                    _ActionButton(
                      icon: Icons.cancel_outlined,
                      color: StockpileColors.error500,
                      tooltip: 'Reject',
                      onTap: () => _reject(req),
                    ),
                  ],
                );
              }

              final submitter = _profiles[req.userId] ?? 'Unknown';
              final role = _roles[req.userId] ?? '';
              final submitterLabel = role.isNotEmpty
                  ? '$submitter ($role)'
                  : submitter;

              if (isDelete) {
                return _buildModernRequestCard(
                  isDark: isDark,
                  accentColor: StockpileColors.error500,
                  icon: icon,
                  title: 'Delete Request',
                  body: req.itemName ?? 'Unknown item',
                  reason: req.reason,
                  submitter: submitterLabel,
                  timeAgo: req.createdAt != null
                      ? _formatDate(req.createdAt!)
                      : '',
                  actions: [
                    _ActionButton(
                      icon: Icons.check_circle_outline,
                      color: StockpileColors.success,
                      tooltip: 'Approve',
                      onTap: () => _approve(req),
                    ),
                    _ActionButton(
                      icon: Icons.cancel_outlined,
                      color: StockpileColors.error500,
                      tooltip: 'Reject',
                      onTap: () => _reject(req),
                    ),
                  ],
                );
              } else {
                return _buildModernRequestCard(
                  isDark: isDark,
                  accentColor: Colors.orange.shade600,
                  icon: icon,
                  title: 'Reduce Stock Request',
                  body: req.itemName ?? 'Unknown item',
                  detail: req.quantity != null
                      ? 'Reduce by ${req.quantity}'
                      : null,
                  reason: req.reason,
                  submitter: submitterLabel,
                  timeAgo: req.createdAt != null
                      ? _formatDate(req.createdAt!)
                      : '',
                  actions: [
                    _ActionButton(
                      icon: Icons.check_circle_outline,
                      color: StockpileColors.success,
                      tooltip: 'Approve',
                      onTap: () => _approve(req),
                    ),
                    _ActionButton(
                      icon: Icons.cancel_outlined,
                      color: StockpileColors.error500,
                      tooltip: 'Reject',
                      onTap: () => _reject(req),
                    ),
                  ],
                );
              }
            },
          ),
        ),
        if (_pendingVisibleCount < _pendingRequests.length || _pendingHasMore)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _loadingMore
                    ? null
                    : () {
                        if (_pendingVisibleCount + _pageSize >
                                _pendingRequests.length &&
                            _pendingHasMore) {
                          _loadPendingNextPage().then((_) {
                            if (mounted)
                              setState(() => _pendingVisibleCount += _pageSize);
                          });
                        } else {
                          setState(() => _pendingVisibleCount += _pageSize);
                        }
                      },
                child: _loadingMore
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Load More (${_pendingVisibleCount.clamp(0, _pendingRequests.length)} of ${_pendingRequests.length}${_pendingHasMore ? "+" : ""})',
                      ),
              ),
            ),
          ),
      ],
    );
  }

  List<PendingRequest> get _filteredHistory {
    return _historyRequests.where((r) {
      if (_historyFilter != 'all' && r.status != _historyFilter) return false;
      if (_historyTypeFilter != 'all' && r.requestType != _historyTypeFilter)
        return false;
      return true;
    }).toList();
  }

  Widget _buildHistoryFilterRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    // Compute counts per filter — each dimension's counts reflect
    // the OTHER dimension's current filter, so they stay in sync.
    // Status counts are computed from the type-filtered subset.
    final typeFiltered = _historyRequests.where((r) {
      if (_historyTypeFilter != 'all' && r.requestType != _historyTypeFilter) {
        return false;
      }
      return true;
    }).toList();
    // Action counts are computed from the status-filtered subset.
    final statusFiltered = _historyRequests.where((r) {
      if (_historyFilter != 'all' && r.status != _historyFilter) return false;
      return true;
    }).toList();

    // "All" per dimension reflects the OTHER dimension's filter
    final statusAllCount = typeFiltered.length;
    final actionAllCount = statusFiltered.length;
    final approvedCount = typeFiltered
        .where((r) => r.status == 'approved')
        .length;
    final rejectedCount = typeFiltered
        .where((r) => r.status == 'rejected')
        .length;
    final deleteCount = statusFiltered
        .where((r) => r.requestType == 'delete')
        .length;
    final reduceCount = statusFiltered
        .where((r) => r.requestType == 'reduce_stock')
        .length;
    final memberCount = statusFiltered
        .where((r) => r.requestType == 'delete_member')
        .length;
    final borrowCount = statusFiltered
        .where((r) => r.requestType == 'borrow')
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status filter row
            Row(
              children: [
                Icon(Icons.filter_list_rounded, size: 15, color: mutedColor),
                const SizedBox(width: 6),
                Text(
                  'Status:',
                  style: StockpileFonts.satoshi(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: mutedColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'All',
                          count: statusAllCount,
                          isSelected: _historyFilter == 'all',
                          onTap: () => setState(() => _historyFilter = 'all'),
                        ),
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: 'Approved',
                          count: approvedCount,
                          isSelected: _historyFilter == 'approved',
                          onTap: () =>
                              setState(() => _historyFilter = 'approved'),
                        ),
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: 'Rejected',
                          count: rejectedCount,
                          isSelected: _historyFilter == 'rejected',
                          onTap: () =>
                              setState(() => _historyFilter = 'rejected'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Action type filter row
            Row(
              children: [
                Icon(Icons.category_rounded, size: 15, color: mutedColor),
                const SizedBox(width: 6),
                Text(
                  'Action:',
                  style: StockpileFonts.satoshi(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: mutedColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'All',
                          count: actionAllCount,
                          isSelected: _historyTypeFilter == 'all',
                          onTap: () =>
                              setState(() => _historyTypeFilter = 'all'),
                        ),
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: 'Delete',
                          count: deleteCount,
                          isSelected: _historyTypeFilter == 'delete',
                          onTap: () =>
                              setState(() => _historyTypeFilter = 'delete'),
                        ),
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: 'Reduce',
                          count: reduceCount,
                          isSelected: _historyTypeFilter == 'reduce_stock',
                          onTap: () => setState(
                            () => _historyTypeFilter = 'reduce_stock',
                          ),
                        ),
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: 'Member',
                          count: memberCount,
                          isSelected: _historyTypeFilter == 'delete_member',
                          onTap: () => setState(
                            () => _historyTypeFilter = 'delete_member',
                          ),
                        ),
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: 'Borrow',
                          count: borrowCount,
                          isSelected: _historyTypeFilter == 'borrow',
                          onTap: () =>
                              setState(() => _historyTypeFilter = 'borrow'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Clear filters button (only shown when a filter is active)
            if (_historyFilter != 'all' || _historyTypeFilter != 'all') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() {
                      _historyFilter = 'all';
                      _historyTypeFilter = 'all';
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: StockpileColors.error500.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.clear_all_rounded,
                            size: 13,
                            color: StockpileColors.error500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Clear filters',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: StockpileColors.error500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(PendingRequest req, bool isDark, ThemeData theme) {
    final isApproved = req.status == 'approved';
    final isMemberDelete = req.requestType == 'delete_member';

    final Color statusColor = isApproved
        ? StockpileColors.success
        : StockpileColors.error500;
    final Color accentColor = switch (req.requestType) {
      'delete' => StockpileColors.error500,
      'reduce_stock' => Colors.orange.shade600,
      'delete_member' => Colors.purple.shade600,
      'borrow' => Colors.orange.shade600,
      _ => StockpileColors.primary900,
    };
    final IconData typeIcon = switch (req.requestType) {
      'delete' => Icons.delete_forever_rounded,
      'reduce_stock' => Icons.arrow_downward_rounded,
      'delete_member' => Icons.person_remove_rounded,
      'borrow' => Icons.swap_horiz_rounded,
      _ => Icons.help_outline_rounded,
    };
    final String typeLabel = switch (req.requestType) {
      'delete' => 'Delete',
      'reduce_stock' => 'Reduce Stock',
      'delete_member' => 'Delete Member',
      'borrow' => 'Borrow',
      _ => req.requestType,
    };

    final submitter = _profiles[req.userId] ?? 'Unknown';
    final role = _roles[req.userId];
    final submitterLabel = role != null
        ? '$submitter (${role[0].toUpperCase()}${role.substring(1)})'
        : submitter;
    final hasRejectionReason =
        req.status == 'rejected' &&
        req.rejectionReason != null &&
        req.rejectionReason!.isNotEmpty;

    final textPrimary = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final textMuted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            children: [
              // ── Left accent bar ──────────────────────
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              // ── Card body ───────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: type chip + status badge
                      Row(
                        children: [
                          // Type chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(typeIcon, size: 13, color: accentColor),
                                const SizedBox(width: 4),
                                Text(
                                  typeLabel,
                                  style: StockpileFonts.satoshi(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: statusColor.withAlpha(60),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isApproved
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_rounded,
                                  size: 13,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isApproved ? 'Approved' : 'Rejected',
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
                      const SizedBox(height: 8),
                      // Item/Member name
                      Text(
                        isMemberDelete
                            ? (req.memberName ?? 'Unknown')
                            : (req.itemName ?? 'Unknown'),
                        style: StockpileFonts.satoshi(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Detail line (quantity / price for non-member)
                      if (!isMemberDelete && req.quantity != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '×${req.quantity}${req.price != null && req.price! > 0 ? ' · ₱${req.price} each' : ''}',
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            color: textMuted,
                          ),
                        ),
                      ],
                      // Rejection reason
                      if (hasRejectionReason) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.block_rounded,
                              size: 14,
                              color: StockpileColors.error500,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                req.rejectionReason!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: StockpileColors.error500,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Reason (viewable)
                      if (req.reason != null && req.reason!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _showReasonDialog(context, req.reason!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withAlpha(isDark ? 15 : 10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 12,
                                  color: accentColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'View reason',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Footer: submitter + date
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 13,
                            color: textMuted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              submitterLabel,
                              style: StockpileFonts.satoshi(
                                fontSize: 11,
                                color: textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: textMuted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            req.createdAt != null
                                ? _formatDate(req.createdAt!)
                                : '',
                            style: StockpileFonts.satoshi(
                              fontSize: 11,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

/// Action button used in modern request cards.
class _ActionButton {
  final IconData icon;
  final Color color;
  final String? tooltip;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    this.tooltip,
    this.onTap,
  });
}

/// Toggle chip for Pending | History tab bar.
class _ToggleChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = StockpileColors.primary900;
    final inactiveBg = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final activeBorder = StockpileColors.primary900;
    final inactiveBorder = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? activeBorder : inactiveBorder),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: StockpileColors.primary900.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: StockpileFonts.satoshi(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark
                          ? StockpileColors.darkTextBody
                          : StockpileColors.bodyText),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withAlpha(40)
                      : StockpileColors.primary900.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: StockpileFonts.satoshi(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white
                        : StockpileColors.primary900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small filter chip for history view.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final int? count;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = isDark
        ? StockpileColors.primary900.withAlpha(40)
        : StockpileColors.primary900.withAlpha(20);
    final inactiveBg = isDark
        ? StockpileColors.darkInputBg
        : StockpileColors.inputBg;
    final activeBorder = StockpileColors.primary900;
    final inactiveBorder = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;
    final activeText = isDark ? Colors.white : StockpileColors.primary900;
    final inactiveText = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? activeBorder : inactiveBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: StockpileFonts.satoshi(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? activeText : inactiveText,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeText.withAlpha(30)
                      : inactiveText.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: StockpileFonts.satoshi(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? activeText : inactiveText,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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
  String _settledFilter = 'all'; // all, returned, remitted (sub-filter)

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
        return _filteredSettled;
      default:
        return _borrows;
    }
  }

  List<Borrow> get _allSettled =>
      _borrows.where((b) => b.outstandingQuantity <= 0).toList();

  List<Borrow> get _returnedOnly =>
      _allSettled.where((b) => b.quantityReturned > 0).toList();

  List<Borrow> get _remittedOnly =>
      _allSettled.where((b) => b.quantityRemitted > 0).toList();

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

  int get _returnedCount => _returnedOnly.length;
  int get _remittedCount => _remittedOnly.length;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final qtyCtrl = TextEditingController(
      text: b.outstandingQuantity.toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: StockpileColors.success.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.assignment_return_rounded,
                      color: StockpileColors.success,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Return Item',
                          style: StockpileFonts.satoshi(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? StockpileColors.darkTextPrimary
                                : StockpileColors.darkText,
                          ),
                        ),
                        Text(
                          '${b.itemName}',
                          style: StockpileFonts.satoshi(
                            fontSize: 13,
                            color: isDark
                                ? StockpileColors.darkTextMuted
                                : StockpileColors.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _QtyBadge(
                    label: 'Borrowed',
                    value: b.quantity,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _QtyBadge(
                    label: 'Outstanding',
                    value: b.outstandingQuantity,
                    isDark: isDark,
                    color: StockpileColors.error500,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qtyCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Quantity to return',
                  hintText: 'Enter quantity',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? StockpileColors.darkInputBg
                      : StockpileColors.inputBg,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final q = int.tryParse(qtyCtrl.text) ?? 0;
                        Navigator.pop(ctx, q);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: StockpileColors.success,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Return'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null || result <= 0) return;
    final ok = await repository.returnBorrowedItem(b.id!, result);
    if (!mounted) return;
    BotToast.showText(
      text: ok ? '${b.itemName}: $result returned' : 'Failed to return item',
    );
    _loadData();
  }

  Future<void> _remitItem(Borrow b) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final qtyCtrl = TextEditingController(
      text: b.outstandingQuantity.toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.purple.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.payments_rounded,
                      color: Colors.purple,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Remit Payment',
                          style: StockpileFonts.satoshi(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? StockpileColors.darkTextPrimary
                                : StockpileColors.darkText,
                          ),
                        ),
                        Text(
                          '${b.itemName} ·  ₱${b.price} each',
                          style: StockpileFonts.satoshi(
                            fontSize: 13,
                            color: isDark
                                ? StockpileColors.darkTextMuted
                                : StockpileColors.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _QtyBadge(
                    label: 'Borrowed',
                    value: b.quantity,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _QtyBadge(
                    label: 'Outstanding',
                    value: b.outstandingQuantity,
                    isDark: isDark,
                    color: StockpileColors.error500,
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.withAlpha(15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.purple.withAlpha(50)),
                    ),
                    child: Text(
                      'Total: ₱${b.price * b.outstandingQuantity}',
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.purple,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qtyCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Quantity to remit',
                  hintText: 'Enter quantity',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? StockpileColors.darkInputBg
                      : StockpileColors.inputBg,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final q = int.tryParse(qtyCtrl.text) ?? 0;
                        Navigator.pop(ctx, q);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.purple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Remit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null || result <= 0) return;
    final ok = await repository.remitBorrowedItem(b.id!, result);
    if (!mounted) return;
    BotToast.showText(
      text: ok ? '${b.itemName}: $result remitted' : 'Failed to remit payment',
    );
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
            color: isDark
                ? StockpileColors.error500.withAlpha(30)
                : StockpileColors.error50,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: StockpileColors.error500.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: StockpileColors.error500,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_overdueCount Overdue',
                        style: StockpileFonts.satoshi(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? StockpileColors.darkTextPrimary
                              : StockpileColors.darkText,
                        ),
                      ),
                      Text(
                        'These borrows have exceeded their due date.',
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
              ],
            ),
          ),

        // Summary cards row
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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

        // Settled sub-filter chips
        if (_filter == 'settled')
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                _SettledSubChip(
                  label: 'All',
                  count: _settledCount,
                  isSelected: _settledFilter == 'all',
                  color: StockpileColors.success,
                  onTap: () => setState(() => _settledFilter = 'all'),
                ),
                const SizedBox(width: 6),
                _SettledSubChip(
                  label: 'Returned',
                  count: _returnedCount,
                  isSelected: _settledFilter == 'returned',
                  color: StockpileColors.success,
                  onTap: () => setState(() => _settledFilter = 'returned'),
                ),
                const SizedBox(width: 6),
                _SettledSubChip(
                  label: 'Remitted',
                  count: _remittedCount,
                  isSelected: _settledFilter == 'remitted',
                  color: Colors.purple,
                  onTap: () => setState(() => _settledFilter = 'remitted'),
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
                      final memName = b.memberName ?? _memberName(b.memberId);
                      final statusLbl = _statusLabel(b);
                      final overdue = b.isOverdue && b.outstandingQuantity > 0;
                      final statusCol = _statusColor(b.status, overdue, isDark);
                      final isSettled = b.outstandingQuantity <= 0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? StockpileColors.darkSurface
                                : StockpileColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: overdue
                                  ? StockpileColors.error500.withAlpha(120)
                                  : isDark
                                  ? StockpileColors.darkDivider
                                  : StockpileColors.divider,
                              width: overdue ? 1.5 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: IntrinsicHeight(
                            child: Row(
                              children: [
                                // ── Left accent bar ──────────────
                                Container(
                                  width: 4,
                                  decoration: BoxDecoration(
                                    color: overdue
                                        ? StockpileColors.error500
                                        : statusCol,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(12),
                                      bottomLeft: Radius.circular(12),
                                    ),
                                  ),
                                ),
                                // ── Card body ────────────────────
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Header: item name + status badge
                                        Row(
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: statusCol.withAlpha(30),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                isSettled
                                                    ? Icons.check_circle_outline
                                                    : Icons.swap_horiz_rounded,
                                                size: 20,
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
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: isDark
                                                          ? StockpileColors
                                                                .darkTextPrimary
                                                          : StockpileColors
                                                                .darkText,
                                                    ),
                                                  ),
                                                  Text(
                                                    memName,
                                                    style: StockpileFonts.satoshi(
                                                      fontSize: 12,
                                                      color: isDark
                                                          ? StockpileColors
                                                                .darkTextMuted
                                                          : StockpileColors
                                                                .mutedText,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Status badge
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: statusCol.withAlpha(25),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: statusCol.withAlpha(
                                                    60,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    overdue
                                                        ? Icons
                                                              .warning_amber_rounded
                                                        : isSettled
                                                        ? Icons
                                                              .check_circle_rounded
                                                        : Icons
                                                              .hourglass_bottom_rounded,
                                                    size: 13,
                                                    color: statusCol,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    statusLbl,
                                                    style:
                                                        StockpileFonts.satoshi(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: statusCol,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 10),

                                        // Quantity badges row
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              _QtyBadge(
                                                label: 'Borrowed',
                                                value: b.quantity,
                                                isDark: isDark,
                                              ),
                                              const SizedBox(width: 6),
                                              _QtyBadge(
                                                label: 'Returned',
                                                value: b.quantityReturned,
                                                isDark: isDark,
                                                color: StockpileColors.success,
                                              ),
                                              const SizedBox(width: 6),
                                              _QtyBadge(
                                                label: 'Remitted',
                                                value: b.quantityRemitted,
                                                isDark: isDark,
                                                color: Colors.purple,
                                              ),
                                              const SizedBox(width: 6),
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
                                        ),

                                        const SizedBox(height: 8),

                                        // Date row
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.event_rounded,
                                              size: 13,
                                              color: isDark
                                                  ? StockpileColors
                                                        .darkTextMuted
                                                  : StockpileColors.mutedText,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Borrowed ${_formatDateShort(b.borrowedAt ?? DateTime.now())}',
                                              style: StockpileFonts.satoshi(
                                                fontSize: 11,
                                                color: isDark
                                                    ? StockpileColors
                                                          .darkTextMuted
                                                    : StockpileColors.mutedText,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Icon(
                                              Icons.schedule_rounded,
                                              size: 13,
                                              color: overdue
                                                  ? StockpileColors.error500
                                                  : isDark
                                                  ? StockpileColors
                                                        .darkTextMuted
                                                  : StockpileColors.mutedText,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Due ${_formatDateShort(b.dueDate)}',
                                              style: StockpileFonts.satoshi(
                                                fontSize: 11,
                                                color: overdue
                                                    ? StockpileColors.error500
                                                    : isDark
                                                    ? StockpileColors
                                                          .darkTextMuted
                                                    : StockpileColors.mutedText,
                                                fontWeight: overdue
                                                    ? FontWeight.w700
                                                    : FontWeight.w400,
                                              ),
                                            ),
                                            if (overdue) ...[
                                              const SizedBox(width: 4),
                                              Text(
                                                '(${DateTime.now().difference(b.dueDate).inDays}d late)',
                                                style: StockpileFonts.satoshi(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      StockpileColors.error500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),

                                        // Notes
                                        if (b.notes != null &&
                                            b.notes!.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.notes_rounded,
                                                size: 13,
                                                color: isDark
                                                    ? StockpileColors
                                                          .darkTextMuted
                                                    : StockpileColors.mutedText,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  b.notes!,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontStyle: FontStyle.italic,
                                                    color: isDark
                                                        ? StockpileColors
                                                              .darkTextMuted
                                                        : StockpileColors
                                                              .mutedText,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],

                                        // Action buttons
                                        if (b.outstandingQuantity > 0) ...[
                                          const SizedBox(height: 10),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              OutlinedButton.icon(
                                                icon: const Icon(
                                                  Icons
                                                      .assignment_return_rounded,
                                                  size: 18,
                                                ),
                                                label: const Text('Return'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      StockpileColors.success,
                                                  side: BorderSide(
                                                    color: StockpileColors
                                                        .success
                                                        .withAlpha(80),
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 8,
                                                      ),
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
                                                  backgroundColor:
                                                      Colors.purple,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 8,
                                                      ),
                                                ),
                                                onPressed: () => _remitItem(b),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
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

  String _formatDateShort(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
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
    final borderColor = isSelected
        ? color.withAlpha(120)
        : (isDark ? StockpileColors.darkDivider : StockpileColors.divider);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withAlpha(25)
                : (isDark
                      ? StockpileColors.darkSurface
                      : StockpileColors.surface),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withAlpha(30),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
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

class _SettledSubChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _SettledSubChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isSelected
        ? color.withAlpha(isDark ? 100 : 80)
        : (isDark ? StockpileColors.darkDivider : StockpileColors.divider);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withAlpha(isDark ? 30 : 20)
                : (isDark
                      ? StockpileColors.darkSurface
                      : StockpileColors.surface),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$count',
                style: StockpileFonts.satoshi(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isSelected
                      ? color
                      : (isDark
                            ? StockpileColors.darkTextBody
                            : StockpileColors.bodyText),
                ),
              ),
              const SizedBox(width: 5),
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
