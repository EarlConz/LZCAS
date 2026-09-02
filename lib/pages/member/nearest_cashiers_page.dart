// lib/pages/member/nearest_cashiers_page.dart
// Dedicated "Nearest Cashiers" screen for Members (Buyers).
//
// Static GPS map only: it plots the member's current position and every
// cashier / branch cashier who has saved a location, sorted by straight-line
// distance. There is NO live navigation or routing.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../db/db.dart';
import '../../services/geocoding_service.dart';
import '../../theme.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart' show formatDistance;

class NearestCashiersPage extends StatefulWidget {
  const NearestCashiersPage({super.key});

  @override
  State<NearestCashiersPage> createState() => _NearestCashiersPageState();
}

/// A cashier with its precomputed distance from the member, for the list.
class _NearbyCashier {
  final CashierLocation location;
  final double distanceMeters;

  const _NearbyCashier(this.location, this.distanceMeters);

  LatLng get point => LatLng(location.latitude, location.longitude);
  String get distanceLabel => formatDistance(distanceMeters);
}

class _NearestCashiersPageState extends State<NearestCashiersPage> {
  bool _loading = true;
  String? _error;
  LatLng? _myPosition;
  List<_NearbyCashier> _cashiers = const [];
  _NearbyCashier? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final access = await GeocodingService.ensureAccess();
      if (!mounted) return;
      if (access != LocationAccess.granted) {
        setState(() {
          _loading = false;
          _error = _messageFor(access);
        });
        return;
      }

      final point = await GeocodingService.currentPosition();
      final myPos = LatLng(point.latitude, point.longitude);

      final locations = await repository.fetchCashierLocations();

      final nearby = <_NearbyCashier>[];
      for (final loc in locations) {
        final meters = Geolocator.distanceBetween(
          myPos.latitude,
          myPos.longitude,
          loc.latitude,
          loc.longitude,
        );
        nearby.add(_NearbyCashier(loc, meters));
      }
      nearby.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

      if (!mounted) return;
      setState(() {
        _myPosition = myPos;
        _cashiers = nearby;
        _loading = false;
      });
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

  LatLng get _mapCenter {
    if (_myPosition != null) return _myPosition!;
    if (_cashiers.isNotEmpty) return _cashiers.first.point;
    // Default fallback — somewhere central in the Philippines.
    return const LatLng(12.8797, 121.7740);
  }

  double get _mapZoom {
    if (_myPosition != null && _cashiers.isNotEmpty) {
      // Zoom out a little when markers are far apart so they all fit.
      return 12;
    }
    return 14;
  }

  void _showDetails(_NearbyCashier cashier) {
    setState(() => _selected = cashier);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CashierDetailSheet(cashier: cashier),
    ).whenComplete(() {
      if (mounted) setState(() => _selected = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            ? _buildError(isDark)
            : _buildContent(isDark),
      ),
    );
  }

  Widget _buildError(bool isDark) {
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_disabled_rounded, size: 48, color: muted),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: StockpileFonts.satoshi(fontSize: 14, color: muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
              onPressed: _load,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;
    final textPrimary = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Column(
      children: [
        // ── Map ──────────────────────────────────────────────────
        SizedBox(
          height: 300,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: _mapZoom,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.lzcas.app',
              ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Result count / heading ───────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _cashiers.isEmpty
                      ? 'No nearby cashiers found'
                      : '${_cashiers.length} nearby '
                            '${_cashiers.length == 1 ? 'cashier' : 'cashiers'}',
                  style: StockpileFonts.satoshi(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
              if (_cashiers.isNotEmpty)
                Text(
                  'Closest first',
                  style: StockpileFonts.satoshi(fontSize: 12, color: muted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Divider(height: 1, color: divider),

        // ── Cashier list ────────────────────────────────────────
        Expanded(
          child: _cashiers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.store_mall_directory_outlined,
                        size: 48,
                        color: muted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No cashiers have saved a location yet.\n'
                        'Check back later.',
                        textAlign: TextAlign.center,
                        style: StockpileFonts.satoshi(
                          fontSize: 13,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _cashiers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final c = _cashiers[index];
                    return _CashierCard(
                      cashier: c,
                      surface: surface,
                      divider: divider,
                      textPrimary: textPrimary,
                      muted: muted,
                      selected: _selected?.location.id == c.location.id,
                      onTap: () => _showDetails(c),
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_myPosition != null) {
      markers.add(
        Marker(
          point: _myPosition!,
          width: 44,
          height: 44,
          child: const Icon(
            Icons.my_location_rounded,
            size: 34,
            color: Color(0xFF1D4ED8),
            shadows: [Shadow(color: Colors.white, blurRadius: 4)],
          ),
        ),
      );
    }

    for (final c in _cashiers) {
      markers.add(
        Marker(
          point: c.point,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _showDetails(c),
            child: Icon(
              c.location.isBranchCashier
                  ? Icons.storefront_rounded
                  : Icons.point_of_sale_rounded,
              size: 34,
              color: StockpileColors.primary900,
              shadows: const [Shadow(color: Colors.white, blurRadius: 4)],
            ),
          ),
        ),
      );
    }

    return markers;
  }
}

// ─── Cashier list card ─────────────────────────────────────────────────────

class _CashierCard extends StatelessWidget {
  final _NearbyCashier cashier;
  final Color surface;
  final Color divider;
  final Color textPrimary;
  final Color muted;
  final bool selected;
  final VoidCallback onTap;

  const _CashierCard({
    required this.cashier,
    required this.surface,
    required this.divider,
    required this.textPrimary,
    required this.muted,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = cashier.location;
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? StockpileColors.primary900 : divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: StockpileColors.primary900.withAlpha(25),
                child: Icon(
                  loc.isBranchCashier
                      ? Icons.storefront_rounded
                      : Icons.point_of_sale_rounded,
                  size: 20,
                  color: StockpileColors.primary900,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.name,
                      style: StockpileFonts.satoshi(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loc.roleLabel,
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
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
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: StockpileColors.primary900.withAlpha(25),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${cashier.distanceLabel} away',
                  style: StockpileFonts.satoshi(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: StockpileColors.primary900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Detail bottom sheet ───────────────────────────────────────────────────

class _CashierDetailSheet extends StatelessWidget {
  final _NearbyCashier cashier;

  const _CashierDetailSheet({required this.cashier});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
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

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  backgroundColor: StockpileColors.primary900.withAlpha(25),
                  child: Icon(
                    loc.isBranchCashier
                        ? Icons.storefront_rounded
                        : Icons.point_of_sale_rounded,
                    color: StockpileColors.primary900,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.name,
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
            const SizedBox(height: 20),
            _detailRow(Icons.place_rounded, 'Address', textPrimary, muted),
            const SizedBox(height: 6),
            Text(
              loc.address?.trim().isNotEmpty == true
                  ? loc.address!
                  : 'No readable address available.',
              style: StockpileFonts.satoshi(fontSize: 14, color: textPrimary),
            ),
            const SizedBox(height: 12),
            _detailRow(
              Icons.my_location_rounded,
              'Coordinates',
              textPrimary,
              muted,
            ),
            const SizedBox(height: 6),
            Text(
              '${loc.latitude.toStringAsFixed(5)}, '
              '${loc.longitude.toStringAsFixed(5)}',
              style: StockpileFonts.satoshi(fontSize: 14, color: textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    Color textPrimary,
    Color muted,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: muted),
        const SizedBox(width: 8),
        Text(
          label,
          style: StockpileFonts.satoshi(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
      ],
    );
  }
}
