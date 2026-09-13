// lib/pages/delivery/rider_order_detail_page.dart
//
// One order, everything a rider needs to carry it, and the ONE action that
// is valid right now. The action changes with the status:
//
//   Assigned   → "Picked up" (asks for an ETA first)
//   Picked Up  → "Hand over"  → marks Delivered
//   Delivered  → nothing; waiting on the member
//
// Handover is where v51's QR scan will go for cash orders. In this build
// it is the plain "Mark delivered" that every order gets; the scanner is
// deliberately not stubbed in, because a fake scanner that always
// succeeds is worse than a button that says what it does.
//
// Turn-by-turn is the phone's maps app, not ours — flutter_map has no
// routing and should not grow any (plan §2).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/pages/delivery/rider_order_card.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart';
import 'package:lzcas/utils/toast_utils.dart';

class RiderOrderDetailPage extends StatefulWidget {
  final String orderId;

  /// What the list already had, so the page paints instantly. Refreshed
  /// from the server on open and after every action.
  final DeliveryOrder initial;
  final double? metersAway;

  const RiderOrderDetailPage({
    super.key,
    required this.orderId,
    required this.initial,
    this.metersAway,
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
    final ok = await showAnimatedDialog<bool>(
      context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Hand over?'),
        content: Text(
          _order.isCod
              ? 'Confirm you have handed the order to '
                    '${_order.receiverDisplayName} and collected '
                    '${formatMoney(_order.finalTotal)}.'
              : 'Confirm you have handed the order to '
                    '${_order.receiverDisplayName}. They will confirm on '
                    'their side.',
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
                    _mapCard(isDark, body),
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

  Widget _mapCard(bool isDark, Color body) {
    final o = _order;
    final hasPin = o.deliveryLatitude != null && o.deliveryLongitude != null;

    return _card(
      isDark,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (hasPin)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: SizedBox(
                height: 140,
                child: IgnorePointer(
                  // A preview, not a map to fumble with. Tapping Navigate
                  // opens the real thing.
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(
                        o.deliveryLatitude!,
                        o.deliveryLongitude!,
                      ),
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.lzcas.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                              o.deliveryLatitude!,
                              o.deliveryLongitude!,
                            ),
                            width: 36,
                            height: 36,
                            child: const Icon(
                              Icons.location_on,
                              color: StockpileColors.primary900,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    o.deliveryAddress ?? 'No address on this order',
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      height: 1.45,
                      color: body,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
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
