// lib/services/geocoding_service.dart
// Hybrid, cross-platform location + reverse geocoding.
//
// Coordinate resolution, in order of trust:
//
//   1. A fresh device fix. On phones we listen to the position stream for
//      up to [resolvePosition]'s timeout and stop early at the first fix
//      inside [goodAccuracyMeters]; if nothing that good arrives we keep the
//      best we saw. On desktop we ask once (Windows positions from Wi-Fi,
//      or its own IP fallback, and reports how sure it is).
//   2. The device's last known fix, if it is recent. Seconds old and usually
//      metres accurate — far better than guessing.
//   3. The caller's own saved point, when it passes one in.
//   4. IP geolocation, clearly marked. This is the ISP's location, not the
//      user's, and can be a province away; it is a last resort, never a
//      quiet substitute for GPS.
//
// Every result carries its source and accuracy so screens can say how much
// to trust it, and refuse to save the ones that shouldn't be saved.
//
// The 1.5.0 pipeline gave GPS five seconds and then silently used the IP
// guess — which is why the same member got a real fix one time and Manila
// the next. Address resolution: the native `geocoding` package on mobile,
// Nominatim (HTTP) on desktop/web.
//
// No live routing — distances are computed with Geolocator.distanceBetween().

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'nominatim_geocoding_service.dart';

/// How a [LocatedPoint] was obtained, best first.
enum PositionSource {
  /// A fresh fix from the device (GPS, or Wi-Fi/cell positioning).
  gps,

  /// The device's cached last fix, recent enough to trust.
  lastKnown,

  /// The point the user saved earlier (their profile location).
  saved,

  /// Guessed from the public IP address — the ISP's location.
  ip,
}

/// A resolved coordinate pair, plus the method that produced it and how
/// accurate the device claims it is.
class LocatedPoint {
  final double latitude;
  final double longitude;
  final PositionSource source;

  /// Radius in metres the device is confident about, when it says. Null for
  /// IP guesses and saved points, which have no honest number.
  final double? accuracyMeters;

  final DateTime? timestamp;

  const LocatedPoint({
    required this.latitude,
    required this.longitude,
    this.source = PositionSource.gps,
    this.accuracyMeters,
    this.timestamp,
  });

  factory LocatedPoint.fromPosition(Position p, PositionSource source) =>
      LocatedPoint(
        latitude: p.latitude,
        longitude: p.longitude,
        source: source,
        accuracyMeters: p.accuracy > 0 ? p.accuracy : null,
        timestamp: p.timestamp,
      );

  /// IP-derived, or a device fix too loose to put a pin on a shop with.
  /// Android's "Approximate location" permission yields ~2 km fixes that
  /// also drift over time; those must not be saved as if they were exact.
  bool get isApproximate =>
      source == PositionSource.ip ||
      (accuracyMeters != null &&
          accuracyMeters! > GeocodingService.approximateAccuracyMeters);

  /// Good enough to save as a place: a real fix inside ~100 m.
  bool get isPrecise =>
      (source == PositionSource.gps || source == PositionSource.lastKnown) &&
      accuracyMeters != null &&
      accuracyMeters! <= GeocodingService.goodAccuracyMeters;
}

class GeocodingService {
  GeocodingService._();

  /// A fix inside this radius ends the wait early — it is a door, not a
  /// district.
  static const double goodAccuracyMeters = 100;

  /// Beyond this the fix is labelled approximate and the setter refuses to
  /// save it without the user adjusting the pin.
  static const double approximateAccuracyMeters = 250;

  /// How stale a cached fix may be before we'd rather have nothing.
  static const Duration lastKnownMaxAge = Duration(minutes: 5);

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

  /// Android 12+ / iOS 14+ let the user grant "Approximate location" only,
  /// which fuzzes every fix to a couple of kilometres. True when that is
  /// the case, so the UI can ask for Precise. False wherever the concept
  /// does not exist.
  static Future<bool> isReducedAccuracy() async {
    try {
      final status = await Geolocator.getLocationAccuracy();
      return status == LocationAccuracyStatus.reduced;
    } catch (_) {
      return false;
    }
  }

  /// Take the user to the system page where the problem is fixed. Both
  /// return false when the platform has no such page.
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();
  static Future<bool> openLocationSettings() =>
      Geolocator.openLocationSettings();

  // ── Coordinate resolution ────────────────────────────────────────────────

  /// Resolve where this device is. See the file header for the order.
  ///
  /// [saved] is the caller's stored point, tried before the IP guess.
  /// [allowIp] false means "I would rather have null than a guess" — the
  /// right choice for anything that will be persisted.
  static Future<LocatedPoint?> resolvePosition({
    Duration gpsTimeout = const Duration(seconds: 20),
    LocatedPoint? saved,
    bool allowIp = true,
  }) async {
    final fresh = await freshFix(timeout: gpsTimeout);
    if (fresh != null) return fresh;

    final cached = await lastKnown();
    if (cached != null) return cached;

    if (saved != null) return saved;

    return allowIp ? await ipGeolocation() : null;
  }

  /// A fresh device fix, or null if none arrived within [timeout]. Never
  /// throws.
  static Future<LocatedPoint?> freshFix({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      return _isMobile
          ? await _bestFixWithin(timeout)
          : await _singleFix(timeout);
    } catch (_) {
      return null;
    }
  }

  /// Phones: watch the stream and stop at the first good fix. The fused
  /// provider typically emits a coarse fix within a second and refines it;
  /// a single `getCurrentPosition` with a short timeout only ever saw the
  /// coarse one — or nothing, indoors.
  static Future<LocatedPoint?> _bestFixWithin(Duration timeout) async {
    final completer = Completer<Position?>();
    Position? best;

    final sub =
        Geolocator.getPositionStream(
          locationSettings: _streamSettings(),
        ).listen(
          (p) {
            if (best == null || p.accuracy < best!.accuracy) best = p;
            if (p.accuracy > 0 &&
                p.accuracy <= goodAccuracyMeters &&
                !completer.isCompleted) {
              completer.complete(p);
            }
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete(best);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete(best);
          },
        );
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(best);
    });

    try {
      final p = await completer.future;
      return p == null
          ? null
          : LocatedPoint.fromPosition(p, PositionSource.gps);
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  static LocationSettings _streamSettings() {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best);
  }

  /// Desktop: one request, cancelled by the plugin at [timeout] (the Dart
  /// `.timeout` is a backstop, since a plugin-side limit is the one that
  /// actually stops the platform call).
  static Future<LocatedPoint?> _singleFix(Duration timeout) async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: timeout,
      ),
    ).timeout(timeout + const Duration(seconds: 3));
    return LocatedPoint.fromPosition(p, PositionSource.gps);
  }

  /// The device's cached fix, if it is younger than [lastKnownMaxAge].
  static Future<LocatedPoint?> lastKnown() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p == null) return null;
      if (DateTime.now().difference(p.timestamp) > lastKnownMaxAge) {
        return null;
      }
      return LocatedPoint.fromPosition(p, PositionSource.lastKnown);
    } catch (_) {
      return null;
    }
  }

  /// Approximate coordinates from the device's public IP address — the
  /// ISP's location. Returns null when the request fails, the device is
  /// offline, or the free tier's daily quota for this IP is spent.
  static Future<LocatedPoint?> ipGeolocation() async {
    try {
      final response = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      if (body['error'] == true) return null;

      final lat = (body['latitude'] as num?)?.toDouble();
      final lon = (body['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;

      return LocatedPoint(
        latitude: lat,
        longitude: lon,
        source: PositionSource.ip,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Reverse geocoding (native on mobile, Nominatim elsewhere) ────────────

  /// Convert coordinates into a readable address, e.g. "Poblacion, Solana,
  /// Cagayan". Mobile uses the native `geocoding` package; desktop/web (and
  /// any mobile failure) use Nominatim. Returns '' when neither can name
  /// the place — never a coordinate string dressed up as an address.
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

  /// True on Android/iOS — the only platforms with native geocoding support
  /// and a position stream worth waiting on.
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
