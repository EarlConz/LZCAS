// lib/pages/admin/admin_dashboard.dart
// Admin Dashboard — full unrestricted access to ALL application features.
// The admin role passes every role assertion and can access every tab
// from every dashboard (admin, inventory, and cashier).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/inventorytable.dart' as inventory;
import 'package:lzcas/widgets/stockpile_topbar.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _pageTitles = [
    'Admin · Overview',
    'Admin · User Management',
    'Admin · Global Config',
    'Inventory · Stock',
    'Inventory · Reports',
    'Cashier · POS Terminal',
    'Cashier · Members',
    'Cashier · Deletion Requests',
    'Cashier · Borrow Stock',
  ];

  List<Widget> _buildPages() => const [
    // Admin section (3 pages)
    _AdminOverviewTab(),
    _UserManagementTab(),
    _GlobalConfigTab(),
    // Inventory section (2 pages)
    _AdminInventoryTab(),
    _AdminReportsTab(),
    // Cashier section (4 pages)
    _AdminTransactionTab(),
    _AdminMembersTab(),
    _AdminDeleteRequestTab(),
    _AdminBorrowStockTab(),
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
                // ── Temp Admin Warning Banner ──────────────────────────
                if (auth.isTempAdmin)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    color: StockpileColors.primary50,
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: StockpileColors.primary800,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Temporary Admin — Create a real admin from '
                            '"Users" to secure the system.',
                            style: StockpileFonts.satoshi(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: StockpileColors.primary800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // ── Top Bar (from UI Changes) ──────────────────────────
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

// ─── Overview Tab ───────────────────────────────────────────────────────────

class _AdminOverviewTab extends StatelessWidget {
  const _AdminOverviewTab();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Overview',
            style: StockpileFonts.satoshi(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.people_alt_rounded,
                  label: 'Total Users',
                  value: '—',
                  color: StockpileColors.secondary500,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.inventory_2_rounded,
                  label: 'Inventory Items',
                  value: '—',
                  color: StockpileColors.primary700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.receipt_long_rounded,
                  label: 'Total Sales',
                  value: '—',
                  color: StockpileColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.group_rounded,
                  label: 'Active Members',
                  value: '—',
                  color: StockpileColors.secondary300,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: StockpileColors.primary50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: StockpileColors.primary200.withAlpha(120),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  size: 32,
                  color: StockpileColors.primary700,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Full Administrative Control',
                        style: StockpileFonts.satoshi(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: StockpileColors.primary900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'You have all rights. Manage users, configurations, '
                        'and system settings from the tabs above.',
                        style: StockpileFonts.satoshi(
                          fontSize: 13,
                          color: StockpileColors.primary800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

      // Create the user locally (offline-first, no backend needed)
      final ok = await auth.createLocalUser(
        username: email,
        password: password,
        role: _selectedRole,
      );

      if (!ok) {
        setState(() => _createError = 'Username already exists.');
        return;
      }

      if (!mounted) return;
      _nameCtrl.clear();
      _emailCtrl.clear();
      _passwordCtrls[0].clear();

      // Deactivate the temp admin account now that a real user exists
      await auth.deactivateTempAdmin();

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

// ─── Global Config Tab ──────────────────────────────────────────────────────

class _GlobalConfigTab extends StatelessWidget {
  const _GlobalConfigTab();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Global Configuration',
            style: StockpileFonts.satoshi(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          const SizedBox(height: 16),

          _ConfigTile(
            icon: Icons.palette_outlined,
            title: 'Theme Settings',
            subtitle: 'Customize application appearance',
            trailing: Switch(value: !isDark, onChanged: (_) {}),
          ),
          _ConfigTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Configure system alerts and email notifications',
            trailing: Switch(value: true, onChanged: (_) {}),
          ),
          _ConfigTile(
            icon: Icons.backup_outlined,
            title: 'Cloud Sync',
            subtitle: 'Supabase synchronization settings',
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
    _NavItem(Icons.admin_panel_settings_rounded, 'Overview'),
    _NavItem(Icons.person_add_alt_rounded, 'Users'),
    _NavItem(Icons.settings_rounded, 'Config'),
    _NavItem(Icons.inventory_2_rounded, 'Inventory'),
    _NavItem(Icons.history_rounded, 'Reports'),
    _NavItem(Icons.point_of_sale_rounded, 'POS Terminal'),
    _NavItem(Icons.people_alt_rounded, 'Members'),
    _NavItem(Icons.person_remove_rounded, 'Del. Requests'),
    _NavItem(Icons.add_box_rounded, 'Borrow Requests'),
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
                // Settings
                _AdminSidebarTile(
                  item: _bottomItems[0],
                  isSelected: selectedIndex == _navItems.length,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () {
                    // Settings — not in nav items yet
                  },
                ),
                // Help & Support
                _AdminSidebarTile(
                  item: _bottomItems[1],
                  isSelected: selectedIndex == _navItems.length + 1,
                  activeBg: activeBg,
                  isDark: isDark,
                  onTap: () {
                    // Help — not in nav items yet
                  },
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: StockpileFonts.satoshi(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? StockpileColors.darkTextPrimary
                        : StockpileColors.darkText,
                  ),
                ),
                Text(
                  label,
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
    );
  }
}

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.assessment_rounded,
            size: 48,
            color: isDark
                ? StockpileColors.darkTextMuted
                : StockpileColors.mutedText,
          ),
          const SizedBox(height: 12),
          Text(
            'Inventory Reports',
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
            'Stock in/out logs and borrowing trends — full read access.',
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
}

// ─── Admin · Transaction (POS) Tab ──────────────────────────────────────────

class _AdminTransactionTab extends StatelessWidget {
  const _AdminTransactionTab();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.point_of_sale_rounded,
            size: 48,
            color: isDark
                ? StockpileColors.darkTextMuted
                : StockpileColors.mutedText,
          ),
          const SizedBox(height: 12),
          Text(
            'Point-of-Sale Terminal',
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
            'Admin has full access to process sales and manage transactions.',
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
}

// ─── Admin · Members Tab ────────────────────────────────────────────────────

class _AdminMembersTab extends StatelessWidget {
  const _AdminMembersTab();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_alt_rounded,
            size: 48,
            color: isDark
                ? StockpileColors.darkTextMuted
                : StockpileColors.mutedText,
          ),
          const SizedBox(height: 12),
          Text(
            'Member Directory',
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
            'Full read/write access to all member records.',
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
}

// ─── Admin · Delete Request Tab ─────────────────────────────────────────────

class _AdminDeleteRequestTab extends StatelessWidget {
  const _AdminDeleteRequestTab();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            'Pending Deletion Requests',
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
            'Review and approve/reject member deletion requests.',
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
}

// ─── Admin · Borrow Stock Tab ───────────────────────────────────────────────

class _AdminBorrowStockTab extends StatelessWidget {
  const _AdminBorrowStockTab();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_box_rounded,
            size: 48,
            color: StockpileColors.secondary500,
          ),
          const SizedBox(height: 12),
          Text(
            'Pending Borrow Requests',
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
            'Review and approve/reject stock borrowing requests.',
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
}

// ─── Nav Item Model ─────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem(this.icon, this.label);
}
