// lib/widgets/location_selection_widget.dart
// Reusable "set my location" panel shared by Cashier, Branch Cashier and
// Member roles. It owns the cross-platform location pipeline:
//
//   1. GPS (strict 5s timeout)  → reverse geocode → fills the detected area
//   2. IP geolocation fallback  → reverse geocode → fills the detected area
//   3. Manual address search    → forward geocode → fills the detected area
//
// The detected locality (barangay/city/province) is shown as a reference and
// appended to the user's typed "Detailed / Complete Address" when they tap
// "Save Location" (e.g. "House #12, Green St. (Poblacion, Solana, Cagayan)").
//
// The GPS/geocoding logic itself lives in `GeocodingService` and
// `NominatimGeocodingService` — this widget only orchestrates it and renders
// the results, parameterised so each role can supply its own labels and
// persistence callbacks without duplicating any pipeline code.

import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import '../services/geocoding_service.dart';
import '../services/nominatim_geocoding_service.dart';
import '../theme.dart';
import '../utils/fonts.dart';
import '../utils/formatters.dart' show formatRelativeDate;

/// A saved coordinate pair plus the fields the UI renders. Deliberately a
/// plain, role-agnostic value type so callers can map any repository model
/// (`CashierLocation`, `Member`, …) onto it.
class SavedLocation {
  final double latitude;
  final double longitude;
  final String? address;
  final DateTime? updatedAt;

  const SavedLocation({
    required this.latitude,
    required this.longitude,
    this.address,
    this.updatedAt,
  });
}

/// Reusable location settings panel.
///
/// All persistence is injected via callbacks so the widget never talks to a
/// repository directly — [onLoad] returns the current saved location (or
/// null), [onSave] persists a new one, and [onClear] removes it.
class LocationSelectionWidget extends StatefulWidget {
  /// Card heading, e.g. 'Cashier Location' or 'Member Location'.
  final String title;

  /// One-paragraph explanation shown under the heading.
  final String description;

  /// The primary action button label, e.g.
  /// 'Do you want to use your current location as your Cashier Location?'.
  final String actionLabel;

  /// Toast shown after a successful save.
  final String savedToast;

  /// Toast shown when the saved point came from IP geolocation.
  final String approximateToast;

  /// Title of the "remove saved location" confirmation dialog.
  final String removeDialogTitle;

  /// Body of the "remove saved location" confirmation dialog.
  final String removeDialogBody;

  final Future<SavedLocation?> Function() onLoad;
  final Future<void> Function(double latitude, double longitude, String address)
  onSave;
  final Future<void> Function() onClear;

  /// When false the panel renders as a bare column of cards so it can live
  /// inside an existing scroll view (e.g. the Member Profile tab). When true
  /// (the default) it wraps itself in a `SingleChildScrollView` for use as a
  /// full-height tab body (Cashier / Branch Cashier).
  final bool scrollable;

  const LocationSelectionWidget({
    super.key,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.savedToast,
    required this.approximateToast,
    required this.removeDialogTitle,
    required this.removeDialogBody,
    required this.onLoad,
    required this.onSave,
    required this.onClear,
    this.scrollable = true,
  });

  @override
  State<LocationSelectionWidget> createState() =>
      _LocationSelectionWidgetState();
}

class _LocationSelectionWidgetState extends State<LocationSelectionWidget> {
  bool _loading = true;
  bool _saving = false;
  bool _searching = false;
  SavedLocation? _location;

  final _searchCtrl = TextEditingController();
  final _detailCtrl = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  List<NominatimSearchResult> _searchResults = const [];

  /// Detected (but not yet saved) coordinates + auto-resolved locality.
  double? _detectedLat;
  double? _detectedLng;
  String? _detectedArea;
  bool _detectedApproximate = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _detailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final loc = await widget.onLoad();
      if (!mounted) return;
      setState(() {
        _location = loc;
        _loading = false;
        // Seed the detected coordinates from the saved location so the user
        // can simply refine the address and re-save without re-detecting.
        _detectedLat = loc?.latitude;
        _detectedLng = loc?.longitude;
        // Pre-fill the detailed field with the existing saved address.
        if (loc?.address?.trim().isNotEmpty == true) {
          _detailCtrl.text = loc!.address!.trim();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_saving) return;

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

      // Detect only — do not persist yet. The user still needs to type their
      // detailed address and tap "Save Location".
      if (!mounted) return;
      setState(() {
        _detectedLat = point.latitude;
        _detectedLng = point.longitude;
        _detectedArea = address.trim().isEmpty ? null : address.trim();
        _detectedApproximate = point.isApproximate;
      });
      BotToast.showText(
        text: 'Location detected — enter your detailed address, then Save.',
      );
    } catch (e) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not get your location: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Remove the saved location after confirming. Behind a confirmation
  /// because the consequence is invisible from this screen — the role simply
  /// stops appearing on (or relying on) the location map.
  Future<void> _removeLocation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(widget.removeDialogTitle),
        content: Text(widget.removeDialogBody),
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
      await widget.onClear();
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
    // Select only — the picked place becomes the detected locality and the
    // user finishes the detailed address before saving. Reverse-geocoding
    // these coordinates instead would fire a second Nominatim call within a
    // second of the search (their policy allows one per second).
    setState(() {
      _detectedLat = result.latitude;
      _detectedLng = result.longitude;
      _detectedArea = result.displayName;
      _detectedApproximate = false;
      _searchResults = const [];
    });
    _searchCtrl.clear();
  }

  /// Persist the detected coordinates plus the combined address string.
  Future<void> _saveLocation() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final lat = _detectedLat;
    final lng = _detectedLng;
    if (lat == null || lng == null) {
      BotToast.showText(text: 'Detect your location or pick a place first.');
      return;
    }

    setState(() => _saving = true);
    try {
      final combined = _combineAddress(_detailCtrl.text, _detectedArea);
      await widget.onSave(lat, lng, combined);
      if (!mounted) return;
      BotToast.showText(
        text: _detectedApproximate
            ? widget.approximateToast
            : widget.savedToast,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not save location: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Join the typed street detail with the auto-resolved locality, e.g.
  /// "House #12, Green St. (Poblacion, Solana, Cagayan)". Dedupes when the
  /// detail already contains the locality.
  String _combineAddress(String detailed, String? area) {
    final d = detailed.trim();
    final a = (area ?? '').trim();
    if (a.isEmpty) return d;
    if (d.isEmpty) return a;
    if (d.toLowerCase().contains(a.toLowerCase())) return d;
    return '$d ($a)';
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

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLocationCard(isDark, surface, divider, textPrimary, muted),
        const SizedBox(height: 16),
        _buildSearchCard(isDark, surface, divider, textPrimary, muted),
      ],
    );

    if (!widget.scrollable) return content;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: content,
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
                  widget.title,
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
              widget.description,
              style: StockpileFonts.satoshi(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 20),
            _buildSavedLocation(isDark, muted, textPrimary, divider),
            const SizedBox(height: 20),
            _buildDetailedAddressField(isDark, muted, textPrimary, divider),
            const SizedBox(height: 12),
            _buildDetectedAreaCard(isDark, muted, textPrimary, divider),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
                label: Text(
                  _saving ? 'Detecting…' : widget.actionLabel,
                  textAlign: TextAlign.center,
                ),
                onPressed: _saving ? null : _useCurrentLocation,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: StockpileColors.primary900,
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(_saving ? 'Saving…' : 'Save Location'),
                onPressed: _saving ? null : _saveLocation,
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

  /// Required "Detailed / Complete Address" field — pre-filled from any
  /// existing saved address.
  Widget _buildDetailedAddressField(
    bool isDark,
    Color muted,
    Color textPrimary,
    Color divider,
  ) {
    final inputFill = isDark
        ? StockpileColors.darkInputBg
        : StockpileColors.inputBg;

    return Form(
      key: _formKey,
      child: TextFormField(
        controller: _detailCtrl,
        maxLines: 3,
        validator: (v) => (v == null || v.trim().isEmpty)
            ? 'Enter your detailed address'
            : null,
        decoration: InputDecoration(
          labelText: 'Detailed / Complete Address *',
          hintText: 'e.g., House/Block/Lot No., Street Name, Floor, Landmark',
          alignLabelWithHint: true,
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
    );
  }

  /// Reference card for the auto-resolved locality (barangay/city/province)
  /// and the detected coordinates.
  Widget _buildDetectedAreaCard(
    bool isDark,
    Color muted,
    Color textPrimary,
    Color divider,
  ) {
    final inputFill = isDark
        ? StockpileColors.darkInputBg
        : StockpileColors.inputBg;
    final hasArea = (_detectedArea ?? '').trim().isNotEmpty;
    final hasCoords = _detectedLat != null && _detectedLng != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.my_location_rounded,
                size: 20,
                color: StockpileColors.primary900,
              ),
              const SizedBox(width: 8),
              Text(
                'Detected area',
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
            hasArea
                ? _detectedArea!
                : (hasCoords
                      ? 'Coordinates detected — no locality resolved.'
                      : 'No location detected yet.'),
            style: StockpileFonts.satoshi(fontSize: 13, color: muted),
          ),
          if (hasCoords) ...[
            const SizedBox(height: 4),
            Text(
              '${_detectedLat!.toStringAsFixed(5)}, '
              '${_detectedLng!.toStringAsFixed(5)}',
              style: StockpileFonts.satoshi(fontSize: 11, color: muted),
            ),
          ],
        ],
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
              'address, then pick a result to save it.',
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
          if (loc.updatedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Last updated ${formatRelativeDate(loc.updatedAt)}',
              style: StockpileFonts.satoshi(fontSize: 11, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
