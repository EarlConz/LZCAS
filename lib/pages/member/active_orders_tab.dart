// lib/pages/member/active_orders_tab.dart
// Member "Active Orders" — shows cashier-assigned item prices, the items
// total, and the proposed delivery fee. The member may Agree (lock the
// final total and route to the POS) or Counter the delivery fee (the ONLY
// negotiable component). Realtime-refreshed.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../db/db.dart';
import '../../services/config_service.dart';
import '../../theme.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart'
    show formatAgo, formatMoney, formatRelativeDate, formatTimeOfDay;
import 'order_payment_sheet.dart';

class ActiveOrdersTab extends StatefulWidget {
  final Member member;

  const ActiveOrdersTab({super.key, required this.member});

  @override
  State<ActiveOrdersTab> createState() => _ActiveOrdersTabState();
}

class _ActiveOrdersTabState extends State<ActiveOrdersTab> {
  List<DeliveryOrder> _orders = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<String>? _sub;
  String? _busy;

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

  Future<void> _agree(DeliveryOrder order) async {
    setState(() => _busy = order.id);
    try {
      await repository.memberRespondDeliveryOrder(
        orderId: order.id,
        action: 'agree',
      );
      if (!mounted) return;
      BotToast.showText(text: 'Order agreed — routing to the cashier.');
      await _load();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not agree. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// "I have it." Delivered → Completed, recorded as member_tap (v50).
  Future<void> _confirmReceived(DeliveryOrder order) async {
    setState(() => _busy = order.id);
    try {
      await repository.memberConfirmReceived(order.id);
      if (!mounted) return;
      BotToast.showText(text: 'Thanks — order complete.');
      await _load();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not confirm. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Outside payment (v61): the member says they sent it, with the
  /// reference number if they have one.
  Future<void> _markSent(DeliveryOrder order) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sent your payment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The store checks it arrived, then sends your order. The '
              'reference number helps them find it.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Reference number (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("I've sent it"),
          ),
        ],
      ),
    );
    final reference = controller.text.trim();
    controller.dispose();
    if (ok != true || !mounted) return;

    setState(() => _busy = order.id);
    final error = await repository.memberMarkPaymentSent(
      orderId: order.id,
      reference: reference.isEmpty ? null : reference,
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (error != null) {
      BotToast.showText(text: error, duration: const Duration(seconds: 6));
      return;
    }
    BotToast.showText(text: 'The store was told. They will confirm it soon.');
    await _load();
  }

  Future<void> _counter(DeliveryOrder order) async {
    final fee = await _showCounterDialog(order.deliveryFee ?? 0);
    if (fee == null) return;
    setState(() => _busy = order.id);
    try {
      await repository.memberRespondDeliveryOrder(
        orderId: order.id,
        action: 'counter',
        counterFee: fee,
      );
      if (!mounted) return;
      BotToast.showText(text: 'Counter-offer sent.');
      await _load();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not send the counter-offer.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// A member may back out until the goods are moving: not once a rider
  /// has picked it up, nor once a courier has it. `cancel_delivery_order`
  /// enforces the same.
  bool _canCancel(DeliveryOrder order) =>
      order.isOpen || order.isAgreed || (order.isAssigned && !order.isCourier);

  /// Cancel with an optional reason, like the store's and the rider's
  /// cancel. Funds come back by themselves (v57); an outside payment is
  /// refunded the way it was paid.
  Future<void> _cancel(DeliveryOrder order) async {
    final currency = context.read<ConfigService>().currencySymbol;
    final total = formatMoney(order.finalTotal, symbol: currency);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.isFunds && order.isPaid
                  ? 'Your $total goes back to your funds.'
                  : order.isOutside && order.isPaid
                  ? 'You paid outside the app, so the store refunds you the '
                        'same way.'
                  : order.isAssigned
                  ? 'The rider assigned to it will see it cancelled.'
                  : 'The store will see it cancelled.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: StockpileColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    final why = reason.text.trim();
    reason.dispose();
    if (ok != true || !mounted) return;

    setState(() => _busy = order.id);
    try {
      if (why.isEmpty) {
        await repository.cancelDeliveryOrder(order.id);
      } else {
        await repository.cancelDeliveryOrderWithReason(
          orderId: order.id,
          reason: why,
        );
      }
      if (!mounted) return;
      BotToast.showText(text: 'Order cancelled.');
      await _load();
    } on PostgrestException catch (e) {
      // The database's sentence, e.g. "already on its way".
      if (!mounted) return;
      BotToast.showText(
        text: e.message.trim().isEmpty ? 'Could not cancel.' : e.message,
        duration: const Duration(seconds: 5),
      );
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not cancel. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<double?> _showCounterDialog(double currentFee) async {
    final controller = TextEditingController(
      text: currentFee == currentFee.roundToDouble()
          ? currentFee.round().toString()
          : currentFee.toString(),
    );
    final currency = context.read<ConfigService>().currencySymbol;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Counter Delivery Fee'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Proposed delivery fee',
            prefixText: '$currency ',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final fee = double.tryParse(controller.text.trim());
              if (fee == null || fee < 0) {
                BotToast.showText(text: 'Enter a valid delivery fee.');
                return;
              }
              Navigator.pop(ctx, fee);
            },
            child: const Text('Send Counter'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_shipping_outlined,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            const Text('No orders yet.'),
            const SizedBox(height: 4),
            const Text('Browse the Marketplace to place your first order.'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _orders.length,
      itemBuilder: (context, i) => _buildOrderCard(_orders[i]),
    );
  }

  Widget _buildOrderCard(DeliveryOrder order) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final currency = context.watch<ConfigService>().currencySymbol;
    final busy = _busy == order.id;

    return Card(
      elevation: 0,
      color: surface,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order · ${formatRelativeDate(order.createdAt)}',
                    style: StockpileFonts.satoshi(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: text,
                    ),
                  ),
                ),
                _StatusBadge(status: order.status),
              ],
            ),
            if ((order.deliveryAddress ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_outlined, size: 16, color: muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.deliveryAddress!,
                      style: StockpileFonts.satoshi(fontSize: 13, color: muted),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.productName ?? 'Item'} × ${item.quantity}',
                        style: StockpileFonts.satoshi(
                          fontSize: 14,
                          color: text,
                        ),
                      ),
                    ),
                    Text(
                      item.unitPrice == null
                          ? '—'
                          : formatMoney(
                              (item.unitPrice! * item.quantity),
                              symbol: currency,
                            ),
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _totalsRow(
              'Items total',
              formatMoney(order.itemsTotal, symbol: currency),
              text,
            ),
            const SizedBox(height: 6),
            _totalsRow(
              order.isCourier
                  ? 'Shipping fee · ${order.routeLabel}'
                  : 'Delivery fee',
              formatMoney(order.deliveryFee, symbol: currency),
              order.deliveryFee == null ? muted : text,
            ),
            if (order.finalTotal != null) ...[
              const SizedBox(height: 6),
              _totalsRow(
                'Final total',
                formatMoney(order.finalTotal, symbol: currency),
                StockpileColors.primary900,
                bold: true,
              ),
            ],
            if (order.isCourier && order.isOpen) ...[
              const SizedBox(height: 10),
              _riderLine(
                Icons.local_shipping_outlined,
                'Sent by ${order.routeLabel}. Pay from your funds or outside '
                'the app (GCash or similar); there is no cash on delivery.',
                muted,
              ),
            ],
            if (order.status == DeliveryOrderStatus.cashierPricing) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => _counter(order),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('Counter Delivery Fee'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => _agree(order),
                      icon: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Agree'),
                    ),
                  ),
                ],
              ),
            ] else if (order.status == DeliveryOrderStatus.orderPlaced) ...[
              const SizedBox(height: 12),
              Text(
                'Waiting for the cashier to price your items…',
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
            ] else if (order.status ==
                DeliveryOrderStatus.memberNegotiating) ...[
              const SizedBox(height: 12),
              Text(
                'Counter-offer sent — waiting for the cashier…',
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
            ] else if (order.isAgreed && order.isCourier) ...[
              const SizedBox(height: 12),
              Text(
                order.isPaid
                    ? 'Paid — the store is booking your order with '
                          '${order.routeLabel}.'
                    : order.isOutside
                    ? 'Agreed — pay outside the app, below. The store sends '
                          'it by ${order.routeLabel} once your payment is '
                          'confirmed.'
                    : 'Agreed — now choose how to pay. The store sends it by '
                          '${order.routeLabel} once you have paid.',
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
            ] else if (order.isAgreed) ...[
              const SizedBox(height: 12),
              Text(
                order.readyForRider
                    ? 'Agreed — the store is getting your order ready.'
                    : 'Agreed — now choose how to pay. The store sends your '
                          'order once you pay or choose cash on delivery.',
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
            ] else if (order.isShipped) ...[
              const SizedBox(height: 12),
              _riderLine(
                Icons.local_shipping_rounded,
                'Sent by ${order.routeLabel}'
                '${order.shippedAt == null ? '' : ' ${formatAgo(order.shippedAt)}'}'
                '${(order.trackingNumber ?? '').trim().isEmpty ? '.' : '. Tracking number:'}',
                muted,
              ),
              if ((order.trackingNumber ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 26),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          order.trackingNumber!.trim(),
                          style: StockpileFonts.satoshi(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: text,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy tracking number',
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: order.trackingNumber!.trim()),
                          );
                          BotToast.showText(text: 'Tracking number copied');
                        },
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : () => _confirmReceived(order),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('I received it'),
                ),
              ),
            ] else if (order.isAssigned) ...[
              // (payment row is rendered below for every unpaid stage)
              const SizedBox(height: 12),
              _riderLine(
                Icons.two_wheeler_rounded,
                '${order.deliveryName ?? 'A rider'} will bring your order.',
                muted,
              ),
            ] else if (order.isPickedUp) ...[
              const SizedBox(height: 12),
              _riderLine(
                Icons.two_wheeler_rounded,
                '${order.deliveryName ?? 'Your rider'} is on the way'
                '${order.etaAt == null ? '' : ' · arriving about ${formatTimeOfDay(order.etaAt)}'}.',
                muted,
              ),
            ] else if (order.isDelivered) ...[
              const SizedBox(height: 12),
              _riderLine(
                Icons.inventory_2_rounded,
                '${order.deliveryName ?? 'The rider'} marked this delivered. '
                'Did you receive it?',
                muted,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : () => _confirmReceived(order),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Yes, I received it'),
                ),
              ),
            ],

            // ── Payment ────────────────────────────────────────────────
            // Shown from Agreed onwards, because that is the first moment
            // there is a total to pay (plan §7). Deliberately outside the
            // status chain above: an unpaid order needs this whether it is
            // sitting with the cashier or already on a rider's bike.
            if (order.isOutside && order.canStillPay) ...[
              const SizedBox(height: 12),
              _outsidePayment(order, currency, text, muted, busy),
            ] else if (order.isPaid || order.canStillPay) ...[
              const SizedBox(height: 12),
              _paymentRow(order, currency, text, muted, busy),
            ],

            // ── Backing out, until the order is on its way ─────────────
            if (_canCancel(order)) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : () => _cancel(order),
                  style: TextButton.styleFrom(
                    foregroundColor: StockpileColors.danger,
                  ),
                  child: const Text('Cancel order'),
                ),
              ),
            ],

            // ── Cancelled: why, and where the money went ───────────────
            if (order.isCancelled &&
                (order.cancelReason ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Cancelled: ${order.cancelReason!.trim()}',
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
            ],
            if (order.isCancelled && order.isOutside && order.isPaid) ...[
              const SizedBox(height: 8),
              _riderLine(
                Icons.undo_rounded,
                'You paid outside the app, so the store refunds you the '
                'same way.',
                muted,
              ),
            ],
            if (order.isRefunded) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.undo_rounded,
                    size: 18,
                    color: Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your payment of '
                      '${formatMoney(order.finalTotal, symbol: currency)} '
                      'was returned to your funds.',
                      style: StockpileFonts.satoshi(fontSize: 13, color: muted),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The payment line: what was chosen, and the way to change it while it
  /// still can be changed.
  Widget _paymentRow(
    DeliveryOrder order,
    String currency,
    Color text,
    Color muted,
    bool busy,
  ) {
    if (order.isPaid) {
      return Row(
        children: [
          const Icon(
            Icons.verified_rounded,
            size: 18,
            color: Color(0xFF16A34A),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              switch (order.paymentMethod) {
                'cod' => 'Paid in cash on delivery.',
                'counter' => 'Paid at the counter.',
                'outside' => 'Paid outside the app, confirmed by the store.',
                _ => 'Paid from your funds.',
              },
              style: StockpileFonts.satoshi(fontSize: 13, color: muted),
            ),
          ),
        ],
      );
    }

    // CoD chosen but not yet collected: the member needs their code back,
    // not the chooser again.
    final chosenCod = order.isCod;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: busy ? null : () => _openPayment(order),
        icon: Icon(
          chosenCod ? Icons.qr_code_2_rounded : Icons.payments_rounded,
          size: 18,
        ),
        label: Text(
          chosenCod
              ? 'Show my cash code'
              : order.canPayWithFunds
              ? 'Pay ${formatMoney(order.finalTotal, symbol: currency)}'
              // Dispatched and still unchosen: cash is the only way left,
              // so the button says so rather than promising a choice.
              : 'Pay the rider in cash',
        ),
      ),
    );
  }

  Future<void> _openPayment(DeliveryOrder order) async {
    final changed = await showOrderPaymentSheet(
      context,
      order: order,
      currencySymbol: context.read<ConfigService>().currencySymbol,
    );
    if (changed && mounted) _load();
  }

  /// A courier order being paid outside the app (v61): where to send it,
  /// and the one thing the member does next.
  Widget _outsidePayment(
    DeliveryOrder order,
    String currency,
    Color text,
    Color muted,
    bool busy,
  ) {
    final total = formatMoney(order.finalTotal, symbol: currency);
    final details = (order.paymentDetails ?? '').trim();
    final rejected = (order.paymentRejectedNote ?? '').trim();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final children = <Widget>[];
    if (details.isEmpty) {
      children.add(
        _riderLine(
          Icons.hourglass_top_rounded,
          'You chose to pay outside the app. The store will send where to '
          'send $total. You will get a notification.',
          muted,
        ),
      );
    } else {
      children.addAll([
        Text(
          'Send $total to:',
          style: StockpileFonts.satoshi(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: text,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            color: isDark
                ? StockpileColors.primary900.withAlpha(30)
                : StockpileColors.primary50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  details,
                  style: StockpileFonts.satoshi(
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: text,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: details));
                  BotToast.showText(text: 'Copied');
                },
              ),
            ],
          ),
        ),
      ]);
      if (rejected.isNotEmpty && order.paymentSentAt == null) {
        children.addAll([
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: StockpileColors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The store could not confirm your last payment: $rejected',
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    height: 1.45,
                    color: StockpileColors.danger,
                  ),
                ),
              ),
            ],
          ),
        ]);
      }
      children.add(const SizedBox(height: 10));
      if (order.paymentSentAt != null) {
        children.add(
          _riderLine(
            Icons.mark_email_read_outlined,
            'You said you sent it ${formatAgo(order.paymentSentAt)}'
            '${(order.paymentReference ?? '').trim().isEmpty ? '' : ' (reference ${order.paymentReference!.trim()})'}. '
            'Waiting for the store to confirm.',
            muted,
          ),
        );
      } else {
        children.add(
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : () => _markSent(order),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text("I've sent the payment"),
            ),
          ),
        );
      }
    }
    // Funds stay open until the store confirms: a member short on GCash
    // credit can still switch.
    if (order.paymentSentAt == null) {
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: busy ? null : () => _openPayment(order),
            child: const Text('Pay from my funds instead'),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// One line about the rider, with an icon so it reads as a status rather
  /// than more body text.
  Widget _riderLine(IconData icon, String text, Color muted) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: StockpileColors.primary900),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: StockpileFonts.satoshi(
              fontSize: 13,
              height: 1.45,
              color: muted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _totalsRow(
    String label,
    String value,
    Color color, {
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: StockpileFonts.satoshi(fontSize: 14, color: color)),
        Text(
          value,
          style: StockpileFonts.satoshi(
            fontSize: 14,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (status) {
      DeliveryOrderStatus.agreed => (
        StockpileColors.success,
        StockpileColors.successBg,
      ),
      DeliveryOrderStatus.completed => (
        StockpileColors.success,
        StockpileColors.successBg,
      ),
      DeliveryOrderStatus.cancelled => (
        StockpileColors.danger,
        StockpileColors.dangerBg,
      ),
      DeliveryOrderStatus.memberNegotiating ||
      DeliveryOrderStatus.assigned ||
      DeliveryOrderStatus.pickedUp ||
      DeliveryOrderStatus.delivered ||
      DeliveryOrderStatus.shipped => (
        StockpileColors.secondary500,
        StockpileColors.secondary500.withAlpha(30),
      ),
      _ => (
        StockpileColors.primary900,
        StockpileColors.primary900.withAlpha(25),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: StockpileFonts.satoshi(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
