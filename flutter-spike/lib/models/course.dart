// Dart port of the subset of NormalizedCourse needed to render the
// 7-layer course overlay. Source of truth: the iOS CourseModel.swift /
// HoleModel.swift / GeoJSONTypes.swift in the native CaddieAI app.
//
// Server JSON uses GeoJSON-ordered coordinates ([lon, lat]) inside
// `coordinates` arrays. We keep the raw arrays as-is and expose typed
// accessors for the geometry the renderer actually needs.
//
// This file is deliberately minimal: no confidence scores, no rawRefs,
// no tee-yardage totals — only the fields the map screen reads.

import 'dart:math' as math;

class LngLat {
  final double lon;
  final double lat;
  const LngLat(this.lon, this.lat);

  /// Parses a 2-element [lon, lat] array from a GeoJSON-style coords list.
  factory LngLat.fromArray(List<dynamic> a) =>
      LngLat((a[0] as num).toDouble(), (a[1] as num).toDouble());

  /// Parses `{"latitude": ..., "longitude": ...}` (used by centroid fields).
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

  /// Simple centroid — arithmetic mean of the ring vertices. Good enough
  /// for camera-fit math and bearing calculations at course scale.
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

class NormalizedHole {
  final int number;
  final int par;
  final int? strokeIndex;
  final Map<String, int> yardages;
  final List<Polygon> teeAreas;
  final LineString? lineOfPlay;
  final Polygon? green;
  final LngLat? pin;
  final List<Polygon> bunkers;
  final List<Polygon> water;

  const NormalizedHole({
    required this.number,
    required this.par,
    required this.strokeIndex,
    required this.yardages,
    required this.teeAreas,
    required this.lineOfPlay,
    required this.green,
    required this.pin,
    required this.bunkers,
    required this.water,
  });

  factory NormalizedHole.fromJson(Map<String, dynamic> j) {
    Map<String, int> parseYardages(dynamic raw) {
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry(k as String, (v as num).toInt()));
    }

    List<Polygon> parsePolygons(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .map((p) => Polygon.fromJson(p as Map<String, dynamic>))
          .toList(growable: false);
    }

    return NormalizedHole(
      number: (j['number'] as num).toInt(),
      par: (j['par'] as num).toInt(),
      strokeIndex: j['strokeIndex'] == null
          ? null
          : (j['strokeIndex'] as num).toInt(),
      yardages: parseYardages(j['yardages']),
      teeAreas: parsePolygons(j['teeAreas']),
      lineOfPlay: j['lineOfPlay'] == null
          ? null
          : LineString.fromJson(j['lineOfPlay'] as Map<String, dynamic>),
      green: j['green'] == null
          ? null
          : Polygon.fromJson(j['green'] as Map<String, dynamic>),
      pin: j['pin'] == null
          ? null
          : LngLat.fromLatLonObject(j['pin'] as Map<String, dynamic>),
      bunkers: parsePolygons(j['bunkers']),
      water: parsePolygons(j['water']),
    );
  }

  /// Tee-to-green bearing matching the iOS implementation at
  /// MapboxMapRepresentable.swift:358-388. Returns compass degrees
  /// (0 = north, 90 = east). Falls back to 0 (north-up) when either
  /// endpoint is unknown.
  double teeToGreenBearing() {
    final tee = lineOfPlay?.startPoint ?? _firstTeeCentroid();
    final greenPt = green?.centroid ?? pin ?? lineOfPlay?.endPoint;
    if (tee == null || greenPt == null) return 0;
    return _bearingDegrees(tee, greenPt);
  }

  LngLat? _firstTeeCentroid() =>
      teeAreas.isEmpty ? null : teeAreas.first.centroid;

  /// All geometry vertices flattened to a single list — used by the camera
  /// fitter when flying to a hole.
  List<LngLat> allGeometryPoints() {
    final out = <LngLat>[];
    final lop = lineOfPlay;
    if (lop != null) out.addAll(lop.points);
    for (final t in teeAreas) {
      out.addAll(t.outerRing);
    }
    final g = green;
    if (g != null) out.addAll(g.outerRing);
    for (final b in bunkers) {
      out.addAll(b.outerRing);
    }
    for (final w in water) {
      out.addAll(w.outerRing);
    }
    final p = pin;
    if (p != null) out.add(p);
    return out;
  }

  /// Label anchor for the hole-label layer. Matches the iOS
  /// `CourseGeoJSONBuilder.holeLabelPoint(for:)` exactly:
  /// prefer green centroid, fall back to the midpoint of the line of play.
  LngLat? labelAnchor() {
    final g = green;
    if (g != null) {
      final c = g.centroid;
      if (c != null) return c;
    }
    final lop = lineOfPlay;
    if (lop != null && lop.points.isNotEmpty) {
      return lop.points[lop.points.length ~/ 2];
    }
    return null;
  }
}

class NormalizedCourse {
  final String id;
  final String name;
  final String? city;
  final String? state;
  final LngLat centroid;
  final List<NormalizedHole> holes;

  const NormalizedCourse({
    required this.id,
    required this.name,
    required this.city,
    required this.state,
    required this.centroid,
    required this.holes,
  });

  factory NormalizedCourse.fromJson(Map<String, dynamic> j) {
    return NormalizedCourse(
      id: j['id'] as String,
      name: j['name'] as String,
      city: j['city'] as String?,
      state: j['state'] as String?,
      centroid: LngLat.fromLatLonObject(j['centroid'] as Map<String, dynamic>),
      holes: (j['holes'] as List<dynamic>)
          .map((h) => NormalizedHole.fromJson(h as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

// ---------------------------------------------------------------------------
// Geo math — kept here so the course models are the single home for all
// coordinate-space operations used by the spike.
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

/// Meters → yards (match of iOS `distance / 0.9144`).
double metersToYards(double meters) => meters / _metersPerYard;

/// Initial compass bearing from `a` to `b`, in degrees 0..360.
/// Matches `CLLocationCoordinate2D.bearing(to:)` used in iOS.
double _bearingDegrees(LngLat a, LngLat b) {
  final lat1 = _degToRad(a.lat);
  final lat2 = _degToRad(b.lat);
  final dLon = _degToRad(b.lon - a.lon);
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  final brng = _radToDeg(math.atan2(y, x));
  return (brng + 360) % 360;
}
