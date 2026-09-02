// lib/services/geocoding_service.dart
// Hybrid, cross-platform location + reverse geocoding for the Nearest Cashier
// Finder.
//
// Coordinate resolution: geolocator GPS first (with a strict timeout), then
// IP geolocation for desktops without a GPS chip. Address resolution: the
// native `geocoding` package on mobile, Nominatim (HTTP) on desktop/web — so
// it works on Windows/Linux and on devices without GPS hardware.
//
// No live routing — coordinates are fetched once and distances are computed
// with Geolocator.distanceBetween().

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'nominatim_geocoding_service.dart';

/// A resolved coordinate pair, plus the method that produced it.
class LocatedPoint {
  final double latitude;
  final double longitude;
  final PositionSource source;

  const LocatedPoint({
    required this.latitude,
    required this.longitude,
    this.source = PositionSource.gps,
  });

  /// IP-derived coordinates are approximate — the UI can say so.
  bool get isApproximate => source == PositionSource.ip;
}

/// How a [LocatedPoint] was obtained.
enum PositionSource { gps, ip }

class GeocodingService {
  GeocodingService._();

  // ── Permission ───────────────────────────────────────────────────────────

  /// Ensure location services are on and permission has been granted.
  ///
  /// Returns an enum so the caller can show a precise, actionable message.
  static Future<LocationAccess> ensureAccess() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return LocationAccess.serviceDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return LocationAccess.granted;
      case LocationPermission.denied:
        return LocationAccess.denied;
      case LocationPermission.deniedForever:
        return LocationAccess.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationAccess.unableToDetermine;
    }
  }

  // ── Coordinate resolution (GPS → IP fallback) ────────────────────────────

  /// Fetch GPS coordinates with a strict [timeout]. Throws on failure.
  static Future<LocatedPoint> currentPosition({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(timeout);
    return LocatedPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  /// Resolve a location for this device: GPS first (with [gpsTimeout]), then
  /// IP geolocation. Returns null only when both fail.
  static Future<LocatedPoint?> resolvePosition({
    Duration gpsTimeout = const Duration(seconds: 5),
  }) async {
    try {
      return await currentPosition(timeout: gpsTimeout);
    } catch (_) {
      return await ipGeolocation();
    }
  }

  /// Approximate desktop coordinates from the device's public IP address.
  /// Returns null when the request fails or the device is offline.
  static Future<LocatedPoint?> ipGeolocation() async {
    try {
      final response = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;

      final lat = (body['latitude'] as num?)?.toDouble();
      final lon = (body['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;

      return LocatedPoint(
        latitude: lat,
        longitude: lon,
        source: PositionSource.ip,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Reverse geocoding (native on mobile, Nominatim elsewhere) ────────────

  /// Convert coordinates into a readable address, e.g. "Poblacion, Solana,
  /// Cagayan". Mobile uses the native `geocoding` package; desktop/web (and
  /// any mobile failure) use Nominatim. Never throws.
  static Future<String> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    if (_isMobile) {
      try {
        final placemarks = await geocoding.placemarkFromCoordinates(
          latitude,
          longitude,
        );
        if (placemarks.isNotEmpty) {
          final formatted = _formatPlacemark(placemarks.first);
          if (formatted.isNotEmpty) return formatted;
        }
      } catch (_) {
        // Fall through to Nominatim below.
      }
    }
    return NominatimGeocodingService.reverseGeocode(latitude, longitude);
  }

  /// Build the address string from the parts geocoding gives us for PH-style
  /// addresses. `subLocality` carries the barangay and `locality` the
  /// city/municipality, with `administrativeArea` as the province.
  static String _formatPlacemark(geocoding.Placemark p) {
    final parts = <String>[
      if (_nonEmpty(p.street)) p.street!.trim(),
      if (_nonEmpty(p.subLocality)) p.subLocality!.trim(), // barangay
      if (_nonEmpty(p.locality)) p.locality!.trim(), // city / municipality
      if (_nonEmpty(p.administrativeArea))
        p.administrativeArea!.trim(), // province
    ];
    return parts.join(', ');
  }

  static bool _nonEmpty(String? s) => s != null && s.trim().isNotEmpty;

  /// True on Android/iOS — the only platforms with native geocoding support.
  static bool get _isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }
}

/// Outcome of [GeocodingService.ensureAccess] so the UI can tailor its error.
enum LocationAccess {
  granted,
  serviceDisabled,
  denied,
  deniedForever,
  unableToDetermine,
}
