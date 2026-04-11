// Dart port of ios/CaddieAI/Services/CourseGeoJSONBuilder.swift.
//
// Produces a GeoJSON FeatureCollection (as a plain Map/List structure) that
// mapbox_maps_flutter's GeoJsonSource can consume via `data: jsonEncode(fc)`.
// The feature order, `type` property values, `holeNumber` property, and
// `label` property all match the iOS implementation exactly — the layer
// filters in map_screen.dart rely on those exact string values.

import '../core/geo/geo.dart';
import '../models/normalized_course.dart';

/// Feature type string values — mirror `type` filter values in iOS layers.
class CourseFeatureType {
  static const boundary = 'boundary';
  static const holeLine = 'holeLine';
  static const green = 'green';
  static const tee = 'tee';
  static const bunker = 'bunker';
  static const water = 'water';
  static const holeLabel = 'holeLabel';
  static const pin = 'pin';
}

class CourseGeoJsonBuilder {
  /// Builds the full FeatureCollection for a course in the same order
  /// as the iOS builder: boundary first, then per-hole
  /// (holeLine → green → teeAreas → bunkers → water → holeLabel → pin).
  static Map<String, dynamic> buildFeatureCollection(NormalizedCourse course) {
    final features = <Map<String, dynamic>>[];

    // Course boundary — not present in the current server schema, but the
    // branch stays here so the layer starts working immediately when the
    // field is added.
    //
    // (iOS: `if let boundary = course.courseBoundary { ... }`)

    for (final hole in course.holes) {
      final lop = hole.lineOfPlay;
      if (lop != null && lop.points.isNotEmpty) {
        features.add(_lineFeature(
          lop.points,
          type: CourseFeatureType.holeLine,
          holeNumber: hole.number,
        ));
      }

      final green = hole.green;
      if (green != null && green.outerRing.isNotEmpty) {
        features.add(_polygonFeature(
          green.outerRing,
          type: CourseFeatureType.green,
          holeNumber: hole.number,
        ));
      }

      for (final tee in hole.teeAreas) {
        if (tee.outerRing.isEmpty) continue;
        features.add(_polygonFeature(
          tee.outerRing,
          type: CourseFeatureType.tee,
          holeNumber: hole.number,
        ));
      }

      for (final bunker in hole.bunkers) {
        if (bunker.outerRing.isEmpty) continue;
        features.add(_polygonFeature(
          bunker.outerRing,
          type: CourseFeatureType.bunker,
          holeNumber: hole.number,
        ));
      }

      for (final water in hole.water) {
        if (water.outerRing.isEmpty) continue;
        features.add(_polygonFeature(
          water.outerRing,
          type: CourseFeatureType.water,
          holeNumber: hole.number,
        ));
      }

      final labelAnchor = hole.labelAnchor();
      if (labelAnchor != null) {
        features.add(_pointFeature(
          labelAnchor,
          type: CourseFeatureType.holeLabel,
          holeNumber: hole.number,
        ));
      }

      final pin = hole.pin;
      if (pin != null) {
        features.add(_pointFeature(
          pin,
          type: CourseFeatureType.pin,
          holeNumber: hole.number,
        ));
      }
    }

    return {
      'type': 'FeatureCollection',
      'features': features,
    };
  }

  // ---------------------------------------------------------------------
  // Feature constructors
  // ---------------------------------------------------------------------

  static Map<String, dynamic> _polygonFeature(
    List<LngLat> ring, {
    required String type,
    int? holeNumber,
  }) {
    final ringClosed = _closed(ring);
    return {
      'type': 'Feature',
      'properties': _props(type: type, holeNumber: holeNumber),
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          ringClosed.map((p) => [p.lon, p.lat]).toList(growable: false),
        ],
      },
    };
  }

  static Map<String, dynamic> _lineFeature(
    List<LngLat> points, {
    required String type,
    int? holeNumber,
  }) {
    return {
      'type': 'Feature',
      'properties': _props(type: type, holeNumber: holeNumber),
      'geometry': {
        'type': 'LineString',
        'coordinates': points.map((p) => [p.lon, p.lat]).toList(growable: false),
      },
    };
  }

  static Map<String, dynamic> _pointFeature(
    LngLat p, {
    required String type,
    int? holeNumber,
  }) {
    final props = _props(type: type, holeNumber: holeNumber);
    if (holeNumber != null) {
      // iOS sets `label` only on point features with a holeNumber.
      props['label'] = '$holeNumber';
    }
    return {
      'type': 'Feature',
      'properties': props,
      'geometry': {
        'type': 'Point',
        'coordinates': [p.lon, p.lat],
      },
    };
  }

  static Map<String, dynamic> _props({required String type, int? holeNumber}) {
    final p = <String, dynamic>{'type': type};
    if (holeNumber != null) p['holeNumber'] = holeNumber;
    return p;
  }

  /// Ensures the polygon ring is closed (first == last). GeoJSON requires
  /// it; the server JSON is already closed in practice but we belt-and-
  /// suspenders it for safety.
  static List<LngLat> _closed(List<LngLat> ring) {
    if (ring.length < 3) return ring;
    final first = ring.first;
    final last = ring.last;
    if (first.lon == last.lon && first.lat == last.lat) return ring;
    return [...ring, first];
  }
}
