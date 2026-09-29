// lib/pages/delivery/rider_order_detail_page.dart
//
// One order, everything a rider needs to carry it, and the ONE action that
// is valid right now. The action changes with the status:
//
//   Assigned   → "Picked up" (asks for an ETA first)
//   Picked Up  → "Hand over"  → marks Delivered
//   Delivered  → nothing; waiting on the member
//
// Cash orders end differently (v52, plan §7): "Hand over" collects the
// money and scans the code on the member's phone, and that single scan is
// both the receipt confirmation and the payment record — so a CoD order
// never passes through Delivered at all, it goes straight to Completed.
// The typed fallback exists for a cracked screen or a camera that will
// not focus; there is deliberately no "mark delivered anyway" for cash,
// because that would be a rider closing an order with the money still
// uncollected and nothing recording it.
//
// Turn-by-turn is the phone's maps app, not ours — flutter_map has no
// routing and should not grow any (plan §2).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/dialogs/qr_scanner_dialog.dart';
import 'package:lzcas/pages/delivery/rider_order_card.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart';
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/widgets/map_kit.dart';

class RiderOrderDetailPage extends StatefulWidget {
  final String orderId;

  /// What the list already had, so the page paints instantly. Refreshed
  /// from the server on open and after every action.
  final DeliveryOrder initial;
  final double? metersAway;

  /// The rider's own last fix, from the dashboard's pinger — drawn as the
  /// blue dot so the preview shows "me and the door", not just the door.
  final LatLng? myPosition;

  const RiderOrderDetailPage({
    super.key,
    required this.orderId,
    required this.initial,
    this.metersAway,
    this.myPosition,
  });

  @override
  State<RiderOrderDetailPage> createState() => _RiderOrderDetailPageState();
}

class _RiderOrderDetailPageState extends State<RiderOrderDetailPage> {
  late DeliveryOrder _order = widget.initial;
  bool _busy = false;

  Future<void> _refresh() async {
    try {
      final rows = await repository.fetchDeliveryOrders(
        deliveryId: _order.deliveryId,
      );
      final fresh = rows.where((o) => o.id == widget.orderId).firstOrNull;
      if (fresh != null && mounted) setState(() => _order = fresh);
    } catch (_) {}
  }

  // ── Actions ───────────────────────────────────────────────────────

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showSuccessToast(success);
      await _refresh();
    } catch (e) {
      if (mounted) showErrorToast(_plain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The RPCs raise with a human sentence; surface that rather than the
  /// PostgrestException wrapper around it.
  String _plain(Object e) {
    final s = e.toString();
    final m = RegExp(r'message: ([^,]+)').firstMatch(s);
    return m?.group(1)?.trim() ?? 'Something went wrong.';
  }

  Future<void> _pickUp() async {
    final eta = await _askEta(
      initial: DateTime.now().add(const Duration(minutes: 30)),
    );
    if (eta == null) return;
    await _run(
      () => repository.deliveryPickup(orderId: _order.id, etaAt: eta),
      'Picked up — customer can see your ETA',
    );
  }

  Future<void> _editEta() async {
    final eta = await _askEta(initial: _order.etaAt ?? DateTime.now());
    if (eta == null) return;
    await _run(
      () => repository.deliveryUpdateEta(orderId: _order.id, etaAt: eta),
      'ETA updated',
    );
  }

  Future<void> _handOver() async {
    // Cash orders end with a scan, not a button: that one gesture is both
    // the receipt confirmation and the payment record (v52, plan §7), and
    // it requires the member to be standing there with their phone.
    if (_order.isCod && !_order.isPaid) {
      await _collectCash();
      return;
    }

    final ok = await showAnimatedDialog<bool>(
      context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Hand over?'),
        content: Text(
          'Confirm you have handed the order to '
          '${_order.receiverDisplayName}. They will confirm on their side.',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delivered'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => repository.deliveryMarkDelivered(_order.id),
      'Marked delivered',
    );
  }

  /// Cash on delivery: collect the money, then scan the member's code.
  Future<void> _collectCash() async {
    final how = await showAnimatedDialog<String>(
      context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Collect payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Collect ${formatMoney(_order.finalTotal)} from '
              '${_order.receiverDisplayName}, then scan the code on their '
              'phone.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'If their camera code will not scan, they can read you the '
              'characters underneath it.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'type'),
            child: const Text('Enter code'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'scan'),
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: const Text('Scan'),
          ),
        ],
      ),
    );
    if (how == null || !mounted) return;

    final code = how == 'scan'
        ? await showQrScannerDialog(context)
        : await _askCode();
    if (code == null || code.trim().isEmpty || !mounted) return;

    setState(() => _busy = true);
    final error = await repository.confirmCodDelivery(
      orderId: _order.id,
      nonce: code.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (error != null) {
      // Shown as the database phrased it — "that code is not valid for this
      // order" is the difference between a wrong order and a wrong code,
      // and the rider is the one who has to work out which.
      showErrorToast(error);
      return;
    }
    showSuccessToast('Payment collected — delivery complete');
    await _refresh();
  }

  /// Typed fallback for a code that will not scan: a cracked screen, a
  /// camera that will not focus, a member holding the phone in the sun.
  Future<String?> _askCode() {
    final controller = TextEditingController();
    return showAnimatedDialog<String>(
      context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Enter the code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Code from the member’s screen',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel() async {
    final reason = await _askReason();
    if (reason == null) return;
    await _run(
      () => repository.cancelDeliveryOrderWithReason(
        orderId: _order.id,
        reason: reason,
      ),
      'Order cancelled — the cashier has been told why',
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// A time picker, seeded sensibly, returning a DateTime today (or
  /// tomorrow if the chosen time has already passed — nobody delivers
  /// at 4:30 PM when it is 5 PM).
  Future<DateTime?> _askEta({required DateTime initial}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'When will it arrive?',
    );
    if (t == null) return null;
    final now = DateTime.now();
    var eta = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    if (!eta.isAfter(now)) eta = eta.add(const Duration(days: 1));
    return eta;
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final result = await showAnimatedDialog<String>(
      context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Cancel this delivery?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The cashier will restock it. Say what happened — this is '
              'what they read.',
              style: Theme.of(
                ctx,
              ).textTheme.bodySmall?.copyWith(color: StockpileColors.mutedText),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Customer refused · address unreachable · …',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep delivering'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: StockpileColors.danger,
            ),
            onPressed: () {
              final r = ctrl.text.trim();
              if (r.length < 3) return;
              Navigator.pop(ctx, r);
            },
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  // ── Outbound links ────────────────────────────────────────────────

  Future<void> _navigate() async {
    final lat = _order.deliveryLatitude, lng = _order.deliveryLongitude;
    final uri = lat != null && lng != null
        ? Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
          )
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query='
            '${Uri.encodeComponent(_order.deliveryAddress ?? '')}',
          );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showErrorToast('Could not open a maps app.');
    }
  }

  Future<void> _call() async {
    final n = (_order.receiverContact ?? '').replaceAll(RegExp(r'[^\d+]'), '');
    if (n.isEmpty) return;
    if (!await launchUrl(Uri.parse('tel:$n'))) {
      if (mounted) showErrorToast('Could not start a call.');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final body = isDark
        ? StockpileColors.darkTextBody
        : StockpileColors.bodyText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Scaffold(
      backgroundColor: isDark
          ? StockpileColors.darkBg
          : StockpileColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: isDark
            ? StockpileColors.darkBg
            : StockpileColors.scaffoldBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order ${o.shortId}',
              style: StockpileFonts.satoshi(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
            Text(
              'Placed ${formatRelativeDate(o.createdAt).toLowerCase()}',
              style: StockpileFonts.satoshi(fontSize: 12, color: muted),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: StatusChip(status: o.status, isDark: isDark),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  children: [
                    _mapCard(isDark, body, muted),
                    const SizedBox(height: 12),
                    _receiverCard(isDark, text, muted),
                    const SizedBox(height: 12),
                    _itemsCard(isDark, text, muted),
                    const SizedBox(height: 12),
                    _moneyAndEta(isDark, text, muted),
                    if (o.isCancelled && (o.cancelReason ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _cancelledNote(o.cancelReason!, body),
                    ],
                  ],
                ),
              ),
            ),
            _actionBar(isDark, muted),
          ],
        ),
      ),
    );
  }

  LatLng? get _destination {
    final o = _order;
    return o.deliveryLatitude == null || o.deliveryLongitude == null
        ? null
        : LatLng(o.deliveryLatitude!, o.deliveryLongitude!);
  }

  /// Destination, the rider's own dot, and a dashed straight line between
  /// them — drawn dashed so nobody mistakes it for a route.
  List<Marker> _mapMarkers({bool labelled = false}) {
    final dest = _destination;
    final me = widget.myPosition;
    return [
      if (me != null) mapMarker(point: me, kind: MapPinKind.you),
      if (dest != null)
        mapMarker(
          point: dest,
          kind: MapPinKind.destination,
          label: labelled ? _order.receiverDisplayName : null,
        ),
    ];
  }

  List<Polyline> _mapLines() {
    final dest = _destination, me = widget.myPosition;
    return dest != null && me != null ? [straightLine(me, dest)] : const [];
  }

  List<LatLng> get _mapPoints => [
    if (widget.myPosition != null) widget.myPosition!,
    if (_destination != null) _destination!,
  ];

  String? get _distanceLine =>
      widget.metersAway == null ? null : '${formatDistance(widget.metersAway!)} to go';

  Future<void> _expandMap() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FullscreenMapPage(
        title: 'Order ${_order.shortId}',
        markers: _mapMarkers(labelled: true),
        polylines: _mapLines(),
        fitTo: _mapPoints,
        statusChip: _distanceLine == null
            ? null
            : MapStatusChip(icon: Icons.navigation_rounded, text: _distanceLine!),
      ),
    ),
  );

  Widget _mapCard(bool isDark, Color body, Color muted) {
    final o = _order;
    final dest = _destination;
    final points = _mapPoints;

    return _card(
      isDark,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (dest != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: SizedBox(
                height: 180,
                child: MapOverlay(
                  // A preview, not a map to fumble with: tapping anywhere
                  // opens the full-screen one.
                  map: GestureDetector(
                    onTap: _expandMap,
                    child: IgnorePointer(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: dest,
                          initialZoom: 15,
                          initialCameraFit: fitPoints(points, padding: 40),
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          osmTileLayer(),
                          if (_mapLines().isNotEmpty)
                            PolylineLayer(polylines: _mapLines()),
                          MarkerLayer(markers: _mapMarkers()),
                        ],
                      ),
                    ),
                  ),
                  topRight: [
                    MapControlButton(
                      icon: Icons.open_in_full_rounded,
                      tooltip: 'Expand map',
                      onTap: _expandMap,
                    ),
                  ],
                  bottomRight: _distanceLine == null
                      ? null
                      : MapStatusChip(
                          icon: Icons.navigation_rounded,
                          text: _distanceLine!,
                        ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.deliveryAddress ?? 'No address on this order',
                        style: StockpileFonts.satoshi(
                          fontSize: 13,
                          height: 1.45,
                          color: body,
                        ),
                      ),
                      if (widget.metersAway != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Straight-line distance from your last fix',
                          style: StockpileFonts.satoshi(
                            fontSize: 11,
                            color: muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _navigate,
                  icon: const Icon(Icons.navigation_rounded, size: 16),
                  label: const Text('Navigate'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiverCard(bool isDark, Color text, Color muted) {
    final o = _order;
    final name = o.receiverDisplayName;
    final initials = name
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();

    return _card(
      isDark,
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: StockpileColors.primary900.withValues(alpha: 0.10),
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: StockpileFonts.satoshi(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: StockpileColors.primary900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('RECEIVER', muted),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: StockpileFonts.satoshi(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: text,
                  ),
                ),
                if ((o.receiverContact ?? '').isNotEmpty)
                  Text(
                    o.receiverContact!,
                    style: StockpileFonts.satoshi(fontSize: 12, color: muted),
                  ),
              ],
            ),
          ),
          if ((o.receiverContact ?? '').isNotEmpty)
            IconButton.filledTonal(
              tooltip: 'Call',
              onPressed: _call,
              icon: const Icon(Icons.call_rounded),
            ),
        ],
      ),
    );
  }

  Widget _itemsCard(bool isDark, Color text, Color muted) {
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;
    return _card(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('ITEMS · ${_order.items.length}', muted),
          const SizedBox(height: 6),
          for (var i = 0; i < _order.items.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${_order.items[i].quantity}×',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: StockpileColors.primary900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _order.items[i].productName ??
                          'Item #${_order.items[i].productId}',
                      style: StockpileFonts.satoshi(fontSize: 14, color: text),
                    ),
                  ),
                ],
              ),
            ),
            if (i < _order.items.length - 1) Divider(height: 1, color: divider),
          ],
        ],
      ),
    );
  }

  Widget _moneyAndEta(bool isDark, Color text, Color muted) {
    final o = _order;
    final moneyCard = o.isCod
        ? Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: StockpileColors.primary50,
              border: Border.all(color: StockpileColors.primary200),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('COLLECT · CoD', const Color(0xFFB24800)),
                const SizedBox(height: 4),
                Text(
                  formatMoney(o.finalTotal),
                  style: StockpileFonts.satoshi(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: StockpileColors.darkText,
                  ),
                ),
                if (o.deliveryFee != null)
                  Text(
                    'incl. ${formatMoney(o.deliveryFee)} delivery',
                    style: StockpileFonts.satoshi(
                      fontSize: 11,
                      color: StockpileColors.bodyText,
                    ),
                  ),
              ],
            ),
          )
        : _card(
            isDark,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(o.isFunds ? 'PAID · FUNDS' : 'TOTAL', muted),
                const SizedBox(height: 4),
                Text(
                  formatMoney(o.finalTotal),
                  style: StockpileFonts.satoshi(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: text,
                  ),
                ),
                Text(
                  o.isFunds ? 'nothing to collect' : 'payment not set',
                  style: StockpileFonts.satoshi(fontSize: 11, color: muted),
                ),
              ],
            ),
          );

    final etaCard = _card(
      isDark,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _label('YOUR ETA', muted)),
              if (o.isPickedUp)
                GestureDetector(
                  onTap: _busy ? null : _editEta,
                  child: Text(
                    'Edit',
                    style: StockpileFonts.satoshi(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: StockpileColors.primary900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            o.etaAt == null ? '—' : formatTimeOfDay(o.etaAt),
            style: StockpileFonts.satoshi(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: text,
            ),
          ),
          Text(
            o.etaAt == null ? 'set when you pick up' : 'customer can see this',
            style: StockpileFonts.satoshi(fontSize: 11, color: muted),
          ),
        ],
      ),
    );

    // Two cards side by side get ~150px each on a phone, which is enough
    // for a number and two short lines. Below that they stack.
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < 320
          ? Column(children: [moneyCard, const SizedBox(height: 12), etaCard])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: moneyCard),
                const SizedBox(width: 12),
                Expanded(child: etaCard),
              ],
            ),
    );
  }

  Widget _cancelledNote(String reason, Color body) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: StockpileColors.dangerBg,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      'Cancelled: $reason',
      style: StockpileFonts.satoshi(fontSize: 13, height: 1.45, color: body),
    ),
  );

  /// The single valid action for the current status, full width, with the
  /// cancel escape hatch underneath while the rider still holds the order.
  Widget _actionBar(bool isDark, Color muted) {
    final o = _order;
    final (label, icon, onTap, hint) = switch (o.status) {
      DeliveryOrderStatus.assigned => (
        'Picked up',
        Icons.inventory_2_rounded,
        _pickUp,
        "You'll be asked for an ETA.",
      ),
      DeliveryOrderStatus.pickedUp => (
        'Hand over',
        Icons.handshake_rounded,
        _handOver,
        o.isCod
            ? 'Cash order — collect ${formatMoney(o.finalTotal)} first.'
            : 'The customer confirms on their side.',
      ),
      DeliveryOrderStatus.delivered => (
        'Waiting for the customer to confirm',
        Icons.hourglass_top_rounded,
        null,
        null,
      ),
      _ => (null, null, null, null),
    };
    if (label == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
        border: Border(
          top: BorderSide(
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy || onTap == null ? null : onTap,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, size: 18),
              label: Text(label),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: StockpileFonts.satoshi(fontSize: 11, color: muted),
            ),
          ],
          if (o.isAssigned || o.isPickedUp)
            TextButton(
              onPressed: _busy ? null : _cancel,
              style: TextButton.styleFrom(
                foregroundColor: StockpileColors.danger,
              ),
              child: const Text("Can't deliver this"),
            ),
        ],
      ),
    );
  }

  // ── Bits ──────────────────────────────────────────────────────────

  Widget _card(bool isDark, {required Widget child, EdgeInsets? padding}) =>
      Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
          border: Border.all(
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );

  Widget _label(String text, Color color) => Text(
    text,
    style: StockpileFonts.satoshi(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: color,
    ),
  );
}
