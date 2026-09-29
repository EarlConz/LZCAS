// lib/pages/delivery/delivery_orders_page.dart
// Cashier / Admin "Delivery Orders" module (Branch Cashiers are excluded).
//
//   * 'Order Placed'           → assign item prices (Step A) + delivery fee
//                                (Step B), then "Send Quote".
//   * 'Member Negotiating'     → accept the counter, or repropose a fee.
//   * 'Agreed'                 → complete the sale (record in POS + print the
//                                receipt) and mark Completed.
//   * 'Completed', cash        → "Cash Received from Rider" once the rider
//                                hands the money in (v52 cashier_remit_cod).
//                                Listed under "Cash to Remit" until then.
//
// Realtime-refreshed via `repository.changes`.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bot_toast/bot_toast.dart';
import '../../auth/auth.dart';
import '../../db/db.dart';
import '../../services/config_service.dart';
import '../../theme.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart'
    show formatMoney, formatRelativeDate, formatTimeOfDay;
import '../../dialogs/assign_rider_dialog.dart';
import '../../dialogs/delivery_order_receipt_dialog.dart';

class DeliveryOrdersPage extends StatefulWidget {
  const DeliveryOrdersPage({super.key});

  @override
  State<DeliveryOrdersPage> createState() => _DeliveryOrdersPageState();
}

enum _Filter {
  action('Needs Action'),
  awaiting('Awaiting Member'),
  agreed('Agreed'),
  // Completed cash orders whose money is still with the rider. Separate
  // from Completed because Completed is where a cashier stops looking —
  // exactly the wrong place for money nobody has handed in.
  cash('Cash to Remit'),
  completed('Completed'),
  cancelled('Cancelled'),
  all('All');

  const _Filter(this.label);
  final String label;
}

class _DeliveryOrdersPageState extends State<DeliveryOrdersPage> {
  List<DeliveryOrder> _orders = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<String>? _sub;
  _Filter _filter = _Filter.action;
  String? _busyOrderId;

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
    try {
      // Fetch ALL orders (no server-side status filter) so 'Order Placed' is
      // never accidentally hidden; the filter chips narrow the view locally.
      final orders = await repository.fetchDeliveryOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load delivery orders.';
        _loading = false;
      });
    }
  }

  int get _cashPending => _orders.where((o) => o.awaitingRemittance).length;

  List<DeliveryOrder> get _visible {
    return switch (_filter) {
      _Filter.action =>
        _orders
            .where(
              (o) =>
                  o.status == DeliveryOrderStatus.orderPlaced ||
                  o.status == DeliveryOrderStatus.memberNegotiating,
            )
            .toList(),
      _Filter.awaiting =>
        _orders
            .where((o) => o.status == DeliveryOrderStatus.cashierPricing)
            .toList(),
      // Agreed AND everything a rider is carrying, so an order does not
      // vanish from the cashier's view the moment it is dispatched.
      _Filter.agreed =>
        _orders.where((o) => o.isAgreed || o.isWithRider).toList(),
      _Filter.cash => _orders.where((o) => o.awaitingRemittance).toList(),
      _Filter.completed =>
        _orders
            .where((o) => o.status == DeliveryOrderStatus.completed)
            .toList(),
      _Filter.cancelled =>
        _orders
            .where((o) => o.status == DeliveryOrderStatus.cancelled)
            .toList(),
      _Filter.all => _orders,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delivery Orders',
                style: StockpileFonts.satoshi(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Price member orders and negotiate the delivery fee. '
                'Item prices are final once quoted.',
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              for (final f in _Filter.values) ...[
                ChoiceChip(
                  // The cash chip carries its count, so money waiting to be
                  // handed in is visible from whichever view is open.
                  label: Text(
                    f == _Filter.cash && _cashPending > 0
                        ? '${f.label} ($_cashPending)'
                        : f.label,
                  ),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
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
    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No orders in this view.'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final order = visible[i];
        return _OrderCard(
          order: order,
          busy: _busyOrderId == order.id,
          // Riders already carrying one of this cashier's other orders,
          // so the assign dialog can mark them busy.
          busyRiderIds: {
            for (final o in _orders)
              if (o.id != order.id && o.isWithRider && o.deliveryId != null)
                o.deliveryId!,
          },
          onBusyChanged: (b) =>
              setState(() => _busyOrderId = b ? order.id : null),
          onChanged: _load,
        );
      },
    );
  }
}

class _OrderCard extends StatefulWidget {
  final DeliveryOrder order;
  final bool busy;
  final Set<String> busyRiderIds;
  final ValueChanged<bool> onBusyChanged;
  final VoidCallback onChanged;

  const _OrderCard({
    required this.order,
    required this.busy,
    required this.onBusyChanged,
    required this.onChanged,
    this.busyRiderIds = const {},
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  late final Map<int, TextEditingController> _priceCtrls;
  late final TextEditingController _deliveryCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrls = {
      for (final it in widget.order.items)
        it.productId: TextEditingController(
          text: it.unitPrice == null
              ? ''
              : it.unitPrice == it.unitPrice!.roundToDouble()
              ? it.unitPrice!.round().toString()
              : it.unitPrice.toString(),
        ),
    };
    final fee = widget.order.deliveryFee;
    _deliveryCtrl = TextEditingController(
      text: fee == null
          ? ''
          : fee == fee.roundToDouble()
          ? fee.round().toString()
          : fee.toString(),
    );
  }

  @override
  void dispose() {
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    _deliveryCtrl.dispose();
    super.dispose();
  }

  String get _currency => context.read<ConfigService>().currencySymbol;

  Future<void> _sendQuote() async {
    final lines = <Map<String, dynamic>>[];
    var itemsTotal = 0.0;
    for (final item in widget.order.items) {
      final raw = _priceCtrls[item.productId]?.text.trim() ?? '';
      final price = double.tryParse(raw);
      if (price == null || price < 0) {
        BotToast.showText(
          text: 'Enter a valid price for ${item.productName ?? 'every item'}.',
        );
        return;
      }
      final subtotal = price * item.quantity;
      itemsTotal += subtotal;
      lines.add({
        'product_id': item.productId,
        'unit_price': price,
        'subtotal': subtotal,
      });
    }
    final fee = double.tryParse(_deliveryCtrl.text.trim());
    if (fee == null || fee < 0) {
      BotToast.showText(text: 'Enter a valid delivery fee.');
      return;
    }
    final auth = context.read<AuthState>();
    final cashierId = auth.userId;
    if (cashierId == null) return;

    widget.onBusyChanged(true);
    try {
      await repository.sendDeliveryQuote(
        orderId: widget.order.id,
        cashierId: cashierId,
        itemsTotal: itemsTotal,
        deliveryFee: fee,
        lines: lines,
      );
      if (!mounted) return;
      BotToast.showText(text: 'Quote sent to the member.');
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not send the quote.');
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  Future<void> _acceptCounter() async {
    widget.onBusyChanged(true);
    try {
      await repository.cashierResolveDeliveryOrder(
        orderId: widget.order.id,
        action: 'accept',
      );
      if (!mounted) return;
      BotToast.showText(text: 'Counter accepted — order agreed.');
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not accept the counter.');
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  Future<void> _repropose() async {
    final fee = await _promptFee('Propose a new delivery fee');
    if (fee == null) return;
    widget.onBusyChanged(true);
    try {
      await repository.cashierResolveDeliveryOrder(
        orderId: widget.order.id,
        action: 'repropose',
        newFee: fee,
      );
      if (!mounted) return;
      BotToast.showText(text: 'New fee proposed to the member.');
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not send the new fee.');
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  Future<void> _completeSale() async {
    widget.onBusyChanged(true);
    try {
      // The sale and the stock decrement happen SERVER-SIDE, inside
      // complete_delivery_order → order_record_sales (v52). This loop used
      // to do both here, which is why an order the MEMBER confirmed was
      // never recorded as sold: that path has no cashier client to run it.
      //
      // Do not reinstate it. The RPC is idempotent on
      // `orders.sales_recorded_at`, but that only protects the RPC — a
      // client writing its own `sales` rows would double the revenue and
      // decrement stock twice, and nothing would flag it.
      await repository.completeDeliveryOrder(widget.order.id);
      if (!mounted) return;
      await DeliveryOrderReceiptDialog(
        order: widget.order,
        currencySymbol: _currency,
      ).show(context);
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not complete the sale.');
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  // ── Dispatch (v50) ─────────────────────────────────────────────────

  /// Pick a rider. The list is sorted by distance from THIS cashier's
  /// saved location, using each rider's last known position — a rider who
  /// has never pinged sorts last, not first.
  Future<void> _assignRider() async {
    // Read before the first await — context must not be used across it.
    final uid = context.read<AuthState>().userId;
    widget.onBusyChanged(true);
    List<UserProfile> riders;
    CashierLocation? here;
    try {
      riders = await repository.fetchRiders();
      here = uid == null ? null : await repository.fetchCashierLocation(uid);
    } catch (_) {
      if (mounted) BotToast.showText(text: 'Could not load riders.');
      widget.onBusyChanged(false);
      return;
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
    if (!mounted) return;
    if (riders.isEmpty) {
      BotToast.showText(
        text: 'No delivery accounts yet — ask an admin to create one.',
      );
      return;
    }

    // Sorting, the map and the busy/live states live in the dialog.
    final chosen = await showAssignRiderDialog(
      context,
      order: widget.order,
      riders: riders,
      pickup: here,
      busyRiderIds: widget.busyRiderIds,
    );
    if (chosen == null || !mounted) return;

    widget.onBusyChanged(true);
    try {
      await repository.assignRider(
        orderId: widget.order.id,
        riderId: chosen.id,
      );
      if (!mounted) return;
      BotToast.showText(text: 'Assigned to ${chosen.username}.');
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not assign the rider.');
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  /// The member never confirmed. Closing it is recorded as a cashier
  /// override, so it stays visible as a judgement call rather than a
  /// confirmation.
  Future<void> _closeUnconfirmed() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Close without confirmation?'),
        content: Text(
          '${widget.order.deliveryName ?? 'The rider'} marked this delivered '
          'but the member has not confirmed. Closing it records that you '
          'overrode the confirmation.',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Wait'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close order'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _completeSale();
  }

  Future<void> _cancel() async {
    widget.onBusyChanged(true);
    try {
      await repository.cancelDeliveryOrder(widget.order.id);
      if (!mounted) return;
      BotToast.showText(text: 'Order cancelled.');
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not cancel the order.');
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  /// The rider has handed this order's cash to you. Records it so the
  /// collected-vs-remitted tally closes; it settles no balances and moves
  /// no money in the system — the money moved in your hand.
  Future<void> _remit() async {
    final order = widget.order;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Cash received?'),
        content: Text(
          'Confirm ${order.deliveryName ?? 'the rider'} has handed you '
          '${formatMoney(order.finalTotal, symbol: _currency)} for this '
          'order. Count it first — this cannot be undone from the app.',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cash received'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    widget.onBusyChanged(true);
    final error = await repository.remitCod(order.id);
    if (!mounted) return;
    widget.onBusyChanged(false);
    if (error != null) {
      // Verbatim: "already remitted" and "no collected cash" are different
      // problems, and the cashier needs to know which one they have.
      BotToast.showText(text: error, duration: const Duration(seconds: 5));
      return;
    }
    BotToast.showText(text: 'Cash recorded as received.');
    widget.onChanged();
  }

  /// Reprint for any completed order — until now a receipt only ever
  /// appeared at the moment of a counter sale, so orders a rider delivered
  /// never had one.
  Future<void> _viewReceipt() => DeliveryOrderReceiptDialog(
    order: widget.order,
    currencySymbol: _currency,
  ).show(context);

  Future<double?> _promptFee(String title) async {
    final ctrl = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Delivery fee',
            prefixText: '$_currency ',
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
              final fee = double.tryParse(ctrl.text.trim());
              if (fee == null || fee < 0) {
                BotToast.showText(text: 'Enter a valid delivery fee.');
                return;
              }
              Navigator.pop(ctx, fee);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
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
    final order = widget.order;
    final currency = _currency;
    final status = order.status;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.memberName ?? 'Member order',
                        style: StockpileFonts.satoshi(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                      Text(
                        '${formatRelativeDate(order.createdAt)} · '
                        '${order.items.length} line${order.items.length == 1 ? '' : 's'}',
                        style: StockpileFonts.satoshi(
                          fontSize: 12,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: status),
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
            if (status == DeliveryOrderStatus.orderPlaced)
              _buildQuoteEditor(text, muted)
            else
              _buildItemizedLines(text, muted),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildTotals(text, currency),
            const SizedBox(height: 16),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuoteEditor(Color text, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assign item prices (fixed once sent)',
          style: StockpileFonts.satoshi(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        for (final item in widget.order.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.productName ?? 'Item'} × ${item.quantity}',
                    style: StockpileFonts.satoshi(fontSize: 14, color: text),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _priceCtrls[item.productId],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixText: '$_currency ',
                      hintText: 'Unit price',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                'Delivery fee',
                style: StockpileFonts.satoshi(fontSize: 14, color: text),
              ),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _deliveryCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: '$_currency ',
                  hintText: 'Fee',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildItemizedLines(Color text, Color muted) {
    return Column(
      children: [
        for (final item in widget.order.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.productName ?? 'Item'} × ${item.quantity}',
                    style: StockpileFonts.satoshi(fontSize: 14, color: text),
                  ),
                ),
                Text(
                  item.unitPrice == null
                      ? '—'
                      : formatMoney(
                          (item.unitPrice! * item.quantity),
                          symbol: _currency,
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
      ],
    );
  }

  Widget _buildTotals(Color text, String currency) {
    final order = widget.order;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Items total',
              style: StockpileFonts.satoshi(fontSize: 14, color: text),
            ),
            Text(
              formatMoney(order.itemsTotal, symbol: currency),
              style: StockpileFonts.satoshi(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Delivery fee',
              style: StockpileFonts.satoshi(fontSize: 14, color: text),
            ),
            Text(
              formatMoney(order.deliveryFee, symbol: currency),
              style: StockpileFonts.satoshi(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: order.deliveryFee == null
                    ? text
                    : StockpileColors.primary900,
              ),
            ),
          ],
        ),
        if (order.finalTotal != null) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Final total',
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
              Text(
                formatMoney(order.finalTotal, symbol: currency),
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: StockpileColors.primary900,
                ),
              ),
            ],
          ),
          // How it is paid, from the moment there is a total to pay. This is
          // what tells a cashier, before dispatching, whether the rider has
          // cash to collect at the door.
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Payment',
                style: StockpileFonts.satoshi(fontSize: 14, color: text),
              ),
              Flexible(
                child: Text(
                  order.isPaid
                      ? '${order.paymentLabel} · paid'
                      : order.paymentLabel,
                  textAlign: TextAlign.right,
                  style: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: order.isPaid || order.isCompleted
                        ? const Color(0xFF16A34A)
                        : order.isCod
                        ? StockpileColors.primary900
                        : StockpileColors.mutedText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildActions() {
    final status = widget.order.status;
    final busy = widget.busy;

    switch (status) {
      case DeliveryOrderStatus.orderPlaced:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : _sendQuote,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send Quote'),
            ),
            TextButton(
              onPressed: busy ? null : _cancel,
              child: const Text('Cancel Order'),
            ),
          ],
        );
      case DeliveryOrderStatus.memberNegotiating:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _repropose,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Propose New Fee'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : _acceptCounter,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Accept Counter'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: busy ? null : _cancel,
              child: const Text('Cancel Order'),
            ),
          ],
        );
      case DeliveryOrderStatus.cashierPricing:
        return Text(
          'Waiting for the member to review the quote…',
          style: StockpileFonts.satoshi(fontSize: 13, color: Colors.grey),
        );
      case DeliveryOrderStatus.agreed:
        // Two ways out of Agreed: hand it to a rider, or hand it over at
        // the counter yourself. Both stay available — the rider is optional.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : _assignRider,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.two_wheeler_rounded, size: 18),
              label: const Text('Assign a Rider'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : _completeSale,
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text('Complete at Counter & Print Receipt'),
            ),
          ],
        );
      case DeliveryOrderStatus.assigned:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Waiting for ${widget.order.deliveryName ?? 'the rider'} to pick up.',
              style: StockpileFonts.satoshi(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : _assignRider,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Reassign Rider'),
            ),
            TextButton(
              onPressed: busy ? null : _cancel,
              child: const Text('Cancel Order'),
            ),
          ],
        );
      case DeliveryOrderStatus.pickedUp:
        final eta = widget.order.etaAt;
        return Text(
          'On its way with ${widget.order.deliveryName ?? 'the rider'}'
          '${eta == null ? '' : ' · ETA ${formatTimeOfDay(eta)}'}.',
          style: StockpileFonts.satoshi(fontSize: 13, color: Colors.grey),
        );
      case DeliveryOrderStatus.delivered:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Delivered by ${widget.order.deliveryName ?? 'the rider'} — '
              'waiting for the member to confirm.',
              style: StockpileFonts.satoshi(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : _closeUnconfirmed,
              icon: const Icon(Icons.task_alt_rounded, size: 18),
              label: const Text('Close Without Confirmation'),
            ),
          ],
        );
      case DeliveryOrderStatus.completed:
        final order = widget.order;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (order.awaitingRemittance) ...[
              // Money that exists only in a rider's pocket. The one
              // completed state that still needs something from a cashier.
              Text(
                '${order.deliveryName ?? 'The rider'} collected '
                '${formatMoney(order.finalTotal, symbol: _currency)} in cash '
                '— not handed in yet.',
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: StockpileColors.primary900,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: busy ? null : _remit,
                icon: const Icon(Icons.payments_rounded, size: 18),
                label: const Text('Cash Received from Rider'),
              ),
            ] else
              Text(
                order.isCod && order.codRemittedAt != null
                    ? 'Order completed · cash handed in '
                          '${formatRelativeDate(order.codRemittedAt)}.'
                    : 'Order completed.',
                style: StockpileFonts.satoshi(fontSize: 13, color: Colors.grey),
              ),
            TextButton.icon(
              onPressed: busy ? null : _viewReceipt,
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text('View Receipt'),
            ),
          ],
        );
      case DeliveryOrderStatus.cancelled:
        return Text(
          'Order cancelled.',
          style: StockpileFonts.satoshi(fontSize: 13, color: Colors.grey),
        );
      default:
        return const SizedBox.shrink();
    }
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
      DeliveryOrderStatus.memberNegotiating => (
        StockpileColors.secondary500,
        StockpileColors.secondary500.withAlpha(30),
      ),
      DeliveryOrderStatus.cashierPricing => (
        StockpileColors.primary900,
        StockpileColors.primary900.withAlpha(25),
      ),
      // Rider states: blue while it is out of the cashier's hands.
      DeliveryOrderStatus.assigned ||
      DeliveryOrderStatus.pickedUp ||
      DeliveryOrderStatus.delivered => (
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
