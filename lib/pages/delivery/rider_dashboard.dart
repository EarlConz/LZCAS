// lib/pages/delivery/rider_dashboard.dart
//
// The delivery rider's home. Two sections — what they are carrying now,
// and what they have carried — behind the same sidebar/drawer idiom the
// other dashboards use, so a rider who is also a member sees one app.
//
// What a rider can reach is the narrowest surface in the app: their own
// assigned orders and nothing else. That is enforced by RLS (v49) and by
// the rider RPCs (v50), not here; this file only decides what to draw.
//
// Position pings: while ANY order is Picked Up, the rider's position is
// written to their profile every 60 seconds so the cashier's dispatch
// list and the member's "rider is 2 km away" have something to read.
// Never otherwise — nobody is tracked off-shift. See plan §3.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/dialogs/update_dialog.dart';
import 'package:lzcas/pages/delivery/rider_order_card.dart';
import 'package:lzcas/pages/delivery/rider_order_detail_page.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/services/geocoding_service.dart';
import 'package:lzcas/services/updater_service.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart';

class RiderDashboard extends StatefulWidget {
  const RiderDashboard({super.key});

  @override
  State<RiderDashboard> createState() => _RiderDashboardState();
}

enum _RiderTab {
  deliveries('My Deliveries', Icons.two_wheeler_rounded),
  history('History', Icons.history_rounded);

  const _RiderTab(this.title, this.icon);
  final String title;
  final IconData icon;
}

class _RiderDashboardState extends State<RiderDashboard> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  _RiderTab _tab = _RiderTab.deliveries;

  List<DeliveryOrder> _orders = const [];
  bool _loading = true;
  StreamSubscription<String>? _changes;

  /// Last position we managed to resolve. Drives the distance shown on
  /// each card; null until the first fix.
  LocatedPoint? _me;
  Timer? _pinger;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = repository.changes.listen((e) {
      if ((e == 'order_updated' || e == 'order_added') && mounted) _load();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<UpdaterService>().checkForUpdate(silent: true).then((info) {
        if (mounted && info != null) UpdateDialog.showIfAvailable(context);
      });
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    _pinger?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = context.read<AuthState>().userId;
    if (uid == null) return;
    try {
      final rows = await repository.fetchDeliveryOrders(deliveryId: uid);
      if (!mounted) return;
      setState(() {
        _orders = rows;
        _loading = false;
      });
      _syncPinger();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Start pinging when something is on its way; stop the moment nothing
  /// is. Idempotent, so it is safe to call after every reload.
  void _syncPinger() {
    final onTheWay = _orders.any((o) => o.isPickedUp);
    if (onTheWay && _pinger == null) {
      _ping();
      _pinger = Timer.periodic(const Duration(seconds: 60), (_) => _ping());
    } else if (!onTheWay && _pinger != null) {
      _pinger!.cancel();
      _pinger = null;
    }
  }

  Future<void> _ping() async {
    final p = await GeocodingService.resolvePosition();
    if (p == null || !mounted) return;
    setState(() => _me = p);
    await repository.deliveryUpdatePosition(
      latitude: p.latitude,
      longitude: p.longitude,
    );
  }

  /// One-off fix for the distances on the cards, without starting the
  /// pinger. A rider with nothing picked up still wants to know how far
  /// the next pickup is.
  Future<void> _locateOnce() async {
    final p = await GeocodingService.resolvePosition();
    if (p != null && mounted) setState(() => _me = p);
  }

  double? _metersTo(DeliveryOrder o) {
    final me = _me;
    if (me == null ||
        o.deliveryLatitude == null ||
        o.deliveryLongitude == null) {
      return null;
    }
    return Geolocator.distanceBetween(
      me.latitude,
      me.longitude,
      o.deliveryLatitude!,
      o.deliveryLongitude!,
    );
  }

  Future<void> _open(DeliveryOrder o) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RiderOrderDetailPage(
          orderId: o.id,
          initial: o,
          metersAway: _metersTo(o),
          myPosition: _me == null
              ? null
              : LatLng(_me!.latitude, _me!.longitude),
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    assertRoleOrThrow(context, {UserRole.delivery});

    final auth = context.watch<AuthState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    final sidebar = _RiderSidebar(
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
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: () async {
                              await _locateOnce();
                              await _load();
                            },
                            child: switch (_tab) {
                              _RiderTab.deliveries => _buildDeliveries(isDark),
                              _RiderTab.history => _buildHistory(isDark),
                            },
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
          if (_me == null)
            IconButton(
              tooltip: 'Find my location',
              icon: const Icon(Icons.my_location_rounded),
              onPressed: _locateOnce,
            ),
        ],
      ),
    );
  }

  // ── My Deliveries ─────────────────────────────────────────────────

  Widget _buildDeliveries(bool isDark) {
    final onTheWay = _orders.where((o) => o.isPickedUp).toList();
    final assigned = _orders.where((o) => o.isAssigned).toList();
    final delivered = _orders.where((o) => o.isDelivered).toList();
    final codToRemit = _orders
        .where((o) => o.isCod && (o.isDelivered || o.isCompleted))
        .fold<double>(0, (s, o) => s + (o.finalTotal ?? 0));

    if (onTheWay.isEmpty && assigned.isEmpty && delivered.isEmpty) {
      return _empty(
        isDark,
        icon: Icons.two_wheeler_rounded,
        title: 'Nothing to deliver right now',
        body: 'When a cashier assigns you an order, it shows up here.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (onTheWay.isNotEmpty) ...[
          _sectionLabel('ON THE WAY', onTheWay.length, isDark),
          for (final o in onTheWay)
            RiderOrderCard(
              order: o,
              metersAway: _metersTo(o),
              isDark: isDark,
              highlighted: true,
              onTap: () => _open(o),
            ),
          const SizedBox(height: 14),
        ],
        if (assigned.isNotEmpty) ...[
          _sectionLabel('ASSIGNED TO YOU', assigned.length, isDark),
          for (final o in assigned)
            RiderOrderCard(
              order: o,
              metersAway: _metersTo(o),
              isDark: isDark,
              onTap: () => _open(o),
            ),
          const SizedBox(height: 14),
        ],
        if (delivered.isNotEmpty) ...[
          _sectionLabel('WAITING FOR CONFIRMATION', delivered.length, isDark),
          for (final o in delivered)
            RiderOrderCard(
              order: o,
              metersAway: null,
              isDark: isDark,
              onTap: () => _open(o),
            ),
          const SizedBox(height: 14),
        ],
        if (codToRemit > 0) _remitBanner(codToRemit, isDark),
      ],
    );
  }

  // ── History ───────────────────────────────────────────────────────

  Widget _buildHistory(bool isDark) {
    final done = _orders.where((o) => o.isCompleted || o.isCancelled).toList();

    if (done.isEmpty) {
      return _empty(
        isDark,
        icon: Icons.history_rounded,
        title: 'No deliveries yet',
        body: 'Completed and cancelled orders will be listed here.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        _codTally(done, isDark),
        const SizedBox(height: 16),
        _sectionLabel('DELIVERED', done.length, isDark),
        for (final o in done)
          RiderOrderCard(
            order: o,
            metersAway: null,
            isDark: isDark,
            compact: true,
            onTap: () => _open(o),
          ),
      ],
    );
  }

  /// Collected / remitted / outstanding cash. Remittance is recorded by the
  /// cashier (v51's `cod_remitted_at`), so until then everything CoD is
  /// "to remit" — which is the honest number for a rider to see.
  Widget _codTally(List<DeliveryOrder> done, bool isDark) {
    final cod = done.where((o) => o.isCod && o.isCompleted).toList();
    if (cod.isEmpty) return const SizedBox.shrink();
    final collected = cod.fold<double>(0, (s, o) => s + (o.finalTotal ?? 0));

    return _card(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('CASH ON DELIVERY', isDark),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stat('Collected', formatMoney(collected), isDark),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: StockpileColors.primary50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _stat(
                    'To remit',
                    formatMoney(collected),
                    isDark,
                    labelColor: const Color(0xFFB24800),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
          ),
          const SizedBox(height: 10),
          Text(
            'Hand cash to the cashier. They mark it remitted — not you.',
            style: StockpileFonts.satoshi(
              fontSize: 12,
              height: 1.5,
              color: isDark
                  ? StockpileColors.darkTextBody
                  : StockpileColors.bodyText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _remitBanner(double amount, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: StockpileColors.primary50,
        border: Border.all(color: StockpileColors.primary200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.payments_outlined,
            color: StockpileColors.primary900,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatMoney(amount)} cash to remit',
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: StockpileColors.darkText,
                  ),
                ),
                Text(
                  'Hand it to the cashier — they record it.',
                  style: StockpileFonts.satoshi(
                    fontSize: 11,
                    color: StockpileColors.bodyText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bits ──────────────────────────────────────────────────────────

  Widget _sectionLabel(String text, int count, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Row(
        children: [
          _label(text, isDark),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: StockpileFonts.satoshi(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: StockpileColors.primary900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, bool isDark) => Text(
    text,
    style: StockpileFonts.satoshi(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: isDark ? StockpileColors.darkTextMuted : StockpileColors.mutedText,
    ),
  );

  Widget _stat(String label, String value, bool isDark, {Color? labelColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: StockpileFonts.satoshi(
            fontSize: 11,
            fontWeight: labelColor == null ? FontWeight.w400 : FontWeight.w700,
            color:
                labelColor ??
                (isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: StockpileFonts.satoshi(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: isDark
                ? StockpileColors.darkTextPrimary
                : StockpileColors.darkText,
          ),
        ),
      ],
    );
  }

  Widget _card(bool isDark, {required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
      border: Border.all(
        color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _empty(
    bool isDark, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    // Inside a ListView so pull-to-refresh still works on an empty screen.
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      children: [
        Icon(
          icon,
          size: 48,
          color: isDark
              ? StockpileColors.darkTextMuted
              : StockpileColors.mutedText,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: StockpileFonts.satoshi(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark
                ? StockpileColors.darkTextPrimary
                : StockpileColors.darkText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: StockpileFonts.satoshi(
            fontSize: 13,
            height: 1.5,
            color: isDark
                ? StockpileColors.darkTextMuted
                : StockpileColors.mutedText,
          ),
        ),
      ],
    );
  }
}

// ─── Sidebar ────────────────────────────────────────────────────────────────

class _RiderSidebar extends StatelessWidget {
  final _RiderTab selected;
  final String username;
  final bool isDark;
  final AuthState auth;
  final ValueChanged<_RiderTab> onSelected;

  const _RiderSidebar({
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
                    'Deliveries',
                    style: StockpileFonts.satoshi(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$username · Rider',
                    overflow: TextOverflow.ellipsis,
                    style: StockpileFonts.satoshi(fontSize: 13, color: muted),
                  ),
                ],
              ),
            ),
            for (final tab in _RiderTab.values)
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
                  IconButton(
                    tooltip: 'Log out',
                    icon: const Icon(Icons.logout_rounded),
                    onPressed: () async {
                      await auth.logout();
                      if (!context.mounted) return;
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
                    },
                  ),
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
