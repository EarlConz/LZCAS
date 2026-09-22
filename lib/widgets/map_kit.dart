// lib/widgets/map_kit.dart
//
// One visual language for every map in the app. Before this file each
// screen drew its own pins — white discs with an orange ring on the member
// map, a bare red `location_on` on the rider's, tinted glyphs on the
// admin's — and none of them agreed on what a branch looked like.
//
// The kit is deliberately small:
//
//   • MapPin / mapMarker   the disc-with-glyph pin and the Marker that
//                          sizes and anchors it correctly
//   • MapControlButton     the translucent white buttons in a map's corner
//   • MapLegend            "what the colours mean", bottom-left
//   • MapBanner            one line of context, top-left
//   • MapStatusChip        one fact about the whole map, bottom-right
//   • MapFrame             the rounded, bordered card that clips a map
//   • osmTileLayer / fitPoints / MapEdge   the bits every FlutterMap needs
//
// Screens compose these; nothing here knows about orders, stock or roles
// beyond the colour each role is drawn in.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';

// ─── Pins ───────────────────────────────────────────────────────────────────

/// What a pin stands for. The colour and glyph follow from this alone, so
/// a branch cashier is the same blue storefront on every screen.
enum MapPinKind {
  cashier(StockpileColors.primary900, Icons.point_of_sale_rounded),
  branch(StockpileColors.secondary500, Icons.storefront_rounded),
  rider(Color(0xFFB24800), Icons.two_wheeler_rounded),

  /// Where an order is going. Dark so it reads as "the fixed target"
  /// against the coloured, moving things around it.
  destination(StockpileColors.darkText, Icons.home_rounded),

  /// The viewer's own position — a plain dot, not a disc with a glyph,
  /// because it is not a "thing" on the map, it is the reader.
  you(Color(0xFF1D4ED8), Icons.circle);

  const MapPinKind(this.color, this.glyph);

  final Color color;
  final IconData glyph;

  /// The same mapping `profiles.role` → pin everywhere.
  static MapPinKind forRole(String role) => switch (role) {
    'branch_cashier' => MapPinKind.branch,
    'delivery' => MapPinKind.rider,
    _ => MapPinKind.cashier,
  };
}

/// The disc. 30 px normally, 38 px with a 3 px ring when [selected]; a
/// green halo when [live]; 55 % opacity when [muted] (out of stock, offline).
/// [label] adds a white pill underneath — distance for members, a name for
/// riders, never both.
class MapPin extends StatelessWidget {
  final MapPinKind kind;
  final bool selected;
  final bool live;
  final bool muted;
  final String? label;
  final VoidCallback? onTap;

  const MapPin({
    super.key,
    required this.kind,
    this.selected = false,
    this.live = false,
    this.muted = false,
    this.label,
    this.onTap,
  });

  static const double _disc = 30;
  static const double _selectedDisc = 38;
  static const double _halo = 46;
  static const double _labelHeight = 18;
  static const double _labelGap = 3;
  static const double _labelWidth = 96;

  /// Height of the disc region (halo or ring included) for [kind] and state.
  static double discBox({bool selected = false, bool live = false}) {
    if (live) return _halo + 8; // halo plus room for the selected ring
    if (selected) return _selectedDisc + 6;
    return _disc + 4; // shadow bleed
  }

  static double markerWidth({bool hasLabel = false}) =>
      hasLabel ? _labelWidth : discBox(live: true);

  static double markerHeight({
    bool selected = false,
    bool live = false,
    bool hasLabel = false,
  }) =>
      discBox(selected: selected, live: live) +
      (hasLabel ? _labelGap + _labelHeight : 0);

  @override
  Widget build(BuildContext context) {
    final color = muted ? StockpileColors.mutedText : kind.color;
    final size = selected ? _selectedDisc : _disc;
    final isYou = kind == MapPinKind.you;

    Widget disc = Container(
      width: isYou ? 18 : size,
      height: isYou ? 18 : size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: selected ? 3 : 2),
        boxShadow: [
          if (selected) BoxShadow(color: color, spreadRadius: 3),
          BoxShadow(
            color: Colors.black.withAlpha(selected ? 75 : 60),
            blurRadius: selected ? 10 : 6,
            offset: Offset(0, selected ? 4 : 2),
          ),
        ],
      ),
      child: isYou
          ? null
          : Icon(kind.glyph, size: selected ? 18 : 15, color: Colors.white),
    );

    if (muted) disc = Opacity(opacity: 0.55, child: disc);

    // The halo: live riders and the reader's own GPS dot.
    if (live || isYou) {
      disc = SizedBox(
        width: _halo,
        height: _halo,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: _halo,
              height: _halo,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isYou ? kind.color : StockpileColors.success).withAlpha(
                  isYou ? 40 : 46,
                ),
              ),
            ),
            disc,
          ],
        ),
      );
    }

    Widget pin = SizedBox(
      height: discBox(selected: selected, live: live || isYou),
      child: Center(child: disc),
    );

    if (label != null) {
      pin = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pin,
          const SizedBox(height: _labelGap),
          Container(
            height: _labelHeight,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: StockpileColors.divider),
              boxShadow: [
                BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 3),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StockpileFonts.satoshi(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: muted
                    ? StockpileColors.mutedText
                    : StockpileColors.darkText,
              ),
            ),
          ),
        ],
      );
    }

    if (onTap == null) return pin;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: pin,
    );
  }
}

/// A [Marker] whose box is sized for the pin's state and anchored so the
/// DISC — not the label — sits on [point]. Every screen goes through this
/// so a labelled pin never drifts off its coordinate.
Marker mapMarker({
  required LatLng point,
  required MapPinKind kind,
  bool selected = false,
  bool live = false,
  bool muted = false,
  String? label,
  VoidCallback? onTap,
  Key? key,
}) {
  final isYou = kind == MapPinKind.you;
  final hasLabel = label != null;
  final width = MapPin.markerWidth(hasLabel: hasLabel);
  final height = MapPin.markerHeight(
    selected: selected,
    live: live || isYou,
    hasLabel: hasLabel,
  );
  final discCenter = MapPin.discBox(selected: selected, live: live || isYou) / 2;
  return Marker(
    key: key,
    point: point,
    width: width,
    height: height,
    alignment: Marker.computePixelAlignment(
      width: width,
      height: height,
      left: width / 2,
      top: discCenter,
    ),
    child: MapPin(
      kind: kind,
      selected: selected,
      live: live,
      muted: muted,
      label: label,
      onTap: onTap,
    ),
  );
}

// ─── Furniture ──────────────────────────────────────────────────────────────

/// The translucent white surface every corner widget sits on.
BoxDecoration _glass(BuildContext context, {bool shadow = true}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: (isDark ? StockpileColors.darkSurface : Colors.white).withAlpha(240),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(
      color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
    ),
    boxShadow: shadow
        ? [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 6)]
        : null,
  );
}

/// A corner button: icon alone (40 × 40, a real touch target) or icon +
/// short label. [tint] colours the icon — blue for "my location".
class MapControlButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? tint;

  const MapControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.label,
    this.onTap,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg =
        tint ??
        (isDark ? StockpileColors.darkTextBody : StockpileColors.bodyText);
    final compact = label == null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: compact ? 40 : 36,
            width: compact ? 40 : null,
            padding: compact ? null : const EdgeInsets.symmetric(horizontal: 12),
            decoration: _glass(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: compact ? 18 : 16, color: fg),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    label!,
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MapLegendItem {
  final Color color;
  final String label;
  final bool muted;

  const MapLegendItem(this.color, this.label, {this.muted = false});
}

/// Bottom-left. Only worth showing when two or more pin kinds are on
/// screen; callers decide.
class MapLegend extends StatelessWidget {
  final List<MapLegendItem> items;

  const MapLegend({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: _glass(context, shadow: false),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final it in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: it.muted ? 0.6 : 1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: it.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  it.label,
                  style: StockpileFonts.satoshi(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? StockpileColors.darkTextBody
                        : StockpileColors.bodyText,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Top-left, under nothing. One at a time — the caller picks the most
/// important thing to say.
class MapBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? iconColor;

  const MapBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _glass(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon,
              size: 15,
              color: iconColor ?? StockpileColors.mutedText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: StockpileFonts.satoshi(
                fontSize: 11,
                height: 1.4,
                color: isDark
                    ? StockpileColors.darkTextBody
                    : StockpileColors.bodyText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-right. One fact: "2.4 km to go", "GPS · ±12 m".
class MapStatusChip extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String text;

  const MapStatusChip({super.key, required this.text, this.icon, this.leading})
    : assert(icon == null || leading == null);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: _glass(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          if (icon != null) ...[
            Icon(icon, size: 14, color: StockpileColors.primary900),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: StockpileFonts.satoshi(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Which corner a piece of furniture goes in. [MapOverlay] lays them out
/// with the same 12 px inset everywhere.
class MapOverlay extends StatelessWidget {
  final Widget map;
  final Widget? topLeft;
  final List<Widget> topRight;
  final Widget? bottomLeft;
  final Widget? bottomRight;

  const MapOverlay({
    super.key,
    required this.map,
    this.topLeft,
    this.topRight = const [],
    this.bottomLeft,
    this.bottomRight,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: map),
        if (topRight.isNotEmpty)
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < topRight.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  topRight[i],
                ],
              ],
            ),
          ),
        if (topLeft != null)
          Positioned(
            top: 12,
            left: 12,
            // Leave room for the controls column.
            right: topRight.isEmpty ? 12 : 64,
            child: topLeft!,
          ),
        if (bottomLeft != null)
          Positioned(bottom: 12, left: 12, child: bottomLeft!),
        if (bottomRight != null)
          Positioned(bottom: 12, right: 12, child: bottomRight!),
      ],
    );
  }
}

/// The card frame: 16 px radius, 1 px divider, clipped. [height] null
/// means "fill whatever the parent gives".
class MapFrame extends StatelessWidget {
  final Widget child;
  final double? height;
  final double radius;

  const MapFrame({
    super.key,
    required this.child,
    this.height,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

// ─── Map plumbing ───────────────────────────────────────────────────────────

/// The one tile source. Kept in one place so a switch to a paid provider
/// is a one-line change.
TileLayer osmTileLayer() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.lzcas.app',
);

/// Frame every point with the kit's standard padding and zoom ceiling.
/// Returns null for fewer than two points — callers fall back to a centre
/// and zoom, because a single point has no bounds worth fitting.
CameraFit? fitPoints(List<LatLng> points, {double padding = 48}) {
  if (points.length < 2) return null;
  return CameraFit.bounds(
    bounds: LatLngBounds.fromPoints(points),
    padding: EdgeInsets.all(padding),
    // Two nearly-identical points otherwise fit to maximum zoom and the
    // map opens on one rooftop.
    maxZoom: 16,
  );
}

/// Move the camera to frame [points], tolerating a map that has not laid
/// out yet (the first frame after build).
void fitCameraTo(
  MapController controller,
  List<LatLng> points, {
  double padding = 48,
  double singleZoom = 15,
}) {
  try {
    if (points.isEmpty) return;
    if (points.length == 1) {
      controller.move(points.first, singleZoom);
      return;
    }
    controller.fitCamera(fitPoints(points, padding: padding)!);
  } catch (_) {
    // Not ready yet; MapOptions.initialCameraFit already framed it.
  }
}

/// The Philippines, generously. Coordinates outside this box are almost
/// always an IP-geolocation miss (the ISP's exchange in another country),
/// not a real branch.
bool isInPhilippines(double lat, double lng) =>
    lat >= 4.5 && lat <= 21.5 && lng >= 116 && lng <= 127;

/// A dashed straight line between two points — "as the crow flies", drawn
/// as such so nobody mistakes it for a route.
Polyline straightLine(LatLng a, LatLng b) => Polyline(
  points: [a, b],
  color: StockpileColors.primary900,
  strokeWidth: 2.5,
  pattern: StrokePattern.dashed(segments: const [6, 6]),
);

// ─── Full-screen map ────────────────────────────────────────────────────────

/// A preview's "expand": the same markers, full-bleed and interactive.
/// Callers pass the markers (and an optional line) already built with
/// [mapMarker]; this page adds nothing but room.
class FullscreenMapPage extends StatefulWidget {
  final String title;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final List<LatLng> fitTo;
  final Widget? legend;
  final Widget? statusChip;

  const FullscreenMapPage({
    super.key,
    required this.title,
    required this.markers,
    required this.fitTo,
    this.polylines = const [],
    this.legend,
    this.statusChip,
  });

  @override
  State<FullscreenMapPage> createState() => _FullscreenMapPageState();
}

class _FullscreenMapPageState extends State<FullscreenMapPage> {
  final _controller = MapController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.fitTo;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: MapOverlay(
        map: FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: points.isEmpty
                ? const LatLng(12.8797, 121.7740)
                : points.first,
            initialZoom: 15,
            initialCameraFit: fitPoints(points),
          ),
          children: [
            osmTileLayer(),
            if (widget.polylines.isNotEmpty)
              PolylineLayer(polylines: widget.polylines),
            MarkerLayer(markers: widget.markers),
          ],
        ),
        topRight: [
          MapControlButton(
            icon: Icons.fit_screen_rounded,
            label: 'Fit all',
            tooltip: 'Frame everything',
            onTap: () => fitCameraTo(_controller, points),
          ),
        ],
        bottomLeft: widget.legend,
        bottomRight: widget.statusChip,
      ),
    );
  }
}
