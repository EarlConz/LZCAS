// lib/pages/delivery/delivery_orders_page.dart
//
// Cashier / Admin "Delivery Orders" (branch cashiers excluded).
//
// One queue, one order, one next step. Six stage tiles across the top act
// as the filters, grouped by WHO acts next rather than by database status:
//
//   To price           Order Placed — set item prices and the delivery fee
//   Negotiating        a counter-offer to answer, or a quote with the member
//   Ready to dispatch  Agreed — assign a rider or hand over at the counter
//   Out for delivery   with a rider, or delivered and awaiting the member
//   Cash to remit      cash a rider collected and has not handed in
//   History            completed and cancelled
//
// Below them the orders in that stage, and the selected order in a pane
// (delivery_order_pane.dart) whose action bar always holds the next step.
// On a phone the list is the page, and an order opens as its own screen.
//
// Nothing here writes `sales` or touches stock — the completion RPCs do
// that server-side (v52). Realtime-refreshed via `repository.changes`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/pages/delivery/delivery_order_pane.dart';
import 'package:lzcas/pages/delivery/delivery_orders_parts.dart';
import 'package:lzcas/services/config_service.dart';
import 'package:lzcas/services/ui_prefs.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart';

/// Wider than this, the list and the order pane sit side by side.
const _kSideBySide = 1000.0;

/// On a wide screen every text on the page is this much larger: read at
/// arm's length from a counter PC, the phone sizes were too small (client
/// feedback, 2026-10-02). On top of the person's own text size setting.
const _kDesktopText = 1.2;

class DeliveryOrdersPage extends StatefulWidget {
  const DeliveryOrdersPage({super.key});

  @override
  State<DeliveryOrdersPage> createState() => _DeliveryOrdersPageState();
}

class _DeliveryOrdersPageState extends State<DeliveryOrdersPage> {
  List<DeliveryOrder> _orders = const [];
  List<UserProfile> _riders = const [];

  /// Rider → orders they carry, across every cashier (v62).
  Map<String, Set<String>> _busy = const {};
  CashierLocation? _branch;

  /// Every main cashier's saved store. An admin has no store of their own,
  /// so an order they handle leaves from the one nearest the member.
  List<CashierLocation> _stores = const [];

  bool _loading = true;
  String? _error;
  DateTime? _loadedAt;

  /// Null until the first load picks where the work is.
  OrderStage? _stage;
  String _query = '';
  bool _newestFirst = false;

  /// An order id, or `rider:<id>` for a rider's cash in the Cash stage.
  String? _selected;

  final _search = TextEditingController();
  StreamSubscription<String>? _sub;
  Timer? _tick;

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Which parts this device folded away; redraws when the file lands.
    UiPrefs.instance.addListener(_onPrefs);
    UiPrefs.instance.load();
    _load();
    _sub = repository.changes.listen((e) {
      if (e.startsWith('order_') || e == 'orders_changed') _load();
    });
    // Waiting times and "updated 12 s ago" move on their own. A list that
    // has not loaded for a minute also reloads: a safety net for a missed
    // live update (Part 3: a member's counter-offer not showing).
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final at = _loadedAt;
      if (at != null && DateTime.now().difference(at) >= const Duration(seconds: 60)) {
        _load();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _search.dispose();
    UiPrefs.instance.removeListener(_onPrefs);
    super.dispose();
  }

  Future<void> _load() async {
    final uid = context.read<AuthState>().userId;
    try {
      final orders = await repository.fetchDeliveryOrders();
      // Riders and the branch location only enrich the view; failing to get
      // them must not blank the orders.
      List<UserProfile> riders = _riders;
      try {
        riders = await repository.fetchRiders();
      } catch (_) {}
      final busy = await repository.fetchBusyRiders();
      CashierLocation? branch = _branch;
      if (uid != null) {
        try {
          branch = await repository.fetchCashierLocation(uid);
        } catch (_) {}
      }
      List<CashierLocation> stores = _stores;
      try {
        stores = (await repository.fetchCashierLocations())
            .where((s) => !s.isBranchCashier)
            .toList();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _riders = riders;
        _busy = busy;
        _branch = branch;
        _stores = stores;
        _loading = false;
        _error = null;
        _loadedAt = DateTime.now();
        _stage ??= _defaultStage();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load delivery orders.';
        _loading = false;
      });
    }
  }

  /// The other cashier handling [o], when the viewer may only look at it
  /// (see [OrderStageOf.handledByOther]).
  String? _heldBy(DeliveryOrder o) {
    final auth = context.read<AuthState>();
    return o.handledByOther(me: auth.userId, isAdmin: auth.userRole == UserRole.admin);
  }

  /// Waiting on THIS viewer. Another cashier's order is theirs to move.
  bool _needsMe(DeliveryOrder o) => o.needsCashier && _heldBy(o) == null;

  /// Open on the first stage where the cashier is the one holding things
  /// up; failing that, what is on the road; failing that, history.
  OrderStage _defaultStage() {
    for (final s in [OrderStage.toPrice, OrderStage.negotiating, OrderStage.toDispatch, OrderStage.cash]) {
      if (_inStage(s).any(_needsMe)) return s;
    }
    if (_inStage(OrderStage.onTheWay).isNotEmpty) return OrderStage.onTheWay;
    return OrderStage.toPrice;
  }

  // ── Derived lists ──────────────────────────────────────────────────

  List<DeliveryOrder> _inStage(OrderStage s) =>
      _orders.where((o) => o.stage == s).toList();

  bool _matches(DeliveryOrder o) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      o.memberName,
      o.shortId,
      'del-${o.shortId}',
      o.deliveryName,
      o.deliveryAddress,
    ].any((f) => (f ?? '').toLowerCase().contains(q));
  }

  /// The selected stage's orders, searched and sorted. Work queues default
  /// to oldest first — the one waiting longest is the one to do next;
  /// History to newest first.
  List<DeliveryOrder> get _visible {
    final stage = _stage ?? OrderStage.toPrice;
    final list = _inStage(stage).where(_matches).toList();
    final newest = stage == OrderStage.history ? !_newestFirst : _newestFirst;
    DateTime key(DeliveryOrder o) => o.updatedAt ?? o.createdAt ?? DateTime(2000);
    list.sort((a, b) => newest ? key(b).compareTo(key(a)) : key(a).compareTo(key(b)));
    return list;
  }

  /// Cash-stage rows: one per rider, with the orders whose cash they hold.
  List<({String riderId, String name, List<DeliveryOrder> orders})> get _cashByRider {
    final byRider = <String, List<DeliveryOrder>>{};
    for (final o in _inStage(OrderStage.cash).where(_matches)) {
      byRider.putIfAbsent(o.deliveryId ?? '?', () => []).add(o);
    }
    final rows = [
      for (final e in byRider.entries)
        (
          riderId: e.key,
          name: e.value.first.deliveryName ??
              _riders.where((r) => r.id == e.key).firstOrNull?.username ??
              'Rider',
          orders: e.value,
        ),
    ];
    rows.sort((a, b) => _sum(b.orders).compareTo(_sum(a.orders)));
    return rows;
  }

  static double _sum(List<DeliveryOrder> os) =>
      os.fold(0, (s, o) => s + (o.finalTotal ?? 0));

  /// Riders carrying an order other than [exceptId]: from this list, and
  /// from the server's, which also sees other cashiers' orders (v62).
  Set<String> _busyRiders(String exceptId) => {
    for (final o in _orders)
      if (o.id != exceptId && o.isWithRider && o.deliveryId != null) o.deliveryId!,
    for (final e in _busy.entries)
      if (e.value.any((id) => id != exceptId)) e.key,
  };

  /// The payment details most recently sent on any order (v61), to start
  /// the next one from: the store's GCash number rarely changes.
  String? get _lastPaymentDetails {
    DeliveryOrder? latest;
    for (final o in _orders) {
      if (o.paymentDetailsAt == null) continue;
      if (latest == null || o.paymentDetailsAt!.isAfter(latest.paymentDetailsAt!)) latest = o;
    }
    return latest?.paymentDetails;
  }

  String _m(num? v) => formatMoney(v, symbol: context.read<ConfigService>().currencySymbol);

  // ── Build ──────────────────────────────────────────────────────────

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _text => _dark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
  Color get _body => _dark ? StockpileColors.darkTextMuted : StockpileColors.bodyText;
  Color get _line => _dark ? StockpileColors.darkDivider : StockpileColors.divider;
  Color get _surface => _dark ? StockpileColors.darkSurface : StockpileColors.surface;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= _kSideBySide;
        final pad = wide ? 24.0 : 16.0;

        if (_loading) return const Center(child: CircularProgressIndicator());
        if (_error != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, style: StockpileFonts.satoshi(fontSize: 14, color: _body)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          );
        }

        final page = Padding(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, wide ? 24 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(wide),
              const SizedBox(height: 14),
              wide ? _tiles(wide) : _stagePicker(),
              const SizedBox(height: 14),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (DeliveryFolds.isOpen(DeliveryFolds.list))
                            SizedBox(width: 400, child: _list(wide))
                          else
                            _rail(),
                          const SizedBox(width: 16),
                          Expanded(child: _pane()),
                        ],
                      )
                    : _list(wide),
              ),
            ],
          ),
        );
        if (!wide) return page;
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1) * _kDesktopText),
          ),
          child: page,
        );
      },
    );
  }

  // ── Header ─────────────────────────────────────────────────────────

  Widget _header(bool wide) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Delivery Orders', style: StockpileFonts.satoshi(fontSize: 20, fontWeight: FontWeight.w800, color: _text)),
        const SizedBox(height: 4),
        Text(
          wide
              ? 'Member orders from quote to doorstep. Item prices lock once '
                    'quoted; only the delivery fee is negotiated.'
              : 'Updated ${formatAgo(_loadedAt)}',
          style: StockpileFonts.satoshi(fontSize: 13, color: kCaption),
        ),
      ],
    );

    final search = TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      style: StockpileFonts.satoshi(fontSize: 14, color: _text),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search member, rider or order #',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: _dark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );

    final refresh = IconButton.outlined(
      tooltip: 'Refresh',
      onPressed: _load,
      icon: const Icon(Icons.refresh_rounded, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: _line),
      ),
    );

    if (wide) {
      final summaryOpen = DeliveryFolds.isOpen(DeliveryFolds.summary);
      return Row(
        children: [
          Expanded(
            child: Text(
              'Delivery Orders',
              style: StockpileFonts.satoshi(fontSize: 20, fontWeight: FontWeight.w800, color: _text),
            ),
          ),
          const SizedBox(width: 24),
          Text('Updated ${formatAgo(_loadedAt)}', style: StockpileFonts.satoshi(fontSize: 12, color: kCaption)),
          const SizedBox(width: 10),
          SizedBox(width: 320, child: search),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => DeliveryFolds.toggle(DeliveryFolds.summary),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              foregroundColor: _text,
              side: BorderSide(color: _line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.grid_view_rounded, size: 18),
            label: Text(summaryOpen ? 'Hide summary' : 'Summary'),
          ),
          const SizedBox(width: 10),
          refresh,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [Expanded(child: title), refresh]),
        const SizedBox(height: 12),
        search,
      ],
    );
  }

  // ── Stage tiles ────────────────────────────────────────────────────

  ({String value, String hint, bool urgent}) _tileFacts(OrderStage s) {
    final list = _inStage(s);
    switch (s) {
      case OrderStage.toPrice:
        if (list.isEmpty) return (value: '0', hint: 'Nothing to price', urgent: false);
        final oldest = list.map((o) => o.waiting).reduce((a, b) => a > b ? a : b);
        return (value: '${list.length}', hint: 'Oldest waiting ${formatWaiting(oldest)}', urgent: oldest >= kWaitingTooLong);
      case OrderStage.negotiating:
        final mine = list.where(_needsMe).length;
        final others = list.where((o) => _heldBy(o) != null).length;
        return (
          value: '${list.length}',
          hint: list.isEmpty
              ? 'No open quotes'
              : [
                  '$mine need${mine == 1 ? 's' : ''} you',
                  '${list.length - mine - others} with member',
                  if (others > 0) '$others with other cashiers',
                ].join(' · '),
          urgent: mine > 0,
        );
      case OrderStage.toDispatch:
        return (value: '${list.length}', hint: list.isEmpty ? 'Nothing to send out' : 'Agreed · needs a rider', urgent: list.isNotEmpty);
      case OrderStage.onTheWay:
        final waiting = list.where((o) => o.isDelivered).length;
        return (
          value: '${list.length}',
          hint: list.isEmpty ? 'Nothing on the road' : '${list.length - waiting} on the road · $waiting awaiting member',
          urgent: false,
        );
      case OrderStage.cash:
        final riders = list.map((o) => o.deliveryId).toSet().length;
        return (
          value: _m(_sum(list)),
          hint: list.isEmpty
              ? 'All cash handed in'
              : 'Held by $riders rider${riders == 1 ? '' : 's'} · ${list.length} order${list.length == 1 ? '' : 's'}',
          urgent: list.isNotEmpty,
        );
      case OrderStage.history:
        return (value: '${list.length}', hint: 'Completed and cancelled', urgent: false);
    }
  }

  void _pickStage(OrderStage s) => setState(() {
    _stage = s;
    _selected = null;
  });

  /// Wide screens: the six tiles, or (folded, the default) a row of chips.
  Widget _tiles(bool wide) {
    if (!DeliveryFolds.isOpen(DeliveryFolds.summary)) {
      return Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < OrderStage.values.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _chip(OrderStage.values[i]),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('Orange counts need you', style: StockpileFonts.satoshi(fontSize: 12, color: kCaption)),
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < OrderStage.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: Builder(
              builder: (_) {
                final s = OrderStage.values[i];
                final f = _tileFacts(s);
                return StageTile(
                  stage: s,
                  value: f.value,
                  hint: f.hint,
                  hintUrgent: f.urgent && s != OrderStage.toDispatch,
                  selected: _stage == s,
                  isDark: _dark,
                  onTap: () => _pickStage(s),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  /// Orders in [s] waiting on the cashier.
  int _needsYou(OrderStage s) => s == OrderStage.cash || s == OrderStage.history
      ? 0
      : _inStage(s).where(_needsMe).length;

  /// What a chip or picker row says after the stage's name, when it has no
  /// orange count: how many, or for cash how much.
  String? _stageSuffix(OrderStage s) {
    final list = _inStage(s);
    if (list.isEmpty || s == OrderStage.history) return null;
    if (s == OrderStage.cash) return _m(_sum(list));
    return _needsYou(s) > 0 ? null : '${list.length}';
  }

  Widget _chip(OrderStage s) => StageChip(
    stage: s,
    needsYou: _needsYou(s),
    suffix: _stageSuffix(s),
    selected: _stage == s,
    isDark: _dark,
    onTap: () => _pickStage(s),
  );

  /// "2 more need you: 1 counter-offer, 1 to dispatch", for the stages
  /// other than the one shown; null when nothing else is waiting.
  ({String text, OrderStage first})? get _needsElsewhere {
    final parts = <String>[];
    OrderStage? first;
    var total = 0;
    for (final s in OrderStage.values) {
      if (s == _stage) continue;
      final n = s == OrderStage.cash
          ? _inStage(s).map((o) => o.deliveryId).toSet().length
          : _needsYou(s);
      if (n == 0) continue;
      first ??= s;
      total += n;
      parts.add(switch (s) {
        OrderStage.toPrice => '$n to price',
        OrderStage.negotiating => '$n counter-offer${n == 1 ? '' : 's'}',
        OrderStage.toDispatch => '$n to dispatch',
        OrderStage.cash => '$n rider${n == 1 ? '' : 's'} with cash',
        _ => '$n in ${s.label}',
      });
    }
    if (first == null) return null;
    return (text: '$total more need you: ${parts.join(', ')}', first: first);
  }

  /// Phone: one stage at a time, picked from a sheet, and a line naming
  /// what waits in the others.
  Widget _stagePicker() {
    final stage = _stage ?? OrderStage.toPrice;
    final count = stage == OrderStage.cash
        ? _cashByRider.length
        : _inStage(stage).length;
    final elsewhere = _needsElsewhere;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: _dark ? StockpileColors.primary900.withAlpha(30) : StockpileColors.primary50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: StockpileColors.primary900, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _openStageSheet,
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(color: stage.dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${stage.label} · $count',
                        style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w700, color: _text),
                      ),
                    ),
                    Text('Change stage', style: StockpileFonts.satoshi(fontSize: 12, color: _body)),
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more_rounded, size: 20, color: _body),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (elsewhere != null) ...[
          const SizedBox(height: 8),
          Material(
            color: _dark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _pickStage(elsewhere.first),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          elsewhere.text,
                          style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w600, color: _text),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 20, color: _body),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openStageSheet() async {
    final picked = await showModalBottomSheet<OrderStage>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in OrderStage.values)
              ListTile(
                minTileHeight: 52,
                selected: s == _stage,
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: s.dot, shape: BoxShape.circle),
                ),
                title: Text(s.label, style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: Text(_tileFacts(s).hint, style: StockpileFonts.satoshi(fontSize: 12, color: kCaption)),
                trailing: _needsYou(s) > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCC4900),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          '${_needsYou(s)}',
                          style: StockpileFonts.satoshi(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      )
                    : Text(_tileFacts(s).value, style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) _pickStage(picked);
  }

  // ── The list ───────────────────────────────────────────────────────

  /// The rows of the shown stage. On a wide screen it also keeps a
  /// selection, so the pane is never empty while there is something to show.
  ({
    bool isCash,
    List<DeliveryOrder> orders,
    List<({String riderId, String name, List<DeliveryOrder> orders})> cash,
  }) _rows(bool wide) {
    final isCash = (_stage ?? OrderStage.toPrice) == OrderStage.cash;
    final orders = isCash ? const <DeliveryOrder>[] : _visible;
    final cash = isCash ? _cashByRider : const <({String riderId, String name, List<DeliveryOrder> orders})>[];
    if (wide && (isCash ? cash.isNotEmpty : orders.isNotEmpty)) {
      final ids = isCash ? cash.map((r) => 'rider:${r.riderId}') : orders.map((o) => o.id);
      if (_selected == null || !ids.contains(_selected)) {
        _selected = ids.first;
      }
    }
    return (isCash: isCash, orders: orders, cash: cash);
  }

  Widget _list(bool wide) {
    final stage = _stage ?? OrderStage.toPrice;
    final (:isCash, :orders, :cash) = _rows(wide);
    final count = isCash ? cash.length : orders.length;

    final heading = switch (stage) {
      OrderStage.toPrice => '$count to price',
      OrderStage.negotiating => '$count in negotiation',
      OrderStage.toDispatch => '$count ready to dispatch',
      OrderStage.onTheWay => '$count out for delivery',
      OrderStage.cash => '$count rider${count == 1 ? '' : 's'} holding cash',
      OrderStage.history => '$count in history',
    };

    // Work waiting in OTHER stages, so a cashier focused on one queue does
    // not miss a counter-offer sitting in the next.
    final elsewhere = OrderStage.values
        .where((s) => s != stage && s != OrderStage.history)
        .map((s) => (s, _inStage(s).where(_needsMe).length))
        .where((e) => e.$2 > 0)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
            child: Row(
              children: [
                Expanded(child: Text(heading, style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: _text))),
                if (!isCash)
                  TextButton.icon(
                    onPressed: () => setState(() => _newestFirst = !_newestFirst),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      foregroundColor: _body,
                    ),
                    icon: const Icon(Icons.swap_vert_rounded, size: 18),
                    label: Text(
                      (stage == OrderStage.history) != _newestFirst ? 'Newest first' : 'Oldest first',
                      style: StockpileFonts.satoshi(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (wide)
                  IconButton(
                    tooltip: 'Hide the list',
                    onPressed: () => DeliveryFolds.toggle(DeliveryFolds.list),
                    icon: Icon(Icons.keyboard_double_arrow_left_rounded, size: 20, color: _body),
                  ),
              ],
            ),
          ),
          Expanded(
            child: count == 0
                ? _empty(stage)
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: count,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (_, i) => isCash
                        ? _cashRow(cash[i], wide)
                        : _orderRow(orders[i], wide),
                  ),
          ),
          // A phone says this above the list, under the stage picker.
          if (elsewhere != null && wide)
            Material(
              color: _dark ? StockpileColors.secondary500.withAlpha(30) : StockpileColors.secondary50,
              child: InkWell(
                onTap: () => _pickStage(elsewhere.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Also needs you: ${elsewhere.$2} in ${elsewhere.$1.label}',
                          style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w600, color: StockpileColors.secondary500),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: 18, color: StockpileColors.secondary500),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The list folded to a narrow rail of initials, so the open order gets
  /// the width. Each one still opens its order; hover says who it is.
  Widget _rail() {
    final stage = _stage ?? OrderStage.toPrice;
    final (:isCash, :orders, :cash) = _rows(true);

    Widget dot({
      required String id,
      required String tooltip,
      required Widget child,
      bool needsYou = false,
    }) {
      final selected = _selected == id;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Tooltip(
          message: tooltip,
          child: Semantics(
            button: true,
            selected: selected,
            label: tooltip,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _selected = id),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? (_dark ? StockpileColors.primary900.withAlpha(30) : StockpileColors.primary50)
                          : (_dark ? StockpileColors.darkInputBg : StockpileColors.inputBg),
                      border: Border.all(
                        color: selected ? stage.dot : _line,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: ExcludeSemantics(child: child),
                  ),
                  if (needsYou)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCC4900),
                          shape: BoxShape.circle,
                          border: Border.all(color: _surface, width: 2),
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

    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          IconButton.filledTonal(
            tooltip: 'Show the list',
            onPressed: () => DeliveryFolds.toggle(DeliveryFolds.list),
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 20),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SizedBox(width: 32, child: Divider(height: 1, color: _line)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Center(
                  child: Column(
                    children: [
                      if (isCash)
                        for (final r in cash)
                          dot(
                            id: 'rider:${r.riderId}',
                            tooltip: '${r.name} · ${_m(_sum(r.orders))}',
                            needsYou: true,
                            child: const Icon(Icons.two_wheeler_rounded, size: 20, color: kOrangeText),
                          )
                      else
                        for (final o in orders)
                          dot(
                            id: o.id,
                            tooltip: '${o.memberName ?? 'Member order'} · ${_rowFacts(o).$1}',
                            needsYou: _needsMe(o),
                            child: Text(
                              _initials(o.memberName),
                              style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w700, color: _text),
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

  Widget _empty(OrderStage stage) {
    final text = _query.trim().isNotEmpty
        ? 'No matches for "${_query.trim()}".'
        : switch (stage) {
            OrderStage.toPrice => 'No orders waiting for a price.',
            OrderStage.negotiating => 'No quotes out right now.',
            OrderStage.toDispatch => 'Nothing waiting to be sent out.',
            OrderStage.onTheWay => 'No orders on the road.',
            OrderStage.cash => 'Every rider has handed in their cash.',
            OrderStage.history => 'No completed or cancelled orders yet.',
          };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: kCaption),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: StockpileFonts.satoshi(fontSize: 13, color: _body)),
          ],
        ),
      ),
    );
  }

  String _initials(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  /// What the right-hand side of a row says, by stage — the one fact that
  /// decides which order to open next.
  (String, String?, bool) _rowFacts(DeliveryOrder o) {
    // Another cashier's quote or dispatch: who has it, not what it needs.
    final held = _heldBy(o);
    if (held != null && (o.stage == OrderStage.negotiating || o.stage == OrderStage.toDispatch)) {
      final who = held == 'another cashier' ? held : held.split(RegExp(r'\s+')).first;
      return ('With $who', formatWaiting(o.waiting), false);
    }
    switch (o.stage) {
      case OrderStage.toDispatch when !_needsMe(o):
        return ('With member', o.isCourier ? 'to pay · ${o.routeLabel}' : 'to pay', false);
      case OrderStage.toPrice || OrderStage.toDispatch:
        return (formatWaiting(o.waiting), 'waiting', o.waiting >= kWaitingTooLong);
      case OrderStage.negotiating:
        return _needsMe(o)
            ? (formatWaiting(o.waiting), 'countered', o.waiting >= kWaitingTooLong)
            : ('With member', formatWaiting(o.waiting), false);
      case OrderStage.onTheWay:
        return switch (o.status) {
          DeliveryOrderStatus.assigned => ('Pickup', o.deliveryName, false),
          DeliveryOrderStatus.pickedUp =>
            (o.etaAt == null ? 'On the way' : 'ETA ${formatTimeOfDay(o.etaAt)}', o.deliveryName, false),
          DeliveryOrderStatus.shipped => ('Shipped', '${o.routeLabel} · ${formatWaiting(o.waiting)}', false),
          _ => ('Awaiting member', formatWaiting(o.waiting), false),
        };
      case OrderStage.cash:
        return (_m(o.finalTotal), null, false);
      case OrderStage.history:
        return (o.isCancelled ? 'Cancelled' : _m(o.finalTotal), formatRelativeDate(o.updatedAt ?? o.createdAt), false);
    }
  }

  Widget _orderRow(DeliveryOrder o, bool wide) {
    final selected = wide && _selected == o.id;
    final (main, sub, urgent) = _rowFacts(o);
    final n = o.items.length;
    final place = (o.deliveryAddress ?? '').split(',').take(2).join(',').trim();

    return Material(
      color: selected
          ? (_dark ? StockpileColors.primary900.withAlpha(30) : StockpileColors.primary50)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => wide ? setState(() => _selected = o.id) : _openOrder(o),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: selected ? _surface : (_dark ? StockpileColors.darkInputBg : StockpileColors.inputBg),
                child: Text(_initials(o.memberName), style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w700, color: _body)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.memberName ?? 'Member order',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: _text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '$n item${n == 1 ? '' : 's'}',
                        if (place.isNotEmpty) place,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StockpileFonts.satoshi(fontSize: 12, color: kCaption),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    main,
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: urgent ? kOrangeText : _body,
                    ),
                  ),
                  if (sub != null && sub.isNotEmpty)
                    Text(sub, style: StockpileFonts.satoshi(fontSize: 11, color: kCaption)),
                ],
              ),
              if (!wide) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 20, color: kCaption),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cashRow(({String riderId, String name, List<DeliveryOrder> orders}) r, bool wide) {
    final id = 'rider:${r.riderId}';
    final selected = wide && _selected == id;
    final oldest = r.orders.map((o) => o.paidAt).whereType<DateTime>().fold<DateTime?>(
      null,
      (a, b) => a == null || b.isBefore(a) ? b : a,
    );
    return Material(
      color: selected
          ? (_dark ? StockpileColors.primary900.withAlpha(30) : StockpileColors.primary50)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => wide ? setState(() => _selected = id) : _openCash(r.name, r.riderId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFFB24800),
                child: Icon(Icons.two_wheeler_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: _text)),
                    const SizedBox(height: 2),
                    Text(
                      '${r.orders.length} order${r.orders.length == 1 ? '' : 's'}'
                      '${oldest == null ? '' : ' · oldest ${formatAgo(oldest)}'}',
                      style: StockpileFonts.satoshi(fontSize: 12, color: kCaption),
                    ),
                  ],
                ),
              ),
              Text(_m(_sum(r.orders)), style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w800, color: _text)),
              if (!wide) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 20, color: kCaption),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── The pane (wide) ────────────────────────────────────────────────

  Widget _pane() {
    final sel = _selected;
    if (sel != null && sel.startsWith('rider:')) {
      final riderId = sel.substring(6);
      final r = _cashByRider.where((x) => x.riderId == riderId).firstOrNull;
      if (r != null) {
        return CashRemitPane(
          key: ValueKey(sel),
          riderName: r.name,
          orders: r.orders,
          onChanged: _load,
        );
      }
    }
    final o = _orders.where((x) => x.id == sel).firstOrNull;
    if (o == null) {
      return Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
        ),
        alignment: Alignment.center,
        child: Text('Select an order to see it here.', style: StockpileFonts.satoshi(fontSize: 14, color: _body)),
      );
    }
    // Keyed on the status too: a new stage is a new form, and typed-in
    // prices from one stage must never leak into the next.
    return DeliveryOrderPane(
      key: ValueKey('${o.id}|${o.status}'),
      order: o,
      riders: _riders,
      branch: _branch,
      stores: _stores,
      busyRiderIds: _busyRiders(o.id),
      lastPaymentDetails: _lastPaymentDetails,
      onChanged: _load,
    );
  }

  // ── Phone: an order is its own screen ──────────────────────────────

  void _openOrder(DeliveryOrder o) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _OrderScreen(
          orderId: o.id,
          initial: o,
          riders: _riders,
          branch: _branch,
          stores: _stores,
          busyRiderIds: _busyRiders(o.id),
          lastPaymentDetails: _lastPaymentDetails,
        ),
      ),
    );
  }

  void _openCash(String name, String riderId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CashScreen(riderName: name, riderId: riderId),
      ),
    );
  }
}

/// One order, full screen, on a phone. Follows realtime like the page does.
class _OrderScreen extends StatefulWidget {
  final String orderId;
  final DeliveryOrder initial;
  final List<UserProfile> riders;
  final CashierLocation? branch;
  final List<CashierLocation> stores;
  final Set<String> busyRiderIds;
  final String? lastPaymentDetails;

  const _OrderScreen({
    required this.orderId,
    required this.initial,
    required this.riders,
    required this.branch,
    required this.stores,
    required this.busyRiderIds,
    this.lastPaymentDetails,
  });

  @override
  State<_OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<_OrderScreen> {
  late DeliveryOrder _order = widget.initial;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = repository.changes.listen((e) {
      if (e.startsWith('order_') || e == 'orders_changed') _reload();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final all = await repository.fetchDeliveryOrders();
      final fresh = all.where((o) => o.id == widget.orderId).firstOrNull;
      if (fresh != null && mounted) setState(() => _order = fresh);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Order ${_order.shortId}')),
      body: SafeArea(
        top: false,
        child: DeliveryOrderPane(
          key: ValueKey('${_order.id}|${_order.status}'),
          order: _order,
          riders: widget.riders,
          branch: widget.branch,
          stores: widget.stores,
          busyRiderIds: widget.busyRiderIds,
          lastPaymentDetails: widget.lastPaymentDetails,
          onChanged: _reload,
          compact: true,
        ),
      ),
    );
  }
}

/// One rider's cash, full screen, on a phone.
class _CashScreen extends StatefulWidget {
  final String riderName;
  final String riderId;

  const _CashScreen({required this.riderName, required this.riderId});

  @override
  State<_CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<_CashScreen> {
  List<DeliveryOrder> _orders = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final all = await repository.fetchDeliveryOrders();
      if (!mounted) return;
      final mine = all.where((o) => o.awaitingRemittance && o.deliveryId == widget.riderId).toList();
      // Everything handed in: nothing left to show here.
      if (mine.isEmpty) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() => _orders = mine);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cash to remit')),
      body: SafeArea(
        top: false,
        child: _orders.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : CashRemitPane(
                riderName: widget.riderName,
                orders: _orders,
                onChanged: _reload,
                compact: true,
              ),
      ),
    );
  }
}
