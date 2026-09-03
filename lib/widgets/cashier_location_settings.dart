// lib/widgets/cashier_location_settings.dart
// Reusable "Cashier Location" settings panel for Cashier and Branch Cashier
// dashboards. Saves the signed-in staff member's location to their profile:
//
//   1. GPS (strict 5s timeout)  → reverse geocode → save
//   2. IP geolocation fallback  → reverse geocode → save (approximate)
//   3. Manual address search    → forward geocode → save
//
// Address resolution is cross-platform: native geocoding on mobile, Nominatim
// HTTP on desktop/web — so it works on Windows/Linux and devices without GPS.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bot_toast/bot_toast.dart';
import '../auth/auth.dart';
import '../db/db.dart';
import '../services/geocoding_service.dart';
import '../services/nominatim_geocoding_service.dart';
import '../theme.dart';
import '../utils/fonts.dart';
import '../utils/formatters.dart' show formatRelativeDate;

class CashierLocationSettings extends StatefulWidget {
  const CashierLocationSettings({super.key});

  @override
  State<CashierLocationSettings> createState() =>
      _CashierLocationSettingsState();
}

class _CashierLocationSettingsState extends State<CashierLocationSettings> {
  bool _loading = true;
  bool _saving = false;
  bool _searching = false;
  CashierLocation? _location;

  final _searchCtrl = TextEditingController();
  List<NominatimSearchResult> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthState>();
    final uid = auth.userId;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final loc = await repository.fetchCashierLocation(uid);
      if (!mounted) return;
      setState(() {
        _location = loc;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_saving) return;

    // Capture the user id up front so no BuildContext use happens after an
    // async gap below (keeps the linter's use_build_context_synchronously
    // rule happy and avoids acting on a stale context).
    final uid = context.read<AuthState>().userId;
    if (uid == null) {
      BotToast.showText(text: 'Not signed in.');
      return;
    }

    setState(() => _saving = true);

    try {
      final access = await GeocodingService.ensureAccess();
      if (!mounted) return;
      switch (access) {
        case LocationAccess.serviceDisabled:
          BotToast.showText(
            text:
                'Location services are turned off. Enable them in Settings, '
                'or use the address search below.',
          );
          return;
        case LocationAccess.denied:
          BotToast.showText(
            text:
                'Location permission denied. Please allow it, or use the '
                'address search below.',
          );
          return;
        case LocationAccess.deniedForever:
          BotToast.showText(
            text:
                'Location permission is permanently denied. Enable it in your '
                'device settings, or use the address search below.',
          );
          return;
        case LocationAccess.unableToDetermine:
          BotToast.showText(
            text:
                'Could not determine location permission. Try again, or use '
                'the address search below.',
          );
          return;
        case LocationAccess.granted:
          break;
      }

      // GPS first (strict 5s timeout), then IP geolocation for desktops
      // without a GPS chip.
      final point = await GeocodingService.resolvePosition(
        gpsTimeout: const Duration(seconds: 5),
      );
      if (!mounted) return;

      if (point == null) {
        BotToast.showText(
          text:
              "Couldn't detect your location. Use the address search below "
              'to set it manually.',
        );
        return;
      }

      final address = await GeocodingService.reverseGeocode(
        point.latitude,
        point.longitude,
      );

      await repository.updateCashierLocation(
        userId: uid,
        latitude: point.latitude,
        longitude: point.longitude,
        address: address,
      );
      if (!mounted) return;
      BotToast.showText(
        text: point.isApproximate
            ? 'Location saved (approximate, based on your IP address)'
            : 'Cashier location saved',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not get your location: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Remove the saved location after confirming. Behind a confirmation
  /// because the consequence is invisible from this screen — the cashier
  /// simply stops appearing on every member's map.
  Future<void> _removeLocation() async {
    final uid = context.read<AuthState>().userId;
    if (uid == null) {
      BotToast.showText(text: 'Not signed in.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Remove saved location?'),
        content: const Text(
          'You will stop appearing in the members’ Nearest Cashiers map '
          'until you set a location again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: StockpileColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await repository.clearCashierLocation(userId: uid);
      if (!mounted) return;
      BotToast.showText(text: 'Saved location removed');
      await _load();
    } catch (e) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not remove location: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _searchAddress() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      BotToast.showText(text: 'Type an address to search.');
      return;
    }

    setState(() => _searching = true);
    try {
      final results = await NominatimGeocodingService.search(query);
      if (!mounted) return;
      setState(() => _searchResults = results);
      if (results.isEmpty) {
        BotToast.showText(text: 'No matching places found.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _searchResults = const []);
      BotToast.showText(text: 'Address search failed. Try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickSearchResult(NominatimSearchResult result) async {
    final uid = context.read<AuthState>().userId;
    if (uid == null) {
      BotToast.showText(text: 'Not signed in.');
      return;
    }

    setState(() => _saving = true);
    try {
      // Save the name the cashier actually tapped. Reverse-geocoding these
      // coordinates instead would fire a second Nominatim call within a
      // second of the search (their policy allows one per second) and could
      // store an address that reads differently from the row that was picked.
      await repository.updateCashierLocation(
        userId: uid,
        latitude: result.latitude,
        longitude: result.longitude,
        address: result.displayName,
      );
      if (!mounted) return;
      BotToast.showText(text: 'Cashier location saved');
      setState(() => _searchResults = const []);
      _searchCtrl.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not save location: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLocationCard(isDark, surface, divider, textPrimary, muted),
              const SizedBox(height: 16),
              _buildSearchCard(isDark, surface, divider, textPrimary, muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationCard(
    bool isDark,
    Color surface,
    Color divider,
    Color textPrimary,
    Color muted,
  ) {
    return Card(
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on_rounded,
                  color: StockpileColors.primary900,
                ),
                const SizedBox(width: 10),
                Text(
                  'Cashier Location',
                  style: StockpileFonts.satoshi(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Members use this location to find you in the Nearest '
              'Cashiers map. It is a static point — no live tracking.',
              style: StockpileFonts.satoshi(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 20),
            _buildSavedLocation(isDark, muted, textPrimary, divider),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.my_location_rounded),
                label: Text(
                  _saving
                      ? 'Getting location…'
                      : 'Do you want to use your current location '
                            'as your Cashier Location?',
                  textAlign: TextAlign.center,
                ),
                onPressed: _saving ? null : _useCurrentLocation,
              ),
            ),
            // Only offered once there is something to remove.
            if (!_loading && _location != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  icon: const Icon(Icons.location_off_rounded, size: 18),
                  label: const Text('Remove saved location'),
                  style: TextButton.styleFrom(
                    foregroundColor: StockpileColors.danger,
                  ),
                  onPressed: _saving ? null : _removeLocation,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchCard(
    bool isDark,
    Color surface,
    Color divider,
    Color textPrimary,
    Color muted,
  ) {
    final inputFill = isDark
        ? StockpileColors.darkInputBg
        : StockpileColors.inputBg;

    return Card(
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search_rounded, color: StockpileColors.primary900),
                const SizedBox(width: 10),
                Text(
                  'Set your location manually',
                  style: StockpileFonts.satoshi(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Can't detect your location? Search for your city, barangay or "
              'branch address, then pick a result to save it.',
              style: StockpileFonts.satoshi(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onSubmitted: (_) => _searchAddress(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'e.g. Solana, Cagayan',
                      prefixIcon: const Icon(Icons.place_rounded, size: 20),
                      filled: true,
                      fillColor: inputFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: divider),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _searching ? null : _searchAddress,
                  child: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Search'),
                ),
              ],
            ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Results',
                style: StockpileFonts.satoshi(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
              const SizedBox(height: 6),
              ..._searchResults.map(
                (r) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  dense: true,
                  leading: Icon(
                    Icons.add_location_alt_rounded,
                    color: StockpileColors.primary900,
                  ),
                  title: Text(
                    r.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      color: textPrimary,
                    ),
                  ),
                  onTap: _saving ? null : () => _pickSearchResult(r),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSavedLocation(
    bool isDark,
    Color muted,
    Color textPrimary,
    Color divider,
  ) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final loc = _location;
    if (loc == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 20, color: muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No location saved yet.',
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: StockpileColors.success,
              ),
              const SizedBox(width: 8),
              Text(
                'Current saved location',
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            loc.address?.trim().isNotEmpty == true
                ? loc.address!
                : 'Address unavailable',
            style: StockpileFonts.satoshi(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 4),
          Text(
            '${loc.latitude.toStringAsFixed(5)}, '
            '${loc.longitude.toStringAsFixed(5)}',
            style: StockpileFonts.satoshi(fontSize: 11, color: muted),
          ),
          if (loc.locationUpdatedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Last updated ${formatRelativeDate(loc.locationUpdatedAt)}',
              style: StockpileFonts.satoshi(fontSize: 11, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
