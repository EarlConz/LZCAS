// lib/pages/admin/admin_dashboard.dart
// Admin Dashboard — full administrative control, user provisioning, and
// global configuration management.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedTab = 0;

  static const _tabs = [
    _TabInfo(Icons.dashboard_rounded, 'Overview'),
    _TabInfo(Icons.person_add_alt_rounded, 'User Management'),
    _TabInfo(Icons.settings_rounded, 'Global Config'),
  ];

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
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin Panel',
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
                          'Welcome, ${auth.username} · All Rights',
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
            const Divider(height: 1),

            // ── Tab Bar ─────────────────────────────────────────────────
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: List.generate(_tabs.length, (i) {
                  final selected = _selectedTab == i;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _tabs[i].icon,
                            size: 18,
                            color: selected ? Colors.white : null,
                          ),
                          const SizedBox(width: 6),
                          Text(_tabs[i].label),
                        ],
                      ),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedTab = i),
                    ),
                  );
                }),
              ),
            ),
            const Divider(height: 1),

            // ── Tab Content ─────────────────────────────────────────────
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: const [
                  _AdminOverviewTab(),
                  _UserManagementTab(),
                  _GlobalConfigTab(),
                ],
              ),
            ),
          ],
        ),
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
      final api = context.read<AuthState>(); // Using AuthState for CSRF refresh
      await api.refreshCsrfToken();

      // In a real app, this calls the backend user provisioning endpoint.
      // final client = context.read<ApiClient>();
      // await client.post('/api/admin/users', data: { ... });

      // Simulate API call
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;
      _nameCtrl.clear();
      _emailCtrl.clear();
      _passwordCtrls[0].clear();

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

// ─── Shared Logout Button (uses confirmation) ───────────────────────────────

/// A logout icon button that shows a confirmation dialog before clearing the
/// session, posting to `/api/logout`, and redirecting to the login screen.
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

        // Perform the secure logout — POST /api/logout, clear storage, etc.
        await auth.logout();

        if (!context.mounted) return;

        // Wipe the entire navigation stack and land on the login screen.
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
      },
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

// ─── Tab Info Model ─────────────────────────────────────────────────────────

class _TabInfo {
  final IconData icon;
  final String label;

  const _TabInfo(this.icon, this.label);
}
