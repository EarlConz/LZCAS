// lib/pages/member/member_dashboard.dart
// Member-facing dashboard for both basic members and verified resellers.
// Feature visibility is gated by the member's role field in the members table.

import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
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
import '../../widgets/memberqr.dart';

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

  // For basic members: skip earnings and rankings
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
      // _error is set only on a fetch failure (network etc.) — Retry can
      // help there. A null member with no error means the account was
      // deleted/deactivated: retrying is pointless, offer the way out.
      final accountGone = _error == null;
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  accountGone
                      ? 'This account has been deactivated or no longer '
                            'exists. Please contact the administrator.'
                      : _error!,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              if (!accountGone) ...[
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
                const SizedBox(height: 8),
              ],
              TextButton(
                onPressed: _handleLogout,
                child: const Text('Back to Login'),
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
        ? ['Overview', 'My Purchases', 'Earnings', 'Profile']
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
        return _EarningsTab(member: _member!);
      case 3:
        return _ProfileTab(member: _member!, onUpdated: _loadMemberData);
      default:
        return _OverviewTab(member: _member!, isReseller: _isReseller);
    }
  }
}

// ─── My QR Card ────────────────────────────────────────────────────────────

/// Shows the member their own QR code so the terminal can scan it at checkout
/// to attribute the sale to their account. Tappable to enlarge for scanning.
class _MyQrCard extends StatelessWidget {
  final Member member;
  final bool isDark;

  const _MyQrCard({required this.member, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final qrToken = member.qr ?? '';
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;
    final textPrimary = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.qr_code_2_rounded,
                color: StockpileColors.primary900,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'My QR Code',
                style: StockpileFonts.satoshi(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Show this at checkout so the cashier can add your purchase to '
            'your account.',
            textAlign: TextAlign.center,
            style: StockpileFonts.satoshi(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 16),
          if (qrToken.isEmpty)
            Text(
              "Your QR code isn't set up yet. Please contact an admin.",
              textAlign: TextAlign.center,
              style: StockpileFonts.satoshi(fontSize: 13, color: muted),
            )
          else ...[
            InkWell(
              onTap: () => _showFullScreenQr(context),
              borderRadius: BorderRadius.circular(12),
              child: _qrBox(size: 180),
            ),
            const SizedBox(height: 10),
            Text(
              'Tap to enlarge',
              style: StockpileFonts.satoshi(fontSize: 11, color: muted),
            ),
          ],
        ],
      ),
    );
  }

  /// The QR always renders black-on-white (forced light theme + white
  /// background) so it stays scannable regardless of the app's dark mode.
  Widget _qrBox({required double size}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: ThemeData.light(),
        child: MemberQr(
          lastName: member.lastName ?? '',
          firstName: member.firstName ?? '',
          middleName: member.middleName ?? '',
          contactNo: member.contactNo ?? '',
          birthday: member.birthday ?? '',
          address: member.address ?? '',
          referrer: member.referrer ?? '',
          qrToken: member.qr ?? '',
          size: size,
        ),
      ),
    );
  }

  void _showFullScreenQr(BuildContext context) {
    final name = '${member.firstName ?? ''} ${member.lastName ?? ''}'.trim();
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _qrBox(size: 280),
              const SizedBox(height: 16),
              Text(
                name.isEmpty ? 'Member' : name,
                style: StockpileFonts.satoshi(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Show this to the cashier',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
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
  int _totalItemsBought = 0;
  int _purchaseCount = 0;
  List<Sale> _recentSales = [];
  List<Sale> _availedPackages = [];
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final id = widget.member.id!;
    final results = await Future.wait([
      repository.fetchMemberPurchaseHistory(id, limit: 5),
      repository.fetchSalesForMember(id),
      repository.fetchPackages(),
    ]);
    if (!mounted) return;
    setState(() {
      _recentSales = results[0] as List<Sale>;
      _purchaseCount = _recentSales.length;
      final allSales = results[1] as List<Sale>;
      _totalItemsBought = allSales
          .where((s) => !s.isPackage)
          .fold(0, (sum, s) => sum + s.quantity);
      // Availed packages display the CURRENT catalog name/price (renames
      // and price changes must reflect immediately); the sale row's
      // snapshot is only a fallback for packages deleted from the catalog.
      final pkgById = {
        for (final p in results[2] as List<Package>)
          if (p.id != null) p.id!: p,
      };
      _availedPackages =
          allSales.where((s) => s.isPackage).map((s) {
            final current = pkgById[s.packageId];
            return current == null
                ? s
                : s.copyWith(itemName: current.name, price: current.price);
          }).toList()..sort(
            (a, b) => (b.timestamp ?? DateTime(0)).compareTo(
              a.timestamp ?? DateTime(0),
            ),
          );
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
          // My QR — shown at checkout so the cashier can identify the buyer.
          _MyQrCard(member: widget.member, isDark: isDark),
          const SizedBox(height: 20),
          // Quick stats row
          if (_loadingStats)
            const Center(child: CircularProgressIndicator())
          else
            _buildStatsRow(isDark, isWide),
          const SizedBox(height: 20),
          // Availed package — resellers only
          if (widget.isReseller && !_loadingStats) ...[
            _PackageAvailedCard(packages: _availedPackages, isDark: isDark),
            const SizedBox(height: 20),
          ],
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
    final cards = [
      _StatCard(
        icon: Icons.inventory_2_rounded,
        label: 'Items Bought',
        value: '$_totalItemsBought',
        color: StockpileColors.primary900,
        isDark: isDark,
      ),
      _StatCard(
        icon: Icons.card_giftcard_rounded,
        label: 'Packages Availed',
        value: '${_availedPackages.length}',
        color: StockpileColors.secondary500,
        isDark: isDark,
      ),
      _StatCard(
        icon: Icons.receipt_long_rounded,
        label: 'Recent Purchases',
        value: '$_purchaseCount',
        color: const Color(0xFF6366F1),
        isDark: isDark,
      ),
    ];

    if (isWide) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
          ],
        ),
        const SizedBox(height: 12),
        cards[2],
      ],
    );
  }
}

/// "Membership card"-style banner showing the package(s) a reseller availed.
/// The most recent package is featured; earlier ones are listed below it.
class _PackageAvailedCard extends StatelessWidget {
  final List<Sale> packages;
  final bool isDark;

  const _PackageAvailedCard({required this.packages, required this.isDark});

  static String _fmtDate(DateTime dt) {
    // Convert the UTC timestamp to device-local time before formatting,
    // otherwise the date can read a day behind (PH is UTC+8).
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (packages.isEmpty) {
      // Reseller without a recorded availment — slim, quiet card.
      return Card(
        elevation: 0,
        color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
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
          child: Row(
            children: [
              Icon(
                Icons.card_giftcard_outlined,
                size: 20,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
              const SizedBox(width: 10),
              Text(
                'No package availed yet',
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
      );
    }

    final latest = packages.first;
    final earlier = packages.skip(1).toList();

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B1F7E), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withAlpha(isDark ? 40 : 70),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showPackageDetails(context, latest),
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Oversized watermark icon, clipped by the card
              Positioned(
                right: -18,
                top: -18,
                child: Icon(
                  Icons.card_giftcard_rounded,
                  size: 130,
                  color: Colors.white.withAlpha(22),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Eyebrow label
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(35),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        'MY PACKAGE',
                        style: StockpileFonts.satoshi(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(35),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.card_giftcard_rounded,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                latest.itemName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: StockpileFonts.satoshi(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                latest.timestamp != null
                                    ? 'Availed ${_fmtDate(latest.timestamp!)}'
                                    : 'Availed —',
                                style: StockpileFonts.satoshi(
                                  fontSize: 12,
                                  color: Colors.white.withAlpha(190),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '₱${latest.price}',
                          style: StockpileFonts.satoshi(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    if (earlier.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Divider(color: Colors.white.withAlpha(60), height: 1),
                      const SizedBox(height: 10),
                      ...earlier.map(
                        (s) => InkWell(
                          onTap: () => _showPackageDetails(context, s),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  size: 14,
                                  color: Colors.white.withAlpha(160),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s.timestamp != null
                                        ? '${s.itemName} · ${_fmtDate(s.timestamp!)}'
                                        : s.itemName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: StockpileFonts.satoshi(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withAlpha(220),
                                    ),
                                  ),
                                ),
                                Text(
                                  '₱${s.price}',
                                  style: StockpileFonts.satoshi(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withAlpha(220),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 13,
                          color: Colors.white.withAlpha(170),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Tap to view package contents & benefits',
                          style: StockpileFonts.satoshi(
                            fontSize: 11,
                            color: Colors.white.withAlpha(170),
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
      ),
    );
  }

  /// Open a dialog with the contents & benefits of the availed package.
  void _showPackageDetails(BuildContext context, Sale sale) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        backgroundColor: isDark
            ? StockpileColors.darkSurface
            : StockpileColors.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _PackageDetailsSheet(sale: sale, isDark: isDark),
        ),
      ),
    );
  }
}

/// Dialog body: fetches the package behind an availment and lists its
/// contents & benefits (mirrors the admin package manager's semantics).
class _PackageDetailsSheet extends StatelessWidget {
  final Sale sale;
  final bool isDark;

  const _PackageDetailsSheet({required this.sale, required this.isDark});

  static String _fmtDate(DateTime dt) {
    // Convert the UTC timestamp to device-local time before formatting,
    // otherwise the date can read a day behind (PH is UTC+8).
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final mutedColor = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return FutureBuilder<Package?>(
      future: sale.packageId != null
          ? repository.getPackageById(sale.packageId!)
          : Future.value(null),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          );
        }

        final pkg = snapshot.data;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Gradient header (matches the overview card) ─────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF3B1F7E), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.card_giftcard_rounded,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sale.itemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: StockpileFonts.satoshi(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sale.timestamp != null
                              ? 'Availed ${_fmtDate(sale.timestamp!)}'
                              : 'Availed —',
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            color: Colors.white.withAlpha(190),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '₱${sale.price}',
                    style: StockpileFonts.satoshi(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: pkg == null
                  ? Text(
                      'The details of this package are no longer available — '
                      'it may have been removed from the catalog.',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        color: mutedColor,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('BENEFITS', mutedColor),
                        const SizedBox(height: 10),
                        _benefitRow(
                          Icons.person_add_alt_rounded,
                          'Direct Referral Bonus',
                          '₱${pkg.directReferralBonus}',
                          textColor,
                          mutedColor,
                        ),
                        _benefitRow(
                          Icons.group_add_rounded,
                          'Indirect Referral Bonus',
                          '₱${pkg.indirectReferralBonus}',
                          textColor,
                          mutedColor,
                        ),
                        _benefitRow(
                          Icons.workspace_premium_rounded,
                          "Chairman's Bonus",
                          '₱${pkg.chairmansBonus}',
                          textColor,
                          mutedColor,
                        ),
                        _benefitRow(
                          Icons.groups_rounded,
                          'Passive Income (Direct)',
                          '₱5 / item purchased',
                          textColor,
                          mutedColor,
                        ),
                        _benefitRow(
                          Icons.groups_outlined,
                          'Passive Income (Indirect)',
                          '₱3 / item purchased',
                          textColor,
                          mutedColor,
                        ),
                        _benefitRow(
                          Icons.upgrade,
                          'Upgrade Referral Bonus',
                          '₱${pkg.upgradeReferralBonus}',
                          textColor,
                          mutedColor,
                        ),
                      ],
                    ),
            ),

            // ── Close ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionLabel(String text, Color mutedColor) => Text(
    text,
    style: StockpileFonts.satoshi(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: mutedColor,
    ),
  );

  Widget _benefitRow(
    IconData icon,
    String label,
    String value,
    Color textColor,
    Color mutedColor,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withAlpha(isDark ? 45 : 25),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF6366F1)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: StockpileFonts.satoshi(fontSize: 13, color: mutedColor),
          ),
        ),
        Text(
          value,
          style: StockpileFonts.satoshi(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ],
    ),
  );

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

  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
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
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: StockpileColors.primary900.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_rounded,
                size: 32,
                color: StockpileColors.primary900,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No purchase history',
              style: StockpileFonts.satoshi(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your purchases will appear here once you start buying.',
              textAlign: TextAlign.center,
              style: StockpileFonts.satoshi(
                fontSize: 13,
                color: StockpileColors.mutedText,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    final currencySymbol = context.watch<ConfigService>().currencySymbol;
    final now = DateTime.now();

    return RefreshIndicator(
      onRefresh: _load,
      color: StockpileColors.primary900,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _sales.length,
        itemBuilder: (context, i) {
          final s = _sales[i];
          const accent = StockpileColors.primary900;
          final iconBg = StockpileColors.primary900.withValues(alpha: 0.08);
          final age = s.timestamp != null
              ? _relativeTime(s.timestamp!, now)
              : '';

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? StockpileColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border(left: BorderSide(color: accent, width: 3)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.shopping_bag_rounded,
                        size: 20,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Name + meta
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s.itemName,
                                  style: StockpileFonts.satoshi(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? StockpileColors.darkTextPrimary
                                        : StockpileColors.darkText,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (age.isNotEmpty) ...[
                                Text(
                                  age,
                                  style: StockpileFonts.satoshi(
                                    fontSize: 12,
                                    color: StockpileColors.mutedText,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? StockpileColors.darkInputBg
                                      : const Color(0xFFF1F3F5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '×${s.quantity}',
                                  style: StockpileFonts.satoshi(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: StockpileColors.mutedText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Price
                    Text(
                      '$currencySymbol${s.price}',
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
              ),
            ),
          );
        },
      ),
    );
  }

  String _relativeTime(DateTime dt, DateTime now) {
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      if (dt.day == now.day) return 'Today';
      return '${diff.inHours}h ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
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
  int _balance = 0;
  int _totalPurchases = 0;
  int _chairmanBonus = 0;
  int _chairmanFridays = 0;
  List<EarningsSnapshot> _history = [];
  bool _loading = true;
  StreamSubscription<String>? _changeSub;

  @override
  void initState() {
    super.initState();
    _load();
    _changeSub = repository.changes.listen((event) {
      if (event == 'withdrawal_request_approved' ||
          event == 'withdrawal_request_rejected' ||
          event == 'withdrawal_requests_changed') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.member.id!;
    final results = await Future.wait<dynamic>([
      repository.fetchMemberEarningsBreakdown(id),
      repository.fetchSalesForMember(id),
    ]);
    final breakdown = results[0] as Map<String, int>;
    final totalEarnings = breakdown['totalEarnings'] ?? 0;
    final balance = breakdown['balance'] ?? 0;

    // Log a ledger entry when the computed values changed, then load
    // the history (including the entry just written, if any).
    await repository.recordEarningsSnapshot(
      memberId: id,
      totalEarnings: totalEarnings,
      balance: balance,
      indirectBonus: breakdown['indirectBonus'] ?? 0,
      groupSales: breakdown['groupSales'] ?? 0,
      passiveIncome: breakdown['passiveIncome'] ?? 0,
      repeatPurchase: breakdown['repeatPurchase'] ?? 0,
      chairmanBonus: breakdown['chairmanBonus'] ?? 0,
      upgradeBonus: breakdown['upgradeBonus'] ?? 0,
    );
    final history = await repository.fetchEarningsHistory(id);

    if (!mounted) return;
    setState(() {
      _totalEarnings = totalEarnings;
      _balance = balance;
      _totalPurchases = (results[1] as List<Sale>)
          .where((s) => !s.isPackage)
          .fold(0, (sum, s) => sum + s.quantity);
      _chairmanBonus = breakdown['chairmanBonus'] ?? 0;
      _chairmanFridays = breakdown['chairmanFridays'] ?? 0;
      _history = history;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencySymbol = context.watch<ConfigService>().currencySymbol;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final screenWidth = MediaQuery.of(context).size.width;
    // Breakpoints: < 500 mobile, 500-700 tablet, > 700 desktop
    final isMobile = screenWidth < 500;
    final isTablet = screenWidth >= 500 && screenWidth < 700;
    final hPad = isMobile ? 12.0 : 24.0;
    final gap = isMobile ? 8.0 : (isTablet ? 10.0 : 12.0);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
      child: Column(
        children: [
          // ── Top card row: Total Earnings | Balance ──────
          if (isMobile) ...[
            _EarningsHeroCard(
              icon: Icons.account_balance_wallet_rounded,
              label: 'Total Earnings',
              value: '$currencySymbol$_totalEarnings',
              isDark: isDark,
              isCompact: true,
            ),
            SizedBox(height: gap),
            _EarningsHeroCard(
              icon: Icons.savings_rounded,
              label: 'Balance',
              value: '$currencySymbol$_balance',
              isDark: isDark,
              accentColor: const Color(0xFF6366F1),
              isCompact: true,
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _EarningsHeroCard(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Total Earnings',
                    value: '$currencySymbol$_totalEarnings',
                    isDark: isDark,
                    isCompact: isTablet,
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: _EarningsHeroCard(
                    icon: Icons.savings_rounded,
                    label: 'Balance',
                    value: '$currencySymbol$_balance',
                    isDark: isDark,
                    accentColor: const Color(0xFF6366F1),
                    isCompact: isTablet,
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: isMobile ? 8 : 16),
          // ── Withdrawal request buttons ─────────────────
          _WithdrawalButtons(
            isDark: isDark,
            totalEarnings: _totalEarnings,
            balance: _balance,
            memberId: widget.member.id!,
            onWithdrew: _load,
          ),
          SizedBox(height: isMobile ? 8 : 16),
          // ── Stats row ────────────────────────────────────
          if (isMobile)
            _buildStatsMobile(isDark, currencySymbol)
          else if (isTablet)
            _buildStatsTablet(isDark, currencySymbol)
          else
            _buildStatsDesktop(isDark, currencySymbol),
          SizedBox(height: isMobile ? 8 : 16),
          // ── Breakdown explanation ────────────────────────
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
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How earnings are calculated',
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? StockpileColors.darkTextPrimary
                          : StockpileColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _BreakdownRow(
                    label: 'Balance',
                    detail:
                        'Flat one-time signup bonus (₱300/₱600) × number of direct referrals who activated a package',
                    isDark: isDark,
                    isCompact: isMobile,
                  ),
                  _BreakdownRow(
                    label: 'Total Earnings',
                    detail:
                        "Indirect referral bonuses + Passive Income (₱5 per item your direct referrals purchase, ₱3 per item from indirect) + Chairman's Bonus + Upgrade Referral Bonuses",
                    isDark: isDark,
                    isCompact: isMobile,
                  ),
                  _BreakdownRow(
                    label: "Chairman's Bonus",
                    detail:
                        '₱50 per Starter Pack and ₱100 per Ambassador Pack registration in your network — credited on the Friday after each registration, based on the package availed at sign-up',
                    isDark: isDark,
                    isCompact: isMobile,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Group Sales commissions accrue as products are purchased by you and your referral network.',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: isMobile ? 8 : 16),
          // ── Ledger: Earnings History ─────────────────────
          _EarningsLedgerCard(
            history: _history,
            isDark: isDark,
            currencySymbol: currencySymbol,
            isCompact: isMobile,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsDesktop(bool isDark, String currencySymbol) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.inventory_2_rounded,
            label: 'Items Purchased',
            value: '$_totalPurchases',
            color: StockpileColors.primary900,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.workspace_premium_rounded,
            label:
                "Chairman's Bonus"
                '${_chairmanFridays > 0 ? ' ($_chairmanFridays Friday${_chairmanFridays == 1 ? '' : 's'})' : ''}',
            value: '$currencySymbol$_chairmanBonus',
            color: StockpileColors.success,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.trending_up_rounded,
            label: 'Total (Earn + Balance)',
            value: '$currencySymbol${_totalEarnings + _balance}',
            color: const Color(0xFF6366F1),
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsTablet(bool isDark, String currencySymbol) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.inventory_2_rounded,
                label: 'Items Purchased',
                value: '$_totalPurchases',
                color: StockpileColors.primary900,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.workspace_premium_rounded,
                label:
                    "Chairman's Bonus"
                    '${_chairmanFridays > 0 ? ' ($_chairmanFridays Friday${_chairmanFridays == 1 ? '' : 's'})' : ''}',
                value: '$currencySymbol$_chairmanBonus',
                color: StockpileColors.success,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _StatCard(
          icon: Icons.trending_up_rounded,
          label: 'Total (Earn + Balance)',
          value: '$currencySymbol${_totalEarnings + _balance}',
          color: const Color(0xFF6366F1),
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildStatsMobile(bool isDark, String currencySymbol) {
    return Column(
      children: [
        _StatCard(
          icon: Icons.inventory_2_rounded,
          label: 'Items Purchased',
          value: '$_totalPurchases',
          color: StockpileColors.primary900,
          isDark: isDark,
        ),
        const SizedBox(height: 8),
        _StatCard(
          icon: Icons.workspace_premium_rounded,
          label:
              "Chairman's Bonus"
              '${_chairmanFridays > 0 ? ' ($_chairmanFridays Friday${_chairmanFridays == 1 ? '' : 's'})' : ''}',
          value: '$currencySymbol$_chairmanBonus',
          color: StockpileColors.success,
          isDark: isDark,
        ),
        const SizedBox(height: 8),
        _StatCard(
          icon: Icons.trending_up_rounded,
          label: 'Total (Earn + Balance)',
          value: '$currencySymbol${_totalEarnings + _balance}',
          color: const Color(0xFF6366F1),
          isDark: isDark,
        ),
      ],
    );
  }
}

/// Ledger-style log of a member's earnings/balance changes over time.
/// Each row is a snapshot recorded when the computed values changed.
class _EarningsLedgerCard extends StatelessWidget {
  final List<EarningsSnapshot> history;
  final bool isDark;
  final String currencySymbol;
  final bool isCompact;

  const _EarningsLedgerCard({
    required this.history,
    required this.isDark,
    required this.currencySymbol,
    this.isCompact = false,
  });

  static String _fmtDateTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '$h:${local.minute.toString().padLeft(2, '0')}$ampm';
  }

  /// "+₱50" green, "−₱20" red, null when zero (not shown).
  Widget? _deltaChip(int delta, String label) {
    if (delta == 0) return null;
    final up = delta > 0;
    final color = up ? StockpileColors.success : StockpileColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${up ? '+' : '−'}$currencySymbol${delta.abs()} $label',
        style: StockpileFonts.satoshi(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final mutedColor = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    final titleFontSize = isCompact ? 14.0 : 16.0;
    final cardPad = isCompact ? 12.0 : 20.0;

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
        padding: EdgeInsets.all(cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.history_rounded,
                  size: 20,
                  color: StockpileColors.primary900,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Earnings History',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StockpileFonts.satoshi(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Logged whenever your earnings or balance change.',
              style: StockpileFonts.satoshi(fontSize: 11, color: mutedColor),
            ),
            const SizedBox(height: 12),
            () {
              // Hide "ghost" rows (all-zero totals and deltas) — an
              // artifact of early snapshots recorded with nothing earned.
              final visible = history
                  .where(
                    (h) =>
                        h.totalEarnings != 0 ||
                        h.balance != 0 ||
                        h.earningsDelta != 0 ||
                        h.balanceDelta != 0,
                  )
                  .toList();

              if (visible.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No history yet — changes will appear here.',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        color: mutedColor,
                      ),
                    ),
                  ),
                );
              }

              final shown = visible.take(15).toList();
              return Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        color:
                            (isDark
                                    ? StockpileColors.darkDivider
                                    : StockpileColors.divider)
                                .withAlpha(120),
                      ),
                    _historyRow(
                      shown[i],
                      i + 1 < visible.length ? visible[i + 1] : null,
                      visible.length < 30,
                      textColor,
                      mutedColor,
                    ),
                  ],
                  if (visible.length > 15) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Showing the latest 15 entries',
                      style: StockpileFonts.satoshi(
                        fontSize: 11,
                        color: mutedColor,
                      ),
                    ),
                  ],
                ],
              );
            }(),
          ],
        ),
      ),
    );
  }

  /// One ledger entry: direction icon, source chips + date, running totals.
  Widget _historyRow(
    EarningsSnapshot h,
    EarningsSnapshot? prev,
    bool prevIsComplete,
    Color textColor,
    Color mutedColor,
  ) {
    final firstEver = prev == null && prevIsComplete;

    List<Widget> chips;
    final netDelta = h.earningsDelta + h.balanceDelta;
    if (netDelta < 0) {
      // A negative change can only come from an approved withdrawal —
      // earnings otherwise only ever increase. Label it explicitly as a
      // "Withdrawal" instead of attributing it to an earning source or
      // falling through to the generic "Adjustment" text.
      chips = <Widget>[?_deltaChip(netDelta, 'Withdrawal')];
    } else if (h.isLegacy || (prev?.isLegacy ?? false)) {
      // Rows from before component tracking — sources unknown.
      chips = <Widget>[
        ?_deltaChip(h.earningsDelta, 'earnings'),
        ?_deltaChip(h.balanceDelta, 'balance'),
      ];
    } else if (prev != null || firstEver) {
      chips = <Widget>[
        ?_deltaChip(h.balanceDelta, 'Direct Referral'),
        ?_deltaChip(
          h.indirectBonus - (prev?.indirectBonus ?? 0),
          'Indirect Referral',
        ),
        ?_deltaChip(
          h.passiveIncome - (prev?.passiveIncome ?? 0),
          'Passive Income',
        ),
        ?_deltaChip(
          h.chairmanBonus - (prev?.chairmanBonus ?? 0),
          "Chairman's Bonus",
        ),
        ?_deltaChip(
          h.upgradeBonus - (prev?.upgradeBonus ?? 0),
          'Upgrade Bonus',
        ),
      ];
    } else {
      chips = <Widget>[
        ?_deltaChip(h.earningsDelta, 'earnings'),
        ?_deltaChip(h.balanceDelta, 'balance'),
      ];
    }

    // Direction of the net change drives the leading icon.
    final net = h.earningsDelta + h.balanceDelta;
    final IconData dirIcon;
    final Color dirColor;
    if (net > 0) {
      dirIcon = Icons.trending_up_rounded;
      dirColor = StockpileColors.success;
    } else if (net < 0) {
      dirIcon = Icons.trending_down_rounded;
      dirColor = StockpileColors.danger;
    } else {
      dirIcon = Icons.swap_vert_rounded;
      dirColor = mutedColor;
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: isCompact ? 8 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isCompact ? 28 : 32,
            height: isCompact ? 28 : 32,
            decoration: BoxDecoration(
              color: dirColor.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(dirIcon, size: isCompact ? 15 : 17, color: dirColor),
          ),
          SizedBox(width: isCompact ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (chips.isNotEmpty)
                  Wrap(
                    spacing: isCompact ? 4 : 6,
                    runSpacing: 4,
                    children: chips,
                  )
                else
                  Text(
                    'Adjustment',
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      color: mutedColor,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  h.recordedAt != null ? _fmtDateTime(h.recordedAt!) : '—',
                  style: StockpileFonts.satoshi(
                    fontSize: isCompact ? 10 : 11,
                    color: mutedColor,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: isCompact ? 8 : 12),
          if (isCompact)
            // Compact: totals stacked with abbreviated labels
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currencySymbol${h.totalEarnings}',
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                Text(
                  'Earn',
                  style: StockpileFonts.satoshi(fontSize: 8, color: mutedColor),
                ),
                const SizedBox(height: 2),
                Text(
                  '$currencySymbol${h.balance}',
                  style: StockpileFonts.satoshi(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                Text(
                  'Bal',
                  style: StockpileFonts.satoshi(fontSize: 8, color: mutedColor),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currencySymbol${h.totalEarnings}',
                  style: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                Text(
                  'Total Earnings',
                  style: StockpileFonts.satoshi(fontSize: 9, color: mutedColor),
                ),
                const SizedBox(height: 3),
                Text(
                  '$currencySymbol${h.balance}',
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                Text(
                  'Balance',
                  style: StockpileFonts.satoshi(fontSize: 9, color: mutedColor),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EarningsHeroCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final bool isDark;
  final Color? accentColor;
  final bool isCompact;
  const _EarningsHeroCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.accentColor,
    this.isCompact = false,
  });
  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? StockpileColors.primary900;
    final iconSize = isCompact ? 38.0 : 56.0;
    final iconInner = isCompact ? 20.0 : 28.0;
    final vPad = isCompact ? 16.0 : 28.0;
    final hPad = isCompact ? 12.0 : 16.0;
    final valueFont = isCompact ? 22.0 : 28.0;
    return Card(
      elevation: 0,
      color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
        child: isCompact
            ? Row(
                children: [
                  Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: color.withAlpha(25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: iconInner, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: StockpileFonts.satoshi(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? StockpileColors.darkTextMuted
                                : StockpileColors.mutedText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          style: StockpileFonts.satoshi(
                            fontSize: valueFont,
                            fontWeight: FontWeight.w900,
                            color: isDark
                                ? StockpileColors.darkTextPrimary
                                : StockpileColors.darkText,
                            height: 1.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: color.withAlpha(25),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: iconInner, color: color),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: StockpileFonts.satoshi(
                      fontSize: valueFont,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? StockpileColors.darkTextPrimary
                          : StockpileColors.darkText,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label, detail;
  final bool isDark;
  final bool isCompact;
  const _BreakdownRow({
    required this.label,
    required this.detail,
    required this.isDark,
    this.isCompact = false,
  });
  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final textMuted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: StockpileFonts.satoshi(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: StockpileFonts.satoshi(fontSize: 11, color: textMuted),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: StockpileFonts.satoshi(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              detail,
              style: StockpileFonts.satoshi(fontSize: 11, color: textMuted),
            ),
          ),
        ],
      ),
    );
  }
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
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
                      if (isReseller)
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

// ─── Withdrawal Request Buttons (Earnings Tab) ───────────────────────────

class _WithdrawalButtons extends StatelessWidget {
  final bool isDark;
  final int totalEarnings;
  final int balance;
  final int memberId;
  final VoidCallback onWithdrew;

  const _WithdrawalButtons({
    required this.isDark,
    required this.totalEarnings,
    required this.balance,
    required this.memberId,
    required this.onWithdrew,
  });

  // Withdrawals are restricted to Fridays in release builds. In debug
  // builds the gate is bypassed so the withdrawal flow can be tested any
  // day — kDebugMode is compile-time false in release, so the shipped
  // APK/exe still enforces the Friday-only rule.
  bool get _isFriday => kDebugMode || DateTime.now().weekday == DateTime.friday;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // "Withdraw From Total Earnings" — only active on Fridays
        _WithdrawButton(
          label: 'Withdraw Request From Total Earnings',
          icon: Icons.account_balance_wallet_rounded,
          amount: totalEarnings,
          sourceBucket: 'total_earnings',
          isDark: isDark,
          memberId: memberId,
          enabled: _isFriday && totalEarnings > 0,
          lockedHint: _isFriday ? null : 'Available on Fridays only',
          onWithdrew: onWithdrew,
        ),
        const SizedBox(height: 10),
        // "Withdraw From Balance" — always available
        _WithdrawButton(
          label: 'Withdraw Request From Balance',
          icon: Icons.savings_rounded,
          amount: balance,
          sourceBucket: 'balance',
          isDark: isDark,
          memberId: memberId,
          enabled: balance > 0,
          lockedHint: balance <= 0 ? 'No balance available' : null,
          onWithdrew: onWithdrew,
        ),
        const SizedBox(height: 10),
        // "View Withdrawal History" — opens bottom sheet
        _ViewHistoryButton(isDark: isDark, memberId: memberId),
      ],
    );
  }
}

class _ViewHistoryButton extends StatelessWidget {
  final bool isDark;
  final int memberId;

  const _ViewHistoryButton({required this.isDark, required this.memberId});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showHistorySheet(context),
        icon: const Icon(Icons.history_rounded, size: 18),
        label: const Text('View Withdrawal History'),
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark
              ? StockpileColors.darkTextPrimary
              : StockpileColors.darkText,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
          ),
        ),
      ),
    );
  }

  void _showHistorySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) =>
          _WithdrawalHistorySheet(memberId: memberId, isDark: isDark),
    );
  }
}

class _WithdrawButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final int amount;
  final String sourceBucket;
  final bool isDark;
  final int memberId;
  final bool enabled;
  final String? lockedHint;
  final VoidCallback onWithdrew;

  const _WithdrawButton({
    required this.label,
    required this.icon,
    required this.amount,
    required this.sourceBucket,
    required this.isDark,
    required this.memberId,
    required this.enabled,
    this.lockedHint,
    required this.onWithdrew,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<ConfigService>().currencySymbol;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: enabled
            ? () => _showWithdrawalDialog(context, cs)
            : lockedHint != null
            ? () => BotToast.showText(text: lockedHint!)
            : null,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: enabled
              ? (isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText)
              : (isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(
            color: enabled
                ? StockpileColors.primary900.withAlpha(80)
                : (isDark
                      ? StockpileColors.darkDivider
                      : StockpileColors.divider),
          ),
        ),
      ),
    );
  }

  void _showWithdrawalDialog(BuildContext context, String cs) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _WithdrawalRequestDialog(
        sourceBucket: sourceBucket,
        sourceLabel: sourceBucket == 'total_earnings'
            ? 'Total Earnings'
            : 'Balance',
        maxAmount: amount,
        currencySymbol: cs,
        memberId: memberId,
        isDark: isDark,
        onWithdrew: onWithdrew,
      ),
    );
  }
}

// ─── Withdrawal Request Dialog ─────────────────────────────────────────────

class _WithdrawalRequestDialog extends StatefulWidget {
  final String sourceBucket;
  final String sourceLabel;
  final int maxAmount;
  final String currencySymbol;
  final int memberId;
  final bool isDark;
  final VoidCallback onWithdrew;

  const _WithdrawalRequestDialog({
    required this.sourceBucket,
    required this.sourceLabel,
    required this.maxAmount,
    required this.currencySymbol,
    required this.memberId,
    required this.isDark,
    required this.onWithdrew,
  });

  @override
  State<_WithdrawalRequestDialog> createState() =>
      _WithdrawalRequestDialogState();
}

class _WithdrawalRequestDialogState extends State<_WithdrawalRequestDialog> {
  final _amountCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      if (mounted) setState(() => _submitting = false);
      return;
    }

    try {
      final result = await repository.submitWithdrawalRequest(
        memberId: widget.memberId,
        sourceBucket: widget.sourceBucket,
        amount: amount,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (result != null) {
        BotToast.showText(
          text:
              'Withdrawal request submitted for '
              '${widget.currencySymbol}$amount',
        );
        widget.onWithdrew();
      } else {
        BotToast.showText(text: 'Failed to submit request. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      BotToast.showText(text: 'Error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final mutedColor = widget.isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            widget.sourceBucket == 'total_earnings'
                ? Icons.account_balance_wallet_rounded
                : Icons.savings_rounded,
            color: StockpileColors.primary900,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Withdraw from ${widget.sourceLabel}',
              style: StockpileFonts.satoshi(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available: ${widget.currencySymbol}${widget.maxAmount}',
              style: StockpileFonts.satoshi(fontSize: 13, color: mutedColor),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Amount to withdraw',
                prefixText: '${widget.currencySymbol} ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter an amount';
                }
                final n = int.tryParse(v.trim());
                if (n == null || n <= 0) {
                  return 'Enter a valid positive amount';
                }
                if (n > widget.maxAmount) {
                  return 'Amount exceeds available ${widget.sourceLabel} '
                      '(${widget.currencySymbol}${widget.maxAmount})';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit Request'),
        ),
      ],
    );
  }
}

// ─── Withdrawal History Bottom Sheet ────────────────────────────────────────

class _WithdrawalHistorySheet extends StatefulWidget {
  final int memberId;
  final bool isDark;

  const _WithdrawalHistorySheet({required this.memberId, required this.isDark});

  @override
  State<_WithdrawalHistorySheet> createState() =>
      _WithdrawalHistorySheetState();
}

class _WithdrawalHistorySheetState extends State<_WithdrawalHistorySheet> {
  List<WithdrawalRequest> _requests = [];
  bool _loading = true;
  String? _error;
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final requests = await repository.fetchWithdrawalsForMember(
        widget.memberId,
      );
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load history';
        _loading = false;
      });
    }
  }

  void _toggleExpanded(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  static String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '$h:${local.minute.toString().padLeft(2, '0')}$ampm';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return StockpileColors.success;
      case 'rejected':
        return StockpileColors.danger;
      default:
        return Colors.orange.shade600;
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'approved':
        return StockpileColors.successBg;
      case 'rejected':
        return StockpileColors.dangerBg;
      default:
        return Colors.orange.shade50;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<ConfigService>().currencySymbol;
    final isDark = widget.isDark;
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final mutedColor = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // ── Handle + Title ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 22,
                        color: StockpileColors.primary900,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Withdrawal History',
                          style: StockpileFonts.satoshi(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                      ),
                      if (_requests.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: StockpileColors.primary900.withAlpha(20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_requests.length}',
                            style: StockpileFonts.satoshi(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: StockpileColors.primary900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(
                    color: isDark
                        ? StockpileColors.darkDivider
                        : StockpileColors.divider,
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 40,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 8),
                          Text(_error!),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _loading = true;
                                _error = null;
                              });
                              _load();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _requests.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_rounded,
                            size: 48,
                            color: mutedColor,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No withdrawal requests yet',
                            style: StockpileFonts.satoshi(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: mutedColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: _requests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final req = _requests[index];
                        return _HistoryCard(
                          request: req,
                          currencySymbol: cs,
                          isDark: isDark,
                          textColor: textColor,
                          mutedColor: mutedColor,
                          statusColor: _statusColor(req.status),
                          statusBg: _statusBg(req.status),
                          statusLabel: _statusLabel(req.status),
                          formattedDate: req.createdAt != null
                              ? _formatDateTime(req.createdAt!)
                              : '',
                          isExpanded: _expandedIds.contains(req.id),
                          onTap:
                              req.status == 'rejected' &&
                                  req.rejectionReason != null &&
                                  req.rejectionReason!.isNotEmpty
                              ? () => _toggleExpanded(req.id!)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final WithdrawalRequest request;
  final String currencySymbol;
  final bool isDark;
  final Color textColor;
  final Color mutedColor;
  final Color statusColor;
  final Color statusBg;
  final String statusLabel;
  final String formattedDate;
  final bool isExpanded;
  final VoidCallback? onTap;

  const _HistoryCard({
    required this.request,
    required this.currencySymbol,
    required this.isDark,
    required this.textColor,
    required this.mutedColor,
    required this.statusColor,
    required this.statusBg,
    required this.statusLabel,
    required this.formattedDate,
    required this.isExpanded,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: isDark
                ? StockpileColors.darkSurface
                : StockpileColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? StockpileColors.darkDivider
                  : StockpileColors.divider,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: pool icon + source label + status badge ──
              Row(
                children: [
                  Icon(
                    request.sourceBucket == 'total_earnings'
                        ? Icons.account_balance_wallet_rounded
                        : Icons.savings_rounded,
                    size: 18,
                    color: mutedColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      request.sourceLabel,
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: StockpileFonts.satoshi(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── Amount + date ──────────────────────────────────
              Row(
                children: [
                  Text(
                    '$currencySymbol${request.requestedAmount}',
                    style: StockpileFonts.satoshi(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.access_time_rounded, size: 13, color: mutedColor),
                  const SizedBox(width: 4),
                  Text(
                    formattedDate,
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      color: mutedColor,
                    ),
                  ),
                ],
              ),

              // ── Rejection reason (expandable) ──────────────────
              if (request.status == 'rejected' &&
                  request.rejectionReason != null &&
                  request.rejectionReason!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 16,
                      color: StockpileColors.danger,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isExpanded ? 'Hide reason' : 'View rejection reason',
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: StockpileColors.danger,
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: StockpileColors.dangerBg.withAlpha(60),
                        borderRadius: BorderRadius.circular(10),
                        border: Border(
                          left: BorderSide(
                            color: StockpileColors.danger.withAlpha(100),
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        request.rejectionReason!,
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF991B1B),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  crossFadeState: isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
