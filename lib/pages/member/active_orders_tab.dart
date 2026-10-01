// lib/pages/member/active_orders_tab.dart
//
// The member's orders ("Active Orders" and "Past orders" in the Member
// Shop & Orders design). Two tabs: what is still going on, and what has
// finished. Active orders that are waiting on the member come first, under
// "Needs you"; the rest are "In progress". Each card says where the order
// stands in one line and, when there is one, offers the next step; tapping
// it opens the order's own screen (member_order_detail_page.dart), which
// has everything else. Realtime-refreshed.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/db.dart';
import '../../services/config_service.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart'
    show formatMoney, formatRelativeDate, formatTimeOfDay;
import 'member_order_detail_page.dart';
import 'member_order_kit.dart';

class ActiveOrdersTab extends StatefulWidget {
  final Member member;

  /// Opens the Marketplace, from the empty state.
  final VoidCallback? onShop;

  const ActiveOrdersTab({super.key, required this.member, this.onShop});

  @override
  State<ActiveOrdersTab> createState() => _ActiveOrdersTabState();
}

class _ActiveOrdersTabState extends State<ActiveOrdersTab> {
  List<DeliveryOrder> _orders = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<String>? _sub;

  /// The order an action is running on, so only its buttons wait.
  String? _busy;
  bool _past = false;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = repository.changes.listen((event) {
      if (event.startsWith('order_') || event == 'orders_changed') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final memberId = widget.member.id;
    if (memberId == null) return;
    try {
      final orders = await repository.fetchDeliveryOrders(memberId: memberId);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your orders.';
        _loading = false;
      });
    }
  }

  Future<void> _act(
    DeliveryOrder order,
    Future<bool> Function(BuildContext, DeliveryOrder) action,
  ) async {
    if (_busy != null) return;
    setState(() => _busy = order.id);
    final changed = await action(context, order);
    if (!mounted) return;
    setState(() => _busy = null);
    if (changed) await _load();
  }

  Future<void> _open(DeliveryOrder order) async {
    final memberId = widget.member.id;
    if (memberId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MemberOrderDetailPage(initial: order, memberId: memberId),
      ),
    );
    if (mounted) _load();
  }

  String _m(num? v) =>
      formatMoney(v, symbol: context.read<ConfigService>().currencySymbol);

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = ShopColors.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: StockpileFonts.satoshi(color: c.muted)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final active = _orders.where((o) => !o.isPast).toList();
    final past = _orders.where((o) => o.isPast).toList();

    return ColoredBox(
      color: c.ground,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text('Active · ${active.length}'),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Past · ${past.length}'),
                      ),
                    ],
                    selected: {_past},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _past = s.first),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: _past ? _pastList(c, past) : _activeList(c, active),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(ShopColors c, String title, String body, {bool shop = false}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
      children: [
        Icon(Icons.local_shipping_outlined, size: 48, color: c.muted),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: StockpileFonts.satoshi(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          textAlign: TextAlign.center,
          style: StockpileFonts.satoshi(fontSize: 13, color: c.muted),
        ),
        if (shop && widget.onShop != null) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: widget.onShop,
              icon: const Icon(Icons.storefront_rounded, size: 18),
              label: const Text('Go to the Marketplace'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _heading(ShopColors c, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Text(
      text,
      style: StockpileFonts.satoshi(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: c.muted,
      ),
    ),
  );

  Widget _activeList(ShopColors c, List<DeliveryOrder> active) {
    if (active.isEmpty) {
      return _empty(
        c,
        'No orders on the way',
        'Orders you place in the Marketplace show up here.',
        shop: true,
      );
    }
    final needs = active.where((o) => o.memberMustAct).toList();
    final rest = active.where((o) => !o.memberMustAct).toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (needs.isNotEmpty) ...[
          _heading(c, 'Needs you · ${needs.length}'),
          for (final o in needs) ...[
            _activeCard(c, o),
            const SizedBox(height: 12),
          ],
        ],
        if (rest.isNotEmpty) ...[
          _heading(c, 'In progress · ${rest.length}'),
          for (final o in rest) ...[
            _activeCard(c, o),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }

  Widget _pastList(ShopColors c, List<DeliveryOrder> past) {
    if (past.isEmpty) {
      return _empty(
        c,
        'No past orders yet',
        'Completed and cancelled orders show up here.',
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final o in past) ...[_pastCard(c, o), const SizedBox(height: 12)],
      ],
    );
  }

  // ── Cards ──────────────────────────────────────────────────────────

  Widget _cardHead(ShopColors c, DeliveryOrder o, String sub) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order ${o.shortId}',
              style: StockpileFonts.satoshi(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: StockpileFonts.satoshi(fontSize: 12, color: c.muted),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      OrderPill(o),
    ],
  );

  String _placed(DeliveryOrder o) {
    final n = o.itemCount;
    return 'Placed ${formatRelativeDate(o.createdAt).toLowerCase()}, '
        '${formatTimeOfDay(o.createdAt)} · $n item${n == 1 ? '' : 's'}';
  }

  Widget _activeCard(ShopColors c, DeliveryOrder o) {
    final busy = _busy == o.id;
    return ShopCard(
      onTap: () => _open(o),
      borderColor: o.memberMustAct ? c.accent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHead(c, o, _placed(o)),
          const SizedBox(height: 12),
          ..._activeBody(c, o, busy),
        ],
      ),
    );
  }

  List<Widget> _activeBody(ShopColors c, DeliveryOrder o, bool busy) {
    final total = _m(o.finalTotal);
    final rider = o.deliveryName ?? 'Your rider';
    Widget button(
      String label,
      IconData icon,
      Future<bool> Function(BuildContext, DeliveryOrder) action,
    ) => SizedBox(
      height: 44,
      child: FilledButton.icon(
        onPressed: busy || _busy != null ? null : () => _act(o, action),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 18),
        label: Text(label),
      ),
    );
    Widget link(String label) => Row(
      children: [
        Text(
          label,
          style: StockpileFonts.satoshi(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: c.accentText,
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.arrow_forward_rounded, size: 18, color: c.accentText),
      ],
    );

    switch (o.status) {
      case DeliveryOrderStatus.orderPlaced:
        return [
          OrderProgressBars(o),
          const SizedBox(height: 10),
          Text(
            "The cashier will send prices soon. You'll get an alert.",
            style: StockpileFonts.satoshi(fontSize: 13, color: c.muted),
          ),
        ];
      case DeliveryOrderStatus.cashierPricing:
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total to agree',
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        color: c.muted,
                      ),
                    ),
                    Text(
                      _m((o.itemsTotal ?? 0) + (o.deliveryFee ?? 0)),
                      style: StockpileFonts.satoshi(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Items ${_m(o.itemsTotal)}\n'
                '${o.isCourier ? 'Shipping' : 'Delivery'} ${_m(o.deliveryFee)}',
                textAlign: TextAlign.right,
                style: StockpileFonts.satoshi(
                  fontSize: 12,
                  height: 1.5,
                  color: c.muted,
                ),
              ),
            ],
          ),
          if (o.isCourier) ...[
            const SizedBox(height: 8),
            OrderFact(
              Icons.local_shipping_outlined,
              'Sent by ${o.routeLabel}. No cash on delivery.',
            ),
          ],
          const SizedBox(height: 12),
          link('Review the price'),
        ];
      case DeliveryOrderStatus.memberNegotiating:
        return [
          OrderFact(
            Icons.swap_horiz_rounded,
            'You offered ${_m(o.deliveryFee)} for ${o.isCourier ? 'shipping' : 'delivery'}. Waiting for the cashier to reply.',
          ),
        ];
      case DeliveryOrderStatus.agreed:
        if (o.isPaid) {
          return [
            OrderProgressBars(o),
            const SizedBox(height: 10),
            OrderFact(
              Icons.verified_rounded,
              o.isCourier
                  ? 'Paid. The store is booking it with ${o.routeLabel}.'
                  : 'Paid. The store is getting it ready.',
            ),
          ];
        }
        if (o.isCod) {
          return [
            OrderProgressBars(o),
            const SizedBox(height: 10),
            OrderFact(
              Icons.payments_outlined,
              'Cash on delivery · have $total ready. The store sends it soon.',
            ),
          ];
        }
        if (o.isOutside) {
          final rejected = (o.paymentRejectedNote ?? '').trim();
          if (o.paymentDetailsAt == null) {
            return [
              OrderFact(
                Icons.hourglass_top_rounded,
                'You chose to pay outside the app. The store will send where to pay.',
              ),
            ];
          }
          if (o.paymentSentAt != null) {
            return [
              OrderFact(
                Icons.mark_email_read_outlined,
                'You said you sent $total. Waiting for the store to confirm.',
              ),
            ];
          }
          return [
            if (rejected.isNotEmpty) ...[
              OrderFact(
                Icons.error_outline_rounded,
                'The store could not confirm your last payment: $rejected',
                color: const Color(0xFFB91C1C),
              ),
              const SizedBox(height: 10),
            ],
            OrderFact(
              Icons.payments_outlined,
              'Send $total outside the app, then tell the store.',
            ),
            const SizedBox(height: 12),
            link('See where to pay'),
          ];
        }
        return [
          Text(
            'Total $total',
            style: StockpileFonts.satoshi(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const SizedBox(height: 10),
          button(
            'Choose how to pay',
            Icons.payments_rounded,
            MemberOrderActions.pay,
          ),
        ];
      case DeliveryOrderStatus.assigned:
      case DeliveryOrderStatus.pickedUp:
        return [
          OrderProgressBars(o),
          const SizedBox(height: 10),
          OrderFact(
            Icons.two_wheeler_rounded,
            o.isPickedUp
                ? (o.etaAt == null
                      ? '$rider is on the way.'
                      : 'Arriving about ${formatTimeOfDay(o.etaAt)} · $rider')
                : '$rider will bring your order.',
          ),
          if (!o.isPaid) ...[
            const SizedBox(height: 8),
            OrderFact(
              Icons.payments_outlined,
              o.isCod
                  ? 'Cash on delivery · have $total ready'
                  : 'Not paid yet · pay the rider $total in cash',
            ),
          ],
        ];
      case DeliveryOrderStatus.delivered:
        return [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Did you get it? ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text:
                      '${o.deliveryName ?? 'The rider'} handed it over at '
                      '${formatTimeOfDay(o.deliveredAt)}. Confirm so the order can close.',
                ),
              ],
            ),
            style: StockpileFonts.satoshi(
              fontSize: 13,
              height: 1.45,
              color: c.text,
            ),
          ),
          const SizedBox(height: 12),
          button(
            'Yes, I received it',
            Icons.check_circle_rounded,
            MemberOrderActions.confirmReceived,
          ),
        ];
      case DeliveryOrderStatus.shipped:
        final tracking = (o.trackingNumber ?? '').trim();
        return [
          OrderProgressBars(o),
          const SizedBox(height: 10),
          OrderFact(
            Icons.local_shipping_rounded,
            'Sent by ${o.routeLabel}${tracking.isEmpty ? '' : ' · tracking $tracking'}',
          ),
          const SizedBox(height: 12),
          button(
            'I received it',
            Icons.check_circle_rounded,
            MemberOrderActions.confirmReceived,
          ),
        ];
      default:
        return const [];
    }
  }

  Widget _pastCard(ShopColors c, DeliveryOrder o) {
    final n = o.itemCount;
    final items = '$n item${n == 1 ? '' : 's'}';
    final when = formatRelativeDate(o.confirmedAt ?? o.updatedAt);
    final how = o.isCourier ? 'Received' : 'Delivered';
    final line = o.isCancelled
        ? 'Cancelled $when · $items'
        : o.confirmationMethod == null
        ? 'Picked up $when · $items'
        : '$how $when · $items';

    final paid = switch (o.paymentMethod) {
      'cod' => 'Paid in cash to the rider',
      'counter' => 'Paid at the counter',
      'outside' => 'Paid outside the app',
      'funds' => 'Paid from your funds',
      _ => null,
    };
    final closed = switch (o.confirmationMethod) {
      OrderConfirmation.memberTap => 'you confirmed it arrived',
      OrderConfirmation.qr => 'the rider scanned your code',
      OrderConfirmation.cashierOverride => 'closed by the store',
      _ => null,
    };
    final why = (o.cancelReason ?? '').trim();

    return ShopCard(
      onTap: () => _open(o),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order ${o.shortId}',
                  style: StockpileFonts.satoshi(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
              OrderPill(o),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  line,
                  style: StockpileFonts.satoshi(fontSize: 13, color: c.muted),
                ),
              ),
              if (o.finalTotal != null)
                Text(
                  _m(o.finalTotal),
                  style: StockpileFonts.satoshi(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
            ],
          ),
          if (o.isCompleted && (paid != null || closed != null)) ...[
            const SizedBox(height: 6),
            Text(
              [?paid, ?closed].join(' · '),
              style: StockpileFonts.satoshi(fontSize: 13, color: c.text),
            ),
          ],
          if (o.isCancelled) ...[
            const SizedBox(height: 6),
            Text(
              why.isEmpty ? 'No reason given' : 'Reason: $why',
              style: StockpileFonts.satoshi(fontSize: 13, color: c.text),
            ),
            if (o.isRefunded) ...[
              const SizedBox(height: 8),
              OrderFact(
                Icons.undo_rounded,
                '${_m(o.finalTotal)} was returned to your funds',
                color: const Color(0xFF15803D),
              ),
            ] else if (o.isOutside && o.isPaid) ...[
              const SizedBox(height: 8),
              OrderFact(
                Icons.undo_rounded,
                'You paid outside the app; the store refunds you the same way.',
              ),
            ] else if (!o.isPaid) ...[
              const SizedBox(height: 4),
              Text(
                'Nothing was paid',
                style: StockpileFonts.satoshi(fontSize: 12, color: c.muted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
