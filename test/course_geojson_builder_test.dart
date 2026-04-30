// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

// Pure-Dart tests for the GeoJSON builder. Uses synthetic fixtures so
// the test suite has no I/O and no network dependencies — any regression
// in the contract with the iOS native app's GeoJSON feature shape will
// blow these tests up without requiring the server cache.
//
// Full cache-backed tests (with real courses fetched from the server)
// should live in an integration test suite, not here.

import 'package:caddieai/core/geo/geo.dart';
import 'package:caddieai/models/normalized_course.dart';
import 'package:caddieai/services/course_geojson_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NormalizedHole geo helpers', () {
    test('teeToGreenBearing falls back to 0 when tee and green unknown', () {
      final hole = NormalizedHole(
        number: 1,
        par: 4,
        strokeIndex: null,
        yardages: {},
        teeAreas: [],
        lineOfPlay: null,
        green: null,
        pin: null,
        bunkers: [],
        water: [],
      );
      expect(hole.teeToGreenBearing(), 0.0);
    });

    test('teeToGreenBearing returns compass degrees in [0, 360)', () {
      final hole = NormalizedHole(
        number: 1,
        par: 4,
        strokeIndex: null,
        yardages: {},
        teeAreas: [],
        lineOfPlay: LineString([
          LngLat(-104.9595, 39.6555), // tee
          LngLat(-104.9595, 39.6605), // green (due north)
        ]),
        green: null,
        pin: null,
        bunkers: [],
        water: [],
      );
      final b = hole.teeToGreenBearing();
      // Due north should be ~0°. Allow a wide envelope for floating
      // point and the haversine approximation.
      expect(b, inInclusiveRange(0, 1));
    });

    test('labelAnchor prefers green centroid over line midpoint', () {
      final hole = NormalizedHole(
        number: 7,
        par: 4,
        strokeIndex: null,
        yardages: {},
        teeAreas: [],
        lineOfPlay: LineString([
          LngLat(-104.9595, 39.6555),
          LngLat(-104.9595, 39.6605),
        ]),
        green: Polygon([
          LngLat(-104.9590, 39.6600),
          LngLat(-104.9585, 39.6602),
          LngLat(-104.9588, 39.6598),
        ]),
        pin: null,
        bunkers: [],
        water: [],
      );
      final anchor = hole.labelAnchor();
      expect(anchor, isNotNull);
      // Anchor should be near the green centroid (~-104.9588, ~39.6600),
      // not the line midpoint (~-104.9595, ~39.6580).
      expect(anchor!.lon, closeTo(-104.9588, 0.0005));
      expect(anchor.lat, closeTo(39.6600, 0.0005));
    });
  });

  group('CourseGeoJsonBuilder', () {
    final course = NormalizedCourse(
      id: 'synthetic-1',
      name: 'Synthetic Test Course',
      city: null,
      state: null,
      centroid: const LngLat(-104.9595, 39.6580),
      holes: [
        NormalizedHole(
          number: 1,
          par: 4,
          strokeIndex: 1,
          yardages: const {'Blue': 400},
          teeAreas: const [
            Polygon([
              LngLat(-104.9596, 39.6555),
              LngLat(-104.9594, 39.6556),
              LngLat(-104.9595, 39.6554),
            ]),
          ],
          lineOfPlay: const LineString([
            LngLat(-104.9595, 39.6555),
            LngLat(-104.9595, 39.6605),
          ]),
          green: const Polygon([
            LngLat(-104.9590, 39.6600),
            LngLat(-104.9585, 39.6602),
            LngLat(-104.9588, 39.6598),
          ]),
          pin: null,
          bunkers: const [],
          water: const [],
        ),
      ],
    );

    test('emits FeatureCollection with expected top-level shape', () {
      final fc = CourseGeoJsonBuilder.buildFeatureCollection(course);
      expect(fc['type'], 'FeatureCollection');
      expect(fc['features'], isA<List>());
    });

    test('every feature carries a known `type` property', () {
      final fc = CourseGeoJsonBuilder.buildFeatureCollection(course);
      const allowed = {
        CourseFeatureType.boundary,
        CourseFeatureType.holeLine,
        CourseFeatureType.green,
        CourseFeatureType.tee,
        CourseFeatureType.bunker,
        CourseFeatureType.water,
        CourseFeatureType.holeLabel,
        CourseFeatureType.pin,
      };
      for (final f in (fc['features'] as List)) {
        final type = (f as Map)['properties']['type'] as String;
        expect(allowed, contains(type));
      }
    });

    test('hole 1 produces a holeLine and a holeLabel feature', () {
      final fc = CourseGeoJsonBuilder.buildFeatureCollection(course);
      final features = (fc['features'] as List).cast<Map>();
      final hole1Types = features
          .where((f) => f['properties']['holeNumber'] == 1)
          .map((f) => f['properties']['type'])
          .toSet();
      expect(hole1Types, contains(CourseFeatureType.holeLine));
      expect(hole1Types, contains(CourseFeatureType.holeLabel));
    });

    test('holeLabel feature carries a numeric `label` property', () {
      final fc = CourseGeoJsonBuilder.buildFeatureCollection(course);
      final labels = (fc['features'] as List)
          .cast<Map>()
          .where((f) => f['properties']['type'] == CourseFeatureType.holeLabel);
      for (final f in labels) {
        final label = f['properties']['label'] as String;
        expect(int.tryParse(label), isNotNull);
      }
    });
  });

  group('geo math', () {
    test('haversineMeters between two points is positive and symmetric', () {
      const a = LngLat(-104.9595, 39.6555);
      const b = LngLat(-104.9595, 39.6605);
      final ab = haversineMeters(a, b);
      final ba = haversineMeters(b, a);
      expect(ab, greaterThan(0));
      expect(ab, closeTo(ba, 0.001));
      // ~0.005 degrees of latitude ≈ 556 m
      expect(ab, inInclusiveRange(500, 600));
    });

    test('metersToYards matches the iOS constant', () {
      // iOS uses `distance / 0.9144`
      expect(metersToYards(100.0), closeTo(109.36, 0.01));
    });

    test('bearingDegrees due north is ~0, due east is ~90', () {
      const origin = LngLat(-104.9595, 39.6555);
      final north = bearingDegrees(origin, const LngLat(-104.9595, 39.6605));
      final east = bearingDegrees(origin, const LngLat(-104.9540, 39.6555));
      expect(north, inInclusiveRange(0, 1));
      expect(east, inInclusiveRange(89, 91));
    });
  });
}
