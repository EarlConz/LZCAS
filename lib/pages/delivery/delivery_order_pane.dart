// lib/pages/delivery/delivery_order_pane.dart
//
// One delivery order, as the cashier works on it. Every stage has the same
// four parts, in the same places, so the cashier never hunts for the next
// step:
//
//   header        who, which order, its status, and "Cancel order"
//   stepper       Placed → Quote → Agreed → Dispatched → Delivered → Completed
//   content       what this stage needs: the price form, the counter-offer,
//                 the rider picker, the live map, the receipt
//   action bar    the one thing to do next, always bottom-right
//
// On a wide screen this sits beside the order list; on a phone it is the
// body of its own screen (`compact`).
//
// Every action here is a v48–v54 RPC. Nothing writes `sales` or touches
// stock: completion records the sale server-side (v52), and a client that
// did it too would double both.
//
// Also: [CashRemitPane], the rider-grouped "cash handed in" view.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';

import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/dialogs/delivery_order_receipt_dialog.dart';
import 'package:lzcas/pages/delivery/delivery_orders_parts.dart';
import 'package:lzcas/services/config_service.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart';
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/widgets/map_kit.dart';

/// A message fit to show a cashier. The RPCs raise sentences written for
/// people ("This order has not been paid…"), so those pass through; anything
/// else becomes a plain apology rather than a stack trace.
String _plain(Object e) {
  if (e is PostgrestException) {
    final m = e.message.trim();
    if (m.isNotEmpty) return m;
  }
  return 'Something went wrong. Please try again.';
}

/// Parse a typed amount. Commas are allowed ("1,200"); negatives are not.
double? _parseAmount(String raw) {
  final v = double.tryParse(raw.trim().replaceAll(',', ''));
  return v == null || v < 0 ? null : v;
}

String _amountText(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.round().toString() : v.toString();
}

// ═══════════════════════════════════════════════════════════════════════════
// The order pane
// ═══════════════════════════════════════════════════════════════════════════

class DeliveryOrderPane extends StatefulWidget {
  final DeliveryOrder order;
  final List<UserProfile> riders;

  /// This cashier's saved location: where the rider collects the order, and
  /// what distances are measured from.
  final CashierLocation? branch;

  /// Riders already carrying ANOTHER order. Still assignable — the cashier
  /// may know something the app does not — but marked busy.
  final Set<String> busyRiderIds;

  /// Called after any change, so the page reloads the list.
  final VoidCallback onChanged;

  /// Phone layout: tighter padding, stacked content, full-width actions.
  final bool compact;

  const DeliveryOrderPane({
    super.key,
    required this.order,
    required this.riders,
    required this.branch,
    required this.onChanged,
    this.busyRiderIds = const {},
    this.compact = false,
  });

  @override
  State<DeliveryOrderPane> createState() => _DeliveryOrderPaneState();
}

class _DeliveryOrderPaneState extends State<DeliveryOrderPane> {
  final Map<int, TextEditingController> _price = {};
  late final TextEditingController _fee;
  late final TextEditingController _counter;

  List<DeliveryFeeOffer> _offers = const [];
  String? _riderId;
  bool _reassigning = false;
  bool _busy = false;

  DeliveryOrder get _o => widget.order;

  @override
  void initState() {
    super.initState();
    for (final it in _o.items) {
      _price[it.productId] = TextEditingController(
        text: _amountText(it.unitPrice),
      )..addListener(_rebuild);
    }
    _fee = TextEditingController(text: _amountText(_o.deliveryFee))
      ..addListener(_rebuild);
    _counter = TextEditingController()..addListener(_rebuild);

    if (_o.status == DeliveryOrderStatus.cashierPricing ||
        _o.status == DeliveryOrderStatus.memberNegotiating) {
      _loadOffers();
    }
    if (_o.isAgreed) _riderId = _bestRider?.rider.id;

    // The road route, when this order has none yet — one request per order
    // however often it is opened (v53). While pricing it gives the cashier
    // a road distance to set the fee from.
    if (_o.routeWorthRequesting && !_o.isCompleted && !_o.isCancelled) {
      repository.ensureOrderRoute(_o.id).then((ok) {
        if (ok && mounted) widget.onChanged();
      });
    }
  }

  @override
  void didUpdateWidget(covariant DeliveryOrderPane old) {
    super.didUpdateWidget(old);
    // Same order, new fee: the negotiation moved on under us (realtime).
    if (old.order.deliveryFee != _o.deliveryFee &&
        (_o.status == DeliveryOrderStatus.cashierPricing ||
            _o.status == DeliveryOrderStatus.memberNegotiating)) {
      _loadOffers();
    }
  }

  @override
  void dispose() {
    for (final c in _price.values) {
      c.dispose();
    }
    _fee.dispose();
    _counter.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _loadOffers() async {
    final offers = await repository.fetchFeeOffers(_o.id);
    if (mounted) setState(() => _offers = offers);
  }

  // ── Shorthands ─────────────────────────────────────────────────────

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _text => _dark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
  Color get _body => _dark ? StockpileColors.darkTextMuted : StockpileColors.bodyText;
  Color get _line => _dark ? StockpileColors.darkDivider : StockpileColors.divider;
  Color get _surface => _dark ? StockpileColors.darkSurface : StockpileColors.surface;
  String get _cs => context.read<ConfigService>().currencySymbol;
  String _m(num? v) => formatMoney(v, symbol: _cs);
  double get _pad => widget.compact ? 16 : 24;

  LatLng? get _dest => _o.deliveryLatitude == null || _o.deliveryLongitude == null
      ? null
      : LatLng(_o.deliveryLatitude!, _o.deliveryLongitude!);

  LatLng? get _branchPoint => widget.branch == null
      ? null
      : LatLng(widget.branch!.latitude, widget.branch!.longitude);

  List<LatLng> get _route => _o.hasRoute ? routePoints(_o.routePoints) : const [];

  UserProfile? get _rider => _o.deliveryId == null
      ? null
      : widget.riders.where((r) => r.id == _o.deliveryId).firstOrNull;

  String get _riderName => _o.deliveryName ?? _rider?.username ?? 'The rider';

  List<RiderCandidate> get _candidates => rankRiders(
    widget.riders,
    fromLat: widget.branch?.latitude,
    fromLng: widget.branch?.longitude,
    busyIds: widget.busyRiderIds,
  );

  RiderCandidate? get _bestRider {
    final c = _candidates;
    return c.where((x) => !x.busy).firstOrNull ?? c.firstOrNull;
  }

  // ── Pricing arithmetic ─────────────────────────────────────────────

  double? _priceOf(DeliveryOrderItem it) =>
      _parseAmount(_price[it.productId]?.text ?? '');

  int get _unpriced => _o.items.where((it) => _priceOf(it) == null).length;

  double get _itemsTyped => _o.items.fold(
    0,
    (sum, it) => sum + (_priceOf(it) ?? 0) * it.quantity,
  );

  double? get _feeTyped => _parseAmount(_fee.text);

  bool get _quoteReady =>
      _o.items.isNotEmpty && _unpriced == 0 && _feeTyped != null;

  // ═════════════════════════════════════════════════════════════════
  // Actions
  // ═════════════════════════════════════════════════════════════════

  /// Run one RPC with the pane busy, then reload the page. [before] runs
  /// after success but BEFORE the reload — the reload can replace this
  /// pane (its key includes the status), so a receipt must open first.
  Future<void> _run(
    Future<void> Function() action, {
    String? success,
    Future<void> Function()? before,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (success != null) showSuccessToast(success);
      if (before != null) await before();
      if (!mounted) return;
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorToast(_plain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendQuote() async {
    final cashierId = context.read<AuthState>().userId;
    if (cashierId == null || !_quoteReady) return;
    final lines = [
      for (final it in _o.items)
        {
          'product_id': it.productId,
          'unit_price': _priceOf(it),
          'subtotal': _priceOf(it)! * it.quantity,
        },
    ];
    await _run(
      () => repository.sendDeliveryQuote(
        orderId: _o.id,
        cashierId: cashierId,
        itemsTotal: _itemsTyped,
        deliveryFee: _feeTyped!,
        lines: lines,
      ),
      success: 'Quote sent to ${_o.memberFirstName}',
    );
  }

  Future<void> _acceptCounter() => _run(
    () => repository.cashierResolveDeliveryOrder(
      orderId: _o.id,
      action: 'accept',
    ),
    success: 'Counter accepted — order agreed',
  );

  Future<void> _propose(double fee) => _run(
    () => repository.cashierResolveDeliveryOrder(
      orderId: _o.id,
      action: 'repropose',
      newFee: fee,
    ),
    success: 'New fee sent to ${_o.memberFirstName}',
  );

  Future<void> _assign() async {
    final chosen = _candidates.where((c) => c.rider.id == _riderId).firstOrNull;
    if (chosen == null) return;
    await _run(() async {
      await repository.assignRider(orderId: _o.id, riderId: chosen.rider.id);
      // Stored now so the rider's first open already has the road (v53).
      // Not awaited: the assignment has succeeded either way.
      if (_o.routeWorthRequesting) {
        unawaited(repository.ensureOrderRoute(_o.id));
      }
    }, success: 'Assigned to ${chosen.rider.username}');
  }

  /// Complete at the counter (Agreed) or close without the member's
  /// confirmation (Delivered). The receipt opens before the page reloads.
  Future<void> _complete({required bool override}) async {
    final ok = await _confirm(
      title: override ? 'Close without confirmation?' : 'Hand over at the counter?',
      body: override
          ? '$_riderName marked this delivered but ${_o.memberFirstName} has '
                'not confirmed. Closing it is recorded as your override.'
          : _o.isPaid
          ? '${_o.memberFirstName} already paid from their funds. This '
                'records the sale and prints the receipt.'
          : '${_o.memberFirstName} pays ${_m(_o.finalTotal)} now, at the '
                'counter. This records the payment and the sale, and prints '
                'the receipt.',
      confirm: override ? 'Close order' : 'Complete sale',
    );
    if (!ok) return;
    final receiptOf = _o; // the pane may be replaced by the reload
    await _run(
      () => repository.completeDeliveryOrder(_o.id),
      before: () => DeliveryOrderReceiptDialog(
        order: receiptOf,
        currencySymbol: _cs,
      ).show(context),
    );
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Cancel this order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _o.isWithRider
                  ? '$_riderName is carrying it. They will see it cancelled '
                        'and bring the goods back.'
                  : '${_o.memberFirstName} will see it cancelled.',
              style: Theme.of(ctx).textTheme.bodyMedium,
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
            style: FilledButton.styleFrom(backgroundColor: kDangerText),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    final why = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    await _run(
      () => why.isEmpty
          ? repository.cancelDeliveryOrder(_o.id)
          : repository.cancelDeliveryOrderWithReason(orderId: _o.id, reason: why),
      success: 'Order cancelled',
    );
  }

  Future<void> _printReceipt() => DeliveryOrderReceiptDialog(
    order: _o,
    currencySymbol: _cs,
  ).show(context);

  Future<void> _openMaps() async {
    final d = _dest;
    final uri = d != null
        ? Uri.parse('https://www.google.com/maps/search/?api=1&query=${d.latitude},${d.longitude}')
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query='
            '${Uri.encodeComponent(_o.deliveryAddress ?? '')}',
          );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showErrorToast('Could not open a maps app.');
    }
  }

  Future<void> _call() async {
    final n = (_o.receiverContact ?? '').replaceAll(RegExp(r'[^\d+]'), '');
    if (n.isEmpty) return;
    if (!await launchUrl(Uri.parse('tel:$n'))) {
      if (mounted) showErrorToast('Could not start a call.');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirm,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title),
        content: Text(body, style: Theme.of(ctx).textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ═════════════════════════════════════════════════════════════════
  // Build
  // ═════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: widget.compact
          ? BoxDecoration(color: _surface)
          : BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
      clipBehavior: widget.compact ? Clip.none : Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Container(
            padding: EdgeInsets.fromLTRB(_pad, 14, _pad, 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
            child: OrderStepper(order: _o, isDark: _dark, compact: widget.compact),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(_pad, 18, _pad, 24),
              child: _content(),
            ),
          ),
          _actionBar(),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────

  bool get _canCancel =>
      !_o.isCompleted && !_o.isCancelled && !_o.isDelivered;

  Widget _header() {
    final n = _o.items.length;
    final parts = [
      'Order ${_o.shortId}',
      if (_o.finalTotal != null) _m(_o.finalTotal),
      '$n item${n == 1 ? '' : 's'}',
      if (_o.createdAt != null) 'Placed ${formatTimeOfDay(_o.createdAt)}',
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(_pad, widget.compact ? 12 : 16, 12, widget.compact ? 12 : 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _o.memberName ?? 'Member order',
                      style: StockpileFonts.satoshi(
                        fontSize: widget.compact ? 16 : 18,
                        fontWeight: FontWeight.w800,
                        color: _text,
                      ),
                    ),
                    StagePill.forOrder(_o, isDark: _dark),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  parts.join(' · '),
                  style: StockpileFonts.satoshi(fontSize: 12, color: kCaption),
                ),
              ],
            ),
          ),
          if (_canCancel)
            TextButton(
              onPressed: _busy ? null : _cancel,
              style: TextButton.styleFrom(
                foregroundColor: kDangerText,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Cancel order'),
            ),
        ],
      ),
    );
  }

  // ── Content, by status ─────────────────────────────────────────────

  Widget _content() => switch (_o.status) {
    DeliveryOrderStatus.orderPlaced => _pricing(),
    DeliveryOrderStatus.cashierPricing ||
    DeliveryOrderStatus.memberNegotiating => _negotiation(),
    DeliveryOrderStatus.agreed => _dispatch(),
    DeliveryOrderStatus.assigned => _reassigning ? _dispatch() : _onTheWay(),
    DeliveryOrderStatus.pickedUp || DeliveryOrderStatus.delivered => _onTheWay(),
    DeliveryOrderStatus.completed => _completed(),
    DeliveryOrderStatus.cancelled => _cancelled(),
    _ => const SizedBox.shrink(),
  };

  /// Two columns when there is room, stacked on a phone or a narrow pane.
  Widget _split(Widget left, Widget right, {int leftFlex = 7, int rightFlex = 5}) {
    return LayoutBuilder(
      builder: (context, c) {
        if (!widget.compact && c.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: leftFlex, child: left),
              const SizedBox(width: 24),
              Expanded(flex: rightFlex, child: right),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 22), right],
        );
      },
    );
  }

  // ── To price ───────────────────────────────────────────────────────

  Widget _pricing() {
    final started = _unpriced < _o.items.length;
    final form = PaneSection(
      title: 'Price the items',
      trailing: 'Final once sent',
      isDark: _dark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.compact) _priceHeader(),
          for (final it in _o.items)
            widget.compact
                ? _priceCard(it, highlight: started && _priceOf(it) == null)
                : _priceRow(it, highlight: started && _priceOf(it) == null),
          const SizedBox(height: 12),
          _feeRow(),
          const SizedBox(height: 12),
          _totals(
            items: _itemsTyped,
            fee: _feeTyped,
            total: _quoteReady ? _itemsTyped + _feeTyped! : null,
            unpriced: _unpriced,
          ),
        ],
      ),
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _deliverTo(),
        const SizedBox(height: 14),
        PaneNote(
          icon: Icons.payments_outlined,
          title: 'Payment',
          body: '${_o.memberFirstName} chooses funds or cash on delivery '
              'once they agree.',
          dashed: true,
          iconColor: _body,
          isDark: _dark,
        ),
      ],
    );

    return _split(form, side);
  }

  Widget _priceHeader() {
    Widget h(String t, {double? width, bool grow = false, TextAlign align = TextAlign.left}) {
      final child = Text(
        t.toUpperCase(),
        textAlign: align,
        style: StockpileFonts.satoshi(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: _body,
        ),
      );
      return grow ? Expanded(child: child) : SizedBox(width: width, child: child);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _dark ? StockpileColors.darkInputBg : StockpileColors.tableHead,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          h('Item', grow: true),
          h('Qty', width: 44, align: TextAlign.right),
          const SizedBox(width: 12),
          h('Unit price', width: 140),
          const SizedBox(width: 12),
          h('Subtotal', width: 96, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _priceRow(DeliveryOrderItem it, {required bool highlight}) {
    final p = _priceOf(it);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _line.withAlpha(140)))),
      child: Row(
        children: [
          Expanded(
            child: Text(
              it.productName ?? 'Item #${it.productId}',
              style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w600, color: _text),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '× ${it.quantity}',
              textAlign: TextAlign.right,
              style: StockpileFonts.satoshi(fontSize: 13, color: _body),
            ),
          ),
          const SizedBox(width: 12),
          _moneyField(
            _price[it.productId]!,
            label: 'Unit price for ${it.productName ?? 'item'}',
            highlight: highlight,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Text(
              p == null ? '—' : _m(p * it.quantity),
              textAlign: TextAlign.right,
              style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: _text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceCard(DeliveryOrderItem it, {required bool highlight}) {
    final p = _priceOf(it);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? StockpileColors.primary900 : _line,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            it.productName ?? 'Item #${it.productId}',
            style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w600, color: _text),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text('× ${it.quantity}', style: StockpileFonts.satoshi(fontSize: 13, color: _body)),
              ),
              _moneyField(
                _price[it.productId]!,
                label: 'Unit price for ${it.productName ?? 'item'}',
                width: 132,
                highlight: highlight,
              ),
              const Spacer(),
              Text(
                p == null ? 'Needs a price' : _m(p * it.quantity),
                style: StockpileFonts.satoshi(
                  fontSize: p == null ? 12 : 14,
                  fontWeight: FontWeight.w700,
                  color: p == null ? kOrangeText : _text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _feeRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _dark ? StockpileColors.primary900.withAlpha(30) : StockpileColors.primary50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delivery fee',
                  style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w700, color: _text),
                ),
                const SizedBox(height: 2),
                Text(
                  'The only part ${_o.memberFirstName} can counter',
                  style: StockpileFonts.satoshi(fontSize: 12, color: _body),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _moneyField(_fee, label: 'Delivery fee', hint: 'Fee', width: widget.compact ? 120 : 140),
        ],
      ),
    );
  }

  Widget _moneyField(
    TextEditingController c, {
    required String label,
    String hint = 'Set price',
    double width = 140,
    bool highlight = false,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: highlight ? StockpileColors.primary900 : _line,
        width: highlight ? 1.5 : 1,
      ),
    );
    return SizedBox(
      width: width,
      child: Semantics(
        label: label,
        textField: true,
        child: TextField(
          controller: c,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          textAlign: TextAlign.right,
          style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w600, color: _text),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            prefixText: '$_cs ',
            filled: true,
            fillColor: _surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: StockpileColors.primary900, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  /// Items, delivery, total. [total] null means "not known yet".
  Widget _totals({
    required double items,
    required double? fee,
    required double? total,
    String feeLabel = 'Delivery',
    int unpriced = 0,
    bool locked = false,
  }) {
    Widget row(String l, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(l, style: StockpileFonts.satoshi(fontSize: 13, color: _body)),
          if (locked && l == 'Items') ...[
            const SizedBox(width: 6),
            Icon(Icons.lock_outline_rounded, size: 13, color: _body),
          ],
          const Spacer(),
          Text(v, style: StockpileFonts.satoshi(fontSize: 13, color: _body)),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Items', _m(items)),
        row(feeLabel, fee == null ? '—' : _m(fee)),
        Container(
          padding: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: _line))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Total', style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w800, color: _text)),
              const Spacer(),
              Text(
                total == null ? '—' : _m(total),
                style: StockpileFonts.satoshi(fontSize: 20, fontWeight: FontWeight.w800, color: _text),
              ),
            ],
          ),
        ),
        if (unpriced > 0) ...[
          const SizedBox(height: 6),
          Text(
            '$unpriced item${unpriced == 1 ? ' still needs' : 's still need'} a price',
            textAlign: TextAlign.right,
            style: StockpileFonts.satoshi(fontSize: 12, fontWeight: FontWeight.w600, color: kOrangeText),
          ),
        ],
      ],
    );
  }

  /// The priced lines, read-only, for every stage after the quote.
  Widget _itemsSummary() {
    return PaneSection(
      title: 'Items',
      trailing: 'Prices locked',
      isDark: _dark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final it in _o.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${it.productName ?? 'Item #${it.productId}'} × ${it.quantity}',
                      style: StockpileFonts.satoshi(fontSize: 13, color: _text),
                    ),
                  ),
                  Text(
                    it.unitPrice == null ? '—' : _m(it.unitPrice! * it.quantity),
                    style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w600, color: _text),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Where it goes ──────────────────────────────────────────────────

  /// The road when stored (v53), with dashed gaps where the pins sit off
  /// it; otherwise a dashed straight line from the branch.
  List<Polyline> _routeLines({LatLng? from}) {
    final dest = _dest, route = _route;
    if (dest == null) return const [];
    if (route.length >= 2) {
      final b = _branchPoint;
      return [
        roadRoute(route),
        ?lastStretch(route.last, dest),
        if (b != null) ?lastStretch(b, route.first),
      ];
    }
    final start = from ?? _branchPoint;
    return start == null ? const [] : [straightLine(start, dest)];
  }

  String? get _distanceLine {
    if (_o.hasRoute && (_o.routeDistanceM ?? 0) > 0) {
      return '${formatDistance(_o.routeDistanceM!.toDouble())} by road from your branch';
    }
    final b = _branchPoint, d = _dest;
    if (b == null || d == null) return null;
    final m = Geolocator.distanceBetween(b.latitude, b.longitude, d.latitude, d.longitude);
    return '${formatDistance(m)} from your branch, in a straight line';
  }

  Widget _deliverTo() {
    final dest = _dest;
    final b = _branchPoint;
    final facts = [
      ?_distanceLine,
      'Receiver: ${_o.receiverDisplayName}',
    ];
    return PaneSection(
      title: 'Deliver to',
      isDark: _dark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dest != null)
            _map(
              height: 176,
              title: 'Deliver to ${_o.receiverDisplayName}',
              markers: [
                if (b != null) mapMarker(point: b, kind: MapPinKind.cashier),
                mapMarker(point: dest, kind: MapPinKind.destination, selected: true),
              ],
              lines: _routeLines(),
              fit: [..._route, ?b, dest],
            ),
          const SizedBox(height: 10),
          Text(
            _o.deliveryAddress ?? 'No address on this order',
            style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w600, color: _text),
          ),
          const SizedBox(height: 2),
          Text(facts.join(' · '), style: StockpileFonts.satoshi(fontSize: 12, color: kCaption)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _openMaps,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Open in Maps'),
              ),
              if ((_o.receiverContact ?? '').trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _call,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: Text('Call ${_o.receiverDisplayName.split(' ').first}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// A preview map: not interactive, tap anywhere to open it full screen.
  Widget _map({
    required double height,
    required String title,
    required List<Marker> markers,
    required List<Polyline> lines,
    required List<LatLng> fit,
    Widget? topLeft,
    Widget? bottomLeft,
  }) {
    void expand() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullscreenMapPage(
          title: title,
          markers: markers,
          polylines: lines,
          fitTo: fit,
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: MapOverlay(
          map: GestureDetector(
            onTap: expand,
            child: IgnorePointer(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: fit.isNotEmpty ? fit.last : const LatLng(17.65, 121.72),
                  initialZoom: 14,
                  initialCameraFit: fitPoints(fit, padding: 40),
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  osmTileLayer(),
                  if (lines.isNotEmpty) PolylineLayer(polylines: lines),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
          topLeft: topLeft,
          topRight: [
            MapControlButton(
              icon: Icons.open_in_full_rounded,
              tooltip: 'Expand map',
              onTap: expand,
            ),
          ],
          bottomLeft: bottomLeft,
        ),
      ),
    );
  }

  // ── Negotiating ────────────────────────────────────────────────────

  Widget _negotiation() {
    final memberTurn = _o.status == DeliveryOrderStatus.memberNegotiating;
    final first = _o.memberFirstName;
    final lastYours = _offers.where((f) => !f.byMember).lastOrNull;
    final lastTheirs = _offers.where((f) => f.byMember).lastOrNull;
    final items = _o.itemsTotal ?? 0;
    final fee = _o.deliveryFee;

    final top = memberTurn
        ? PaneSection(
            title: 'Delivery fee',
            isDark: _dark,
            child: Row(
              children: [
                Expanded(
                  child: _offerCard(
                    label: 'You proposed',
                    // Before v54 nothing kept the earlier figure.
                    value: lastYours == null ? '—' : _m(lastYours.fee),
                    when: lastYours == null
                        ? 'Not recorded'
                        : formatTimeOfDay(lastYours.offeredAt),
                    highlight: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _offerCard(
                    label: '$first countered',
                    value: _m(fee),
                    when: lastTheirs == null
                        ? ''
                        : '${formatTimeOfDay(lastTheirs.offeredAt)} · ${formatAgo(lastTheirs.offeredAt)}',
                    highlight: true,
                  ),
                ),
              ],
            ),
          )
        : PaneNote(
            icon: Icons.hourglass_top_rounded,
            title: 'Waiting for $first',
            body: 'You quoted ${_m(fee)} for delivery. $first can agree, or '
                'counter the fee.',
            tint: _dark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
            iconColor: _body,
            isDark: _dark,
          );

    final history = _offers.isEmpty
        ? null
        : PaneSection(
            title: 'How it got here',
            isDark: _dark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _offers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 72,
                          child: Text(
                            formatTimeOfDay(_offers[i].offeredAt),
                            style: StockpileFonts.satoshi(fontSize: 13, color: kCaption),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _offers[i].byMember
                                ? '$first countered at ${_m(_offers[i].fee)}'
                                : i == 0
                                ? 'You quoted delivery at ${_m(_offers[i].fee)}'
                                : 'You proposed ${_m(_offers[i].fee)}',
                            style: StockpileFonts.satoshi(fontSize: 13, color: _body),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        top,
        if (history != null) ...[const SizedBox(height: 18), history],
        const SizedBox(height: 18),
        _itemsSummary(),
        const SizedBox(height: 4),
        _totals(
          items: items,
          fee: fee,
          total: fee == null ? null : items + fee,
          feeLabel: memberTurn ? 'Delivery, if you accept' : 'Delivery',
          locked: true,
        ),
        if (memberTurn) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _dark ? StockpileColors.darkDivider : const Color(0xFFD6D6DD)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Or propose a different fee',
                          style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w700, color: _text)),
                      const SizedBox(height: 2),
                      Text('$first can agree, or counter again',
                          style: StockpileFonts.satoshi(fontSize: 12, color: _body)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _moneyField(_counter, label: 'New delivery fee', hint: 'Fee', width: 130),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _offerCard({
    required String label,
    required String value,
    required String when,
    required bool highlight,
  }) {
    final accent = StockpileColors.secondary500;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? (_dark ? accent.withAlpha(40) : StockpileColors.secondary50) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? StockpileColors.secondary100 : _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StockpileFonts.satoshi(
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
              color: highlight ? accent : _body,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: StockpileFonts.satoshi(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: highlight ? accent : _body,
            ),
          ),
          if (when.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(when, style: StockpileFonts.satoshi(fontSize: 12, color: kCaption)),
          ],
        ],
      ),
    );
  }

  // ── Payment, as it stands ──────────────────────────────────────────

  Widget _paymentNote() {
    final first = _o.memberFirstName;
    final total = _m(_o.finalTotal);
    if (_o.isPaid) {
      return PaneNote(
        icon: Icons.verified_rounded,
        title: '${_o.paymentLabel} · $total, paid',
        body: _o.isCod ? null : 'Nothing to collect at the door.',
        tint: StockpileColors.successBg,
        iconColor: const Color(0xFF16A34A),
        isDark: _dark,
      );
    }
    if (_o.isCod) {
      return PaneNote(
        icon: Icons.payments_outlined,
        title: 'Cash on delivery · $total',
        body: 'The rider collects $total at the door and scans $first\'s code.',
        isDark: _dark,
      );
    }
    return PaneNote(
      icon: Icons.help_outline_rounded,
      title: 'Not paid yet',
      body: _o.isAgreed
          ? '$first can still pay from their funds until a rider is '
                'assigned. After that, the rider collects cash at the door.'
          : 'The rider collects $total in cash at the door.',
      tint: _dark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
      iconColor: _body,
      isDark: _dark,
    );
  }

  // ── Ready to dispatch / reassign ───────────────────────────────────

  Widget _dispatch() {
    final cands = _candidates;
    final dest = _dest, b = _branchPoint;

    final picker = cands.isEmpty
        ? PaneNote(
            icon: Icons.person_off_outlined,
            title: 'No riders yet',
            body: 'An admin can create one under User Management, with the '
                'role Delivery. You can still hand this over at the counter.',
            tint: _dark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
            iconColor: _body,
            isDark: _dark,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (dest != null) ...[
                _map(
                  height: 170,
                  title: 'Choose a rider',
                  markers: [
                    if (b != null) mapMarker(point: b, kind: MapPinKind.cashier),
                    mapMarker(point: dest, kind: MapPinKind.destination),
                    for (final c in cands)
                      if (c.hasPosition)
                        mapMarker(
                          point: LatLng(c.rider.latitude!, c.rider.longitude!),
                          kind: MapPinKind.rider,
                          selected: c.rider.id == _riderId,
                          live: c.isLive,
                          muted: c.rider.id != _riderId && (c.busy || !c.isLive),
                        ),
                  ],
                  lines: _routeLines(),
                  fit: [
                    ?b,
                    dest,
                    for (final c in cands)
                      if (c.hasPosition) LatLng(c.rider.latitude!, c.rider.longitude!),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              for (final c in cands) _riderOption(c),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _paymentNote(),
        const SizedBox(height: 18),
        PaneSection(
          title: _reassigning ? 'Choose another rider' : 'Choose a rider',
          trailing: cands.isEmpty ? null : 'Nearest to your branch first',
          isDark: _dark,
          child: picker,
        ),
        const SizedBox(height: 18),
        _itemsSummary(),
        const SizedBox(height: 4),
        _totals(
          items: _o.itemsTotal ?? 0,
          fee: _o.deliveryFee,
          total: _o.finalTotal,
          locked: true,
        ),
      ],
    );
  }

  Widget _riderOption(RiderCandidate c) {
    final selected = c.rider.id == _riderId;
    final at = c.rider.locationUpdatedAt;
    final parts = <String>[
      c.busy ? 'On a delivery' : 'Free',
      if (c.meters != null) '${formatDistance(c.meters!)} from your branch',
      if (c.meters == null) 'no position yet',
    ];
    final stale = at != null && !c.isLive;
    final current = c.rider.id == _o.deliveryId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        label: c.rider.username,
        child: Material(
          color: selected
              ? (_dark ? StockpileColors.primary900.withAlpha(30) : StockpileColors.primary50)
              : _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected ? StockpileColors.primary900 : _line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _busy ? null : () => setState(() => _riderId = c.rider.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.busy ? (_dark ? StockpileColors.darkInputBg : StockpileColors.inputBg) : const Color(0xFFB24800),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.two_wheeler_rounded,
                      size: 18,
                      color: c.busy ? kCaption : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current ? '${c.rider.username} (assigned now)' : c.rider.username,
                          style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: _text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          parts.join(' · '),
                          style: StockpileFonts.satoshi(fontSize: 12, color: _body),
                        ),
                        if (stale || c.isLive)
                          Text(
                            c.isLive
                                ? 'Seen ${formatAgo(at)}'
                                : 'Location ${formatAgo(at)} — may be out of date',
                            style: StockpileFonts.satoshi(
                              fontSize: 12,
                              fontWeight: stale ? FontWeight.w600 : FontWeight.w400,
                              color: stale ? kOrangeText : kCaption,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // A drawn radio: the real one's group API is mid-deprecation.
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? StockpileColors.primary900 : kCaption,
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: selected
                        ? Container(
                            width: 11,
                            height: 11,
                            decoration: const BoxDecoration(
                              color: StockpileColors.primary900,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Out for delivery ───────────────────────────────────────────────

  Widget _onTheWay() {
    final rider = _rider;
    final riderPoint = rider?.latitude == null || rider?.longitude == null
        ? null
        : LatLng(rider!.latitude!, rider.longitude!);
    final at = rider?.locationUpdatedAt;
    final live = at != null && DateTime.now().difference(at.toLocal()) < const Duration(minutes: 5);
    final dest = _dest, b = _branchPoint;

    // Distance left: along the stored road when the rider is on it (free,
    // computed here), else straight — and the line says which.
    String? left;
    if (_o.isPickedUp && riderPoint != null && dest != null) {
      final along = _route.length >= 2 ? remainingAlongRoute(_route, riderPoint) : null;
      left = along != null
          ? '${formatDistance(along + const Distance().as(LengthUnit.Meter, _route.last, dest))} to go by road'
          : '${formatDistance(Geolocator.distanceBetween(riderPoint.latitude, riderPoint.longitude, dest.latitude, dest.longitude))} away';
    }

    final riderLine = switch (_o.status) {
      DeliveryOrderStatus.assigned =>
        'Assigned ${formatTimeOfDay(_o.assignedAt)} · coming to your branch',
      DeliveryOrderStatus.pickedUp =>
        'Picked up ${formatTimeOfDay(_o.pickedUpAt)}${left == null ? '' : ' · $left'}',
      _ => 'Delivered ${formatTimeOfDay(_o.deliveredAt)}',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dest != null) ...[
          _map(
            height: widget.compact ? 220 : 280,
            title: 'Order ${_o.shortId}',
            markers: [
              if (b != null) mapMarker(point: b, kind: MapPinKind.cashier, muted: _o.isPickedUp),
              mapMarker(point: dest, kind: MapPinKind.destination, selected: true),
              if (riderPoint != null)
                mapMarker(point: riderPoint, kind: MapPinKind.rider, live: live, muted: !live),
            ],
            lines: _routeLines(),
            fit: [..._route, ?b, dest, ?riderPoint],
            topLeft: _o.isPickedUp && _o.etaAt != null
                ? MapStatusChip(
                    icon: Icons.schedule_rounded,
                    text: 'Arriving about ${formatTimeOfDay(_o.etaAt)}',
                  )
                : null,
            bottomLeft: at == null
                ? null
                : MapStatusChip(text: 'Rider location ${formatAgo(at)}'),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: Color(0xFFB24800), shape: BoxShape.circle),
                child: const Icon(Icons.two_wheeler_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_riderName, style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: _text)),
                    const SizedBox(height: 2),
                    Text(riderLine, style: StockpileFonts.satoshi(fontSize: 12, color: _body)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _paymentNote(),
        if (_o.isDelivered) ...[
          const SizedBox(height: 12),
          PaneNote(
            icon: Icons.inventory_2_outlined,
            title: '$_riderName marked it delivered ${formatAgo(_o.deliveredAt)}',
            body: 'Waiting for ${_o.memberFirstName} to confirm they received '
                'it. If they cannot, you can close it yourself.',
            tint: _dark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
            iconColor: _body,
            isDark: _dark,
          ),
        ],
        const SizedBox(height: 18),
        _itemsSummary(),
        const SizedBox(height: 4),
        _totals(items: _o.itemsTotal ?? 0, fee: _o.deliveryFee, total: _o.finalTotal, locked: true),
      ],
    );
  }

  // ── Completed / cancelled ──────────────────────────────────────────

  Widget _completed() {
    final first = _o.memberFirstName;
    final (IconData, String, String, bool) confirmation = switch (_o.confirmationMethod) {
      OrderConfirmation.qr => (
        Icons.qr_code_scanner_rounded,
        '$_riderName scanned $first\'s code',
        'Receipt and payment confirmed · ${formatTimeOfDay(_o.confirmedAt)}',
        false,
      ),
      OrderConfirmation.memberTap => (
        Icons.check_circle_outline_rounded,
        '$first confirmed they received it',
        formatTimeOfDay(_o.confirmedAt),
        false,
      ),
      OrderConfirmation.cashierOverride => (
        Icons.warning_amber_rounded,
        'Closed by a cashier without $first\'s confirmation',
        formatTimeOfDay(_o.confirmedAt),
        true,
      ),
      _ => (Icons.storefront_outlined, 'Handed over at the counter', '', false),
    };

    final facts = <(IconData, String, String, bool)>[
      confirmation,
      (
        Icons.payments_outlined,
        _o.paymentLabel,
        _o.paidAt == null ? '' : 'Paid ${formatTimeOfDay(_o.paidAt)}',
        _o.paymentLabel == 'Not collected',
      ),
      _o.salesRecordedAt != null
          ? (
              Icons.receipt_long_outlined,
              'Recorded as ${_o.items.length} sale${_o.items.length == 1 ? '' : 's'}',
              'Stock updated · ${formatTimeOfDay(_o.salesRecordedAt)}',
              false,
            )
          // Completed before v52 moved sale recording server-side.
          : (Icons.receipt_long_outlined, 'Sale recorded before the current system', '', false),
      if (_o.isCod)
        _o.codRemittedAt != null
            ? (Icons.savings_outlined, 'Cash handed in', formatTimeOfDay(_o.codRemittedAt), false)
            : (Icons.savings_outlined, 'Cash still with $_riderName', 'Take it in under Cash to remit', true),
    ];

    final receipt = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dark ? StockpileColors.darkInputBg : StockpileColors.tableHead,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Delivery order receipt',
              textAlign: TextAlign.center,
              style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w800, color: _text)),
          Text('DEL-${_o.shortId}',
              textAlign: TextAlign.center,
              style: StockpileFonts.satoshi(fontSize: 11, color: kCaption)),
          const SizedBox(height: 12),
          for (final it in _o.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text('${it.productName ?? 'Item'} × ${it.quantity}', style: StockpileFonts.satoshi(fontSize: 12, color: _text))),
                  Text(it.unitPrice == null ? '—' : _m(it.unitPrice! * it.quantity), style: StockpileFonts.satoshi(fontSize: 12, color: _text)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          _totals(items: _o.itemsTotal ?? 0, fee: _o.deliveryFee, total: _o.finalTotal),
        ],
      ),
    );

    final ended = PaneSection(
      title: 'How it ended',
      isDark: _dark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(f.$1, size: 18, color: f.$4 ? kOrangeText : const Color(0xFF16A34A)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.$2, style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w600, color: _text)),
                        if (f.$3.isNotEmpty)
                          Text(f.$3, style: StockpileFonts.satoshi(fontSize: 12, color: kCaption)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    return _split(receipt, ended, leftFlex: 1, rightFlex: 1);
  }

  Widget _cancelled() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneNote(
          icon: Icons.cancel_outlined,
          title: 'Cancelled',
          body: (_o.cancelReason ?? '').trim().isEmpty
              ? 'No reason was recorded.'
              : _o.cancelReason,
          tint: StockpileColors.dangerBg,
          iconColor: kDangerText,
          isDark: _dark,
        ),
        const SizedBox(height: 18),
        _itemsSummary(),
      ],
    );
  }

  // ── Action bar ─────────────────────────────────────────────────────

  Widget _actionBar() {
    final (hint, actions) = _actions();
    if (hint == null && actions.isEmpty) return const SizedBox.shrink();

    final hintText = hint == null
        ? null
        : Text(
            hint,
            style: StockpileFonts.satoshi(
              fontSize: 13,
              height: 1.4,
              fontWeight: hint.contains('need') ? FontWeight.w600 : FontWeight.w400,
              color: hint.contains('need') ? kOrangeText : _body,
            ),
          );

    return Container(
      padding: EdgeInsets.fromLTRB(_pad, 14, _pad, widget.compact ? 18 : 14),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: widget.compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ?hintText,
                if (hintText != null && actions.isNotEmpty) const SizedBox(height: 10),
                // Stacked, full width, the primary action last — nearest the
                // thumb. Side by side, "Hand over at counter" has ~170 px on a
                // phone and wraps.
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  actions[i],
                ],
              ],
            )
          : Row(
              children: [
                Expanded(child: hintText ?? const SizedBox.shrink()),
                for (final a in actions) ...[const SizedBox(width: 10), a],
              ],
            ),
    );
  }

  /// The hint on the left and the buttons on the right, per status. The
  /// primary action is always the last button: bottom-right on a wide
  /// screen, right-hand on a phone.
  (String?, List<Widget>) _actions() {
    final first = _o.memberFirstName;
    final busy = _busy;

    switch (_o.status) {
      case DeliveryOrderStatus.orderPlaced:
        final hint = _unpriced > 0
            ? '$_unpriced item${_unpriced == 1 ? ' still needs' : 's still need'} a price'
            : _feeTyped == null
            ? 'Set a delivery fee to send the quote'
            : '$first sees ${_m(_itemsTyped + _feeTyped!)} and can agree, or '
                  'counter the delivery fee.';
        return (
          hint,
          [
            FilledButton(
              onPressed: busy || !_quoteReady ? null : _sendQuote,
              child: const Text('Send quote'),
            ),
          ],
        );

      case DeliveryOrderStatus.cashierPricing:
        return ('Waiting for $first to agree or counter.', const []);

      case DeliveryOrderStatus.memberNegotiating:
        final fee = _o.deliveryFee ?? 0;
        final proposed = _parseAmount(_counter.text);
        final canPropose = proposed != null && proposed != fee;
        return (
          'Accepting agrees the order at ${_m((_o.itemsTotal ?? 0) + fee)}.',
          [
            OutlinedButton(
              onPressed: busy || !canPropose ? null : () => _propose(proposed),
              child: Text(canPropose ? 'Propose ${_m(proposed)}' : 'Propose'),
            ),
            FilledButton(
              onPressed: busy ? null : _acceptCounter,
              child: Text('Accept ${_m(fee)}'),
            ),
          ],
        );

      case DeliveryOrderStatus.agreed:
        final chosen = _candidates.where((c) => c.rider.id == _riderId).firstOrNull;
        return (
          null,
          [
            OutlinedButton(
              onPressed: busy ? null : () => _complete(override: false),
              child: const Text('Hand over at counter'),
            ),
            FilledButton(
              onPressed: busy || chosen == null ? null : _assign,
              child: Text(chosen == null ? 'Assign rider' : 'Assign ${chosen.rider.username.split(' ').first}'),
            ),
          ],
        );

      case DeliveryOrderStatus.assigned:
        if (_reassigning) {
          final chosen = _candidates.where((c) => c.rider.id == _riderId).firstOrNull;
          final changed = chosen != null && chosen.rider.id != _o.deliveryId;
          return (
            null,
            [
              OutlinedButton(
                onPressed: busy ? null : () => setState(() => _reassigning = false),
                child: Text('Keep ${_riderName.split(' ').first}'),
              ),
              FilledButton(
                onPressed: busy || !changed ? null : _assign,
                child: Text(changed ? 'Assign ${chosen.rider.username.split(' ').first}' : 'Assign'),
              ),
            ],
          );
        }
        return (
          'Waiting for $_riderName to pick it up.',
          [
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      _reassigning = true;
                      _riderId = _o.deliveryId;
                    }),
              child: const Text('Reassign'),
            ),
          ],
        );

      case DeliveryOrderStatus.pickedUp:
        return ('Nothing needed from you until it\'s delivered.', const []);

      case DeliveryOrderStatus.delivered:
        return (
          'Waiting for $first to confirm.',
          [
            OutlinedButton(
              onPressed: busy ? null : () => _complete(override: true),
              child: const Text('Close without confirmation'),
            ),
          ],
        );

      case DeliveryOrderStatus.completed:
        return (
          _o.awaitingRemittance
              ? 'The cash is still with $_riderName. Take it in under Cash to remit.'
              : 'Nothing left to do on this order.',
          [
            OutlinedButton.icon(
              onPressed: _printReceipt,
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text('Print receipt'),
            ),
          ],
        );

      default:
        return (null, const []);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash to remit, per rider
// ═══════════════════════════════════════════════════════════════════════════

/// Everything one rider is holding in collected cash. A rider comes back
/// with a day's takings, not one order's, so the cashier counts it once and
/// confirms it once; each ticked order is then marked with
/// `cashier_remit_cod` (v52) in turn.
class CashRemitPane extends StatefulWidget {
  final String riderName;

  /// Completed cash orders this rider has not handed in yet.
  final List<DeliveryOrder> orders;
  final VoidCallback onChanged;
  final bool compact;

  const CashRemitPane({
    super.key,
    required this.riderName,
    required this.orders,
    required this.onChanged,
    this.compact = false,
  });

  @override
  State<CashRemitPane> createState() => _CashRemitPaneState();
}

class _CashRemitPaneState extends State<CashRemitPane> {
  late Set<String> _ticked = {for (final o in widget.orders) o.id};
  bool _busy = false;

  @override
  void didUpdateWidget(covariant CashRemitPane old) {
    super.didUpdateWidget(old);
    // Orders handed in elsewhere drop out; new ones arrive unticked, so a
    // cashier never confirms money they have not seen appear.
    final ids = {for (final o in widget.orders) o.id};
    _ticked = _ticked.intersection(ids);
  }

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  String _m(num? v) => formatMoney(v, symbol: context.read<ConfigService>().currencySymbol);

  double get _held => widget.orders.fold(0, (s, o) => s + (o.finalTotal ?? 0));
  double get _selected => widget.orders
      .where((o) => _ticked.contains(o.id))
      .fold(0, (s, o) => s + (o.finalTotal ?? 0));

  DateTime? get _oldest => widget.orders
      .map((o) => o.paidAt)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);

  Future<void> _receive() async {
    final chosen = widget.orders.where((o) => _ticked.contains(o.id)).toList();
    if (chosen.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Received ${_m(_selected)}?'),
        content: Text(
          'Confirm ${widget.riderName} has handed you ${_m(_selected)} for '
          '${chosen.length} order${chosen.length == 1 ? '' : 's'}. Count it '
          'first — this cannot be undone from the app.',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cash received')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    var done = 0;
    String? firstError;
    for (final o in chosen) {
      final err = await repository.remitCod(o.id);
      if (err == null) {
        done++;
      } else {
        firstError ??= err;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (firstError == null) {
      showSuccessToast('Received ${_m(_selected)} from ${widget.riderName}');
    } else {
      // Some went through: say exactly how many, so the cashier knows which
      // part of the pile is recorded.
      showErrorToast(
        done == 0
            ? firstError
            : 'Recorded $done of ${chosen.length}. The rest: $firstError',
      );
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final text = _dark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
    final body = _dark ? StockpileColors.darkTextMuted : StockpileColors.bodyText;
    final line = _dark ? StockpileColors.darkDivider : StockpileColors.divider;
    final surface = _dark ? StockpileColors.darkSurface : StockpileColors.surface;
    final pad = widget.compact ? 16.0 : 24.0;
    final n = widget.orders.length;
    final oldest = _oldest;

    return Container(
      decoration: widget.compact
          ? BoxDecoration(color: surface)
          : BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: line),
            ),
      clipBehavior: widget.compact ? Clip.none : Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 14),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: line))),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: Color(0xFFB24800), shape: BoxShape.circle),
                  child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(widget.riderName, style: StockpileFonts.satoshi(fontSize: 18, fontWeight: FontWeight.w800, color: text)),
                          StagePill(text: 'Holding cash', dot: OrderStage.cash.dot, isDark: _dark),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Rider · $n cash order${n == 1 ? '' : 's'} not handed in',
                          style: StockpileFonts.satoshi(fontSize: 12, color: kCaption)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 16),
            color: _dark ? StockpileColors.primary900.withAlpha(30) : StockpileColors.primary50,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 16,
              runSpacing: 6,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('TO HAND IN', style: StockpileFonts.satoshi(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: body)),
                    Text(_m(_held), style: StockpileFonts.satoshi(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1, color: text)),
                  ],
                ),
                if (oldest != null)
                  Text('Oldest collected ${formatAgo(oldest)}',
                      style: StockpileFonts.satoshi(fontSize: 12, fontWeight: FontWeight.w600, color: kOrangeText)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(pad, 16, pad, 24),
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Orders', style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: text))),
                    Text('Tick the ones handed to you', style: StockpileFonts.satoshi(fontSize: 12, color: kCaption)),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: line)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < n; i++)
                        Container(
                          decoration: BoxDecoration(
                            border: i == 0 ? null : Border(top: BorderSide(color: line.withAlpha(140))),
                          ),
                          child: CheckboxListTile(
                            value: _ticked.contains(widget.orders[i].id),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                    final id = widget.orders[i].id;
                                    v == true ? _ticked.add(id) : _ticked.remove(id);
                                  }),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: StockpileColors.primary900,
                            title: Text(widget.orders[i].memberName ?? 'Member order',
                                style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w600, color: text)),
                            subtitle: Text(
                              'DEL-${widget.orders[i].shortId}'
                              '${widget.orders[i].paidAt == null ? '' : ' · collected ${formatTimeOfDay(widget.orders[i].paidAt)}'}',
                              style: StockpileFonts.satoshi(fontSize: 12, color: kCaption),
                            ),
                            secondary: Text(_m(widget.orders[i].finalTotal),
                                style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                PaneNote(
                  icon: Icons.info_outline_rounded,
                  title: 'Count the cash before confirming',
                  body: 'This cannot be undone from the app. Untick any order '
                      'whose money was not handed over — it stays on this list.',
                  dashed: true,
                  iconColor: body,
                  isDark: _dark,
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(pad, 14, pad, widget.compact ? 18 : 14),
            decoration: BoxDecoration(color: surface, border: Border(top: BorderSide(color: line))),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_ticked.length} of $n selected',
                    style: StockpileFonts.satoshi(fontSize: 13, color: body),
                  ),
                ),
                FilledButton(
                  onPressed: _busy || _ticked.isEmpty ? null : _receive,
                  child: Text(_ticked.isEmpty ? 'Received' : 'Received ${_m(_selected)}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
