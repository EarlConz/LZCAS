// lib/widgets/adjust_pin_page.dart
//
// "Drag the map until the pin sits on your door." The pin is fixed at the
// centre of the screen and the map moves under it — the pattern every
// ride-hailing app uses, because a finger over a draggable pin hides the
// very spot you are trying to hit.
//
// Nothing is saved here. The page returns the point (and the locality it
// reverse-geocoded, if any) to the location setter, which still needs the
// user's detailed address and a tap on Save.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:latlong2/latlong.dart';

import 'package:lzcas/services/geocoding_service.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart' show formatDistance;
import 'package:lzcas/widgets/map_kit.dart';

/// What the page hands back.
class AdjustedPin {
  final LatLng point;

  /// Reverse-geocoded locality for [point], or null if the lookup failed.
  final String? area;

  const AdjustedPin(this.point, this.area);
}

/// Opens the adjuster centred on [start]; resolves to null on cancel.
Future<AdjustedPin?> showAdjustPinPage(
  BuildContext context, {
  required LatLng start,
  required MapPinKind pinKind,
  LatLng? myPosition,
}) {
  return Navigator.of(context).push<AdjustedPin>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          AdjustPinPage(start: start, pinKind: pinKind, myPosition: myPosition),
    ),
  );
}

class AdjustPinPage extends StatefulWidget {
  final LatLng start;
  final MapPinKind pinKind;

  /// The device's live fix, for the "my location" button. Optional: on a
  /// desktop there is none.
  final LatLng? myPosition;

  const AdjustPinPage({
    super.key,
    required this.start,
    required this.pinKind,
    this.myPosition,
  });

  @override
  State<AdjustPinPage> createState() => _AdjustPinPageState();
}

class _AdjustPinPageState extends State<AdjustPinPage> {
  final _controller = MapController();
  late LatLng _center = widget.start;
  String? _area;
  bool _resolving = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Reverse-geocode once the map has settled — Nominatim allows one
  /// request a second, and a drag fires dozens of move events.
  void _onMapEvent(MapEvent e) {
    if (e is MapEventMoveEnd || e is MapEventFlingAnimationEnd) {
      _center = e.camera.center;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 700), _resolve);
      setState(() {});
    }
  }

  Future<void> _resolve() async {
    final at = _center;
    setState(() => _resolving = true);
    try {
      final a = await GeocodingService.reverseGeocode(
        at.latitude,
        at.longitude,
      );
      if (!mounted || at != _center) return;
      setState(() => _area = a.trim().isEmpty ? null : a.trim());
    } catch (_) {
      if (mounted) setState(() => _area = null);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  double get _movedMeters => Geolocator.distanceBetween(
    widget.start.latitude,
    widget.start.longitude,
    _center.latitude,
    _center.longitude,
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? StockpileColors.darkSurface : Colors.white;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust pin'),
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: MapOverlay(
              map: Stack(
                children: [
                  FlutterMap(
                    mapController: _controller,
                    options: MapOptions(
                      initialCenter: widget.start,
                      initialZoom: 17,
                      onMapEvent: _onMapEvent,
                    ),
                    children: [
                      osmTileLayer(),
                      if (widget.myPosition != null)
                        MarkerLayer(
                          markers: [
                            mapMarker(
                              point: widget.myPosition!,
                              kind: MapPinKind.you,
                            ),
                          ],
                        ),
                    ],
                  ),
                  // The fixed pin. Its disc centre is the map centre; the
                  // small shadow underneath marks the exact point.
                  IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MapPin(kind: widget.pinKind, selected: true),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              topLeft: const MapBanner(
                icon: Icons.open_with_rounded,
                iconColor: StockpileColors.primary900,
                text:
                    'Drag the map until the pin sits on your door. Pinch to '
                    'zoom in.',
              ),
              topRight: [
                if (widget.myPosition != null)
                  MapControlButton(
                    icon: Icons.my_location_rounded,
                    tooltip: 'Jump to my location',
                    tint: MapPinKind.you.color,
                    onTap: () => _controller.move(widget.myPosition!, 17),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(18),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _area ??
                              (_resolving
                                  ? 'Finding the address…'
                                  : 'No readable address here'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: StockpileFonts.satoshi(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _area == null ? muted : text,
                          ),
                        ),
                      ),
                      if (_resolving)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_center.latitude.toStringAsFixed(5)}, '
                    '${_center.longitude.toStringAsFixed(5)}'
                    '${_movedMeters >= 1 ? ' · ${formatDistance(_movedMeters)} from where you started' : ''}',
                    style: StockpileFonts.satoshi(fontSize: 11, color: muted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 10,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 14,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () =>
                              Navigator.pop(context, AdjustedPin(_center, _area)),
                          child: const Text('Use this point'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
