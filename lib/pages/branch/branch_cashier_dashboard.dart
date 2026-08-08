// lib/pages/branch/branch_cashier_dashboard.dart
// Branch Cashier Dashboard — a restricted staff role.
// Two tabs only:
//   1. POS Terminal   — process sales (reuses the existing TransactionsTable).
//   2. Stocks on Hand — READ-ONLY current stock with Good/Low/Out status.
// Branch cashier CANNOT see: members, inventory CRUD, reports, admin, users.
// (The narrow surface is enforced here in the UI; at the DB level the role is
//  treated as staff — see migration_v28_branch_cashier_role.sql.)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/widgets/transactionstable.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/services/updater_service.dart';
import 'package:lzcas/dialogs/update_dialog.dart';

class BranchCashierDashboard extends StatefulWidget {
  const BranchCashierDashboard({super.key});

  @override
  State<BranchCashierDashboard> createState() => _BranchCashierDashboardState();
}

class _BranchCashierDashboardState extends State<BranchCashierDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Defense-in-depth: only branch cashier role may render this dashboard.
    assertRoleOrThrow(context, {UserRole.branchCashier});

    final auth = context.watch<AuthState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Branch Terminal',
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
                          'Welcome, ${auth.username} · Branch Cashier',
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

            // ── Tab Bar ─────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? StockpileColors.darkInputBg
                    : StockpileColors.inputBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: StockpileColors.primary900,
                unselectedLabelColor: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
                indicator: BoxDecoration(
                  color: isDark ? StockpileColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.point_of_sale_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('POS Terminal'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Stocks on Hand'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Tab Content ─────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  // Tab 1: POS terminal (reused)
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: TransactionsTable(),
                  ),
                  // Tab 2: Stocks on Hand (read-only)
                  _StocksOnHandView(),
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
          return _centeredMessage(Icons.cloud_off_rounded,
              'Could not load your stock', '${snap.error}');
        }
        final data = snap.data;
        if (data == null || data.items.isEmpty) {
          return _centeredMessage(
              Icons.inventory_2_outlined,
              'No stock assigned yet',
              'Ask an admin or main cashier to give you stock.');
        }
        return _content(data);
      },
    );
  }

  Widget _content(_StockData data) {
    final term = _search.trim().toLowerCase();
    final items = data.items.where((i) {
      final matchesSearch = term.isEmpty ||
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
                          Icon(Icons.search_off_rounded,
                              size: 34, color: _textMuted),
                          const SizedBox(height: 8),
                          Text('Nothing here',
                              style: StockpileFonts.satoshi(
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary)),
                          const SizedBox(height: 2),
                          Text('No products match this filter.',
                              style: TextStyle(
                                  color: _textMuted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Text(status, style: TextStyle(fontSize: 11, color: color)),
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
          Text('$label  ',
              style: TextStyle(color: _textMuted, fontSize: 12.5)),
          Text('$n',
              style: StockpileFonts.satoshi(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: _textPrimary)),
        ],
      );

  Widget _itemCard(Item it, String status) {
    final color = _statusColor(status);
    final initial = it.name.trim().isNotEmpty ? it.name.trim()[0].toUpperCase() : '?';
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
                              child: Text(initial,
                                  style: StockpileFonts.satoshi(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: color)),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(it.name,
                                      style: StockpileFonts.satoshi(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: _textPrimary)),
                                  const SizedBox(height: 3),
                                  Text(it.category ?? 'Uncategorized',
                                      style: TextStyle(
                                          fontSize: 12, color: _textMuted)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${it.stock}',
                                    style: StockpileFonts.satoshi(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 20,
                                        color: color)),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withAlpha(_fillAlpha),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(status,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: color,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right_rounded,
                                color: _textMuted, size: 22),
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
                  child:
                      Icon(Icons.inventory_2_rounded, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.name,
                          style: StockpileFonts.satoshi(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: _textPrimary)),
                      Text(it.category ?? 'Uncategorized',
                          style: TextStyle(color: _textMuted, fontSize: 13)),
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
                      Text('${it.stock}',
                          style: StockpileFonts.satoshi(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: color)),
                      Text('on hand',
                          style:
                              TextStyle(color: _textMuted, fontSize: 12.5)),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(status,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _detailRow(Icons.category_outlined, 'Category',
                it.category ?? 'Uncategorized'),
            if (it.lastUpdated != null)
              _detailRow(Icons.update_rounded, 'Last updated',
                  _fmtDate(it.lastUpdated!)),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.point_of_sale_rounded,
                    size: 16, color: _textMuted),
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
            Text(value,
                style: StockpileFonts.satoshi(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: _textPrimary)),
          ],
        ),
      );

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
              Text(title,
                  style: StockpileFonts.satoshi(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary)),
              const SizedBox(height: 6),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textMuted, fontSize: 13, height: 1.4)),
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
              Text(centerTop,
                  style: StockpileFonts.satoshi(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: centerTopColor)),
              Text(centerBottom,
                  style: TextStyle(fontSize: 10.5, color: centerBottomColor)),
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
