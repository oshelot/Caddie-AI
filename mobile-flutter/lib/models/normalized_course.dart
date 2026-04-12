// Dart models for the `NormalizedCourse` schema served by the CaddieAI
// course cache. Source of truth for the contract: the iOS native app's
// CourseModel.swift / HoleModel.swift / GeoJSONTypes.swift — these Dart
// models are intentionally lean and only carry the fields actually used
// by rendering, camera fit, and distance math.
//
// Fetch with `platform=ios&schema=1.0` — the server's iOS-platform
// serialization uses GeoJSON-shaped `coordinates` arrays which map
// cleanly onto `LngLat.fromArray`. The Android-platform serialization
// uses a flatter shape (`teeBox`, `fairwayCenterLine.points`) and is
// NOT compatible with these models.

import '../core/geo/geo.dart';

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
      strokeIndex:
          j['strokeIndex'] == null ? null : (j['strokeIndex'] as num).toInt(),
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

  /// Tee-to-green bearing, matching the iOS implementation at
  /// `MapboxMapRepresentable.swift:358-388`. Returns compass degrees
  /// (0 = north, 90 = east). Falls back to 0 when either endpoint is
  /// unknown, which renders the hole north-up.
  double teeToGreenBearing() {
    final tee = lineOfPlay?.startPoint ?? _firstTeeCentroid();
    final greenPt = green?.centroid ?? pin ?? lineOfPlay?.endPoint;
    if (tee == null || greenPt == null) return 0;
    return bearingDegrees(tee, greenPt);
  }

  LngLat? _firstTeeCentroid() =>
      teeAreas.isEmpty ? null : teeAreas.first.centroid;

  /// Every geometry vertex on the hole flattened into a single list.
  /// Used by the camera fitter when flying to a hole.
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

  /// Label anchor for the hole-label layer. Matches iOS
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
      centroid:
          LngLat.fromLatLonObject(j['centroid'] as Map<String, dynamic>),
      holes: (j['holes'] as List<dynamic>)
          .map((h) => NormalizedHole.fromJson(h as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  /// Name-only key for the server cache. Coordinates are deliberately
  /// excluded so iOS (MapKit) and Android/Flutter (Nominatim/Places)
  /// converge on the same cache entry for the same course — different
  /// providers report slightly different centroids for the same place.
  /// Mirrors `ios/CaddieAI/Models/CourseModel.swift:99-104` exactly.
  static String serverCacheKey(String name) {
    return name
        .toLowerCase()
        .replaceAll(' ', '-')
        .replaceAll("'", '')
        .replaceAll('"', '');
  }
}
