// lib/services/nominatim_geocoding_service.dart
// Platform-agnostic reverse geocoding via OpenStreetMap's Nominatim REST API.
//
// Replaces the native `geocoding` package, which only works on Android/iOS
// and throws on Windows desktop — where Cashiers and Branch Cashiers operate.
// Uses plain HTTP so it works on every platform the app targets.

import 'dart:convert';
import 'package:http/http.dart' as http;

/// A forward-geocoded candidate returned by [NominatimGeocodingService.search].
class NominatimSearchResult {
  final String displayName;
  final double latitude;
  final double longitude;

  const NominatimSearchResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
}

class NominatimGeocodingService {
  NominatimGeocodingService._();

  /// Nominatim strictly requires a descriptive User-Agent, otherwise
  /// requests are rejected with HTTP 403. Replace with a real contact address
  /// before shipping.
  static const String _userAgent = 'LZCAS-App/1.0 (contact@lzcas.app)';

  static const String _endpoint = 'https://nominatim.openstreetmap.org/reverse';

  /// Nominatim asks clients to keep requests modest; a short timeout stops a
  /// stalled call from hanging the settings screen indefinitely.
  static const Duration _timeout = Duration(seconds: 8);

  /// Convert coordinates into a human-readable address, e.g.
  /// "Poblacion, Solana, Cagayan".
  ///
  /// Never throws. Falls back to `display_name`, and only uses a raw
  /// "Lat X, Lng Y" string when the HTTP request times out or fails.
  static Future<String> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    final fallback = _fallback(latitude, longitude);

    try {
      final uri = Uri.parse(_endpoint).replace(
        queryParameters: {
          'format': 'json',
          'lat': latitude.toString(),
          'lon': longitude.toString(),
          'zoom': '18',
          'addressdetails': '1',
        },
      );

      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(_timeout);

      if (response.statusCode != 200) return fallback;

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return fallback;

      final address = body['address'];
      final displayName = body['display_name'] as String?;

      if (address is Map<String, dynamic>) {
        final formatted = formatAddress(address);
        if (formatted.isNotEmpty) return formatted;
      }

      if (displayName != null && displayName.trim().isNotEmpty) {
        return displayName.trim();
      }

      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  /// Build a PH-style address from Nominatim's `address` object:
  /// "street/barangay, city/municipality, province".
  ///
  /// Returns '' when nothing useful is present so the caller can fall back to
  /// `display_name`.
  static String formatAddress(Map<String, dynamic> address) {
    final street = _first(address, const ['road', 'pedestrian', 'footway']);
    final district = _first(address, const [
      'barangay',
      'neighbourhood',
      'suburb',
      'quarter',
      'hamlet',
    ]);
    final city = _first(address, const [
      'city',
      'municipality',
      'town',
      'village',
    ]);
    final province = _first(address, const [
      'province',
      'state',
      'region',
      'state_district',
    ]);

    // First component: prefer the road; otherwise use the barangay-level
    // value, so "Poblacion, Solana, Cagayan" (barangay, town, province) is
    // produced when no road is present.
    final level1 = street.isNotEmpty ? street : district;

    final parts = <String>[];
    _add(parts, level1);
    _add(parts, city);
    _add(parts, province);
    return parts.join(', ');
  }

  /// Forward geocode a free-text query (e.g. "Solana, Cagayan") into
  /// candidate coordinates for the manual address picker. Returns an empty
  /// list on failure.
  static Future<List<NominatimSearchResult>> search(
    String query, {
    int limit = 6,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
          .replace(
            queryParameters: {
              'format': 'json',
              'q': trimmed,
              'limit': limit.toString(),
              'addressdetails': '1',
            },
          );

      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(_timeout);

      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body);
      if (body is! List) return const [];

      final results = <NominatimSearchResult>[];
      for (final item in body) {
        if (item is! Map<String, dynamic>) continue;
        final lat = (item['lat'] as num?)?.toDouble();
        final lon = (item['lon'] as num?)?.toDouble();
        final name = item['display_name'] as String? ?? '';
        if (lat == null || lon == null || name.trim().isEmpty) continue;
        results.add(
          NominatimSearchResult(
            displayName: name.trim(),
            latitude: lat,
            longitude: lon,
          ),
        );
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  static String _first(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  /// Add a part unless it duplicates (case-insensitively) one already added.
  static void _add(List<String> parts, String value) {
    if (value.isEmpty) return;
    final lower = value.toLowerCase();
    if (parts.any((p) => p.toLowerCase() == lower)) return;
    parts.add(value);
  }

  static String _fallback(double latitude, double longitude) =>
      'Lat ${latitude.toStringAsFixed(5)}, Lng ${longitude.toStringAsFixed(5)}';
}
