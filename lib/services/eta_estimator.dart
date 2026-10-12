// lib/services/eta_estimator.dart
//
// The rider's arrival time, worked out instead of typed (designed
// 2026-10-05, canvas "Rider · Automatic Arrival Time").
//
// Every rider order already has a road route from the store to the member,
// made at dispatch by the order-route function: the path, its length and
// how long the map says it takes by car. The estimate is that time, scaled
// by a traffic factor (motorbikes in city traffic are not cars), plus a few
// minutes for the hand-over. While the rider is on the way, the same route
// gives the time left: how far along it the rider's last position is, and
// the rest at the route's own average speed. No extra calls to the route
// service: its free plan allows about 2,000 a day.
//
// The factor and the hand-over minutes are admin settings (app_config),
// so they can be tuned against real deliveries without a new build.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/widgets/map_kit.dart' show routePoints;

/// The two numbers an admin can tune.
class EtaTuning {
  /// Above 1 means slower than the map's car time.
  final double factor;

  /// Parking, calling the customer, the hand-over itself.
  final int handoverMinutes;

  const EtaTuning({required this.factor, required this.handoverMinutes});

  static const defaults = EtaTuning(factor: 1.2, handoverMinutes: 3);

  static const factorKey = 'eta_traffic_factor';
  static const handoverKey = 'eta_handover_minutes';

  /// From app_config, clamped so a typo can't make every estimate absurd.
  factory EtaTuning.fromConfig(Map<String, String> config) {
    final f = double.tryParse(config[factorKey] ?? '');
    final h = int.tryParse(config[handoverKey] ?? '');
    return EtaTuning(
      factor: (f ?? defaults.factor).clamp(0.8, 2.5).toDouble(),
      handoverMinutes: (h ?? defaults.handoverMinutes).clamp(0, 15),
    );
  }

  /// The map's car time for a trip, as riders and members are told it.
  Duration apply(Duration mapTime) => Duration(
    seconds: (mapTime.inSeconds * factor).round() + handoverMinutes * 60,
  );

  /// How [apply] got there, for the rider's Arrival card: "Map 15 min ×
  /// 1.2 + 3 min handover". So a rider can trust the time, and a tester
  /// can see an admin's new setting take effect (ET4).
  String explain(Duration mapTime) {
    final m = (mapTime.inSeconds / 60).round();
    final map = 'Map ${m < 1 ? '<1' : m} min × ${factor.toStringAsFixed(1)}';
    return handoverMinutes == 0 ? map : '$map + $handoverMinutes min handover';
  }
}

class EtaEstimator {
  EtaEstimator._();

  /// The per-device flag (UiPrefs) for "the rider set this order's time":
  /// automatic updates leave it alone until they go back to automatic.
  static String manualKey(String orderId) => 'eta_manual:$orderId';

  /// Without a road route: straight-line distance times this is roughly
  /// the road distance, at [_citySpeed].
  static const double _detour = 1.4;
  static const double _citySpeed = 25 / 3.6; // 25 km/h in m/s

  /// A rider further than this from the route has left it (a shortcut, a
  /// wrong turn, another drop first): measure from where they are instead.
  static const double _offRouteMetres = 300;

  static const Distance _distance = Distance();

  /// Time to the member's door, as the map would put it (before tuning).
  /// [from] is the rider's position; null means the whole trip from the
  /// store, as at pickup. Null when there is nothing to measure from.
  static Duration? mapTime(DeliveryOrder o, {LatLng? from}) {
    final dest = (o.deliveryLatitude == null || o.deliveryLongitude == null)
        ? null
        : LatLng(o.deliveryLatitude!, o.deliveryLongitude!);
    if (dest == null) return null;

    final pts = o.hasRoute ? routePoints(o.routePoints) : const <LatLng>[];
    final routeM = (o.routeDistanceM ?? 0).toDouble();
    final routeS = (o.routeDurationS ?? 0).toDouble();

    if (pts.length >= 2 && routeM > 0 && routeS > 0) {
      final speed = routeM / routeS;
      if (from == null) return Duration(seconds: routeS.round());
      final along = _alongRoute(pts, from);
      if (along.offBy <= _offRouteMetres) {
        return Duration(seconds: (routeM * along.remainingFraction / speed).round());
      }
      // Off the route: straight to the door, at the route's own speed.
      final straight = _distance.as(LengthUnit.Meter, from, dest) * _detour;
      return Duration(seconds: (straight / speed).round());
    }

    // No road route (unroutable, failed, or not made yet).
    final start = from ??
        ((o.routeOriginLat != null && o.routeOriginLng != null)
            ? LatLng(o.routeOriginLat!, o.routeOriginLng!)
            : null);
    if (start == null) return null;
    final straight = _distance.as(LengthUnit.Meter, start, dest) * _detour;
    return Duration(seconds: (straight / _citySpeed).round());
  }

  /// The arrival time to show: now plus the tuned trip time.
  static DateTime? arrival(
    DeliveryOrder o,
    EtaTuning tuning, {
    LatLng? from,
    DateTime? now,
  }) {
    final t = mapTime(o, from: from);
    if (t == null) return null;
    return (now ?? DateTime.now()).add(tuning.apply(t));
  }

  /// How far along [pts] the point [p] is: the share of the route still
  /// ahead, and how far [p] is from the route. Measured on a flat local
  /// projection, which is exact enough across a city.
  static ({double remainingFraction, double offBy}) _alongRoute(
    List<LatLng> pts,
    LatLng p,
  ) {
    final lat0 = pts.first.latitude * math.pi / 180;
    final kx = 111320 * math.cos(lat0), ky = 110540.0;
    double x(LatLng q) => q.longitude * kx;
    double y(LatLng q) => q.latitude * ky;

    final px = x(p), py = y(p);
    final lengths = <double>[];
    var total = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      final l = math.sqrt(math.pow(x(pts[i + 1]) - x(pts[i]), 2) +
          math.pow(y(pts[i + 1]) - y(pts[i]), 2));
      lengths.add(l);
      total += l;
    }
    if (total <= 0) return (remainingFraction: 1, offBy: 0);

    var best = double.infinity, travelled = 0.0, before = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      final ax = x(pts[i]), ay = y(pts[i]);
      final dx = x(pts[i + 1]) - ax, dy = y(pts[i + 1]) - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
      final cx = ax + t * dx, cy = ay + t * dy;
      final d = math.sqrt(math.pow(px - cx, 2) + math.pow(py - cy, 2));
      if (d < best) {
        best = d;
        travelled = before + t * lengths[i];
      }
      before += lengths[i];
    }
    return (
      remainingFraction: ((total - travelled) / total).clamp(0.0, 1.0),
      offBy: best,
    );
  }
}

/// How the estimate has done: recent rider deliveries, each with the map's
/// car time for its route and how long it really took from pickup to
/// delivered. For the admin's "how it has done" line.
class EtaCalibration {
  final List<({int routeSeconds, int actualSeconds})> trips;

  const EtaCalibration(this.trips);

  int get samples => trips.length;

  /// Average minutes riders arrived after the estimate [t] would have
  /// said (negative: before).
  double averageLateMinutes(EtaTuning t) {
    if (trips.isEmpty) return 0;
    final total = trips.fold<double>(
      0,
      (sum, x) =>
          sum + (x.actualSeconds - t.apply(Duration(seconds: x.routeSeconds)).inSeconds),
    );
    return total / trips.length / 60;
  }

  /// The factor that would have matched these trips on average, given
  /// [handoverMinutes]; null when there is nothing to go on.
  double? suggestedFactor(int handoverMinutes) {
    final route = trips.fold<int>(0, (s, x) => s + x.routeSeconds);
    if (route <= 0) return null;
    final ride = trips.fold<int>(0, (s, x) => s + x.actualSeconds) -
        handoverMinutes * 60 * trips.length;
    final f = ride / route;
    return f.isFinite ? f.clamp(0.8, 2.5).toDouble() : null;
  }
}
