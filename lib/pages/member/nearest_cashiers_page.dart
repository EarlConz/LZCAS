// lib/pages/member/nearest_cashiers_page.dart
// Dedicated "Nearest Cashiers" screen for Members (Buyers).
//
// Plots the member's position and the three nearest IN-STOCK cashiers /
// branch cashiers as interactive pins, plus nearby out-of-stock locations as
// grayed-out, disabled pins. Distances are straight-line and computed
// client-side; there is NO live navigation or routing.
//
// To keep the map smooth on low-end handsets, at most three active markers
// are rendered; every other located cashier is hidden unless it is both out
// of stock AND within the gray-pin radius.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../db/db.dart';
import '../../services/geocoding_service.dart';
import '../../theme.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart' show formatDistance;
import '../../widgets/map_kit.dart';

class NearestCashiersPage extends StatefulWidget {
  const NearestCashiersPage({super.key});

  @override
  State<NearestCashiersPage> createState() => _NearestCashiersPageState();
}

/// A located cashier plus its precomputed distance from the member.
class _NearbyCashier {
  final CashierWithStock data;
  final double distanceMeters;

  const _NearbyCashier(this.data, this.distanceMeters);

  CashierLocation get location => data.location;
  LatLng get point => LatLng(location.latitude, location.longitude);
  String get distanceLabel => formatDistance(distanceMeters);

  bool get hasStock => data.hasStock;
  List<CashierStockLine> get stock => data.stock;
  int get inStockCount => stock.where((l) => l.inStock).length;

  MapPinKind get kind =>
      location.isBranchCashier ? MapPinKind.branch : MapPinKind.cashier;
}

class _NearestCashiersPageState extends State<NearestCashiersPage> {
  static const int _maxActive = 3; // Top-N stocked locations.
  static const double _grayedRadiusMeters = 5000; // gray pins within 5 km.
  static const int _maxGrayedMarkers = 10;
  static const double _fallbackZoom = 14;

  bool _loading = true;
  String? _error;
  LatLng? _myPosition;

  /// True when [_myPosition] came from IP geolocation rather than GPS, so the
  /// distances are rough. Surfaced in the UI — a member comparing "1.2 km" to
  /// "8 km" deserves to know the origin point may be off by a town.
  bool _approximate = false;

  /// True when [_myPosition] came from the member's saved default location
  /// (set in their Profile) rather than GPS/IP, because live positioning was
  /// unavailable. Surfaced in the UI for the same reason as [_approximate].
  bool _usingSavedLocation = false;

  /// Android 12+ / iOS 14+: the app only has "Approximate location".
  bool _reducedAccuracy = false;

  /// Device-reported radius of [_myPosition], drawn as a circle when it is
  /// wide enough to matter.
  double? _myAccuracyMeters;

  /// Why the last load failed, so the error screen can offer the right
  /// settings shortcut.
  LocationAccess? _access;

  List<_NearbyCashier> _all = const []; // every located cashier, nearest first.
  List<_NearbyCashier> _topThree = const []; // nearest stocked (≤ 3).
  List<_NearbyCashier> _grayed = const []; // out-of-stock within radius.
  _NearbyCashier? _selected;

  final MapController _mapController = MapController();
  final PageController _cardController = PageController();
  int _cardIndex = 0;

  // ── Theme helpers ───────────────────────────────────────────────────────
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _surface =>
      _isDark ? StockpileColors.darkSurface : StockpileColors.surface;
  Color get _textPrimary =>
      _isDark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
  Color get _muted =>
      _isDark ? StockpileColors.darkTextMuted : StockpileColors.mutedText;
  Color get _divider =>
      _isDark ? StockpileColors.darkDivider : StockpileColors.divider;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cardController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _approximate = false;
      _usingSavedLocation = false;
      _reducedAccuracy = false;
      _myAccuracyMeters = null;
    });

    try {
      final access = await GeocodingService.ensureAccess();
      if (!mounted) return;

      // The member's saved default location (Profile → Member Location).
      // It beats the IP guess: a point they chose is better than the ISP's
      // exchange, and it is what keeps this screen alive on a desktop or
      // after a denied permission.
      final savedPos = await _savedMemberPosition();
      if (!mounted) return;
      final saved = savedPos == null
          ? null
          : LocatedPoint(
              latitude: savedPos.latitude,
              longitude: savedPos.longitude,
              source: PositionSource.saved,
            );

      // Fresh fix → recent cached fix → saved → IP guess (last, labelled).
      // 12 s is the ceiling, not the wait: the stream returns as soon as a
      // fix under 100 m arrives, usually within a couple of seconds.
      final point = access == LocationAccess.granted
          ? await GeocodingService.resolvePosition(
              gpsTimeout: const Duration(seconds: 12),
              saved: saved,
            )
          : saved;
      if (!mounted) return;

      if (point == null) {
        setState(() {
          _loading = false;
          _access = access;
          _error = access != LocationAccess.granted
              ? _messageFor(access)
              : 'Could not determine your location. Check that location '
                    'services are turned on, then try again.';
        });
        return;
      }

      final resolvedPos = LatLng(point.latitude, point.longitude);
      final usingSaved = point.source == PositionSource.saved;
      final approximate = point.isApproximate;
      final reduced =
          access == LocationAccess.granted &&
          await GeocodingService.isReducedAccuracy();
      if (!mounted) return;

      // Proximity + live stock in one pass: every located cashier with its
      // current on-hand inventory (see fetchCashiersWithStock).
      final cashiers = await repository.fetchCashiersWithStock();

      final nearby = <_NearbyCashier>[];
      for (final c in cashiers) {
        final meters = Geolocator.distanceBetween(
          resolvedPos.latitude,
          resolvedPos.longitude,
          c.location.latitude,
          c.location.longitude,
        );
        nearby.add(_NearbyCashier(c, meters));
      }
      nearby.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

      // Nearest-first. The first three stocked locations take the active
      // slots; out-of-stock ones become gray, disabled pins (only when close
      // enough to matter) so a restock automatically promotes them on the
      // next refresh — nothing to "re-enable" by hand.
      final top = <_NearbyCashier>[];
      final grayed = <_NearbyCashier>[];
      for (final c in nearby) {
        if (c.hasStock) {
          if (top.length < _maxActive) top.add(c);
        } else if (c.distanceMeters <= _grayedRadiusMeters &&
            grayed.length < _maxGrayedMarkers) {
          grayed.add(c);
        }
      }

      if (!mounted) return;
      setState(() {
        _myPosition = resolvedPos;
        _approximate = approximate;
        _usingSavedLocation = usingSaved;
        _reducedAccuracy = reduced;
        _myAccuracyMeters = point.accuracyMeters;
        _all = nearby;
        _topThree = top;
        _grayed = grayed;
        _loading = false;
        _cardIndex = 0;
        if (_cardController.hasClients) _cardController.jumpToPage(0);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) => _fitCamera());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load nearby cashiers: $e';
      });
    }
  }

  String _messageFor(LocationAccess access) {
    switch (access) {
      case LocationAccess.serviceDisabled:
        return 'Location services are turned off. Enable them in Settings '
            'and try again.';
      case LocationAccess.denied:
        return 'Location permission denied. Please allow it to see nearby '
            'cashiers.';
      case LocationAccess.deniedForever:
        return 'Location permission is permanently denied. Enable it in your '
            'device settings.';
      case LocationAccess.unableToDetermine:
        return 'Could not determine your location. Try again.';
      case LocationAccess.granted:
        return '';
    }
  }

  /// The member's own saved default location, if they set one in their
  /// Profile. Used as a fallback origin when live positioning fails so the
  /// map still has a point to measure distances from. Returns null when the
  /// member has no saved coordinates.
  Future<LatLng?> _savedMemberPosition() async {
    try {
      final member = await repository.fetchMyMember();
      if (member == null ||
          member.latitude == null ||
          member.longitude == null) {
        return null;
      }
      return LatLng(member.latitude!, member.longitude!);
    } catch (_) {
      return null;
    }
  }

  LatLng get _mapCenter {
    if (_myPosition != null) return _myPosition!;
    if (_topThree.isNotEmpty) return _topThree.first.point;
    if (_all.isNotEmpty) return _all.first.point;
    // Default fallback — somewhere central in the Philippines.
    return const LatLng(12.8797, 121.7740);
  }

  /// The member plus the (≤3) active stocked pins — the viewport to frame.
  /// Out-of-stock pins are deliberately excluded so the camera stays tight
  /// around the locations a buyer can actually use.
  List<LatLng> get _focusPoints => [
    if (_myPosition != null) _myPosition!,
    for (final c in _topThree) c.point,
  ];

  CameraFit? get _cameraFit {
    final points = _focusPoints;
    if (points.length < 2) return null;
    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.all(56),
      // Without a ceiling, two nearly-identical points fit to maximum zoom
      // and the map opens on a meaningless close-up of one rooftop.
      maxZoom: 16,
    );
  }

  void _fitCamera() {
    final points = _focusPoints;
    if (points.length < 2) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(56),
          maxZoom: 16,
        ),
      );
    } catch (_) {
      // The map may not be laid out on the very first frame; MapOptions
      // `initialCameraFit` still frames correctly in that case.
    }
  }

  void _focusCashier(_NearbyCashier cashier) {
    try {
      _mapController.move(cashier.point, 15);
    } catch (_) {
      // Ignore — the map may not be ready.
    }
  }

  void _focusMe() {
    final me = _myPosition;
    if (me == null) return;
    try {
      _mapController.move(me, 15);
    } catch (_) {}
  }

  /// A pin tap: highlight it, and bring its card into view — on the phone
  /// that means swiping the card strip to it. Tapping the same pin again
  /// opens the details, so a member never needs to find the card.
  void _selectFromPin(_NearbyCashier cashier) {
    if (_selected?.location.id == cashier.location.id) {
      _showDetails(cashier);
      return;
    }
    setState(() => _selected = cashier);
    final i = _topThree.indexWhere((c) => c.location.id == cashier.location.id);
    if (i >= 0 && _cardController.hasClients) {
      _cardController.animateToPage(
        i,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _showDetails(_NearbyCashier cashier) {
    setState(() => _selected = cashier);
    _focusCashier(cashier);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CashierDetailSheet(
        cashier: cashier,
        onViewOnMap: () => _focusCashier(cashier),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _selected = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearest Cashiers'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _buildError()
            : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_disabled_rounded, size: 48, color: _muted),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: StockpileFonts.satoshi(fontSize: 14, color: _muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
              onPressed: _load,
            ),
            if (_access == LocationAccess.serviceDisabled ||
                _access == LocationAccess.deniedForever) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Open settings'),
                onPressed: _access == LocationAccess.serviceDisabled
                    ? GeocodingService.openLocationSettings
                    : GeocodingService.openAppSettings,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Switches between a stacked phone layout and a side-by-side tablet
  /// layout purely from available width — no platform sniffing.
  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        return wide ? _buildWide() : _buildStacked();
      },
    );
  }

  // ── Map ────────────────────────────────────────────────────────────────
  Widget _buildMap() {
    return MapOverlay(
      map: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _mapCenter,
          initialZoom: _fallbackZoom,
          // Wins over initialCenter/initialZoom when it is non-null.
          initialCameraFit: _cameraFit,
          onTap: (_, _) => setState(() => _selected = null),
        ),
        children: [
          osmTileLayer(),
          // How sure the device is about "you". Only worth drawing when the
          // radius is wide enough to change which cashier is nearest.
          if (_myPosition != null &&
              (_myAccuracyMeters ?? 0) >
                  GeocodingService.approximateAccuracyMeters)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: _myPosition!,
                  radius: _myAccuracyMeters!,
                  useRadiusInMeter: true,
                  color: MapPinKind.you.color.withAlpha(24),
                  borderColor: MapPinKind.you.color.withAlpha(90),
                  borderStrokeWidth: 1.5,
                ),
              ],
            ),
          MarkerLayer(markers: _buildMarkers()),
        ],
      ),
      // One banner at a time, most actionable first.
      topLeft: _reducedAccuracy
          ? GestureDetector(
              onTap: GeocodingService.openAppSettings,
              child: const MapBanner(
                icon: Icons.gps_off_rounded,
                iconColor: StockpileColors.primary900,
                text:
                    'Precise location is off for this app, so distances are '
                    'a few km out. Tap to open settings and turn it on.',
              ),
            )
          : _usingSavedLocation
          ? const MapBanner(
              icon: Icons.bookmark_rounded,
              text:
                  'Using your saved member location — no live fix was '
                  'available.',
            )
          : _approximate
          ? MapBanner(
              text: _myAccuracyMeters != null
                  ? 'Your position is only accurate to about '
                        '${formatDistance(_myAccuracyMeters!)} right now.'
                  : 'Your position is approximate — estimated from your '
                        'internet connection because no fix was available.',
            )
          : null,
      topRight: [
        MapControlButton(
          icon: Icons.fit_screen_rounded,
          tooltip: 'Show everything nearby',
          onTap: _fitCamera,
        ),
        if (_myPosition != null)
          MapControlButton(
            icon: Icons.my_location_rounded,
            tooltip: 'Back to me',
            tint: MapPinKind.you.color,
            onTap: _focusMe,
          ),
      ],
      bottomLeft: MapLegend(
        items: [
          const MapLegendItem(StockpileColors.primary900, 'In stock'),
          if (_grayed.isNotEmpty)
            const MapLegendItem(
              StockpileColors.mutedText,
              'Out of stock',
              muted: true,
            ),
          if (_myPosition != null) MapLegendItem(MapPinKind.you.color, 'You'),
        ],
      ),
    );
  }

  // ── Phone: stacked map + horizontal swipe cards ─────────────────────────
  Widget _buildStacked() {
    return Column(
      children: [
        Expanded(child: _buildMap()),
        _buildBottomPanel(),
      ],
    );
  }

  // ── Tablet: side-by-side map + vertical list ────────────────────────────
  Widget _buildWide() {
    return Row(
      children: [
        Expanded(flex: 3, child: _buildMap()),
        Container(
          width: 360,
          decoration: BoxDecoration(
            color: _surface,
            border: Border(left: BorderSide(color: _divider)),
          ),
          child: _buildVerticalList(),
        ),
      ],
    );
  }

  Widget _buildVerticalList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: _panelHeader(),
        ),
        Divider(height: 1, color: _divider),
        Expanded(
          child: _topThree.isEmpty
              ? _buildEmpty(compact: false)
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _topThree.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final c = _topThree[index];
                    return _CashierCard(
                      cashier: c,
                      surface: _surface,
                      border: _divider,
                      textPrimary: _textPrimary,
                      muted: _muted,
                      selected: _selected?.location.id == c.location.id,
                      onTap: () => _showDetails(c),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surface,
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _panelHeader(),
              const SizedBox(height: 10),
              if (_topThree.isEmpty)
                _buildEmpty(compact: true)
              else ...[
                SizedBox(
                  height: 136,
                  child: PageView.builder(
                    controller: _cardController,
                    itemCount: _topThree.length,
                    // Swiping the strip is selecting: the map follows.
                    onPageChanged: (i) {
                      final c = _topThree[i];
                      setState(() {
                        _cardIndex = i;
                        _selected = c;
                      });
                      _focusCashier(c);
                    },
                    itemBuilder: (context, index) {
                      final c = _topThree[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _CashierCard(
                          cashier: c,
                          surface: _surface,
                          border: _divider,
                          textPrimary: _textPrimary,
                          muted: _muted,
                          selected: _selected?.location.id == c.location.id,
                          onTap: () => _showDetails(c),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                _pageDots(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < _topThree.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _cardIndex ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _cardIndex ? StockpileColors.primary900 : _divider,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }

  Widget _panelHeader() {
    final outCount = _all.length - _topThree.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            _topThree.isEmpty
                ? 'No stocked cashiers nearby'
                : 'Top ${_topThree.length} in stock near you',
            style: StockpileFonts.satoshi(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
        ),
        if (outCount > 0)
          Text(
            '$outCount out of stock',
            style: StockpileFonts.satoshi(fontSize: 12, color: _muted),
          ),
      ],
    );
  }

  Widget _buildEmpty({required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 18 : 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.store_mall_directory_outlined,
            size: compact ? 34 : 48,
            color: _muted,
          ),
          const SizedBox(height: 10),
          Text(
            _all.isEmpty
                ? 'No cashiers have saved a location yet.\nCheck back later.'
                : 'Every nearby cashier is out of stock right now.\n'
                      'Check back later.',
            textAlign: TextAlign.center,
            style: StockpileFonts.satoshi(fontSize: 13, color: _muted),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final selId = _selected?.location.id;
    return [
      // Out-of-stock first so anything live paints over them. No tap: a
      // buyer can't navigate to an empty branch.
      for (final c in _grayed)
        mapMarker(
          key: ValueKey('gray-${c.location.id}'),
          point: c.point,
          kind: c.kind,
          muted: true,
        ),
      if (_myPosition != null)
        mapMarker(point: _myPosition!, kind: MapPinKind.you),
      for (final c in _topThree)
        if (c.location.id != selId)
          mapMarker(
            key: ValueKey(c.location.id),
            point: c.point,
            kind: c.kind,
            label: c.distanceLabel,
            onTap: () => _selectFromPin(c),
          ),
      // Selected last: on top, bigger, with its name floating above.
      if (_selected case final s?) ...[
        mapMarker(
          key: ValueKey('sel-${s.location.id}'),
          point: s.point,
          kind: s.kind,
          selected: true,
          onTap: () => _selectFromPin(s),
        ),
        _callout(s),
      ],
    ];
  }

  Marker _callout(_NearbyCashier c) {
    const w = 200.0, h = 46.0;
    return Marker(
      point: c.point,
      width: w,
      height: h,
      alignment: Marker.computePixelAlignment(
        width: w,
        height: h,
        left: w / 2,
        top: h + 30,
      ),
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _divider),
              boxShadow: [
                BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 12),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.location.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                Text(
                  '${c.distanceLabel} · '
                  '${c.hasStock ? 'In stock · ${c.inStockCount} items' : 'Out of stock'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Cashier card ──────────────────────────────────────────────────────────

class _CashierCard extends StatelessWidget {
  final _NearbyCashier cashier;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color muted;
  final bool selected;
  final VoidCallback onTap;

  const _CashierCard({
    required this.cashier,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.muted,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = cashier.location;
    final inStock = cashier.hasStock;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kind = cashier.kind;
    final address = loc.address?.trim() ?? '';

    // Same avatar tints as the admin roster, so a branch looks like a
    // branch on every screen.
    final avatarBg = !inStock
        ? (isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg)
        : isDark
        ? kind.color.withAlpha(40)
        : kind == MapPinKind.branch
        ? StockpileColors.secondary50
        : const Color(0xFFFFE8D6);

    return Material(
      color: selected
          ? (isDark
                ? StockpileColors.primary900.withAlpha(30)
                : StockpileColors.primary50)
          : surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(selected ? 12 : 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? StockpileColors.primary900 : border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: avatarBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  kind.glyph,
                  size: 22,
                  color: inStock ? kind.color : StockpileColors.mutedText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StockpileFonts.satoshi(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _pill(
                          loc.roleLabel,
                          bg: kind == MapPinKind.branch
                              ? StockpileColors.secondary50
                              : (isDark
                                    ? StockpileColors.darkInputBg
                                    : StockpileColors.inputBg),
                          fg: kind == MapPinKind.branch
                              ? StockpileColors.secondary500
                              : StockpileColors.mutedText,
                        ),
                        const SizedBox(width: 6),
                        Flexible(child: _stockBadge(inStock)),
                      ],
                    ),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StockpileFonts.satoshi(
                          fontSize: 11,
                          color: muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? StockpileColors.primary900
                          : StockpileColors.primary900.withAlpha(25),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      cashier.distanceLabel,
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : StockpileColors.primary900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Icon(Icons.chevron_right_rounded, size: 20, color: muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: StockpileFonts.satoshi(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _stockBadge(bool inStock) {
    final color = inStock ? StockpileColors.success : StockpileColors.danger;
    final bg = inStock ? StockpileColors.successBg : StockpileColors.dangerBg;
    final n = cashier.inStockCount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              inStock ? 'In stock${n > 0 ? ' · $n' : ''}' : 'Out of stock',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StockpileFonts.satoshi(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detail bottom sheet ───────────────────────────────────────────────────

class _CashierDetailSheet extends StatelessWidget {
  final _NearbyCashier cashier;
  final VoidCallback? onViewOnMap;

  const _CashierDetailSheet({required this.cashier, this.onViewOnMap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;
    final textPrimary = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final loc = cashier.location;
    final inStock = cashier.hasStock;
    final inStockCount = cashier.stock.where((l) => l.inStock).length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85, // cap at 85vh.
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor:
                      (inStock ? StockpileColors.primary900 : Colors.grey)
                          .withAlpha(25),
                  child: Icon(
                    loc.isBranchCashier
                        ? Icons.storefront_rounded
                        : Icons.point_of_sale_rounded,
                    color: inStock
                        ? StockpileColors.primary900
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StockpileFonts.satoshi(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        loc.roleLabel,
                        style: StockpileFonts.satoshi(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: StockpileColors.primary900.withAlpha(25),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${cashier.distanceLabel} away',
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: StockpileColors.primary900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!inStock) ...[_outOfStockBadge(), const SizedBox(height: 16)],
            _sectionHeader('Address', textPrimary),
            const SizedBox(height: 6),
            Text(
              loc.address?.trim().isNotEmpty == true
                  ? loc.address!
                  : 'No readable address available.',
              style: StockpileFonts.satoshi(fontSize: 14, color: textPrimary),
            ),
            const SizedBox(height: 20),
            _sectionHeader(
              'Current Stock Inventory'
              '${cashier.stock.isEmpty ? '' : ' ($inStockCount in stock)'}',
              textPrimary,
            ),
            const SizedBox(height: 8),
            if (cashier.stock.isEmpty)
              _emptyInventory(textPrimary, muted)
            else
              for (final line in cashier.stock)
                _stockLine(line, textPrimary, muted, divider),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: inStock
                  ? () {
                      Navigator.pop(context);
                      onViewOnMap?.call();
                    }
                  : null,
              icon: Icon(
                inStock
                    ? Icons.place_rounded
                    : Icons.remove_shopping_cart_outlined,
              ),
              label: Text(inStock ? 'View on map' : 'Out of Stock'),
            ),
          ],
        );
      },
    );
  }

  Widget _outOfStockBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: StockpileColors.dangerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StockpileColors.danger.withAlpha(70)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.remove_shopping_cart_rounded,
            color: StockpileColors.danger,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Out of Stock — this location has no items right now.',
              style: StockpileFonts.satoshi(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: StockpileColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, Color textPrimary) {
    return Text(
      title,
      style: StockpileFonts.satoshi(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
    );
  }

  Widget _emptyInventory(Color textPrimary, Color muted) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        border: Border.all(color: muted.withAlpha(60)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'No inventory listed yet.',
        textAlign: TextAlign.center,
        style: StockpileFonts.satoshi(fontSize: 13, color: muted),
      ),
    );
  }

  Widget _stockLine(
    CashierStockLine line,
    Color textPrimary,
    Color muted,
    Color divider,
  ) {
    final inStock = line.inStock;
    final status = (line.status ?? '').trim();
    final statusColor = _statusColor(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                if (line.category != null && line.category!.trim().isNotEmpty)
                  Text(
                    line.category!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StockpileFonts.satoshi(fontSize: 11, color: muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${line.quantity} ${line.quantity == 1 ? 'unit' : 'units'}',
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: inStock ? textPrimary : muted,
                ),
              ),
              if (status.isNotEmpty) _statusChip(status, statusColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          status,
          style: StockpileFonts.satoshi(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Out of Stock':
        return StockpileColors.danger;
      case 'Low Stock':
        return StockpileColors.primary600;
      default:
        return StockpileColors.success;
    }
  }
}
