// Tests for KAN-403: NormalizedHole.fromJson must accept both schema 1.0
// (full polygon for green/teeAreas) and schema 1.1 (point form). The
// regression risk is that the polygon path silently changes when we add
// the point fallback.

import 'package:caddieai/core/geo/geo.dart';
import 'package:caddieai/models/normalized_course.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Polygon.fromPointWithRadius', () {
    test('produces a closed 8-sided ring near the requested radius', () {
      const center = LngLat(-104.9903, 39.7392); // Denver, ~40°N
      final ring = Polygon.fromPointWithRadius(center, 10.0).outerRing;

      // 8 unique vertices + closing duplicate = 9.
      expect(ring.length, 9);
      expect(ring.first.lon, closeTo(ring.last.lon, 1e-12));
      expect(ring.first.lat, closeTo(ring.last.lat, 1e-12));

      // Every vertex should be ~10 m from the center.
      for (final v in ring) {
        final d = haversineMeters(center, v);
        expect(d, closeTo(10.0, 0.5),
            reason: 'vertex $v should be ~10m from center, got $d');
      }
    });
  });

  group('Polygon.fromJsonOrPoint', () {
    test('parses GeoJSON polygon form (schema 1.0)', () {
      final p = Polygon.fromJsonOrPoint({
        'coordinates': [
          [
            [-104.99, 39.74],
            [-104.99, 39.75],
            [-104.98, 39.75],
            [-104.98, 39.74],
            [-104.99, 39.74],
          ]
        ]
      }, radiusMeters: 8.0);
      expect(p.outerRing.length, 5);
      expect(p.outerRing.first.lon, -104.99);
    });

    test('parses point form (schema 1.1) into a small ring', () {
      final p = Polygon.fromJsonOrPoint({
        'latitude': 39.7392,
        'longitude': -104.9903,
      }, radiusMeters: 8.0);
      // 8 vertices + 1 closing copy
      expect(p.outerRing.length, 9);
      final c = p.centroid!;
      expect(c.lat, closeTo(39.7392, 1e-4));
      expect(c.lon, closeTo(-104.9903, 1e-4));
    });

    test('returns empty polygon for malformed input', () {
      expect(Polygon.fromJsonOrPoint({}, radiusMeters: 8.0).outerRing, isEmpty);
    });
  });

  group('NormalizedHole.fromJson — schema 1.0 (polygon)', () {
    test('parses green and teeAreas as full polygons unchanged', () {
      final h = NormalizedHole.fromJson({
        'number': 1,
        'par': 4,
        'teeAreas': [
          {
            'coordinates': [
              [
                [-104.99, 39.74],
                [-104.99, 39.7401],
                [-104.9899, 39.7401],
                [-104.9899, 39.74],
                [-104.99, 39.74],
              ]
            ]
          }
        ],
        'lineOfPlay': {
          'coordinates': [
            [-104.99, 39.74],
            [-104.98, 39.75],
          ]
        },
        'green': {
          'coordinates': [
            [
              [-104.98, 39.75],
              [-104.98, 39.7501],
              [-104.9799, 39.7501],
              [-104.9799, 39.75],
              [-104.98, 39.75],
            ]
          ]
        },
        'bunkers': <dynamic>[],
        'water': <dynamic>[],
      });

      expect(h.green!.outerRing.length, 5);
      expect(h.teeAreas.length, 1);
      expect(h.teeAreas.first.outerRing.length, 5);
      expect(h.lineOfPlay!.points.length, 2);
    });
  });

  group('NormalizedHole.fromJson — schema 1.1 (point)', () {
    test('synthesizes polygons from point-form green and teeAreas', () {
      final h = NormalizedHole.fromJson({
        'number': 1,
        'par': 4,
        'teeAreas': [
          {'latitude': 39.7392, 'longitude': -104.9903}
        ],
        'lineOfPlay': {
          'coordinates': [
            [-104.9903, 39.7392],
            [-104.9800, 39.7500],
          ]
        },
        'green': {'latitude': 39.7500, 'longitude': -104.9800},
        'bunkers': <dynamic>[],
        'water': <dynamic>[],
      });

      // Green: 8 vertices + closing = 9, centroid near requested point
      expect(h.green!.outerRing.length, 9);
      expect(h.green!.centroid!.lat, closeTo(39.7500, 1e-4));
      expect(h.green!.centroid!.lon, closeTo(-104.9800, 1e-4));

      // Tee: smaller ring (3m radius) but still 9-vertex shape
      expect(h.teeAreas.length, 1);
      expect(h.teeAreas.first.outerRing.length, 9);

      // Line passes through unchanged
      expect(h.lineOfPlay!.points.length, 2);
    });

    test('handles null lineOfPlay (GT-only courses before KAN-404 lands)', () {
      final h = NormalizedHole.fromJson({
        'number': 1,
        'par': 4,
        'teeAreas': [
          {'latitude': 39.7392, 'longitude': -104.9903}
        ],
        'lineOfPlay': null,
        'green': {'latitude': 39.7500, 'longitude': -104.9800},
      });
      expect(h.lineOfPlay, isNull);
      expect(h.green, isNotNull);
      expect(h.teeAreas, hasLength(1));
    });
  });
}
