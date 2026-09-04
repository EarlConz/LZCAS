// lib/pages/branch/branch_cashier_dashboard.dart
// Branch Cashier Dashboard — a restricted staff role.
// Two tabs only:
//   1. POS Terminal   — process sales (reuses the existing TransactionsTable).
//   2. Stocks on Hand — READ-ONLY current stock with Good/Low/Out status.
// Branch cashier CANNOT see: members, inventory CRUD, reports, admin, users.
// (The narrow surface is enforced here in the UI; at the DB level the role is
//  treated as staff — see migration_v28_branch_cashier_role.sql.)

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/widgets/transactionstable.dart';
import 'package:lzcas/widgets/cashier_location_settings.dart';
import 'package:lzcas/widgets/announcement_widgets.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/services/updater_service.dart';
import 'package:lzcas/dialogs/update_dialog.dart';
import 'package:lzcas/dialogs/unseen_announcements_dialog.dart';
import 'package:lzcas/dialogs/announcement_detail_dialog.dart';

class BranchCashierDashboard extends StatefulWidget {
  const BranchCashierDashboard({super.key});

  @override
  State<BranchCashierDashboard> createState() => _BranchCashierDashboardState();
}

/// The three sections of the branch terminal.
enum _BranchTab {
  pos('POS Terminal', Icons.point_of_sale_rounded),
  stocks('Stocks on Hand', Icons.inventory_2_rounded),
  announcements('Announcements', Icons.campaign_rounded),
  location('Location', Icons.location_on_rounded);

  const _BranchTab(this.title, this.icon);

  final String title;
  final IconData icon;
}

class _BranchCashierDashboardState extends State<BranchCashierDashboard> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  _BranchTab _tab = _BranchTab.pos;

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
        if (!mounted) return;
        if (info != null) {
          UpdateDialog.showIfAvailable(context);
          // One modal at a time; the announcements stay unseen and come
          // back on the next open.
          return;
        }
        showUnseenAnnouncements(context);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Defense-in-depth: only branch cashier role may render this dashboard.
    assertRoleOrThrow(context, {UserRole.branchCashier});

    final auth = context.watch<AuthState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Same breakpoint the admin and member dashboards use, so all three
    // switch between inline sidebar and drawer at the same width.
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    final sidebar = _BranchSidebar(
      selected: _tab,
      username: auth.username,
      isDark: isDark,
      auth: auth,
      onSelected: (t) {
        setState(() => _tab = t);
        if (!isDesktop) Navigator.of(context).maybePop();
      },
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: isDesktop ? null : Drawer(child: sidebar),
      body: Row(
        children: [
          if (isDesktop) ...[
            SizedBox(width: 260, child: sidebar),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(isDark, isDesktop),
                  Expanded(child: _buildBody(auth)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// No logout here — it lives at the foot of the sidebar, where the other
  /// dashboards keep theirs.
  Widget _buildTopBar(bool isDark, bool isDesktop) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              icon: const Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          Expanded(
            child: Text(
              _tab.title,
              overflow: TextOverflow.ellipsis,
              style: StockpileFonts.satoshi(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AuthState auth) {
    switch (_tab) {
      case _BranchTab.pos:
        // Sells from THIS cashier's allocation.
        return Padding(
          padding: const EdgeInsets.all(16),
          child: TransactionsTable(branchOwnerId: auth.userId),
        );
      case _BranchTab.stocks:
        // This branch's allocation, read-only.
        return _StocksOnHandView(ownerId: auth.userId);
      case _BranchTab.announcements:
        return const _BranchAnnouncementsView();
      case _BranchTab.location:
        return const CashierLocationSettings();
    }
  }
}

// ─── Announcements ──────────────────────────────────────────────────────────

/// Notices from the office addressed to this branch.
///
/// Same Current/Saved split the member tab uses. Saved items are keyed on
/// the ACCOUNT as of v40, so a branch cashier can keep a notice past its end
/// date exactly as a member can — before that the table keyed on members.id
/// and staff had nothing to save against.
class _BranchAnnouncementsView extends StatefulWidget {
  const _BranchAnnouncementsView();

  @override
  State<_BranchAnnouncementsView> createState() =>
      _BranchAnnouncementsViewState();
}

class _BranchAnnouncementsViewState extends State<_BranchAnnouncementsView> {
  List<Announcement> _all = const [];
  bool _loading = true;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = repository.changes.listen((e) {
      if (e == 'announcements_changed' && mounted) _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await repository.fetchAnnouncementsForMe();
    if (!mounted) return;
    setState(() {
      _all = rows;
      _loading = false;
    });
  }

  /// Optimistic, mirroring the member tab: the star flips immediately and
  /// only rolls back if the write fails.
  Future<void> _toggle(Announcement a) async {
    final wanted = !a.saved;
    setState(() {
      _all = [
        for (final x in _all) x.id == a.id ? x.copyWith(saved: wanted) : x,
      ];
    });

    final ok = await repository.setAnnouncementSaved(
      announcementId: a.id,
      saved: wanted,
    );
    if (!ok && mounted) {
      setState(() {
        _all = [
          for (final x in _all) x.id == a.id ? x.copyWith(saved: !wanted) : x,
        ];
      });
    }
  }

  Future<void> _openDetail(Announcement a) async {
    final changed = await showAnnouncementDetail(context, announcement: a);
    if (changed && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    if (_loading) return const Center(child: CircularProgressIndicator());

    // Same rule as the member tab: Current holds everything still in its
    // window, starred or not; Saved holds only what has EXPIRED and is
    // starred. Nothing appears in both.
    final current = _all.where((a) => a.isCurrent()).toList();
    final savedExpired = _all.where((a) => a.saved && !a.isCurrent()).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card(
            isDark: isDark,
            icon: Icons.campaign_rounded,
            title: 'Announcements',
            subtitle:
                'News and reminders from the GUTVita office. '
                'Tap the star to keep one.',
            emptyText: 'Nothing from the office right now.',
            items: current,
          ),
          if (savedExpired.isNotEmpty) ...[
            const SizedBox(height: 20),
            _card(
              isDark: isDark,
              icon: Icons.star_rounded,
              title: 'Saved',
              trailing: '${savedExpired.length}',
              subtitle:
                  'Kept here after they stopped being current. '
                  'Unstar one to let it go.',
              emptyText: '',
              items: savedExpired,
              asSaved: true,
            ),
          ],
          const SizedBox(height: 8),
          if (current.isEmpty && savedExpired.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Icon(Icons.campaign_outlined, size: 40, color: muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required String emptyText,
    required List<Announcement> items,
    String? trailing,
    bool asSaved = false,
  }) {
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    return Card(
      elevation: 0,
      color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: StockpileColors.primary900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: StockpileFonts.satoshi(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing,
                    style: StockpileFonts.satoshi(fontSize: 13, color: muted),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: StockpileFonts.satoshi(fontSize: 11, color: muted),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  emptyText,
                  style: StockpileFonts.satoshi(fontSize: 13, color: muted),
                ),
              )
            else
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 16),
                  Divider(height: 1, color: divider.withAlpha(120)),
                  const SizedBox(height: 16),
                ],
                AnnouncementTile(
                  announcement: items[i],
                  asSaved: asSaved,
                  isDark: isDark,
                  onToggleSaved: () => _toggle(items[i]),
                  onTap: () => _openDetail(items[i]),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

// ─── Sidebar ────────────────────────────────────────────────────────────────

/// Inline on desktop, inside a Drawer on mobile.
///
/// Replaces a three-item TabBar whose icon+label tabs could not fit a phone
/// width — the labels were being squeezed to the point of clipping. Matching
/// the admin and member dashboards also means a branch cashier moving between
/// devices sees one navigation idiom rather than two.
class _BranchSidebar extends StatelessWidget {
  final _BranchTab selected;
  final String username;
  final bool isDark;
  final AuthState auth;
  final ValueChanged<_BranchTab> onSelected;

  const _BranchSidebar({
    required this.selected,
    required this.username,
    required this.isDark,
    required this.auth,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final activeBg = isDark
        ? StockpileColors.darkSidebarActive
        : StockpileColors.sidebarActive;

    return Container(
      color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Branch Terminal',
                    style: StockpileFonts.satoshi(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$username · Branch Cashier',
                    overflow: TextOverflow.ellipsis,
                    style: StockpileFonts.satoshi(fontSize: 13, color: muted),
                  ),
                ],
              ),
            ),
            for (final tab in _BranchTab.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Material(
                  color: selected == tab ? activeBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelected(tab),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            tab.icon,
                            size: 20,
                            color: selected == tab
                                ? StockpileColors.primary900
                                : muted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tab.title,
                              overflow: TextOverflow.ellipsis,
                              style: StockpileFonts.satoshi(
                                fontSize: 14,
                                fontWeight: selected == tab
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected == tab
                                    ? StockpileColors.primary900
                                    : textColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _LogoutButton(auth: auth),
                  const SizedBox(width: 4),
                  Text(
                    'Log out',
                    style: StockpileFonts.satoshi(fontSize: 13, color: muted),
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

// ─── Logout ─────────────────────────────────────────────────────────────────

class _LogoutButton extends StatelessWidget {
  final AuthState auth;
  const _LogoutButton({required this.auth});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Log out',
      icon: const Icon(Icons.logout_rounded),
      onPressed: () async {
        await auth.logout();
        if (!context.mounted) return;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
      },
    );
  }
}

// ─── Stocks on Hand (read-only) ─────────────────────────────────────────────

class _StocksOnHandView extends StatefulWidget {
  final String? ownerId;
  const _StocksOnHandView({required this.ownerId});

  @override
  State<_StocksOnHandView> createState() => _StocksOnHandViewState();
}

class _StocksOnHandViewState extends State<_StocksOnHandView> {
  late Future<_StockData> _future;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _statusFilter = 'All'; // All | Good | Low Stock | Out of Stock

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<_StockData> _load() async {
    // Only THIS branch cashier's allocation (branch_stock_view). Each item's
    // status is already computed server-side (Good/Low/Out). Read-only.
    final all = widget.ownerId == null
        ? <Item>[]
        : await repository.fetchBranchStock(widget.ownerId!);
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final statusById = {for (final it in all) it.id: it.status ?? ''};
    return _StockData(all, statusById);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  // ── Theme helpers ──────────────────────────────────────────────────────
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _surface =>
      _isDark ? StockpileColors.darkSurface : StockpileColors.surface;
  Color get _textPrimary =>
      _isDark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
  Color get _textMuted =>
      _isDark ? StockpileColors.darkTextMuted : StockpileColors.mutedText;
  Color get _border =>
      _isDark ? StockpileColors.darkDivider : StockpileColors.divider;
  Color get _inputFill =>
      _isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg;

  // Softer, more natural status tones (sage / honey / clay) — easier on the
  // eye than neon green/red, and readable in both light and dark.
  static const _cGood = Color(0xFF5B9B72); // muted sage green
  static const _cLow = Color(0xFFC79A45); // warm honey amber
  static const _cOut = Color(0xFFC77066); // soft clay red

  String _statusOf(Item it, _StockData data) =>
      it.stock <= 0 ? 'Out of Stock' : (data.statusById[it.id] ?? 'Good');

  Color _statusColor(String s) =>
      s == 'Out of Stock' ? _cOut : (s == 'Low Stock' ? _cLow : _cGood);

  // Gentle fill for a status color — soft in light, a touch stronger in dark.
  int get _fillAlpha => _isDark ? 38 : 22;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StockData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _centeredMessage(
            Icons.cloud_off_rounded,
            'Could not load your stock',
            '${snap.error}',
          );
        }
        final data = snap.data;
        if (data == null || data.items.isEmpty) {
          return _centeredMessage(
            Icons.inventory_2_outlined,
            'No stock assigned yet',
            'Ask an admin or main cashier to give you stock.',
          );
        }
        return _content(data);
      },
    );
  }

  Widget _content(_StockData data) {
    final term = _search.trim().toLowerCase();
    final items = data.items.where((i) {
      final matchesSearch =
          term.isEmpty ||
          i.name.toLowerCase().contains(term) ||
          (i.category?.toLowerCase().contains(term) ?? false);
      final matchesStatus =
          _statusFilter == 'All' || _statusOf(i, data) == _statusFilter;
      return matchesSearch && matchesStatus;
    }).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          _heroCard(data),
          const SizedBox(height: 20),
          _filterChips(data),
          const SizedBox(height: 14),
          if (data.items.length > 6)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search products…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _search = '');
                          },
                        ),
                  filled: true,
                  fillColor: _inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _border),
                  ),
                ),
              ),
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: items.isEmpty
                ? Padding(
                    key: const ValueKey('empty'),
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 34,
                            color: _textMuted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Nothing here',
                            style: StockpileFonts.satoshi(
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'No products match this filter.',
                            style: TextStyle(color: _textMuted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    key: ValueKey('list_${_statusFilter}_${items.length}'),
                    children: [
                      for (var i = 0; i < items.length; i++)
                        _entrance(
                          i,
                          _itemCard(items[i], _statusOf(items[i], data)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Subtle staggered fade + slide-up as tiles mount.
  Widget _entrance(int index, Widget child) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 280 + (index * 28).clamp(0, 240)),
    curve: Curves.easeOutCubic,
    builder: (_, t, ch) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: ch),
    ),
    child: child,
  );

  Widget _filterChips(_StockData data) {
    final good = data.items.where((i) => _statusOf(i, data) == 'Good').length;
    final low = data.items
        .where((i) => _statusOf(i, data) == 'Low Stock')
        .length;
    final out = data.items.where((i) => i.stock <= 0).length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(
            'All',
            'All products',
            data.items.length,
            StockpileColors.primary700,
          ),
          const SizedBox(width: 8),
          _chip('Good', 'Good', good, _cGood),
          const SizedBox(width: 8),
          _chip('Low Stock', 'Low', low, _cLow),
          const SizedBox(width: 8),
          _chip('Out of Stock', 'Out', out, _cOut),
        ],
      ),
    );
  }

  Widget _chip(String value, String label, int count, Color color) {
    final selected = _statusFilter == value;
    return ScaleTap(
      child: GestureDetector(
        onTap: () => setState(() => _statusFilter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? color.withAlpha(_isDark ? 60 : 34) : _inputFill,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected ? color : _border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : _textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? color : _textMuted.withAlpha(40),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : _textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<BoxShadow> get _softShadow => [
    BoxShadow(
      color: Colors.black.withAlpha(_isDark ? 46 : 15),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  Widget _heroCard(_StockData data) {
    final units = data.items.fold<int>(0, (s, i) => s + i.stock);
    final products = data.items.length;
    final good = data.items.where((i) => _statusOf(i, data) == 'Good').length;
    final low = data.items
        .where((i) => _statusOf(i, data) == 'Low Stock')
        .length;
    final out = data.items.where((i) => i.stock <= 0).length;
    final cats = data.items
        .map((i) => (i.category ?? 'Uncategorized'))
        .toSet()
        .length;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isDark
              ? [const Color(0xFF262640), const Color(0xFF1B1B2C)]
              : [Colors.white, const Color(0xFFFBF7EF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: _softShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STOCK ON HAND',
                      style: StockpileFonts.satoshi(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _textMuted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$units',
                          style: StockpileFonts.satoshi(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'units',
                            style: StockpileFonts.satoshi(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$products products · $cats categories',
                      style: TextStyle(color: _textMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              _StatusRing(
                size: 104,
                good: good,
                low: low,
                out: out,
                trackColor: _isDark
                    ? Colors.white.withAlpha(16)
                    : Colors.black.withAlpha(12),
                colors: const [_cGood, _cLow, _cOut],
                centerTop: '$products',
                centerBottom: products == 1 ? 'item' : 'items',
                centerTopColor: _textPrimary,
                centerBottomColor: _textMuted,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _legend(_cGood, 'Good', good),
              const SizedBox(width: 18),
              _legend(_cLow, 'Low', low),
              const SizedBox(width: 18),
              _legend(_cOut, 'Out', out),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String label, int n) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Text('$label  ', style: TextStyle(color: _textMuted, fontSize: 12.5)),
      Text(
        '$n',
        style: StockpileFonts.satoshi(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          color: _textPrimary,
        ),
      ),
    ],
  );

  Widget _itemCard(Item it, String status) {
    final color = _statusColor(status);
    final initial = it.name.trim().isNotEmpty
        ? it.name.trim()[0].toUpperCase()
        : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: _softShadow,
      ),
      child: ScaleTap(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _showItemDetail(it, status),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Colored status accent along the leading edge.
                    Container(width: 5, color: color),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color.withAlpha(_fillAlpha),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Text(
                                initial,
                                style: StockpileFonts.satoshi(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.name,
                                    style: StockpileFonts.satoshi(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: _textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    it.category ?? 'Uncategorized',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${it.stock}',
                                  style: StockpileFonts.satoshi(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                    color: color,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withAlpha(_fillAlpha),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: color,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: _textMuted,
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showItemDetail(Item it, String status) {
    final color = _statusColor(status);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: _textMuted.withAlpha(70),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withAlpha(_fillAlpha),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.inventory_2_rounded,
                    color: color,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.name,
                        style: StockpileFonts.satoshi(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                        ),
                      ),
                      Text(
                        it.category ?? 'Uncategorized',
                        style: TextStyle(color: _textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Big quantity + status banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: color.withAlpha(_fillAlpha),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withAlpha(55)),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${it.stock}',
                        style: StockpileFonts.satoshi(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      Text(
                        'on hand',
                        style: TextStyle(color: _textMuted, fontSize: 12.5),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _detailRow(
              Icons.category_outlined,
              'Category',
              it.category ?? 'Uncategorized',
            ),
            if (it.lastUpdated != null)
              _detailRow(
                Icons.update_rounded,
                'Last updated',
                _fmtDate(it.lastUpdated!),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.point_of_sale_rounded, size: 16, color: _textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sell this from the POS Terminal tab. Stock updates here automatically.',
                    style: TextStyle(color: _textMuted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: _textMuted),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: _textMuted, fontSize: 13)),
        const Spacer(),
        Text(
          value,
          style: StockpileFonts.satoshi(
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
            color: _textPrimary,
          ),
        ),
      ],
    ),
  );

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final ap = l.hour < 12 ? 'AM' : 'PM';
    return '${months[l.month - 1]} ${l.day}, $h:${l.minute.toString().padLeft(2, '0')} $ap';
  }

  Widget _centeredMessage(IconData icon, String title, String sub) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: _textMuted),
          const SizedBox(height: 14),
          Text(
            title,
            style: StockpileFonts.satoshi(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: TextStyle(color: _textMuted, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _StockData {
  final List<Item> items;
  final Map<int?, String> statusById;
  const _StockData(this.items, this.statusById);
}

/// A donut chart summarizing the Good / Low / Out distribution, with a value
/// centered in the ring. Draws only a track when there is no data.
class _StatusRing extends StatelessWidget {
  final double size;
  final int good, low, out;
  final Color trackColor;
  final List<Color> colors; // [good, low, out]
  final String centerTop, centerBottom;
  final Color centerTopColor, centerBottomColor;

  const _StatusRing({
    required this.size,
    required this.good,
    required this.low,
    required this.out,
    required this.trackColor,
    required this.colors,
    required this.centerTop,
    required this.centerBottom,
    required this.centerTopColor,
    required this.centerBottomColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (_, t, _) => CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                good: good,
                low: low,
                out: out,
                track: trackColor,
                colors: colors,
                progress: t,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerTop,
                style: StockpileFonts.satoshi(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: centerTopColor,
                ),
              ),
              Text(
                centerBottom,
                style: TextStyle(fontSize: 10.5, color: centerBottomColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int good, low, out;
  final Color track;
  final List<Color> colors;
  final double progress;

  _RingPainter({
    required this.good,
    required this.low,
    required this.out,
    required this.track,
    required this.colors,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = Offset.zero & size;
    final inner = rect.deflate(stroke / 2 + 1);
    final total = good + low + out;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(inner, 0, 2 * math.pi, false, trackPaint);

    if (total == 0) return;

    final segments = <MapEntry<int, Color>>[
      MapEntry(good, colors[0]),
      MapEntry(low, colors[1]),
      MapEntry(out, colors[2]),
    ].where((e) => e.key > 0).toList();

    final gap = segments.length > 1 ? 0.10 : 0.0;
    var start = -math.pi / 2; // 12 o'clock
    for (final seg in segments) {
      final full = (seg.key / total) * 2 * math.pi;
      final sweep = (full - gap) * progress;
      if (sweep <= 0) {
        start += full;
        continue;
      }
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = seg.value;
      canvas.drawArc(inner, start + gap / 2, sweep, false, p);
      start += full;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.good != good ||
      old.low != low ||
      old.out != out ||
      old.progress != progress ||
      old.track != track;
}
