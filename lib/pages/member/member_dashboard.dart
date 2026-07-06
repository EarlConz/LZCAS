// lib/pages/member/member_dashboard.dart
// Member-facing dashboard for both basic members and verified resellers.
// Feature visibility is gated by the member's role field in the members table.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../auth/auth.dart';
import '../../db/db.dart';
import '../../router/route_guard.dart';
import '../../services/config_service.dart';
import '../../theme.dart';
import '../../utils/fonts.dart';
import '../../widgets/member_sidebar.dart';

class MemberDashboard extends StatefulWidget {
  const MemberDashboard({super.key});

  @override
  State<MemberDashboard> createState() => _MemberDashboardState();
}

class _MemberDashboardState extends State<MemberDashboard> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  bool _loading = true;
  Member? _member;
  String? _error;

  /// True when this member's role is 'Verified Reseller'.
  bool get _isReseller => _member?.role == 'Verified Reseller';

  @override
  void initState() {
    super.initState();
    _loadMemberData();
  }

  Future<void> _loadMemberData() async {
    try {
      final auth = context.read<AuthState>();
      final member = await repository.fetchMemberByAuthUserId(auth.userId!);
      if (!mounted) return;
      setState(() {
        _member = member;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load your account. Please try again.';
        _loading = false;
      });
    }
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  Future<void> _handleLogout() async {
    final auth = context.read<AuthState>();
    await auth.logout();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  // ── Reseller-only tab indices (offset by shared tab count) ──────

  // For basic members: skip borrows, earnings, rankings
  int get _effectiveIndex {
    if (_isReseller) return _selectedIndex;
    // Map: Overview→0, Purchases→1, Profile→2
    if (_selectedIndex == 0) return 0;
    if (_selectedIndex == 1) return 1;
    return 4; // Profile
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null || _member == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error ?? 'Account not found.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadMemberData();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final sidebar = MemberSidebar(
      selectedIndex: _selectedIndex,
      isReseller: _isReseller,
      onItemSelected: _onItemTapped,
      onLogout: _handleLogout,
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: isDesktop ? null : sidebar,
      body: Row(
        children: [
          if (isDesktop) SizedBox(width: 260, child: sidebar),
          if (isDesktop) const VerticalDivider(width: 1),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(isDark, isDesktop),
                  Expanded(child: _buildPage(_effectiveIndex)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark, bool isDesktop) {
    final titles = _isReseller
        ? ['Overview', 'My Purchases', 'My Borrows', 'Earnings', 'Profile']
        : ['Overview', 'My Purchases', 'Profile'];
    final title = titles[_selectedIndex.clamp(0, titles.length - 1)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
          ),
        ),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            IconButton(
              icon: Icon(
                Icons.menu,
                color: isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          const SizedBox(width: 8),
          Text(
            title,
            style: StockpileFonts.satoshi(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          const Spacer(),
          Text(
            '${_member!.firstName ?? ''} ${_member!.lastName ?? ''}'
                    .trim()
                    .isEmpty
                ? 'Member'
                : '${_member!.firstName ?? ''} ${_member!.lastName ?? ''}'
                      .trim(),
            style: StockpileFonts.satoshi(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return _OverviewTab(member: _member!, isReseller: _isReseller);
      case 1:
        return _PurchasesTab(member: _member!);
      case 2:
        if (!_isReseller) return _PurchasesTab(member: _member!);
        return _BorrowsTab(member: _member!);
      case 3:
        return _EarningsTab(member: _member!);
      case 4:
        return _ProfileTab(member: _member!, onUpdated: _loadMemberData);
      default:
        return _OverviewTab(member: _member!, isReseller: _isReseller);
    }
  }
}

// ─── Overview Tab ──────────────────────────────────────────────────────────

class _OverviewTab extends StatefulWidget {
  final Member member;
  final bool isReseller;

  const _OverviewTab({required this.member, required this.isReseller});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  int _totalBoxes = 0;
  int _activeBorrows = 0;
  int _purchaseCount = 0;
  List<Sale> _recentSales = [];
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final id = widget.member.id!;
    final results = await Future.wait([
      repository.getTotalRemittedBoxes(id),
      repository.fetchBorrowsForMember(id),
      repository.fetchMemberPurchaseHistory(id, limit: 5),
    ]);
    if (!mounted) return;
    setState(() {
      _totalBoxes = results[0] as int;
      final borrows = results[1] as List<Borrow>;
      _activeBorrows = borrows
          .where((b) => b.status != 'returned' && b.status != 'remitted')
          .length;
      _recentSales = results[2] as List<Sale>;
      _purchaseCount = _recentSales.length;
      _loadingStats = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome hero card
          _OverviewHero(
            member: widget.member,
            isReseller: widget.isReseller,
            isDark: isDark,
          ),
          const SizedBox(height: 20),
          // Quick stats row
          if (_loadingStats)
            const Center(child: CircularProgressIndicator())
          else
            _buildStatsRow(isDark, isWide),
          const SizedBox(height: 20),
          // Recent activity
          _RecentActivityCard(
            sales: _recentSales,
            isDark: isDark,
            onTapViewAll: () {
              // Navigate to purchases tab — handled by parent
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(bool isDark, bool isWide) {
    if (isWide) {
      return Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.inventory_2_rounded,
              label: 'Boxes Remitted',
              value: '$_totalBoxes',
              color: StockpileColors.primary900,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              icon: Icons.swap_horiz_rounded,
              label: 'Active Borrows',
              value: '$_activeBorrows',
              color: _activeBorrows > 0
                  ? StockpileColors.danger
                  : StockpileColors.success,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              icon: Icons.receipt_long_rounded,
              label: 'Purchases',
              value: '$_purchaseCount',
              color: const Color(0xFF6366F1),
              isDark: isDark,
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.inventory_2_rounded,
                label: 'Boxes Remitted',
                value: '$_totalBoxes',
                color: StockpileColors.primary900,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.swap_horiz_rounded,
                label: 'Active Borrows',
                value: '$_activeBorrows',
                color: _activeBorrows > 0
                    ? StockpileColors.danger
                    : StockpileColors.success,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.receipt_long_rounded,
          label: 'Recent Purchases',
          value: '$_purchaseCount',
          color: const Color(0xFF6366F1),
          isDark: isDark,
        ),
      ],
    );
  }
}

class _OverviewHero extends StatelessWidget {
  final Member member;
  final bool isReseller;
  final bool isDark;

  const _OverviewHero({
    required this.member,
    required this.isReseller,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final name = '${member.firstName ?? ''} ${member.lastName ?? ''}'.trim();
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'M';

    return Card(
      elevation: 0,
      color: StockpileColors.primary900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: StockpileFonts.satoshi(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back,',
                    style: StockpileFonts.satoshi(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name.isNotEmpty ? name : 'Member',
                    style: StockpileFonts.satoshi(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (isReseller)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Verified Reseller',
                        style: StockpileFonts.satoshi(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    )
                  else
                    Text(
                      'Member Account',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        color: Colors.white60,
                      ),
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 14),
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
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  final List<Sale> sales;
  final bool isDark;
  final VoidCallback? onTapViewAll;

  const _RecentActivityCard({
    required this.sales,
    required this.isDark,
    this.onTapViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long_rounded,
                  size: 20,
                  color: StockpileColors.primary900,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recent Activity',
                  style: StockpileFonts.satoshi(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? StockpileColors.darkTextPrimary
                        : StockpileColors.darkText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (sales.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.inbox_rounded,
                        size: 40,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No purchases yet',
                        style: StockpileFonts.satoshi(
                          color: isDark
                              ? StockpileColors.darkTextMuted
                              : StockpileColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...sales
                  .take(5)
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: StockpileColors.primary900.withAlpha(
                            25,
                          ),
                          child: Icon(
                            Icons.shopping_bag_rounded,
                            size: 16,
                            color: StockpileColors.primary900,
                          ),
                        ),
                        title: Text(
                          s.itemName,
                          style: StockpileFonts.satoshi(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          s.timestamp != null ? _fmtDate(s.timestamp!) : '—',
                          style: StockpileFonts.satoshi(
                            fontSize: 11,
                            color: isDark
                                ? StockpileColors.darkTextMuted
                                : StockpileColors.mutedText,
                          ),
                        ),
                        trailing: Text(
                          '₱${s.price}',
                          style: StockpileFonts.satoshi(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ─── Purchases Tab ─────────────────────────────────────────────────────────

class _PurchasesTab extends StatefulWidget {
  final Member member;
  const _PurchasesTab({required this.member});

  @override
  State<_PurchasesTab> createState() => _PurchasesTabState();
}

class _PurchasesTabState extends State<_PurchasesTab> {
  List<Sale> _sales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sales = await repository.fetchMemberPurchaseHistory(
      widget.member.id!,
    );
    if (!mounted) return;
    setState(() {
      _sales = sales;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_sales.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_rounded,
              size: 48,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
            const SizedBox(height: 12),
            Text(
              'No purchase history',
              style: StockpileFonts.satoshi(
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
          ],
        ),
      );
    }

    final currencySymbol = context.watch<ConfigService>().currencySymbol;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _sales.length,
      itemBuilder: (context, i) {
        final s = _sales[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: StockpileColors.primary900.withAlpha(30),
              child: Icon(
                Icons.shopping_bag_rounded,
                color: StockpileColors.primary900,
                size: 20,
              ),
            ),
            title: Text(
              s.itemName,
              style: StockpileFonts.satoshi(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${s.timestamp != null ? _fmt(s.timestamp!) : '—'}  ·  ${s.quantity}×',
              style: StockpileFonts.satoshi(
                fontSize: 12,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
            trailing: Text(
              '$currencySymbol${s.price}',
              style: StockpileFonts.satoshi(fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ─── Borrows Tab (Reseller-only) ───────────────────────────────────────────

class _BorrowsTab extends StatefulWidget {
  final Member member;
  const _BorrowsTab({required this.member});

  @override
  State<_BorrowsTab> createState() => _BorrowsTabState();
}

class _BorrowsTabState extends State<_BorrowsTab> {
  List<Borrow> _borrows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final borrows = await repository.fetchBorrowsForMember(widget.member.id!);
    if (!mounted) return;
    setState(() {
      _borrows = borrows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_borrows.isEmpty) {
      return Center(
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
              'No borrows yet',
              style: StockpileFonts.satoshi(
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
          ],
        ),
      );
    }

    final active = _borrows
        .where((b) => b.status != 'returned' && b.status != 'remitted')
        .length;
    final overdue = _borrows.where((b) => b.isOverdue).length;
    final settled = _borrows
        .where((b) => b.status == 'returned' || b.status == 'remitted')
        .length;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _borrows.length + 1, // +1 for summary header
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Active',
                    value: '$active',
                    color: StockpileColors.primary900,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.warning_amber_rounded,
                    label: 'Overdue',
                    value: '$overdue',
                    color: overdue > 0
                        ? StockpileColors.danger
                        : StockpileColors.success,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.check_circle_rounded,
                    label: 'Settled',
                    value: '$settled',
                    color: StockpileColors.success,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          );
        }

        final b = _borrows[i - 1];
        final statusColor =
            b.status == 'active' || b.status == 'partially_settled'
            ? StockpileColors.primary900
            : b.isOverdue
            ? StockpileColors.danger
            : StockpileColors.success;

        return Card(
          elevation: 0,
          color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark
                  ? StockpileColors.darkDivider
                  : StockpileColors.divider,
            ),
          ),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        b.itemName,
                        style: StockpileFonts.satoshi(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? StockpileColors.darkTextPrimary
                              : StockpileColors.darkText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        b.statusLabel,
                        style: StockpileFonts.satoshi(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _borrowStat('Borrowed', '${b.quantity}'),
                    const SizedBox(width: 20),
                    _borrowStat('Returned', '${b.quantityReturned}'),
                    const SizedBox(width: 20),
                    _borrowStat('Remitted', '${b.quantityRemitted}'),
                    const SizedBox(width: 20),
                    _borrowStat('Outstanding', '${b.outstandingQuantity}'),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Due: ${b.dueDate.year}-${b.dueDate.month.toString().padLeft(2, '0')}-${b.dueDate.day.toString().padLeft(2, '0')}',
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                    ),
                    const Spacer(),
                    if (b.price > 0)
                      Text(
                        '₱${b.price}/item',
                        style: StockpileFonts.satoshi(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
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
    );
  }

  Widget _borrowStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: StockpileFonts.satoshi(
            fontSize: 10,
            color: StockpileColors.mutedText,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: StockpileFonts.satoshi(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ─── Earnings Tab (Reseller-only) ──────────────────────────────────────────

class _EarningsTab extends StatefulWidget {
  final Member member;
  const _EarningsTab({required this.member});

  @override
  State<_EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends State<_EarningsTab> {
  int _totalEarnings = 0;
  int _totalBoxes = 0;
  List<Sale> _recentRemits = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.member.id!;
    final results = await Future.wait([
      repository.fetchMemberEarnings(id),
      repository.getTotalRemittedBoxes(id),
      repository.fetchMemberPurchaseHistory(id, limit: 10),
    ]);
    if (!mounted) return;
    setState(() {
      _totalEarnings = results[0] as int;
      _totalBoxes = results[1] as int;
      _recentRemits = results[2] as List<Sale>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencySymbol = context.watch<ConfigService>().currencySymbol;
    final avgPerBox = _totalBoxes > 0
        ? (_totalEarnings / _totalBoxes).round()
        : 0;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // ── Hero earnings card ──────────────────────────
          Card(
            elevation: 0,
            color: isDark
                ? StockpileColors.darkSurface
                : StockpileColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: StockpileColors.primary900.withAlpha(25),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 32,
                      color: StockpileColors.primary900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Total Earnings',
                    style: StockpileFonts.satoshi(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currencySymbol$_totalEarnings',
                    style: StockpileFonts.satoshi(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? StockpileColors.darkTextPrimary
                          : StockpileColors.darkText,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'From $_totalBoxes remitted boxes',
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
          const SizedBox(height: 16),
          // ── Breakdown stats ─────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.inventory_2_rounded,
                  label: 'Boxes Remitted',
                  value: '$_totalBoxes',
                  color: StockpileColors.primary900,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.trending_up_rounded,
                  label: 'Avg per Box',
                  value: '$currencySymbol$avgPerBox',
                  color: const Color(0xFF6366F1),
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Recent remittances ──────────────────────────
          Card(
            elevation: 0,
            color: isDark
                ? StockpileColors.darkSurface
                : StockpileColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark
                    ? StockpileColors.darkDivider
                    : StockpileColors.divider,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 20,
                        color: StockpileColors.primary900,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Recent Remittances',
                        style: StockpileFonts.satoshi(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? StockpileColors.darkTextPrimary
                              : StockpileColors.darkText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_recentRemits.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.inbox_rounded,
                              size: 40,
                              color: isDark
                                  ? StockpileColors.darkTextMuted
                                  : StockpileColors.mutedText,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No remittances yet',
                              style: StockpileFonts.satoshi(
                                color: isDark
                                    ? StockpileColors.darkTextMuted
                                    : StockpileColors.mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._recentRemits
                        .take(8)
                        .map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: StockpileColors.primary900
                                    .withAlpha(25),
                                child: Icon(
                                  Icons.payments_rounded,
                                  size: 16,
                                  color: StockpileColors.primary900,
                                ),
                              ),
                              title: Text(
                                s.itemName,
                                style: StockpileFonts.satoshi(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                s.timestamp != null
                                    ? '${s.quantity}× — ${_fmtDate(s.timestamp!)}'
                                    : '${s.quantity}×',
                                style: StockpileFonts.satoshi(
                                  fontSize: 11,
                                  color: isDark
                                      ? StockpileColors.darkTextMuted
                                      : StockpileColors.mutedText,
                                ),
                              ),
                              trailing: Text(
                                '$currencySymbol${s.price}',
                                style: StockpileFonts.satoshi(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
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
    );
  }

  String _fmtDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ─── Profile Tab ───────────────────────────────────────────────────────────

class _ProfileTab extends StatefulWidget {
  final Member member;
  final VoidCallback onUpdated;

  const _ProfileTab({required this.member, required this.onUpdated});

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  late TextEditingController _firstNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _contactCtrl;
  late TextEditingController _addressCtrl;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(text: widget.member.firstName ?? '');
    _lastNameCtrl = TextEditingController(text: widget.member.lastName ?? '');
    _contactCtrl = TextEditingController(text: widget.member.contactNo ?? '');
    _addressCtrl = TextEditingController(text: widget.member.address ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _contactCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final updated = widget.member.copyWith(
      firstName: _firstNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
      contactNo: _contactCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
    );
    await repository.updateMember(updated);
    if (!mounted) return;
    BotToast.showText(text: 'Profile updated');
    widget.onUpdated();
  }

  String get _fullName {
    final parts = [
      widget.member.firstName,
      widget.member.lastName,
    ].where((p) => p != null && p.trim().isNotEmpty);
    return parts.isNotEmpty ? parts.join(' ') : 'Member';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final isReseller = widget.member.role == 'Verified Reseller';
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final mutedColor = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final surfaceColor = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              // ── Avatar header ─────────────────────────────────
              _buildAvatarHeader(isDark, isReseller, textColor, mutedColor),
              const SizedBox(height: 24),
              // ── Main content: two columns on desktop ──────────
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _buildPersonalInfoCard(
                            isDark,
                            textColor,
                            mutedColor,
                            surfaceColor,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          _buildSecurityCard(isDark, textColor, surfaceColor),
                          const SizedBox(height: 16),
                          _buildDangerZone(isDark, mutedColor),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _buildPersonalInfoCard(
                  isDark,
                  textColor,
                  mutedColor,
                  surfaceColor,
                ),
                const SizedBox(height: 16),
                _buildSecurityCard(isDark, textColor, surfaceColor),
                const SizedBox(height: 16),
                _buildDangerZone(isDark, mutedColor),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarHeader(
    bool isDark,
    bool isReseller,
    Color textColor,
    Color mutedColor,
  ) {
    final initials = _fullName.isNotEmpty && _fullName != 'Member'
        ? _fullName[0].toUpperCase()
        : 'M';

    return Card(
      elevation: 0,
      color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: StockpileColors.primary900.withAlpha(25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [StockpileColors.primary900, Color(0xFF3B1F7E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: StockpileColors.primary900.withAlpha(60),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: StockpileFonts.satoshi(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fullName,
                    style: StockpileFonts.satoshi(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (isReseller)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: StockpileColors.successBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified,
                                size: 14,
                                color: StockpileColors.success,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Verified Reseller',
                                style: StockpileFonts.satoshi(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: StockpileColors.success,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          'Member Account',
                          style: StockpileFonts.satoshi(
                            fontSize: 13,
                            color: mutedColor,
                          ),
                        ),
                      if (isReseller) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: StockpileColors.primary900.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Verified Reseller',
                            style: StockpileFonts.satoshi(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: StockpileColors.primary900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  if ((widget.member.email?.toString() ?? '').isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.email_outlined, size: 14, color: mutedColor),
                        const SizedBox(width: 6),
                        Text(
                          widget.member.email!,
                          style: StockpileFonts.satoshi(
                            fontSize: 13,
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalInfoCard(
    bool isDark,
    Color textColor,
    Color mutedColor,
    Color surfaceColor,
  ) {
    return Card(
      elevation: 0,
      color: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              Icons.person_outline_rounded,
              'Personal Info',
              textColor,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _firstNameCtrl,
              decoration: InputDecoration(
                labelText: 'First Name',
                prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastNameCtrl,
              decoration: InputDecoration(
                labelText: 'Last Name',
                prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactCtrl,
              decoration: InputDecoration(
                labelText: 'Contact Number',
                prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              decoration: InputDecoration(
                labelText: 'Address',
                prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save Changes'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCard(bool isDark, Color textColor, Color surfaceColor) {
    return Card(
      elevation: 0,
      color: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.lock_outline_rounded, 'Security', textColor),
            const SizedBox(height: 16),
            _ChangePasswordForm(memberId: widget.member.id!),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZone(bool isDark, Color mutedColor) {
    return Card(
      elevation: 0,
      color: StockpileColors.dangerBg.withAlpha(80),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: StockpileColors.danger.withAlpha(40)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.logout_rounded, size: 18, color: StockpileColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sign out of your account',
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: StockpileColors.danger,
                ),
              ),
            ),
            OutlinedButton(
              onPressed: () async {
                final auth = context.read<AuthState>();
                await auth.logout();
                if (!context.mounted) return;
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: StockpileColors.danger,
                side: const BorderSide(color: StockpileColors.danger),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title, Color textColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: StockpileColors.primary900.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: StockpileColors.primary900),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: StockpileFonts.satoshi(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

// ─── Change Password Form ──────────────────────────────────────────────────

class _ChangePasswordForm extends StatefulWidget {
  final int memberId;

  const _ChangePasswordForm({required this.memberId});

  @override
  State<_ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<_ChangePasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final supabase = Supabase.instance.client;
      final newPassword = _newPasswordCtrl.text;
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
      if (!mounted) return;

      // Sync the new password to profiles and members so admin can view it
      final userId = supabase.auth.currentUser!.id;
      await Future.wait([
        supabase
            .from('profiles')
            .update({'password': newPassword})
            .eq('id', userId),
        supabase
            .from('members')
            .update({'password': newPassword})
            .eq('id', widget.memberId),
      ]);

      BotToast.showText(text: 'Password changed successfully');
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      BotToast.showText(text: 'Failed to change password. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Change Password',
            style: StockpileFonts.satoshi(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _newPasswordCtrl,
            obscureText: true,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'New Password',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.length < 6) return 'At least 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmPasswordCtrl,
            obscureText: true,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Confirm Password',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outlined),
            ),
            validator: (v) {
              if (v != _newPasswordCtrl.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _saving ? null : _changePassword,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_reset_rounded),
              label: Text(_saving ? 'Changing...' : 'Change Password'),
            ),
          ),
        ],
      ),
    );
  }
}
