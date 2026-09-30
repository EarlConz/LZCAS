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
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart';

/// Wider than this, the list and the order pane sit side by side.
const _kSideBySide = 1000.0;

class DeliveryOrdersPage extends StatefulWidget {
  const DeliveryOrdersPage({super.key});

  @override
  State<DeliveryOrdersPage> createState() => _DeliveryOrdersPageState();
}

class _DeliveryOrdersPageState extends State<DeliveryOrdersPage> {
  List<DeliveryOrder> _orders = const [];
  List<UserProfile> _riders = const [];
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

  @override
  void initState() {
    super.initState();
    _load();
    _sub = repository.changes.listen((e) {
      if (e.startsWith('order_') || e == 'orders_changed') _load();
    });
    // Waiting times and "updated 12 s ago" move on their own.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _search.dispose();
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

  /// Open on the first stage where the cashier is the one holding things
  /// up; failing that, what is on the road; failing that, history.
  OrderStage _defaultStage() {
    for (final s in [OrderStage.toPrice, OrderStage.negotiating, OrderStage.toDispatch, OrderStage.cash]) {
      if (_inStage(s).any((o) => o.needsCashier)) return s;
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

  /// Riders carrying an order other than [exceptId].
  Set<String> _busyRiders(String exceptId) => {
    for (final o in _orders)
      if (o.id != exceptId && o.isWithRider && o.deliveryId != null) o.deliveryId!,
  };

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

        return Padding(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, wide ? 24 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(wide),
              const SizedBox(height: 14),
              _tiles(wide),
              const SizedBox(height: 14),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 400, child: _list(wide)),
                          const SizedBox(width: 16),
                          Expanded(child: _pane()),
                        ],
                      )
                    : _list(wide),
              ),
            ],
          ),
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
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: title),
          const SizedBox(width: 24),
          Text('Updated ${formatAgo(_loadedAt)}', style: StockpileFonts.satoshi(fontSize: 12, color: kCaption)),
          const SizedBox(width: 10),
          SizedBox(width: 320, child: search),
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
        final mine = list.where((o) => o.needsCashier).length;
        return (
          value: '${list.length}',
          hint: list.isEmpty ? 'No open quotes' : '$mine need${mine == 1 ? 's' : ''} you · ${list.length - mine} with member',
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

  Widget _tiles(bool wide) {
    Widget tile(OrderStage s, {bool compact = false}) {
      final f = _tileFacts(s);
      return StageTile(
        stage: s,
        value: f.value,
        hint: f.hint,
        hintUrgent: f.urgent && s != OrderStage.toDispatch,
        selected: _stage == s,
        compact: compact,
        isDark: _dark,
        onTap: () => _pickStage(s),
      );
    }

    if (wide) {
      return Row(
        children: [
          for (var i = 0; i < OrderStage.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: tile(OrderStage.values[i])),
          ],
        ],
      );
    }
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: OrderStage.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => SizedBox(width: 128, child: tile(OrderStage.values[i], compact: true)),
      ),
    );
  }

  // ── The list ───────────────────────────────────────────────────────

  Widget _list(bool wide) {
    final stage = _stage ?? OrderStage.toPrice;
    final isCash = stage == OrderStage.cash;
    final orders = isCash ? const <DeliveryOrder>[] : _visible;
    final cash = isCash ? _cashByRider : const <({String riderId, String name, List<DeliveryOrder> orders})>[];
    final count = isCash ? cash.length : orders.length;

    // Keep a selection on a wide screen so the pane is never empty while
    // there is something to show.
    if (wide && count > 0) {
      final ids = isCash ? cash.map((r) => 'rider:${r.riderId}') : orders.map((o) => o.id);
      if (_selected == null || !ids.contains(_selected)) {
        _selected = ids.first;
      }
    }

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
        .map((s) => (s, _inStage(s).where((o) => o.needsCashier).length))
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
          if (elsewhere != null)
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
    switch (o.stage) {
      case OrderStage.toPrice || OrderStage.toDispatch:
        return (formatWaiting(o.waiting), 'waiting', o.waiting >= kWaitingTooLong);
      case OrderStage.negotiating:
        return o.needsCashier
            ? (formatWaiting(o.waiting), 'countered', o.waiting >= kWaitingTooLong)
            : ('With member', formatWaiting(o.waiting), false);
      case OrderStage.onTheWay:
        return switch (o.status) {
          DeliveryOrderStatus.assigned => ('Pickup', o.deliveryName, false),
          DeliveryOrderStatus.pickedUp =>
            (o.etaAt == null ? 'On the way' : 'ETA ${formatTimeOfDay(o.etaAt)}', o.deliveryName, false),
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

  const _OrderScreen({
    required this.orderId,
    required this.initial,
    required this.riders,
    required this.branch,
    required this.stores,
    required this.busyRiderIds,
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
