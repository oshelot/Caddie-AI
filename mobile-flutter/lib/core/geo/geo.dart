// Low-level geometry primitives and geo math used by every course-related
// feature in the app. Intentionally standalone — no Mapbox, no Flutter, no
// business logic. Everything here is pure Dart so it's trivially testable.
//
// Coordinate convention: we store coordinates as (lon, lat) internally to
// match GeoJSON, which is what the server returns and what Mapbox accepts.
// The server's `centroid` / `pin` fields are the exception — they use
// {latitude, longitude} objects, so we expose a `LngLat.fromLatLonObject`
// factory for those call sites.

import 'dart:math' as math;

class LngLat {
  final double lon;
  final double lat;
  const LngLat(this.lon, this.lat);

  /// Parses a 2-element [lon, lat] array from a GeoJSON-style coords list.
  factory LngLat.fromArray(List<dynamic> a) =>
      LngLat((a[0] as num).toDouble(), (a[1] as num).toDouble());

  /// Parses `{"latitude": ..., "longitude": ...}` (used by server centroid
  /// and pin fields).
  factory LngLat.fromLatLonObject(Map<String, dynamic> j) => LngLat(
        (j['longitude'] as num).toDouble(),
        (j['latitude'] as num).toDouble(),
      );

  List<double> toArray() => [lon, lat];
}

class Polygon {
  /// Outer ring only. Inner rings (holes) are intentionally dropped — the
  /// course features we render don't use them.
  final List<LngLat> outerRing;
  const Polygon(this.outerRing);

  factory Polygon.fromJson(Map<String, dynamic> j) {
    final coords = j['coordinates'] as List<dynamic>;
    if (coords.isEmpty) return const Polygon([]);
    final outer = (coords.first as List<dynamic>)
        .map((p) => LngLat.fromArray(p as List<dynamic>))
        .toList(growable: false);
    return Polygon(outer);
  }

  /// Arithmetic mean of the ring vertices. Good enough for camera fits
  /// and bearing calculations at course scale — do NOT use for precise
  /// geometric centroids where the polygon is far from convex.
  LngLat? get centroid {
    if (outerRing.isEmpty) return null;
    double sumLon = 0;
    double sumLat = 0;
    for (final p in outerRing) {
      sumLon += p.lon;
      sumLat += p.lat;
    }
    return LngLat(sumLon / outerRing.length, sumLat / outerRing.length);
  }
}

class LineString {
  final List<LngLat> points;
  const LineString(this.points);

  factory LineString.fromJson(Map<String, dynamic> j) {
    final coords = j['coordinates'] as List<dynamic>;
    return LineString(
      coords
          .map((p) => LngLat.fromArray(p as List<dynamic>))
          .toList(growable: false),
    );
  }

  LngLat? get startPoint => points.isEmpty ? null : points.first;
  LngLat? get endPoint => points.isEmpty ? null : points.last;
}

// ---------------------------------------------------------------------------
// Geo math
// ---------------------------------------------------------------------------

const double _earthRadiusMeters = 6371000.0;
const double _metersPerYard = 0.9144;

double _degToRad(double d) => d * math.pi / 180.0;
double _radToDeg(double r) => r * 180.0 / math.pi;

/// Great-circle distance in meters between two LngLat points.
double haversineMeters(LngLat a, LngLat b) {
  final lat1 = _degToRad(a.lat);
  final lat2 = _degToRad(b.lat);
  final dLat = lat2 - lat1;
  final dLon = _degToRad(b.lon - a.lon);
  final sinDLat = math.sin(dLat / 2);
  final sinDLon = math.sin(dLon / 2);
  final h =
      sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
  return 2 * _earthRadiusMeters * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Meters → yards. Matches the iOS native app's `distance / 0.9144`.
double metersToYards(double meters) => meters / _metersPerYard;

/// Initial compass bearing from `a` to `b`, in degrees 0..360.
/// Matches `CLLocationCoordinate2D.bearing(to:)` used in the iOS native app.
double bearingDegrees(LngLat a, LngLat b) {
  final lat1 = _degToRad(a.lat);
  final lat2 = _degToRad(b.lat);
  final dLon = _degToRad(b.lon - a.lon);
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  final brng = _radToDeg(math.atan2(y, x));
  return (brng + 360) % 360;
}
