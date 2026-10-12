// lib/pages/member/member_order_detail_page.dart
//
// One order, as the member sees it ("Review the quote" and "On the way" in
// the Member Shop & Orders design): what it is, how far along, what it
// costs, how it is paid, where it goes, and the one thing to do next in a
// bar at the bottom. Follows the order live: it reloads on every order
// change, so a quote or a rider's move appears without leaving the screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/db.dart';
import '../../services/config_service.dart';
import '../../theme.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart'
    show formatAgo, formatMoney, formatRelativeDate, formatTimeOfDay;
import 'member_order_kit.dart';

class MemberOrderDetailPage extends StatefulWidget {
  final DeliveryOrder initial;
  final int memberId;

  const MemberOrderDetailPage({
    super.key,
    required this.initial,
    required this.memberId,
  });

  @override
  State<MemberOrderDetailPage> createState() => _MemberOrderDetailPageState();
}

class _MemberOrderDetailPageState extends State<MemberOrderDetailPage> {
  late DeliveryOrder _o = widget.initial;
  List<DeliveryFeeOffer> _offers = const [];
  StreamSubscription<String>? _sub;
  bool _busy = false;

  /// A safety net while a rider is on the way: the arrival time changes
  /// without the member doing anything, and a missed live update would
  /// leave an old time on screen (test O3).
  Timer? _onTheWay;

  @override
  void initState() {
    super.initState();
    _loadOffers();
    _sub = repository.changes.listen((e) {
      if (e.startsWith('order_') || e == 'orders_changed') _reload();
    });
    _onTheWay = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_o.isAssigned || _o.isPickedUp) _reload();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _onTheWay?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final all = await repository.fetchDeliveryOrders(
        memberId: widget.memberId,
      );
      final fresh = all.where((o) => o.id == _o.id).firstOrNull;
      if (!mounted || fresh == null) return;
      final feeMoved =
          fresh.deliveryFee != _o.deliveryFee || fresh.status != _o.status;
      setState(() => _o = fresh);
      if (feeMoved) _loadOffers();
    } catch (_) {}
  }

  Future<void> _loadOffers() async {
    if (_o.itemsTotal == null) return;
    final offers = await repository.fetchFeeOffers(_o.id);
    if (mounted) setState(() => _offers = offers);
  }

  Future<void> _act(
    Future<bool> Function(BuildContext, DeliveryOrder) action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    final changed = await action(context, _o);
    if (!mounted) return;
    setState(() => _busy = false);
    if (changed) await _reload();
  }

  String _m(num? v) =>
      formatMoney(v, symbol: context.read<ConfigService>().currencySymbol);

  // ── The words ──────────────────────────────────────────────────────

  String get _feeName =>
      _o.isCourier ? 'Shipping fee · ${_o.routeLabel}' : 'Delivery fee';

  String get _heading => switch (_o.status) {
    DeliveryOrderStatus.orderPlaced => 'Waiting for prices',
    DeliveryOrderStatus.cashierPricing => 'Review the price',
    DeliveryOrderStatus.memberNegotiating => 'Your offer was sent',
    DeliveryOrderStatus.agreed =>
      _o.isPaid
          ? (_o.isCourier ? 'Paid · being booked' : 'Paid · being prepared')
          : _o.isCod
          ? 'Cash on delivery'
          : _o.isOutside
          ? 'Pay outside the app'
          : 'Choose how to pay',
    DeliveryOrderStatus.assigned => 'A rider is coming',
    DeliveryOrderStatus.pickedUp =>
      _o.etaAt == null
          ? 'On the way'
          : 'Arriving about ${formatTimeOfDay(_o.etaAt)}',
    DeliveryOrderStatus.delivered => 'Did you get it?',
    DeliveryOrderStatus.shipped => 'Sent by ${_o.routeLabel}',
    DeliveryOrderStatus.completed => 'Completed',
    DeliveryOrderStatus.cancelled => 'Cancelled',
    _ => _o.status,
  };

  String get _subheading {
    final rider = _o.deliveryName ?? 'The rider';
    return switch (_o.status) {
      DeliveryOrderStatus.orderPlaced =>
        'Placed ${formatAgo(_o.createdAt)}. The cashier will send prices soon; you will get an alert.',
      DeliveryOrderStatus.cashierPricing =>
        'Priced by the cashier ${formatAgo(_o.updatedAt)}',
      DeliveryOrderStatus.memberNegotiating =>
        'The cashier can accept it or reply with another.',
      DeliveryOrderStatus.assigned => '$rider will pick it up from the store.',
      DeliveryOrderStatus.pickedUp =>
        '$rider picked it up at ${formatTimeOfDay(_o.pickedUpAt)}',
      DeliveryOrderStatus.delivered =>
        '$rider handed it over at ${formatTimeOfDay(_o.deliveredAt)}. Confirm so the order can close.',
      DeliveryOrderStatus.shipped =>
        'Shipped ${formatAgo(_o.shippedAt)}. Tap "I received it" when it arrives.',
      DeliveryOrderStatus.completed =>
        'Finished ${formatRelativeDate(_o.confirmedAt ?? _o.updatedAt).toLowerCase()}',
      _ => 'Placed ${formatRelativeDate(_o.createdAt).toLowerCase()}',
    };
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = ShopColors.of(context);
    final bar = _actionBar(c);
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: Text('Order ${_o.shortId}'),
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _head(c),
                if (!_o.isCancelled) ...[
                  const SizedBox(height: 16),
                  OrderProgressSteps(_o),
                ],
                ..._sections(c),
                if (_o.memberCanCancel) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _act(MemberOrderActions.cancel),
                      style: TextButton.styleFrom(
                        foregroundColor: StockpileColors.danger,
                        minimumSize: const Size(0, 44),
                      ),
                      child: const Text('Cancel order'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: bar,
    );
  }

  Widget _head(ShopColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OrderPill(_o),
      const SizedBox(height: 8),
      Text(
        _heading,
        style: StockpileFonts.satoshi(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: c.text,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        _subheading,
        style: StockpileFonts.satoshi(
          fontSize: 13,
          height: 1.45,
          color: c.muted,
        ),
      ),
    ],
  );

  List<Widget> _sections(ShopColors c) {
    final out = <Widget>[];
    void add(Widget w) => out
      ..add(const SizedBox(height: 14))
      ..add(w);

    final payment = _payment(c);
    if (payment != null) add(payment);
    if (_o.isShipped || (_o.isCompleted && _o.isCourier)) add(_shipping(c));
    add(_price(c));
    if (_o.status == DeliveryOrderStatus.cashierPricing) {
      add(
        _note(
          c,
          'Item prices are set by the store. Only the '
          '${_o.isCourier ? 'shipping' : 'delivery'} fee can be changed. If it '
          'seems high, offer a different amount and the cashier will reply.',
        ),
      );
    }
    if (_offers.isNotEmpty && _o.isOpen) add(_feeHistory(c));
    if (_o.isCancelled) add(_ended(c));
    add(_deliverTo(c));
    return out;
  }

  Widget _note(ShopColors c, String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: c.soft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: OrderFact(Icons.info_outline_rounded, text, color: c.text),
  );

  /// Items, fee, total. Before pricing: the items alone.
  Widget _price(ShopColors c) {
    final priced = _o.itemsTotal != null;
    Widget row(String l, String r, {bool strong = false, String? sub}) =>
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: strong
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l,
                      style: StockpileFonts.satoshi(
                        fontSize: strong ? 15 : 14,
                        fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                        color: strong ? c.text : c.muted,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        style: StockpileFonts.satoshi(
                          fontSize: 12,
                          color: c.muted,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                r,
                style: StockpileFonts.satoshi(
                  fontSize: strong ? 22 : 14,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                  color: c.text,
                ),
              ),
            ],
          ),
        );

    final feeWho = switch (_o.status) {
      DeliveryOrderStatus.cashierPricing => "The cashier's offer",
      DeliveryOrderStatus.memberNegotiating => 'Your offer',
      _ => null,
    };

    return ShopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_o.itemCount} item${_o.itemCount == 1 ? '' : 's'}',
            style: StockpileFonts.satoshi(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const SizedBox(height: 4),
          for (final it in _o.items)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  ProductTile(
                    it.productName ?? 'Item',
                    imagePath: it.productImagePath,
                    size: 48,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.productName ?? 'Item #${it.productId}',
                          style: StockpileFonts.satoshi(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                        Text(
                          it.unitPrice == null
                              ? '× ${it.quantity}'
                              : '${it.quantity} × ${_m(it.unitPrice)}',
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (it.unitPrice != null)
                    Text(
                      _m(it.unitPrice! * it.quantity),
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                ],
              ),
            ),
          if (!priced) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: c.line),
            const SizedBox(height: 10),
            Text(
              'Prices: set by the cashier after you order',
              style: StockpileFonts.satoshi(fontSize: 13, color: c.muted),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: c.line),
            row('Items', _m(_o.itemsTotal)),
            row(
              _feeName,
              _o.deliveryFee == null ? '—' : _m(_o.deliveryFee),
              sub: feeWho,
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: c.line),
            row(
              'Total',
              _m(_o.finalTotal ?? (_o.itemsTotal ?? 0) + (_o.deliveryFee ?? 0)),
              strong: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _feeHistory(ShopColors c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_o.isCourier ? 'Shipping' : 'Delivery'} fee so far',
          style: StockpileFonts.satoshi(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.muted,
          ),
        ),
        for (final f in _offers)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: f.byMember ? StockpileColors.secondary500 : c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${f.byMember ? 'You offered' : 'Cashier offered'} ${_m(f.fee)}',
                    style: StockpileFonts.satoshi(fontSize: 13, color: c.text),
                  ),
                ),
                Text(
                  formatTimeOfDay(f.offeredAt),
                  style: StockpileFonts.satoshi(fontSize: 13, color: c.muted),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  /// How it is (or was) paid, and what the member does about it.
  Widget? _payment(ShopColors c) {
    if (_o.isOpen) return null;
    final total = _m(_o.finalTotal);

    Widget card(String title, String amount, List<Widget> body) => ShopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: StockpileFonts.satoshi(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
              Text(
                amount,
                style: StockpileFonts.satoshi(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...body,
        ],
      ),
    );

    if (_o.isRefunded) {
      return card('Refunded', total, [
        OrderFact(
          Icons.undo_rounded,
          'Your payment went back to your funds.',
          color: const Color(0xFF15803D),
        ),
      ]);
    }
    if (_o.isPaid) {
      return card('Paid', total, [
        OrderFact(Icons.verified_rounded, switch (_o.paymentMethod) {
          'cod' => 'Paid in cash to the rider.',
          'counter' => 'Paid at the counter.',
          'outside' =>
            _o.isCancelled
                ? 'Paid outside the app. The store refunds you the same way.'
                : 'Paid outside the app, confirmed by the store.',
          _ => 'Paid from your funds.',
        }, color: const Color(0xFF15803D)),
      ]);
    }
    if (_o.isCancelled || _o.isCompleted) return null;

    if (_o.isCod) {
      return card('Cash on delivery', total, [
        OrderFact(
          Icons.payments_outlined,
          "Have the cash ready. When the rider arrives, show your cash code: it's how they record that you paid.",
        ),
      ]);
    }
    if (_o.isOutside) return card('Pay outside the app', total, _outside(c));
    if (_o.canPayWithFunds) {
      return card('Not paid yet', total, [
        OrderFact(
          Icons.payments_outlined,
          _o.isCourier
              ? 'Pay from your Balance or Total Earnings, or outside the app '
                    '(GCash or similar). The store sends it by ${_o.routeLabel} once you have paid.'
              : 'Pay from your Balance or Total Earnings, or choose cash on '
                    'delivery. The store sends your order once you do.',
        ),
      ]);
    }
    if (_o.canStillPay) {
      return card('Not paid yet', total, [
        OrderFact(
          Icons.payments_outlined,
          'Your order is on its way, so it can only be paid in cash to the rider.',
        ),
      ]);
    }
    return null;
  }

  List<Widget> _outside(ShopColors c) {
    final details = (_o.paymentDetails ?? '').trim();
    final rejected = (_o.paymentRejectedNote ?? '').trim();
    final ref = (_o.paymentReference ?? '').trim();
    if (details.isEmpty) {
      return [
        OrderFact(
          Icons.hourglass_top_rounded,
          'The store will send where to pay. You will get a notification.',
        ),
      ];
    }
    return [
      Text(
        'Send ${_m(_o.finalTotal)} to:',
        style: StockpileFonts.satoshi(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: c.text,
        ),
      ),
      const SizedBox(height: 6),
      CopyableLine(details),
      if (rejected.isNotEmpty && _o.paymentSentAt == null) ...[
        const SizedBox(height: 10),
        OrderFact(
          Icons.error_outline_rounded,
          'The store could not confirm your last payment: $rejected',
          color: StockpileColors.danger,
        ),
      ],
      if (_o.paymentSentAt != null) ...[
        const SizedBox(height: 10),
        OrderFact(
          Icons.mark_email_read_outlined,
          'You said you sent it ${formatAgo(_o.paymentSentAt)}'
          '${ref.isEmpty ? '' : ' (reference $ref)'}. Waiting for the store to confirm.',
        ),
      ],
    ];
  }

  Widget _shipping(ShopColors c) {
    final tracking = (_o.trackingNumber ?? '').trim();
    return ShopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sent by ${_o.routeLabel}',
            style: StockpileFonts.satoshi(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const SizedBox(height: 8),
          if (tracking.isEmpty)
            OrderFact(
              Icons.local_shipping_outlined,
              'No tracking number was given.',
            )
          else ...[
            Text(
              'Tracking number',
              style: StockpileFonts.satoshi(fontSize: 12, color: c.muted),
            ),
            const SizedBox(height: 4),
            CopyableLine(tracking, copiedToast: 'Tracking number copied'),
            const SizedBox(height: 8),
            OrderFact(
              Icons.info_outline_rounded,
              "Track it on ${_o.routeLabel}'s website or app with this number.",
            ),
          ],
        ],
      ),
    );
  }

  Widget _ended(ShopColors c) {
    final why = (_o.cancelReason ?? '').trim();
    return ShopCard(
      child: OrderFact(
        Icons.cancel_outlined,
        why.isEmpty
            ? 'This order was cancelled. No reason was given.'
            : 'Cancelled: $why',
        color: c.text,
      ),
    );
  }

  Widget _deliverTo(ShopColors c) {
    final receiver = [
      _o.receiverDisplayName,
      if ((_o.receiverContact ?? '').trim().isNotEmpty)
        _o.receiverContact!.trim(),
    ].join(' · ');
    return ShopCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on_outlined, size: 20, color: c.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deliver to',
                  style: StockpileFonts.satoshi(fontSize: 12, color: c.muted),
                ),
                Text(
                  _o.deliveryAddress ?? 'No address',
                  style: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  receiver,
                  style: StockpileFonts.satoshi(fontSize: 13, color: c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── The one thing to do next ───────────────────────────────────────

  Widget? _actionBar(ShopColors c) {
    final buttons = <Widget>[];
    String? footnote;
    final busy = _busy;

    FilledButton primary(String label, VoidCallback onTap, {IconData? icon}) =>
        icon == null
        ? FilledButton(onPressed: busy ? null : onTap, child: Text(label))
        : FilledButton.icon(
            onPressed: busy ? null : onTap,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );

    switch (_o.status) {
      case DeliveryOrderStatus.cashierPricing:
        final total = (_o.itemsTotal ?? 0) + (_o.deliveryFee ?? 0);
        buttons
          ..add(
            primary(
              'Agree to ${_m(total)}',
              () => _act(MemberOrderActions.agree),
            ),
          )
          ..add(
            OutlinedButton(
              onPressed: busy ? null : () => _act(MemberOrderActions.counter),
              child: Text(
                'Offer a different ${_o.isCourier ? 'shipping' : 'delivery'} fee',
              ),
            ),
          );
        footnote = 'After you agree, you choose how to pay.';
      case DeliveryOrderStatus.delivered:
        buttons.add(
          primary(
            'Yes, I received it',
            () => _act(MemberOrderActions.confirmReceived),
            icon: Icons.check_circle_rounded,
          ),
        );
      case DeliveryOrderStatus.shipped:
        buttons.add(
          primary(
            'I received it',
            () => _act(MemberOrderActions.confirmReceived),
            icon: Icons.check_circle_rounded,
          ),
        );
      default:
        if (_o.isPaid || !_o.canStillPay) break;
        if (_o.isOutside && _o.isAgreed) {
          if (_o.paymentDetailsAt != null && _o.paymentSentAt == null) {
            buttons.add(
              primary(
                "I've sent the payment",
                () => _act(MemberOrderActions.markSent),
                icon: Icons.send_rounded,
              ),
            );
          }
          if (_o.paymentSentAt == null) {
            buttons.add(
              TextButton(
                onPressed: busy ? null : () => _act(MemberOrderActions.pay),
                child: const Text('Pay from my funds instead'),
              ),
            );
          }
        } else if (_o.isCod) {
          buttons.add(
            primary(
              'Show my cash code',
              () => _act(MemberOrderActions.pay),
              icon: Icons.qr_code_2_rounded,
            ),
          );
        } else if (_o.canPayWithFunds) {
          buttons.add(
            primary(
              'Choose how to pay',
              () => _act(MemberOrderActions.pay),
              icon: Icons.payments_rounded,
            ),
          );
        } else {
          buttons.add(
            primary(
              'Pay the rider in cash',
              () => _act(MemberOrderActions.pay),
              icon: Icons.payments_rounded,
            ),
          );
        }
    }
    if (buttons.isEmpty) return null;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    SizedBox(height: 48, child: buttons[i]),
                  ],
                  if (footnote != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      footnote,
                      textAlign: TextAlign.center,
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        color: c.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
