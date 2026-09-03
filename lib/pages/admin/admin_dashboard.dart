// lib/pages/admin/admin_dashboard.dart
// Admin Dashboard — full unrestricted access to ALL application features.
// The admin role passes every role assertion and can access every tab
// from every dashboard (admin, inventory, and cashier).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/action_guard.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/widgets/app_logo.dart';
import 'package:lzcas/widgets/inventorytable.dart' as inventory;
import 'package:lzcas/widgets/stockpile_topbar.dart';
import 'package:lzcas/widgets/transactionstable.dart';
import 'package:lzcas/widgets/memberstable.dart';
import 'package:lzcas/widgets/inventory_reports_view.dart';
import 'package:lzcas/pages/dashboardpage.dart';
import 'package:lzcas/pages/admin/branch_stock_page.dart';
import 'package:lzcas/pages/admin/announcements_page.dart';
import 'package:lzcas/pages/admin/cashier_locations_page.dart';
import 'package:lzcas/dialogs/edit_member_dialog.dart';
import 'package:lzcas/dialogs/adjust_funds_dialog.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/services/notification_service.dart';
import 'package:lzcas/services/config_service.dart';
import 'package:lzcas/services/updater_service.dart';
import 'package:lzcas/dialogs/update_dialog.dart';

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
    'Package',
    'Branch Stock',
    'Announcements',
    'Cashier Locations',
    'Settings',
  ];

  List<Widget> _buildPages() => const [
    // 0: Dashboard — recovered from original DashboardPage
    _AdminDashboardPage(),
    // 1: Users — user provisioning
    _UserManagementTab(),
    // 2: Inventory — full CRUD via InventoryTable
    _AdminInventoryTab(),
    // 3: Reports — In/Out read-only
    _AdminReportsTab(),
    // 4: POS Terminal — shared with Cashier via TransactionsTable
    _AdminPosTab(),
    // 5: Members — recovered full MembersTable
    _AdminMembersPage(),
    // 6: Deletion Requests
    _AdminDeleteRequestTab(),
    // 7: Package Management
    _AdminPackageTab(),
    // 8: Branch Stock — give/return/adjust + all-branches overview
    BranchStockPage(),
    // 9: Announcements — post notices + the automatic birthday greeting
    AdminAnnouncementsPage(),
    // 10: Cashier Locations — review/remove what members see on their map
    AdminCashierLocationsPage(),
    // 11: Settings — Global Config moved here
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
  void initState() {
    super.initState();
    _triggerUpdateCheck();
  }

  void _triggerUpdateCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final updater = context.read<UpdaterService>();
      updater.checkForUpdate(silent: true).then((info) {
        if (info != null && mounted) {
          UpdateDialog.showIfAvailable(context);
        }
      });
    });
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
    return const SingleChildScrollView(child: DashboardPage());
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

    // Pre-check: make sure the username isn't already taken by any user type.
    if (!await repository.isUsernameAvailable(username)) {
      showErrorToast('Username already taken');
      return;
    }

    final password = _passwordCtrls[0].text;
    final confirm = _confirmPasswordCtrl.text;

    if (password != confirm) {
      showErrorToast('Passwords do not match.');
      return;
    }
    // Supabase Auth requires email format — auto-generate from username
    final email = '$username@lzcas.local';

    setState(() {
      _creating = true;
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
        showErrorToast(
          auth.error.isNotEmpty ? auth.error : 'Failed to create user.',
        );
        return;
      }

      if (!mounted) return;
      _nameCtrl.clear();
      _passwordCtrls[0].clear();
      _confirmPasswordCtrl.clear();

      showSuccessToast('User created successfully.');
      _fetchUsers();
    } catch (e) {
      showErrorToast(e.toString());
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
        showErrorToast(
          auth.error.isNotEmpty ? auth.error : 'Failed to delete user.',
        );
      }
    } catch (e) {
      showErrorToast(e.toString());
    }
  }

  Future<void> _editUser(
    String userId,
    String username,
    String role,
    String email,
    bool mobileEnabled,
  ) async {
    final result = await showDialog<_EditUserResult>(
      context: context,
      builder: (ctx) => _EditUserDialog(
        userId: userId,
        username: username,
        role: role,
        email: email,
        mobileEnabled: mobileEnabled,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final auth = context.read<AuthState>();
      final newRole = result.role.isNotEmpty
          ? UserRole.fromString(result.role)
          : null;
      // Only branch-cashier accounts carry a mobile-access flag; for any other
      // role leave it untouched (null = don't write).
      final mobileFlag = result.role == UserRole.branchCashier.dbValue
          ? result.mobileEnabled
          : null;
      final ok = await auth.updateUser(
        userId: userId,
        password: result.password.isNotEmpty ? result.password : null,
        role: newRole,
        username: result.username.isNotEmpty ? result.username : null,
        email: result.email.isNotEmpty ? result.email : null,
        mobileEnabled: mobileFlag,
      );
      if (!mounted) return;
      if (ok) {
        setState(() => _successMessage = 'User updated.');
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _successMessage = null);
        });
        _fetchUsers();
      } else {
        showErrorToast(
          auth.error.isNotEmpty ? auth.error : 'Failed to update user.',
        );
      }
    } catch (e) {
      showErrorToast(e.toString());
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
        _editUser(userId, username, '', '', false);
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
                                // 160 fitted the old labels but clipped
                                // "Branch Cashier" by 35px.
                                width: 200,
                                child: DropdownButtonFormField<String?>(
                                  value: _userRoleFilter,
                                  // Lets the selected label ellipsize instead
                                  // of overflowing, so a longer role name
                                  // added later degrades rather than throws.
                                  isExpanded: true,
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
                                    // Matches profiles.role exactly —
                                    // UserRole.branchCashier persists as
                                    // snake_case, not the enum identifier.
                                    DropdownMenuItem(
                                      value: 'branch_cashier',
                                      child: Text('Branch Cashier'),
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
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return List.generate(users.length, (i) {
      final u = users[i];
      final role = u['role']?.toString() ?? '';
      final username = u['username']?.toString() ?? '';
      final email = u['email']?.toString() ?? '';
      final mobileEnabled = u['mobile_enabled'] == true;
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StockpileFonts.satoshi(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? StockpileColors.darkTextPrimary
                              : StockpileColors.darkText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Email + join date stacked so they never overflow on
                      // narrow screens — each line ellipsizes within the card.
                      if (email.isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              Icons.email_outlined,
                              size: 12,
                              color: isDark
                                  ? StockpileColors.darkTextMuted
                                  : StockpileColors.mutedText,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
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
                          ],
                        ),
                      if (createdAt.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 11,
                                color: isDark
                                    ? StockpileColors.darkTextMuted.withAlpha(
                                        150,
                                      )
                                    : StockpileColors.mutedText,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _formatDate(createdAt),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? StockpileColors.darkTextMuted
                                              .withAlpha(150)
                                        : StockpileColors.mutedText,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                    _roleLabel(role),
                    style: TextStyle(
                      color: _roleColor(role),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // Actions: a compact overflow menu on mobile (the three
                // inline buttons otherwise squeeze the username off-screen);
                // inline icon buttons on desktop.
                if (isMobile)
                  PopupMenuButton<String>(
                    tooltip: 'Actions',
                    icon: Icon(
                      Icons.more_vert,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                    onSelected: (v) {
                      final id = u['id']?.toString() ?? '';
                      switch (v) {
                        case 'password':
                          _viewUserPassword(id, username);
                          break;
                        case 'edit':
                          _editUser(id, username, role, email, mobileEnabled);
                          break;
                        case 'delete':
                          _deleteUser(id, username);
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'password',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.visibility_outlined),
                          title: Text('View Password'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline,
                            color: StockpileColors.danger,
                          ),
                          title: Text('Delete'),
                        ),
                      ),
                    ],
                  )
                else ...[
                  // ── View Password ───────────────────────────
                  ScaleTap(
                    child: IconButton(
                      tooltip: 'View password',
                      onPressed: () => _viewUserPassword(
                        u['id']?.toString() ?? '',
                        username,
                      ),
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
                        mobileEnabled,
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
      final d = dt.toLocal();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
      case 'branch_cashier':
        return Colors.teal.shade700;
      default:
        return Colors.grey;
    }
  }

  /// Friendly display label for a raw `profiles.role` value. Falls back to a
  /// simple capitalization for any unknown value.
  String _roleLabel(String role) {
    try {
      return UserRole.fromString(role).displayName;
    } catch (_) {
      return role.isNotEmpty ? role[0].toUpperCase() + role.substring(1) : '';
    }
  }
}

// ─── Edit User Result ──────────────────────────────────────────────────────

class _EditUserResult {
  final String password;
  final String role;
  final String username;
  final String email;
  final bool mobileEnabled;

  const _EditUserResult({
    required this.password,
    required this.role,
    required this.username,
    required this.email,
    required this.mobileEnabled,
  });
}

// ─── Edit User Dialog ──────────────────────────────────────────────────────

class _EditUserDialog extends StatefulWidget {
  final String userId;
  final String username;
  final String role;
  final String email;
  final bool mobileEnabled;

  const _EditUserDialog({
    required this.userId,
    required this.username,
    required this.role,
    required this.email,
    required this.mobileEnabled,
  });

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _emailCtrl;
  late String _role;
  late bool _mobileEnabled;
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
    _mobileEnabled = widget.mobileEnabled;
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
              // NOTE: item value is `dbValue` (the exact profiles.role string),
              // NOT `.name` — branch cashier persists as `branch_cashier`, so
              // using `.name` here ('branchCashier') would not match the loaded
              // value and crash the dropdown.
              DropdownButtonFormField<String>(
                value: _role,
                items: UserRole.values
                    .where(
                      (r) => r != UserRole.member && r != UserRole.reseller,
                    )
                    .map(
                      (r) => DropdownMenuItem(
                        value: r.dbValue,
                        child: Row(
                          children: [
                            _RoleDot(color: _colorForRole(r.dbValue)),
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

              // ── Mobile access (branch cashier only) ─────────────
              // Branch-cashier accounts are desktop-only unless an admin
              // enables mobile login here.
              if (_role == UserRole.branchCashier.dbValue) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? StockpileColors.darkDivider
                          : StockpileColors.divider,
                    ),
                  ),
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    secondary: Icon(
                      _mobileEnabled
                          ? Icons.smartphone_rounded
                          : Icons.phonelink_erase_rounded,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                      size: 20,
                    ),
                    title: Text(
                      'Allow mobile login',
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? StockpileColors.darkTextPrimary
                            : StockpileColors.darkText,
                      ),
                    ),
                    subtitle: Text(
                      _mobileEnabled
                          ? 'This account can log in on a phone or tablet.'
                          : 'Desktop only. Turn on to permit mobile login.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                    ),
                    value: _mobileEnabled,
                    onChanged: (v) => setState(() => _mobileEnabled = v),
                  ),
                ),
              ],

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
        mobileEnabled: _mobileEnabled,
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

// ─── Admin · Package Management Tab ───────────────────────────────────────

class _AdminPackageTab extends StatefulWidget {
  const _AdminPackageTab();

  @override
  State<_AdminPackageTab> createState() => _AdminPackageTabState();
}

class _AdminPackageTabState extends State<_AdminPackageTab> {
  List<Package> _packages = [];
  Map<int, int> _availerCounts = {};
  bool _loading = true;
  StreamSubscription<String>? _changeSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Availer counts change when members avail packages elsewhere;
    // refresh silently on package/member changes.
    _changeSub = repository.changes.listen((e) {
      const relevant = {
        'package_added',
        'package_updated',
        'package_deleted',
        'member_added',
        'member_updated',
        'members_changed',
      };
      if (relevant.contains(e)) _loadData();
    });
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Only block the view on first load; refreshes are silent.
    if (_packages.isEmpty) setState(() => _loading = true);
    try {
      final packages = await repository.fetchPackages();
      final counts = await repository.fetchPackageAvailerCounts();
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _availerCounts = counts;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminPackageTab] _loadData failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAvailersList(Package pkg) async {
    final members = await repository.fetchMembersByPackage(pkg.id!);
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${pkg.name} — Availers'),
        content: SizedBox(
          width: 400,
          child: members.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No availers yet.')),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: members.length,
                  itemBuilder: (_, i) {
                    final m = members[i];
                    final name = [
                      m.firstName,
                      m.lastName,
                    ].where((p) => p != null && p.isNotEmpty).join(' ');
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: StockpileColors.primary900,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(name.isNotEmpty ? name : 'Member #${m.id}'),
                      subtitle: Text(
                        m.role ?? 'Member',
                        style: TextStyle(
                          color: isDark
                              ? StockpileColors.darkTextMuted
                              : StockpileColors.mutedText,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Popup listing the hierarchy ranks already in use, opened from the info
  /// button on the Hierarchy Rank field so the helper text stays uncluttered.
  void _showRanksInUse(
    BuildContext ctx,
    List<Package> otherPackages,
    ThemeData theme,
    bool isDark,
  ) {
    showDialog<void>(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ranks in use'),
        content: SizedBox(
          width: 320,
          child: otherPackages.isEmpty
              ? const Text('No other packages have a rank yet.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in otherPackages)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withAlpha(
                                  isDark ? 40 : 24,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Rank ${p.hierarchyRank}',
                                style: StockpileFonts.satoshi(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showEditPackageDialog({Package? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null ? '${existing.price}' : '0',
    );
    final directCtrl = TextEditingController(
      text: existing != null ? '${existing.directReferralBonus}' : '0',
    );
    final indirectCtrl = TextEditingController(
      text: existing != null ? '${existing.indirectReferralBonus}' : '0',
    );
    final chairmansCtrl = TextEditingController(
      text: existing != null ? '${existing.chairmansBonus}' : '0',
    );
    final upgradeReferralCtrl = TextEditingController(
      text: existing != null ? '${existing.upgradeReferralBonus}' : '0',
    );
    // Suggest the next open rank for a new package (top of the ladder).
    // Rank 0 is reserved for "no package", so never default to it.
    final maxRank = _packages.isEmpty
        ? 0
        : _packages.map((p) => p.hierarchyRank).reduce((a, b) => a > b ? a : b);
    final hierarchyRankCtrl = TextEditingController(
      text: existing != null ? '${existing.hierarchyRank}' : '${maxRank + 10}',
    );
    // Ranks held by other packages — guarded against in the validator so the
    // upgrade ladder stays strictly ordered, and surfaced on demand via the
    // info button on the field (keeps the helper text uncluttered).
    final otherPackages = _packages.where((p) => p.id != existing?.id).toList()
      ..sort((a, b) => a.hierarchyRank.compareTo(b.hierarchyRank));
    final groupDirectCtrl = TextEditingController(
      text: existing != null ? '${existing.groupSalesDirect}' : '3',
    );
    final groupIndirectCtrl = TextEditingController(
      text: existing != null ? '${existing.groupSalesIndirect}' : '2',
    );
    final formKey = GlobalKey<FormState>();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenW = MediaQuery.of(context).size.width;
    final dialogW = screenW < 620 ? screenW - 48 : 560.0;
    final wide = dialogW >= 460;

    InputDecoration deco(String label, {String? helper, String? prefix}) =>
        InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          prefixText: prefix,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        );

    Widget numField(
      TextEditingController c,
      String label, {
      String? helper,
      String? prefix,
      String? Function(String?)? validator,
    }) => TextFormField(
      controller: c,
      decoration: deco(label, helper: helper, prefix: prefix),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: validator,
    );

    Widget twoCol(Widget a, Widget b) => wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          )
        : Column(children: [a, const SizedBox(height: 14), b]);

    Widget sectionHeader(IconData icon, String title, String subtitle) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(isDark ? 40 : 24),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? StockpileColors.darkTextPrimary
                            : StockpileColors.darkText,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: StockpileFonts.satoshi(
                        fontSize: 11.5,
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
        );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(isDark ? 40 : 24),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                existing != null ? Icons.edit_rounded : Icons.add_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(existing != null ? 'Edit Package' : 'Add Package'),
          ],
        ),
        content: SizedBox(
          width: dialogW,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Context note
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(
                        isDark ? 30 : 18,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'A member who avails this package becomes a '
                            'Verified Reseller and earns the bonuses below.',
                            style: StockpileFonts.satoshi(
                              fontSize: 12,
                              color: isDark
                                  ? StockpileColors.darkTextMuted
                                  : StockpileColors.mutedText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Package Details ──────────────────────────
                  sectionHeader(
                    Icons.inventory_2_rounded,
                    'Package Details',
                    'Name, price and tier ranking',
                  ),
                  TextFormField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: deco('Package Name'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  twoCol(
                    numField(
                      priceCtrl,
                      'Price',
                      prefix: '₱ ',
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n <= 0) {
                          return 'Enter a price above 0';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: hierarchyRankCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration:
                          deco(
                            'Hierarchy Rank',
                            helper: 'Higher = better tier. Must be unique.',
                          ).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                Icons.info_outline_rounded,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              tooltip: 'Ranks in use',
                              onPressed: () => _showRanksInUse(
                                ctx,
                                otherPackages,
                                theme,
                                isDark,
                              ),
                            ),
                          ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1) {
                          return 'Enter a rank of 1 or higher (0 is reserved)';
                        }
                        final clash = otherPackages
                            .where((p) => p.hierarchyRank == n)
                            .toList();
                        if (clash.isNotEmpty) {
                          return 'Rank $n already used by "${clash.first.name}"';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Referral Bonuses ─────────────────────────
                  sectionHeader(
                    Icons.groups_2_rounded,
                    'Referral Bonuses',
                    "Earned as this reseller's network grows",
                  ),
                  twoCol(
                    numField(
                      directCtrl,
                      'Direct Referral',
                      prefix: '₱ ',
                      helper: 'Per direct referral who activates',
                    ),
                    numField(
                      indirectCtrl,
                      'Indirect Referral',
                      prefix: '₱ ',
                      helper: 'Per level-2 (indirect) referral',
                    ),
                  ),
                  const SizedBox(height: 14),
                  numField(
                    upgradeReferralCtrl,
                    'Upgrade Referral Bonus',
                    prefix: '₱ ',
                    helper:
                        'Earned by the holder when a direct downline upgrades '
                        'from one package to a higher one',
                  ),
                  const SizedBox(height: 24),

                  // ── Recurring & Sales Bonuses ────────────────
                  sectionHeader(
                    Icons.savings_rounded,
                    'Recurring & Sales Bonuses',
                    'Weekly payouts and per-item product commissions',
                  ),
                  numField(
                    chairmansCtrl,
                    "Chairman's Bonus",
                    prefix: '₱ ',
                    helper: 'Paid to the holder for each direct referral',
                  ),
                  const SizedBox(height: 14),
                  twoCol(
                    numField(
                      groupDirectCtrl,
                      'Group Sales — Direct',
                      prefix: '₱ ',
                      helper: 'Per item a direct referral buys',
                    ),
                    numField(
                      groupIndirectCtrl,
                      'Group Sales — Indirect',
                      prefix: '₱ ',
                      helper: 'Per item an indirect referral buys',
                    ),
                  ),
                ],
              ), // Column
            ), // Form
          ), // SingleChildScrollView
        ), // SizedBox
        actions: [
          if (existing != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                // Members hold a live reference to their package (name,
                // price, chairman's bonus) — deleting an availed package
                // would silently break their earnings. Block it.
                final availers = _availerCounts[existing.id] ?? 0;
                if (availers > 0) {
                  final isDark = Theme.of(ctx).brightness == Brightness.dark;
                  await showDialog<void>(
                    context: ctx,
                    builder: (c) => AlertDialog(
                      insetPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 40,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      titlePadding: EdgeInsets.zero,
                      contentPadding: EdgeInsets.zero,
                      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      content: SizedBox(
                        width: 420,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Header ─────────────────────────────
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                20,
                                20,
                                16,
                              ),
                              decoration: BoxDecoration(
                                color: StockpileColors.danger.withAlpha(
                                  isDark ? 26 : 16,
                                ),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: StockpileColors.danger.withAlpha(
                                        isDark ? 46 : 28,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(
                                      Icons.gpp_bad_rounded,
                                      color: StockpileColors.danger,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Package Deletion Blocked',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: StockpileColors.danger,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          existing.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? StockpileColors
                                                      .darkTextPrimary
                                                : StockpileColors.darkText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ── Availer summary bar ────────────────
                            Container(
                              margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: StockpileColors.primary900.withAlpha(18),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: StockpileColors.primary900.withAlpha(
                                    60,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.people_alt_rounded,
                                    size: 20,
                                    color: StockpileColors.primary900,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '$availers member'
                                      '${availers == 1 ? '' : 's'} '
                                      'currently hold'
                                      '${availers == 1 ? 's' : ''} '
                                      'this package',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? StockpileColors.darkTextBody
                                            : StockpileColors.bodyText,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ── Explanation ────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                              child: Text(
                                "Their chairman's bonus, earnings history, "
                                'and package benefits are computed from this '
                                'package. Deleting it would silently break '
                                'them.\n\nReassign those members to another '
                                'package first, then delete.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: isDark
                                      ? StockpileColors.darkTextMuted
                                      : StockpileColors.bodyText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(c);
                            _showAvailersList(existing);
                          },
                          child: const Text('View Availers'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Got It'),
                        ),
                      ],
                    ),
                  );
                  return;
                }
                final confirmed = await showDialog<bool>(
                  context: ctx,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete Package'),
                    content: Text(
                      'Delete "${existing.name}"? This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    await repository.deletePackage(existing.id!);
                    BotToast.showText(text: '"${existing.name}" deleted');
                  } catch (e) {
                    BotToast.showText(text: 'Failed to delete package: $e');
                    return;
                  }
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _loadData();
                }
              },
              child: const Text('Delete'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => ActionGuard.run('save_package', () async {
              if (!formKey.currentState!.validate()) return;
              try {
                if (existing != null) {
                  final updated = existing.copyWith(
                    name: nameCtrl.text.trim(),
                    price: int.tryParse(priceCtrl.text) ?? 0,
                    directReferralBonus: int.tryParse(directCtrl.text) ?? 0,
                    indirectReferralBonus: int.tryParse(indirectCtrl.text) ?? 0,
                    chairmansBonus: int.tryParse(chairmansCtrl.text) ?? 0,
                    upgradeReferralBonus:
                        int.tryParse(upgradeReferralCtrl.text) ?? 0,
                    hierarchyRank: int.tryParse(hierarchyRankCtrl.text) ?? 0,
                    groupSalesDirect: int.tryParse(groupDirectCtrl.text) ?? 0,
                    groupSalesIndirect:
                        int.tryParse(groupIndirectCtrl.text) ?? 0,
                  );
                  await repository.updatePackage(updated);
                  BotToast.showText(text: '"${updated.name}" saved');
                } else {
                  await repository.addPackage(
                    name: nameCtrl.text.trim(),
                    price: int.tryParse(priceCtrl.text) ?? 0,
                    directReferralBonus: int.tryParse(directCtrl.text) ?? 0,
                    indirectReferralBonus: int.tryParse(indirectCtrl.text) ?? 0,
                    chairmansBonus: int.tryParse(chairmansCtrl.text) ?? 0,
                    upgradeReferralBonus:
                        int.tryParse(upgradeReferralCtrl.text) ?? 0,
                    hierarchyRank: int.tryParse(hierarchyRankCtrl.text) ?? 0,
                    groupSalesDirect: int.tryParse(groupDirectCtrl.text) ?? 0,
                    groupSalesIndirect:
                        int.tryParse(groupIndirectCtrl.text) ?? 0,
                  );
                  BotToast.showText(text: '"${nameCtrl.text.trim()}" created');
                }
              } catch (e) {
                BotToast.showText(text: 'Failed to save package: $e');
                return;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _loadData();
            }),
            child: Text(existing != null ? 'Save' : 'Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Package Management',
                      style: StockpileFonts.satoshi(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? StockpileColors.darkTextPrimary
                            : StockpileColors.darkText,
                      ),
                    ),
                    Text(
                      'Configure membership packages, bonuses, and view availers.',
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
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Package'),
                onPressed: () => _showEditPackageDialog(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Analytics Cards ────────────────────────
          if (_packages.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Icon(
                      Icons.card_giftcard_outlined,
                      size: 64,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No packages configured yet.',
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
            ),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _packages.map((pkg) {
              final count = _availerCounts[pkg.id] ?? 0;
              // Full-width cards on mobile (one per row, filling the row);
              // fixed 240px on wider screens so several fit per row.
              return SizedBox(
                width: MediaQuery.sizeOf(context).width < 600
                    ? double.infinity
                    : 240,
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isDark
                          ? StockpileColors.darkDivider
                          : StockpileColors.divider,
                    ),
                  ),
                  color: isDark
                      ? StockpileColors.darkSurface
                      : StockpileColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: StockpileColors.primary900.withAlpha(
                                  isDark ? 40 : 20,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.card_giftcard_rounded,
                                color: StockpileColors.primary900,
                                size: 22,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () =>
                                  _showEditPackageDialog(existing: pkg),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          pkg.name,
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
                          '₱${NumberFormat('#,##0').format(pkg.price)}',
                          style: StockpileFonts.satoshi(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: StockpileColors.primary900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Availer chip doubles as the "view availers"
                        // button — InkWell gives it real tap affordance.
                        Material(
                          color:
                              (count > 0
                                      ? StockpileColors.success
                                      : theme.colorScheme.onSurfaceVariant)
                                  .withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: count > 0
                                ? () => _showAvailersList(pkg)
                                : null,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.people_alt_rounded,
                                    size: 18,
                                    color: count > 0
                                        ? StockpileColors.success
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$count Availer${count == 1 ? '' : 's'}',
                                      style: StockpileFonts.satoshi(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: count > 0
                                            ? StockpileColors.success
                                            : theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  if (count > 0)
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: StockpileColors.success,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _BonusRow(
                          label: 'Direct Bonus',
                          value: '₱${pkg.directReferralBonus}',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 4),
                        _BonusRow(
                          label: 'Indirect Bonus',
                          value: '₱${pkg.indirectReferralBonus}',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 4),
                        _BonusRow(
                          label: "Chairman's Bonus",
                          value: '₱${pkg.chairmansBonus} / referral',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 8),
                        _GroupSalesRow(
                          icon: Icons.arrow_downward_rounded,
                          label: 'Group Sales Direct',
                          value: '${pkg.groupSalesDirect} / item',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 4),
                        _GroupSalesRow(
                          icon: Icons.keyboard_double_arrow_down_rounded,
                          label: 'Group Sales Indirect',
                          value: '${pkg.groupSalesIndirect} / item',
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _BonusRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _BonusRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: StockpileFonts.satoshi(
              fontSize: 12,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
        ),
        Text(
          value,
          style: StockpileFonts.satoshi(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark
                ? StockpileColors.darkTextPrimary
                : StockpileColors.darkText,
          ),
        ),
      ],
    );
  }
}

class _GroupSalesRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _GroupSalesRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: isDark
              ? StockpileColors.darkTextMuted
              : StockpileColors.mutedText,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: StockpileFonts.satoshi(
              fontSize: 12,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
        ),
        Text(
          value,
          style: StockpileFonts.satoshi(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: StockpileColors.primary900,
          ),
        ),
      ],
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
  late final TabController _tabController;
  // General config state
  bool _configLoading = true;
  final _currencyCtrl = TextEditingController();
  bool _notificationsOn = true;

  // Category state
  List<Category> _categories = [];
  bool _catLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadConfig();
    _loadCategories();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _currencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await repository.fetchAppConfig();
    if (!mounted) return;
    setState(() {
      _currencyCtrl.text = config['currency_symbol'] ?? '₱';
      _notificationsOn = config['notifications_enabled'] != 'false';
      _configLoading = false;
    });
  }

  Future<void> _saveConfig() async {
    await repository.updateAppConfig('currency_symbol', _currencyCtrl.text);
    await repository.updateAppConfig(
      'notifications_enabled',
      _notificationsOn ? 'true' : 'false',
    );
    if (!mounted) return;
    context.read<ConfigService>().refresh();
    BotToast.showText(text: 'Settings saved');
  }

  Future<void> _loadCategories() async {
    final cats = await repository.fetchProductCategories();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _catLoading = false;
    });
  }

  void _showCategoryDialog({Category? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final thresholdCtrl = TextEditingController(
      text: existing?.lowStockThreshold?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing != null ? 'Edit Category' : 'Add Category'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: thresholdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Low Stock Threshold',
                    helperText: 'Stock below this is flagged Low Stock',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) {
                      return 'Enter a threshold greater than 0';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () async {
                  final deleted = await repository.deleteCategory(existing.id!);
                  if (!ctx.mounted) return;
                  if (deleted) {
                    Navigator.pop(ctx);
                    _loadCategories();
                  } else {
                    _showCategoryInUseDialog(ctx);
                  }
                },
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final threshold = int.tryParse(thresholdCtrl.text.trim());
                if (existing != null) {
                  await repository.updateCategory(
                    existing.copyWith(
                      name: nameCtrl.text.trim(),
                      lowStockThreshold: threshold,
                    ),
                  );
                } else {
                  await repository.addCategory(
                    name: nameCtrl.text.trim(),
                    lowStockThreshold: threshold,
                  );
                }
                if (!ctx.mounted) return;
                // Refresh cached category thresholds so status recomputes.
                context.read<ConfigService>().refresh();
                Navigator.pop(ctx);
                _loadCategories();
              },
              child: Text(existing != null ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoryInUseDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: StockpileColors.primary900.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.info_outline_rounded,
                size: 28,
                color: StockpileColors.primary900,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Category In Use',
              style: StockpileFonts.satoshi(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This category cannot be deleted because items in your '
              'inventory are still assigned to it. Please reassign or '
              'delete those items before removing this category.',
              textAlign: TextAlign.center,
              style: StockpileFonts.satoshi(
                fontSize: 14,
                color: StockpileColors.mutedText,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0037FD),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              onPressed: () => Navigator.pop(dCtx),
              child: Text(
                'Got It',
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      ),
    );
  }

  Widget _buildCategoryTab(bool isDark) {
    if (_catLoading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                'Categories',
                style: StockpileFonts.satoshi(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                ),
              );
              final addBtn = FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Category'),
                onPressed: () => _showCategoryDialog(),
              );
              // Narrow: stack the button under the title (full-width);
              // wide: title left, button right on one row.
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 12), addBtn],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  addBtn,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (_categories.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No categories yet',
                  style: StockpileFonts.satoshi(
                    color: isDark
                        ? StockpileColors.darkTextMuted
                        : StockpileColors.mutedText,
                  ),
                ),
              ),
            )
          else
            ..._categories.map(
              (c) => _ConfigTile(
                icon: Icons.category_rounded,
                title: c.name,
                subtitle: 'Low stock below ${c.lowStockThreshold ?? '—'}',
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _showCategoryDialog(existing: c),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
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
              indicator: BoxDecoration(
                color: isDark ? StockpileColors.darkSurface : Colors.white,
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
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(child: Text('General')),
                Tab(child: Text('Category')),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildGeneralTab(isDark), _buildCategoryTab(isDark)],
          ),
        ),
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
          const SizedBox(height: 32),

          // ── Updates ───────────────────────────────────
          Text(
            'Updates',
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
            'Check for and install the latest version of GUTVita.',
            style: StockpileFonts.satoshi(
              fontSize: 13,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.system_update_rounded),
              label: const Text('Check for Updates'),
              onPressed: () async {
                final updater = context.read<UpdaterService>();
                final info = await updater.checkForUpdate(silent: false);
                if (info != null && mounted) {
                  await UpdateDialog.showIfAvailable(context);
                } else if (mounted && updater.errorMessage != null) {
                  BotToast.showText(text: updater.errorMessage!);
                } else if (mounted) {
                  BotToast.showText(text: 'You are on the latest version.');
                }
              },
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
    _NavItem(Icons.card_giftcard_rounded, 'Package'),
    _NavItem(Icons.local_shipping_rounded, 'Branch Stock'),
    _NavItem(Icons.campaign_rounded, 'Announcements'),
    _NavItem(Icons.pin_drop_rounded, 'Cashier Locations'),
  ];

  /// How the flat `_navItems` list is presented: Dashboard on its own, then
  /// three groups that follow what an admin is actually doing — running the
  /// shop, looking after members, and administering staff.
  ///
  /// Indices, not items — see [_NavGroup].
  static const _navGroups = <_NavGroup>[
    _NavGroup(null, [0]), // Dashboard
    _NavGroup('Selling & Stock', [4, 2, 8, 3]),
    _NavGroup('Members', [5, 7, 6, 9]),
    _NavGroup('Staff', [1, 10]),
  ];

  static const _bottomItems = <_NavItem>[
    _NavItem(Icons.settings_rounded, 'Settings'),
  ];

  /// A group heading. The collapsed sidebar has no room for the words, so it
  /// keeps the grouping as a rule instead — the separation survives, which is
  /// the part that was doing the work.
  static Widget _navSectionHeader(String text, bool wide, bool isDark) {
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    if (!wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Divider(height: 1, color: divider),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 12, 8),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: StockpileFonts.satoshi(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark
              ? StockpileColors.darkTextMuted
              : StockpileColors.mutedText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final activeBg = isDark
        ? StockpileColors.darkSidebarActive
        : StockpileColors.sidebarActive;

    // Fixed geometry shared by both states: an icon slot at
    // 8 (padding) + 4 = 12 from the left, 44 wide — icon center x = 34.
    // Text reveals to the right as the sidebar width animates, so nothing
    // slides or jumps between the compact and expanded forms.
    Widget buildContent(bool wide) => Column(
      children: [
        // ── Brand ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 28, 8, 24),
          child: Row(
            children: [
              const SizedBox(width: 4),
              const SizedBox(
                width: 44,
                child: Center(child: AppLogo(size: 32, radius: 8)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    'GUTVita · Admin',
                    maxLines: 1,
                    softWrap: false,
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
              ),
            ],
          ),
        ),

        // ── Navigation Items ─────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final group in _navGroups) ...[
                if (group.header != null)
                  _navSectionHeader(group.header!, wide, isDark),
                ...group.indices.map((i) {
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
              ],
              const SizedBox(height: 8),
              Divider(
                color: isDark
                    ? StockpileColors.darkDivider
                    : StockpileColors.divider,
                indent: 12,
                endIndent: 12,
              ),
              const SizedBox(height: 8),
              // Settings sits after every main item. Derived rather than
              // hardcoded so adding a nav item can't silently collide with
              // it — which is exactly what a literal 9 did.
              _AdminSidebarTile(
                item: _bottomItems[0],
                isSelected: selectedIndex == _navItems.length,
                activeBg: activeBg,
                isDark: isDark,
                onTap: () => onItemSelected(_navItems.length),
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
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? StockpileColors.darkInputBg
                    : StockpileColors.inputBg,
                borderRadius: BorderRadius.circular(14),
              ),
              // Avatar sits in the same fixed 44-wide slot as the nav
              // icons (center x = 34) in both compact and expanded forms.
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 44,
                    child: Center(
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
                  if (wide) ...[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              auth.username.isNotEmpty
                                  ? auth.username
                                  : 'Admin',
                              maxLines: 1,
                              softWrap: false,
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
                    const SizedBox(width: 6),
                  ],
                ],
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

    // Same layout in both states: fixed 44-wide icon slot on the left,
    // label revealed/clipped by the animating sidebar width. Keeps the
    // icon at the exact same x-position whether compact or expanded.
    final content = Row(
      children: [
        const SizedBox(width: 4),
        SizedBox(
          width: 44,
          child: Center(child: Icon(item.icon, size: 20, color: textColor)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: StockpileFonts.satoshi(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ),
      ],
    );

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
              ? content
              : Tooltip(message: item.label, child: content),
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

  void _showMemberDetail(
    BuildContext context,
    Map<String, dynamic> member,
  ) async {
    // Resolve package name client-side from the member's packageId.
    String packageName = '';
    try {
      final pkgIdRaw = member['packageId'];
      final pkgId = pkgIdRaw is int ? pkgIdRaw : int.tryParse('$pkgIdRaw');
      if (pkgId != null) {
        final packages = await repository.fetchPackages();
        final pkg = packages.where((p) => p.id == pkgId).firstOrNull;
        if (pkg != null) packageName = pkg.name;
      }
    } catch (_) {}

    if (!mounted) return;

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

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            // Recomputed on each rebuild so an in-place upgrade refreshes the
            // badges and package name live, without closing the modal.
            final fullName =
                [member['firstName'], member['middleName'], member['lastName']]
                    .where((p) => p != null && p.toString().trim().isNotEmpty)
                    .join(' ');
            final initials = fullName.isNotEmpty
                ? fullName[0].toUpperCase()
                : 'M';
            final isReseller =
                (member['role']?.toString() ?? '') == 'Verified Reseller';
            final email = (member['email']?.toString() ?? '').trim();
            final hasAccount = email.isNotEmpty;

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
                              packageName: packageName,
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
                            _ReferralModalCard(
                              member: member,
                              isDark: isDark,
                              textColor: textColor,
                              muted: muted,
                              surface: surface,
                              divider: divider,
                            ),
                            const SizedBox(height: 12),

                            // ── Action buttons ─────────────────
                            const SizedBox(height: 20),

                            // Create account button (only if no account)
                            if (!hasAccount)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
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
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _viewMemberPassword(
                                      ctx,
                                      member,
                                      fullName,
                                    ),
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
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
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
                            // ── Upgrade Package ─────────────────────────────
                            // Always available to staff: for a plain Member it
                            // assigns their first package (promoting them to
                            // Verified Reseller); for a reseller it raises their
                            // tier. Account-less members are caught by the guard in
                            // _showUpgradePackageDialog (prompts to create one).
                            ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () => _showUpgradePackageDialog(
                                    ctx,
                                    member,
                                    onUpgraded: (pkg) {
                                      // Reflect the new package on the still-open
                                      // modal (the list refreshes via realtime).
                                      member['packageId'] = pkg.id;
                                      member['role'] = 'Verified Reseller';
                                      packageName = pkg.name;
                                      setModalState(() {});
                                    },
                                  ),
                                  icon: const Icon(Icons.upgrade, size: 18),
                                  label: const Text('Upgrade Package'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: StockpileColors.primary900,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            // ── Adjust Funds ────────────────────────────────
                            // Admin-only, and gated again server-side by
                            // is_admin() in admin_adjust_member_funds. Hidden
                            // rather than disabled for other roles: a cashier
                            // has no business seeing a control for moving
                            // money that was already earned.
                            if (context
                                    .read<AuthState>()
                                    .userRole
                                    ?.canAdjustFunds ??
                                false) ...[
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _openAdjustFundsDialog(
                                    ctx,
                                    member,
                                    fullName,
                                  ),
                                  icon: const Icon(
                                    Icons.account_balance_wallet_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Adjust Funds'),
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
                              const SizedBox(height: 12),
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: () =>
                                    _confirmDeleteMemberDialog(ctx, member),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                label: const Text('Delete Member'),
                                style: TextButton.styleFrom(
                                  foregroundColor: StockpileColors.danger,
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
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Correct one of a member's earnings buckets, with a reason.
  ///
  /// Closes the detail modal first: posting an adjustment changes the very
  /// figures behind it, and the modal has no way to reload them — leaving it
  /// open would show stale numbers over a completed change.
  Future<void> _openAdjustFundsDialog(
    BuildContext ctx,
    Map<String, dynamic> member,
    String fullName,
  ) async {
    final memberId = (member['id'] ?? 0) as int;
    if (memberId == 0) {
      showErrorToast('This member has no record to adjust.');
      return;
    }

    Navigator.pop(ctx);
    if (!mounted) return;

    await showAdjustFundsDialog(
      context,
      memberId: memberId,
      memberName: fullName.isEmpty ? 'Member #$memberId' : fullName,
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
                            final time = s.timestamp?.toLocal();
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

  Future<void> _showUpgradePackageDialog(
    BuildContext ctx,
    Map<String, dynamic> member, {
    void Function(Package pkg)? onUpgraded,
  }) async {
    final memberId = member['id'] as int?;
    if (memberId == null) return;

    // A package makes this member a Verified Reseller, and reseller records are
    // tied to a login account. Block availing one for an account-less member.
    final hasAccount = (member['email']?.toString() ?? '').trim().isNotEmpty;
    if (!hasAccount) {
      BotToast.showText(
        text:
            'This member needs a login account before availing a package. '
            'Create one from their details first.',
      );
      return;
    }

    // Get current package rank
    final rawPkgId = member['packageId'];
    final currentPkgId = rawPkgId is int ? rawPkgId : int.tryParse('$rawPkgId');
    int currentRank = 0;
    if (currentPkgId != null) {
      final currentPkg = await repository.getPackageById(currentPkgId);
      currentRank = currentPkg?.hierarchyRank ?? 0;
    }

    final selected = await showModalBottomSheet<Package>(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => _PackageUpgradeSheet(
        currentRank: currentRank,
        currentPkgId: currentPkgId,
        memberName: member['firstName']?.toString() ?? 'Member',
      ),
    );

    if (selected == null || !mounted) return;

    // Guard against a double-click availing the package (and paying the
    // referrer bonus + writing the availment sale) twice.
    await ActionGuard.run('avail_upgrade_$memberId', () async {
      try {
        // RPC handles: rank validation, member update, AND referrer bonus
        await repository.submitUpgrade(
          memberId: memberId,
          targetPackageId: selected.id!,
        );
        // POS sale record (client-side)
        await repository.addSale(
          itemId: 0,
          itemName: 'Package Upgrade: ${selected.name}',
          quantity: 1,
          price: selected.price,
          buyerId: memberId,
          buyerName: [
            member['firstName'],
            member['lastName'],
          ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' '),
          packageId: selected.id,
          timestamp: DateTime.now(),
        );
        BotToast.showText(
          text:
              '${member['firstName'] ?? 'Member'} upgraded to ${selected.name}',
        );
        onUpgraded?.call(selected);
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('Invalid upgrade') || msg.contains('downgrade')) {
          BotToast.showText(text: 'Cannot downgrade or side-grade packages.');
        } else {
          BotToast.showText(text: 'Failed: $e');
        }
      }
    });
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
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscured ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscured = !obscured),
                    ),
                  ),
                  obscureText: obscured,
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
                    Navigator.pop(c); // close create dialog
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
      ), // StatefulBuilder
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

// ─── Package Upgrade Bottom Sheet ──────────────────────────────────────────

class _PackageUpgradeSheet extends StatelessWidget {
  final int currentRank;
  final int? currentPkgId;
  final String memberName;

  const _PackageUpgradeSheet({
    required this.currentRank,
    required this.currentPkgId,
    required this.memberName,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Upgrade Package',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Available upgrades for $memberName',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: FutureBuilder<List<Package>>(
                future: repository.fetchAvailableUpgrades(currentRank),
                builder: (_, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final upgrades = snap.data ?? [];
                  if (upgrades.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified,
                            size: 56,
                            color: const Color(0xFF0037FD).withAlpha(100),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'You are currently on the highest tier!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: upgrades.length,
                    itemBuilder: (_, i) {
                      final pkg = upgrades[i];
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white12
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0037FD).withAlpha(25),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Text(
                                    pkg.name.isNotEmpty
                                        ? pkg.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Color(0xFF0037FD),
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pkg.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '₱${pkg.price}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0037FD),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _UpgradeButton(
                                package: pkg,
                                memberName: memberName,
                              ),
                            ],
                          ),
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
    );
  }
}

class _UpgradeButton extends StatefulWidget {
  final Package package;
  final String memberName;
  const _UpgradeButton({required this.package, required this.memberName});
  @override
  State<_UpgradeButton> createState() => _UpgradeButtonState();
}

class _UpgradeButtonState extends State<_UpgradeButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _loading ? null : _onTap,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF0037FD),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text(
              'Upgrade',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
    );
  }

  Future<void> _onTap() async {
    setState(() => _loading = true);
    try {
      await Future.delayed(const Duration(milliseconds: 400)); // brief feedback
      if (!mounted) return;
      Navigator.pop(context, widget.package);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
    required this.packageName,
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
  final String packageName;
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
                    // Package badge (always visible beside account status)
                    _InfoBadge(
                      icon: Icons.inventory_2,
                      label: packageName.isNotEmpty
                          ? packageName
                          : 'Standard Account',
                      bgColor: packageName.isNotEmpty
                          ? StockpileColors.secondary400.withAlpha(26)
                          : textColor.withAlpha(12),
                      textColor: packageName.isNotEmpty
                          ? StockpileColors.secondary400
                          : muted,
                      iconColor: packageName.isNotEmpty
                          ? StockpileColors.secondary400
                          : muted,
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
  List<WithdrawalRequest> _withdrawalRequests = [];
  List<WithdrawalRequest> _withdrawalHistory = []; // approved/rejected
  Map<String, String> _profiles = {};
  Map<String, String> _roles = {};
  Map<int, String> _memberNames = {}; // memberId → "First Last"
  bool _showHistory = false;
  String _historyFilter = 'all'; // all, approved, rejected
  String _historyTypeFilter = 'all'; // all, delete, reduce, withdrawal
  bool _loading = true;
  bool _loadingMore = false;
  static const _pageSize = 25;
  int _pendingVisibleCount = _pageSize;
  int _pendingPage = 0;
  bool _pendingHasMore = true;
  int _historyVisibleCount = _pageSize;
  int _historyPage = 0;
  bool _historyHasMore = true;
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
      if (event == 'withdrawal_request_added' ||
          event == 'withdrawal_request_approved' ||
          event == 'withdrawal_request_rejected' ||
          event == 'withdrawal_requests_changed') {
        _loadWithdrawals();
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

      if (!mounted) return;
      setState(() {
        _pendingRequests = page.rows;
        _pendingPage = 1;
        _pendingHasMore = page.hasMore;
        _pendingVisibleCount = _pageSize;
        _profiles = profiles;
        _loading = false;
      });
      _loadProfiles();
      _loadWithdrawals();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadWithdrawals() async {
    try {
      final withdrawals = await repository.fetchPendingWithdrawals();

      // Load member names for display
      final memberIds = <int>{};
      for (final w in withdrawals) {
        memberIds.add(w.memberId);
      }
      final names = <int, String>{};
      for (final id in memberIds) {
        final m = await repository.getMemberById(id);
        if (m != null) {
          names[id] = '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim();
        }
      }

      if (!mounted) return;
      setState(() {
        _withdrawalRequests = withdrawals;
        _memberNames = names;
      });
    } catch (_) {}
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
      // Processed withdrawals live in a separate table — load them so the
      // admin's history includes the money-movement audit trail.
      final withdrawalHistory = await repository.fetchWithdrawalHistory();
      final profiles = await repository.fetchProfilesMap();
      if (!mounted) return;
      // Resolve member names for withdrawal cards.
      for (final w in withdrawalHistory) {
        if (!_memberNames.containsKey(w.memberId)) {
          final m = await repository.getMemberById(w.memberId);
          if (m != null) {
            _memberNames[w.memberId] =
                '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim();
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _historyRequests = page.rows;
        _withdrawalHistory = withdrawalHistory;
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

  Future<void> _approveWithdrawal(WithdrawalRequest req) async {
    if (req.id == null) return;

    // Guard against a double-click approving (and deducting) twice.
    await ActionGuard.run('approve_wd_${req.id}', () async {
      final err = await repository.approveWithdrawalRequest(req.id!);
      if (!mounted) return;
      if (err == null) {
        BotToast.showText(
          text:
              'Withdrawal (${req.sourceLabel} ₱${req.requestedAmount}) — approved',
        );
      } else {
        BotToast.showText(text: 'Failed to approve withdrawal: $err');
      }
      _loadWithdrawals();
    });
  }

  Future<void> _rejectWithdrawal(WithdrawalRequest req) async {
    if (req.id == null) return;

    // Show rejection reason dialog
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Withdrawal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Withdraw ₱${req.requestedAmount} from ${req.sourceLabel}',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Rejection reason',
                hintText: 'Explain why this withdrawal is being rejected',
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

    final ok = await repository.rejectWithdrawalRequest(
      req.id!,
      rejectionReason: reason,
    );
    if (!mounted) return;
    if (ok) {
      BotToast.showText(text: 'Withdrawal — rejected');
    } else {
      BotToast.showText(text: 'Failed to reject withdrawal');
    }
    _loadWithdrawals();
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
      if (_historyRequests.isEmpty && _withdrawalHistory.isEmpty) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  _ToggleChip(
                    label: 'Pending',
                    count: _pendingRequests.length + _withdrawalRequests.length,
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
                  count: _pendingRequests.length + _withdrawalRequests.length,
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
                    child: Builder(
                      builder: (context) {
                        final wh = _filteredWithdrawalHistory;
                        final ph = _filteredHistory
                            .take(_historyVisibleCount)
                            .toList();
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: wh.length + ph.length,
                          itemBuilder: (context, index) {
                            if (index < wh.length) {
                              return _buildWithdrawalCard(
                                wh[index],
                                isDark,
                                theme,
                                isHistory: true,
                              );
                            }
                            return _buildHistoryCard(
                              ph[index - wh.length],
                              isDark,
                              theme,
                            );
                          },
                        );
                      },
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
    if (_pendingRequests.isEmpty && _withdrawalRequests.isEmpty) {
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
                    'Deletion, stock reduction, and withdrawal requests '
                    'will appear here for your review and approval.',
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
                count: _pendingRequests.length + _withdrawalRequests.length,
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
        Expanded(child: _buildCombinedPendingList(isDark, theme)),
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

  /// Processed withdrawals for the history view. Withdrawals only match the
  /// 'all' or 'withdrawal' type filter (they aren't delete/stock requests).
  List<WithdrawalRequest> get _filteredWithdrawalHistory {
    if (_historyTypeFilter != 'all' && _historyTypeFilter != 'withdrawal') {
      return const [];
    }
    return _withdrawalHistory.where((w) {
      if (_historyFilter != 'all' && w.status != _historyFilter) return false;
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

    // "All" per dimension reflects the OTHER dimension's filter.
    //
    // Withdrawals live in a separate list but render in this same history
    // view, so they must feed the Status counts too — otherwise the chips
    // read 0 while approved/rejected withdrawal cards are on screen. They
    // participate only when the Action filter is 'all' or 'withdrawal'
    // (mirrors _filteredWithdrawalHistory).
    final withdrawalsInType =
        _historyTypeFilter == 'all' || _historyTypeFilter == 'withdrawal';
    int withdrawalStatusCount(String status) => withdrawalsInType
        ? _withdrawalHistory.where((w) => w.status == status).length
        : 0;

    final statusAllCount =
        typeFiltered.length +
        (withdrawalsInType ? _withdrawalHistory.length : 0);
    final withdrawalCount = _withdrawalHistory
        .where((w) => _historyFilter == 'all' || w.status == _historyFilter)
        .length;
    final actionAllCount = statusFiltered.length + withdrawalCount;
    final approvedCount =
        typeFiltered.where((r) => r.status == 'approved').length +
        withdrawalStatusCount('approved');
    final rejectedCount =
        typeFiltered.where((r) => r.status == 'rejected').length +
        withdrawalStatusCount('rejected');
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
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: 'Withdrawal',
                          count: withdrawalCount,
                          isSelected: _historyTypeFilter == 'withdrawal',
                          onTap: () =>
                              setState(() => _historyTypeFilter = 'withdrawal'),
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
    final diff = dt.difference(now); // positive = future, negative = past
    if (diff.inDays > 0) return 'in ${diff.inDays}d';
    if (diff.inDays == 0) return 'today';
    // Past — overdue
    final overdue = -diff.inDays;
    return '${overdue}d overdue';
  }

  Widget _buildCombinedPendingList(bool isDark, ThemeData theme) {
    // Show withdrawal requests first, then pending requests
    final pendingSlice = _pendingRequests.take(_pendingVisibleCount).toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount:
          _withdrawalRequests.length +
          pendingSlice.length +
          (_withdrawalRequests.isNotEmpty ? 1 : 0), // section header
      itemBuilder: (context, index) {
        // Withdrawal section header
        if (_withdrawalRequests.isNotEmpty && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 18,
                  color: StockpileColors.primary900,
                ),
                const SizedBox(width: 8),
                Text(
                  'Withdrawal Requests',
                  style: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? StockpileColors.darkTextPrimary
                        : StockpileColors.darkText,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: StockpileColors.primary900.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_withdrawalRequests.length}',
                    style: StockpileFonts.satoshi(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: StockpileColors.primary900,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Withdrawal cards
        final withdrawalOffset = _withdrawalRequests.isNotEmpty ? 1 : 0;
        if (index < _withdrawalRequests.length + withdrawalOffset) {
          final wIndex = index - withdrawalOffset;
          return _buildWithdrawalCard(
            _withdrawalRequests[wIndex],
            isDark,
            theme,
          );
        }

        // Pending request cards
        final reqIndex = index - _withdrawalRequests.length - withdrawalOffset;
        final req = pendingSlice[reqIndex];
        return _buildPendingRequestCard(req, isDark, theme);
      },
    );
  }

  Widget _buildPendingRequestCard(
    PendingRequest req,
    bool isDark,
    ThemeData theme,
  ) {
    final isMemberDelete = req.requestType == 'delete_member';
    final isDelete = req.requestType == 'delete';
    final icon = isMemberDelete
        ? Icons.person_remove_rounded
        : isDelete
        ? Icons.delete_forever_rounded
        : Icons.arrow_downward_rounded;

    if (isMemberDelete) {
      final submitter = _profiles[req.userId] ?? 'Unknown';
      final role = _roles[req.userId] ?? '';
      final submitterLabel = role.isNotEmpty ? '$submitter ($role)' : submitter;

      return _buildModernRequestCard(
        isDark: isDark,
        accentColor: Colors.purple.shade600,
        icon: icon,
        title: 'Delete Member Request',
        body: req.memberName ?? 'Unknown',
        reason: req.reason,
        submitter: submitterLabel,
        timeAgo: req.createdAt != null ? _formatDate(req.createdAt!) : '',
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

    final submitter = _profiles[req.userId] ?? 'Unknown';
    final role = _roles[req.userId] ?? '';
    final submitterLabel = role.isNotEmpty ? '$submitter ($role)' : submitter;

    if (isDelete) {
      return _buildModernRequestCard(
        isDark: isDark,
        accentColor: StockpileColors.error500,
        icon: icon,
        title: 'Delete Request',
        body: req.itemName ?? 'Unknown item',
        reason: req.reason,
        submitter: submitterLabel,
        timeAgo: req.createdAt != null ? _formatDate(req.createdAt!) : '',
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
        detail: req.quantity != null ? 'Reduce by ${req.quantity}' : null,
        reason: req.reason,
        submitter: submitterLabel,
        timeAgo: req.createdAt != null ? _formatDate(req.createdAt!) : '',
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
  }

  /// Read-only status pill for processed withdrawals in the history view.
  Widget _withdrawalStatusBadge(WithdrawalRequest req, bool isDark) {
    final approved = req.status == 'approved';
    final color = approved ? StockpileColors.success : StockpileColors.error500;
    final label = approved ? 'Approved' : 'Rejected';
    final icon = approved ? Icons.check_circle : Icons.cancel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 30 : 20),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWithdrawalCard(
    WithdrawalRequest req,
    bool isDark,
    ThemeData theme, {
    bool isHistory = false,
  }) {
    final memberName = _memberNames[req.memberId] ?? 'Member #${req.memberId}';
    final cs = context.read<ConfigService>().currencySymbol;

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
            // Left accent bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
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
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF6366F1,
                            ).withAlpha(isDark ? 30 : 20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 18,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Withdrawal Request',
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
                    Text(
                      '$cs${req.requestedAmount} from ${req.sourceLabel}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'By $memberName',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Divider(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      height: 1,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 13,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  req.createdAt != null
                                      ? _formatDateTimeShort(req.createdAt!)
                                      : '',
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
                        if (isHistory)
                          _withdrawalStatusBadge(req, isDark)
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Material(
                                  color: StockpileColors.success.withAlpha(
                                    isDark ? 25 : 15,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    onTap: () => _approveWithdrawal(req),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.check_circle_outline,
                                        size: 20,
                                        color: StockpileColors.success,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Material(
                                  color: StockpileColors.error500.withAlpha(
                                    isDark ? 25 : 15,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    onTap: () => _rejectWithdrawal(req),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.cancel_outlined,
                                        size: 20,
                                        color: StockpileColors.error500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (isHistory &&
                        req.status == 'rejected' &&
                        (req.rejectionReason ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Reason: ${req.rejectionReason}',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTimeShort(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '$h:${local.minute.toString().padLeft(2, '0')}$ampm';
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

// ─── Nav Item Model ─────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem(this.icon, this.label);
}

/// A titled run of sidebar tiles.
///
/// Holds INDICES into `_navItems` rather than the items themselves, so
/// grouping stays a purely presentational concern: `_buildPages()`,
/// `_pageTitles`, the Requests badge at index 6 and the Settings index
/// (`_navItems.length`) all keep working untouched. Reordering the flat list
/// instead would have silently repointed every one of them.
///
/// Every index in `_navItems` must appear in exactly one group — an omitted
/// index is a page with no way to reach it.
class _NavGroup {
  /// Null renders the tiles with no heading, for the standalone first entry.
  final String? header;
  final List<int> indices;

  const _NavGroup(this.header, this.indices);
}

// ── Referral card for admin member detail modal ──────────────────────────

class _ReferralModalCard extends StatefulWidget {
  const _ReferralModalCard({
    required this.member,
    required this.isDark,
    required this.textColor,
    required this.muted,
    required this.surface,
    required this.divider,
  });

  final Map<String, dynamic> member;
  final bool isDark;
  final Color textColor;
  final Color muted;
  final Color surface;
  final Color divider;

  @override
  State<_ReferralModalCard> createState() => _ReferralModalCardState();
}

class _ReferralModalCardState extends State<_ReferralModalCard> {
  int _referralCount = 0;
  List<Member> _directReferrals = [];
  List<Member> _indirectReferrals = [];
  String _referrerName = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _computeReferrals();
  }

  Future<void> _computeReferrals() async {
    final memberId = widget.member['id'] as int?;
    if (memberId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final memberName =
        '${widget.member['firstName'] ?? ''} ${widget.member['lastName'] ?? ''}'
            .trim()
            .toLowerCase();

    final all = await repository.fetchMembers();
    if (!mounted) return;

    // Resolve referrer name
    String referrerName = '';
    final referrerIdRaw = widget.member['referrerId'] as int?;
    if (referrerIdRaw != null) {
      final refMember = all.where((m) => m.id == referrerIdRaw).firstOrNull;
      if (refMember != null) {
        referrerName = [
          refMember.firstName,
          refMember.lastName,
        ].where((p) => p != null && p.isNotEmpty).join(' ');
      }
    }
    if (referrerName.isEmpty) {
      referrerName = (widget.member['referrer']?.toString() ?? '').trim();
    }

    // Direct referrals
    final direct = all.where((m) {
      if (m.referrerId == memberId) return true;
      if (memberName.isNotEmpty) {
        final ref = (m.referrer ?? '').trim().toLowerCase();
        if (ref.isNotEmpty && ref == memberName) return true;
      }
      return false;
    }).toList();

    // Indirect referrals
    final directIds = direct.map((d) => d.id).whereType<int>().toSet();
    final indirect = all.where((m) {
      if (m.referrerId != null && directIds.contains(m.referrerId)) return true;
      return false;
    }).toList();

    if (!mounted) return;
    setState(() {
      _referrerName = referrerName;
      _directReferrals = direct;
      _indirectReferrals = indirect;
      _referralCount = direct.length + indirect.length;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;

    return _ModalInfoCard(
      isDark: w.isDark,
      textColor: w.textColor,
      muted: w.muted,
      surface: w.surface,
      divider: w.divider,
      title: 'Referral',
      icon: Icons.group_outlined,
      children: [
        // Referral details — 2×2 grid when wide, single full-width column
        // on narrow (mobile). In the half-width grid cell the fixed-width
        // label leaves the value ~0px, so names wrap vertically; stacking
        // gives each item the full width.
        LayoutBuilder(
          builder: (context, constraints) {
            final referredBy = _ModalInfoRow(
              icon: Icons.person_add_outlined,
              label: 'Referred by',
              value: _loading
                  ? '...'
                  : (_referrerName.isEmpty ? 'None' : _referrerName),
              muted: w.muted,
              textColor: w.textColor,
              isDark: w.isDark,
              italic: _referrerName.isEmpty,
            );
            final directRef = _ModalReferralDropdown(
              label: 'Direct Referral',
              members: _directReferrals,
              emptyText: 'No direct referrals',
              isLoading: _loading,
            );
            final referralCountRow = _ModalInfoRow(
              icon: Icons.people_outline,
              label: 'Referral Count',
              value: _loading ? '...' : '$_referralCount',
              muted: w.muted,
              textColor: w.textColor,
              isDark: w.isDark,
              isLast: true,
            );
            final indirectRef = _ModalReferralDropdown(
              label: 'Indirect Referral',
              members: _indirectReferrals,
              emptyText: 'No indirect referrals',
              isLoading: _loading,
            );

            if (constraints.maxWidth < 380) {
              return Column(
                children: [
                  referredBy,
                  const SizedBox(height: 8),
                  referralCountRow,
                  const SizedBox(height: 8),
                  directRef,
                  const SizedBox(height: 8),
                  indirectRef,
                ],
              );
            }

            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: referredBy),
                    const SizedBox(width: 10),
                    Expanded(child: directRef),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: referralCountRow),
                    const SizedBox(width: 10),
                    Expanded(child: indirectRef),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Dropdown widget matching the modal's visual style.
class _ModalReferralDropdown extends StatelessWidget {
  const _ModalReferralDropdown({
    required this.label,
    required this.members,
    required this.emptyText,
    this.isLoading = false,
  });

  final String label;
  final List<Member> members;
  final String emptyText;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasItems = members.isNotEmpty && !isLoading;

    return PopupMenuButton<Member>(
      enabled: hasItems,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => members.map((m) {
        final name = [
          m.firstName,
          m.lastName,
        ].where((p) => p != null && p.isNotEmpty).join(' ');
        return PopupMenuItem<Member>(
          value: m,
          child: Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name.isNotEmpty ? name : 'Member #${m.id}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                isLoading
                    ? '...'
                    : hasItems
                    ? '${members.length} ▼'
                    : emptyText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: hasItems ? FontWeight.w600 : FontWeight.normal,
                  color: hasItems
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
