// lib/dialogs/assign_rider_dialog.dart
//
// The cashier picks a rider for an Agreed order. A plain list sorted by
// distance was the first cut; this puts the same list next to a map, so
// "1.8 km" is also a pin the cashier can see is on the right side of town.
//
// Distances are from the PICKUP — this cashier's saved location — because
// the rider comes here first. If the cashier has no saved location the
// member's address is the origin instead, and the header says so.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:latlong2/latlong.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart'
    show formatAgo, formatDistance, formatMoney;
import 'package:lzcas/widgets/map_kit.dart';

/// Returns the chosen rider, or null if the cashier backed out.
Future<UserProfile?> showAssignRiderDialog(
  BuildContext context, {
  required DeliveryOrder order,
  required List<UserProfile> riders,
  required CashierLocation? pickup,

  /// Riders already carrying another order. Still assignable — the cashier
  /// may know something the app doesn't — but shown as busy.
  Set<String> busyRiderIds = const {},
}) {
  return showDialog<UserProfile>(
    context: context,
    builder: (_) => _AssignRiderDialog(
      order: order,
      riders: riders,
      pickup: pickup,
      busyRiderIds: busyRiderIds,
    ),
  );
}

class _Candidate {
  final UserProfile rider;
  final double? meters;
  final bool busy;

  const _Candidate(this.rider, this.meters, this.busy);

  bool get hasPosition => rider.latitude != null && rider.longitude != null;
  LatLng get point => LatLng(rider.latitude!, rider.longitude!);

  /// A ping in the last 5 minutes: on the road right now.
  bool get isLive {
    final at = rider.locationUpdatedAt;
    return at != null &&
        DateTime.now().difference(at.toLocal()) < const Duration(minutes: 5);
  }
}

class _AssignRiderDialog extends StatefulWidget {
  final DeliveryOrder order;
  final List<UserProfile> riders;
  final CashierLocation? pickup;
  final Set<String> busyRiderIds;

  const _AssignRiderDialog({
    required this.order,
    required this.riders,
    required this.pickup,
    required this.busyRiderIds,
  });

  @override
  State<_AssignRiderDialog> createState() => _AssignRiderDialogState();
}

class _AssignRiderDialogState extends State<_AssignRiderDialog> {
  late final List<_Candidate> _candidates;
  String? _selectedId;
  final _mapController = MapController();

  LatLng? get _destination {
    final o = widget.order;
    return o.deliveryLatitude == null || o.deliveryLongitude == null
        ? null
        : LatLng(o.deliveryLatitude!, o.deliveryLongitude!);
  }

  LatLng? get _pickupPoint => widget.pickup == null
      ? null
      : LatLng(widget.pickup!.latitude, widget.pickup!.longitude);

  /// Where distances are measured from.
  LatLng? get _origin => _pickupPoint ?? _destination;

  @override
  void initState() {
    super.initState();
    final origin = _origin;
    _candidates = [
      for (final r in widget.riders)
        _Candidate(
          r,
          origin == null || r.latitude == null || r.longitude == null
              ? null
              : Geolocator.distanceBetween(
                  origin.latitude,
                  origin.longitude,
                  r.latitude!,
                  r.longitude!,
                ),
          widget.busyRiderIds.contains(r.id),
        ),
    ]..sort((a, b) {
      // Free before busy; then nearest; a rider who has never pinged last.
      if (a.busy != b.busy) return a.busy ? 1 : -1;
      final da = a.meters, db = b.meters;
      if (da == null && db == null) {
        return a.rider.username.compareTo(b.rider.username);
      }
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    // Pre-select the current rider on a reassign, else the best candidate.
    _selectedId =
        widget.order.deliveryId ??
        _candidates.where((c) => !c.busy).firstOrNull?.rider.id ??
        _candidates.firstOrNull?.rider.id;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<LatLng> get _allPoints => [
    if (_pickupPoint != null) _pickupPoint!,
    if (_destination != null) _destination!,
    for (final c in _candidates)
      if (c.hasPosition) c.point,
  ];

  void _select(String id, {bool pan = false}) {
    setState(() => _selectedId = id);
    if (!pan) return;
    final c = _candidates.where((c) => c.rider.id == id).firstOrNull;
    if (c != null && c.hasPosition) {
      try {
        _mapController.move(c.point, 14);
      } catch (_) {}
    }
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
    final o = widget.order;
    final chosen = _candidates
        .where((c) => c.rider.id == _selectedId)
        .firstOrNull;
    final narrow = MediaQuery.sizeOf(context).width < 600;

    return Dialog(
      insetPadding: EdgeInsets.all(narrow ? 12 : 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: isDark ? StockpileColors.darkSurface : Colors.white,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.isAssigned ? 'Reassign rider' : 'Assign a rider',
                          style: StockpileFonts.satoshi(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            'Order ${o.shortId}',
                            o.memberName,
                            if ((o.deliveryAddress ?? '').isNotEmpty)
                              o.deliveryAddress!,
                            '${formatMoney(o.finalTotal)}${o.isCod ? ' CoD' : ''}',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: StockpileFonts.satoshi(
                            fontSize: 13,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: muted,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Map
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: MapFrame(
                height: narrow ? 200 : 240,
                radius: 12,
                child: _allPoints.isEmpty
                    ? Container(
                        color: isDark
                            ? StockpileColors.darkInputBg
                            : StockpileColors.inputBg,
                        alignment: Alignment.center,
                        child: Text(
                          'No positions to show yet.',
                          style: StockpileFonts.satoshi(
                            fontSize: 13,
                            color: muted,
                          ),
                        ),
                      )
                    : _map(),
              ),
            ),

            // Riders
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
              child: Text(
                '${_candidates.length} ${_candidates.length == 1 ? 'RIDER' : 'RIDERS'}'
                ' · NEAREST TO ${_pickupPoint != null ? 'YOU' : 'THE MEMBER'} FIRST',
                style: StockpileFonts.satoshi(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                  color: muted,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _candidates.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _RiderRow(
                  candidate: _candidates[i],
                  selected: _candidates[i].rider.id == _selectedId,
                  current: _candidates[i].rider.id == o.deliveryId,
                  onTap: () => _select(_candidates[i].rider.id, pan: true),
                ),
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: chosen == null
                        ? null
                        : () => Navigator.pop(context, chosen.rider),
                    child: Text(
                      chosen == null
                          ? 'Assign'
                          : 'Assign ${chosen.rider.username}',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _map() {
    final points = _allPoints;
    final hasLive = _candidates.any((c) => c.hasPosition && c.isLive);
    return MapOverlay(
      map: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: points.first,
          initialZoom: 13,
          initialCameraFit: fitPoints(points, padding: 40),
        ),
        children: [
          osmTileLayer(),
          MarkerLayer(
            markers: [
              if (_pickupPoint != null)
                mapMarker(
                  point: _pickupPoint!,
                  kind: MapPinKind.cashier,
                  label: 'Pickup',
                ),
              if (_destination != null)
                mapMarker(
                  point: _destination!,
                  kind: MapPinKind.destination,
                  label: 'Deliver to',
                ),
              for (final c in _candidates)
                if (c.hasPosition && c.rider.id != _selectedId)
                  mapMarker(
                    key: ValueKey(c.rider.id),
                    point: c.point,
                    kind: MapPinKind.rider,
                    live: c.isLive,
                    muted: c.busy || !c.isLive,
                    label: c.busy
                        ? '${c.rider.username} · busy'
                        : c.meters == null
                        ? c.rider.username
                        : '${c.rider.username} · ${formatDistance(c.meters!)}',
                    onTap: () => _select(c.rider.id),
                  ),
              for (final c in _candidates)
                if (c.hasPosition && c.rider.id == _selectedId)
                  mapMarker(
                    key: ValueKey('sel-${c.rider.id}'),
                    point: c.point,
                    kind: MapPinKind.rider,
                    selected: true,
                    live: c.isLive,
                    label: c.meters == null
                        ? c.rider.username
                        : '${c.rider.username} · ${formatDistance(c.meters!)}',
                    onTap: () => _select(c.rider.id),
                  ),
            ],
          ),
        ],
      ),
      topRight: [
        MapControlButton(
          icon: Icons.fit_screen_rounded,
          label: 'Fit all',
          tooltip: 'Frame everything',
          onTap: () => fitCameraTo(_mapController, points, padding: 40),
        ),
      ],
      bottomLeft: MapLegend(
        items: [
          if (_pickupPoint != null)
            const MapLegendItem(StockpileColors.primary900, 'Pickup'),
          if (_destination != null)
            const MapLegendItem(StockpileColors.darkText, 'Deliver to'),
          MapLegendItem(MapPinKind.rider.color, 'Rider'),
          if (hasLive) const MapLegendItem(StockpileColors.success, 'Live'),
        ],
      ),
    );
  }
}

class _RiderRow extends StatelessWidget {
  final _Candidate candidate;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  const _RiderRow({
    required this.candidate,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    final seen = c.rider.locationUpdatedAt;
    final status = [
      c.busy ? 'On a delivery' : 'Free',
      if (seen == null)
        'no position yet'
      else ...[
        'last seen ${formatAgo(seen)}',
        if (!c.isLive && !c.busy) 'position may be old',
      ],
      if (current) 'currently assigned',
    ].join(' · ');

    return Opacity(
      opacity: c.busy && !selected ? 0.7 : 1,
      child: Material(
        color: selected
            ? (isDark
                  ? StockpileColors.primary900.withAlpha(30)
                  : StockpileColors.primary50)
            : (isDark ? StockpileColors.darkSurface : Colors.white),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 13 : 14,
              vertical: selected ? 11 : 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? StockpileColors.primary900 : divider,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.busy
                              ? (isDark
                                    ? StockpileColors.darkInputBg
                                    : StockpileColors.inputBg)
                              : (isDark
                                    ? MapPinKind.rider.color.withAlpha(40)
                                    : StockpileColors.primary50),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.two_wheeler_rounded,
                          size: 20,
                          color: c.busy
                              ? StockpileColors.mutedText
                              : MapPinKind.rider.color,
                        ),
                      ),
                      if (c.isLive)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: StockpileColors.success,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? StockpileColors.darkSurface
                                    : Colors.white,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.rider.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: StockpileFonts.satoshi(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: text,
                              ),
                            ),
                          ),
                          if (c.isLive) ...[
                            const SizedBox(width: 8),
                            _chip(
                              'Live',
                              bg: StockpileColors.successBg,
                              fg: const Color(0xFF15803D),
                              dot: true,
                            ),
                          ] else if (c.busy) ...[
                            const SizedBox(width: 8),
                            _chip(
                              'On a delivery',
                              bg: isDark
                                  ? StockpileColors.darkInputBg
                                  : StockpileColors.inputBg,
                              fg: StockpileColors.mutedText,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StockpileFonts.satoshi(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.meters == null || c.busy
                        ? (isDark
                              ? StockpileColors.darkInputBg
                              : StockpileColors.inputBg)
                        : selected
                        ? StockpileColors.primary900
                        : StockpileColors.primary900.withAlpha(25),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    c.meters == null ? 'no position' : formatDistance(c.meters!),
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.meters == null || c.busy
                          ? StockpileColors.mutedText
                          : selected
                          ? Colors.white
                          : StockpileColors.primary900,
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

  Widget _chip(
    String label, {
    required Color bg,
    required Color fg,
    bool dot = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: const BoxDecoration(
                color: StockpileColors.success,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            label,
            style: StockpileFonts.satoshi(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
