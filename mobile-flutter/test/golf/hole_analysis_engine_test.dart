// Tests for KAN-293 (S7.2) HoleAnalysisEngine. Five synthetic
// hole geometries cover the AC requirements:
//
//   1. Straight par 4 — no dogleg, single bunker on the right
//   2. Dogleg-left par 4 — bend angle ≥ 15°, hazard on inside
//   3. Dogleg-right par 4 — symmetric to dogleg-left, opposite sign
//   4. Par 3 — short, no dogleg, no bend math
//   5. Par 5 — long with two hazards, larger landing-zone fraction
//
// All synthetic geometries are built with simple lat/lon offsets
// (degrees) so the math is reproducible by hand. The expected
// values are computed via the same formulas iOS uses (Haversine
// for distance, projection-on-axis for green dimensions, cross
// product for hazard side).

import 'package:caddieai/core/geo/geo.dart';
import 'package:caddieai/core/golf/hole_analysis.dart';
import 'package:caddieai/core/golf/hole_analysis_engine.dart';
import 'package:caddieai/models/normalized_course.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a square polygon centered at (lon, lat) with the given
/// half-width in degrees. Used for greens and hazards in the
/// fixtures.
Polygon _square(double lon, double lat, double halfDeg) {
  return Polygon([
    LngLat(lon - halfDeg, lat - halfDeg),
    LngLat(lon + halfDeg, lat - halfDeg),
    LngLat(lon + halfDeg, lat + halfDeg),
    LngLat(lon - halfDeg, lat + halfDeg),
    LngLat(lon - halfDeg, lat - halfDeg),
  ]);
}

NormalizedHole _straightPar4() {
  // Tee at (0, 0), green centered at (0, 0.0036) → ~400 m north
  // → about 437 yards. The line of play is straight north.
  return NormalizedHole(
    number: 1,
    par: 4,
    strokeIndex: 7,
    yardages: const {'white': 380},
    teeAreas: const [],
    lineOfPlay: const LineString([
      LngLat(0, 0),
      LngLat(0, 0.0018),
      LngLat(0, 0.0036),
    ]),
    green: _square(0, 0.0036, 0.0001),
    pin: const LngLat(0, 0.0036),
    bunkers: [
      // Bunker 60% along the line of play, ~1.5 m east of the line.
      _square(0.00002, 0.00216, 0.000005),
    ],
    water: const [],
  );
}

NormalizedHole _doglegLeftPar4() {
  // Tee → mid (north) → green (north-west, dogleg left).
  return NormalizedHole(
    number: 2,
    par: 4,
    strokeIndex: 1,
    yardages: const {'white': 410},
    teeAreas: const [],
    lineOfPlay: const LineString([
      LngLat(0, 0),
      LngLat(0, 0.0020),
      LngLat(-0.0010, 0.0035),
    ]),
    green: _square(-0.0010, 0.0035, 0.0001),
    pin: const LngLat(-0.0010, 0.0035),
    bunkers: const [],
    water: const [],
  );
}

NormalizedHole _doglegRightPar4() {
  return NormalizedHole(
    number: 3,
    par: 4,
    strokeIndex: 3,
    yardages: const {'white': 410},
    teeAreas: const [],
    lineOfPlay: const LineString([
      LngLat(0, 0),
      LngLat(0, 0.0020),
      LngLat(0.0010, 0.0035),
    ]),
    green: _square(0.0010, 0.0035, 0.0001),
    pin: const LngLat(0.0010, 0.0035),
    bunkers: const [],
    water: const [],
  );
}

NormalizedHole _par3() {
  return NormalizedHole(
    number: 4,
    par: 3,
    strokeIndex: 17,
    yardages: const {'white': 165},
    teeAreas: const [],
    lineOfPlay: const LineString([
      LngLat(0, 0),
      LngLat(0, 0.00135),
    ]),
    green: _square(0, 0.00135, 0.00012),
    pin: const LngLat(0, 0.00135),
    bunkers: const [],
    water: const [],
  );
}

NormalizedHole _par5WithTwoHazards() {
  // Long straight par 5: ~530y. Water on the left at ~50% along,
  // bunker greenside on the right.
  return NormalizedHole(
    number: 5,
    par: 5,
    strokeIndex: 5,
    yardages: const {'white': 530},
    teeAreas: const [],
    lineOfPlay: const LineString([
      LngLat(0, 0),
      LngLat(0, 0.0024),
      LngLat(0, 0.00485),
    ]),
    green: _square(0, 0.00485, 0.00012),
    pin: const LngLat(0, 0.00485),
    bunkers: [
      _square(0.00003, 0.00475, 0.000004), // greenside, right side
    ],
    water: [
      _square(-0.00010, 0.00240, 0.000020), // mid-fairway, left
    ],
  );
}

void main() {
  group('Hole 1: straight par 4', () {
    test('reports total distance', () {
      final analysis = HoleAnalysisEngine.analyze(hole: _straightPar4());
      // Selected tee not specified → falls back to geometry-based
      // distance. The line of play is ~400 m → ~437 yards.
      expect(analysis.totalDistanceYards, isNotNull);
      expect(analysis.totalDistanceYards!, greaterThan(390));
      expect(analysis.totalDistanceYards!, lessThan(450));
    });

    test('uses selected tee yardage when supplied', () {
      final analysis = HoleAnalysisEngine.analyze(
        hole: _straightPar4(),
        selectedTee: 'white',
      );
      expect(analysis.totalDistanceYards, 380);
    });

    test('no dogleg detected (straight line of play)', () {
      final analysis = HoleAnalysisEngine.analyze(hole: _straightPar4());
      expect(analysis.dogleg, isNull);
    });

    test('green dimensions are positive integers', () {
      final analysis = HoleAnalysisEngine.analyze(hole: _straightPar4());
      expect(analysis.greenDepthYards, greaterThan(0));
      expect(analysis.greenWidthYards, greaterThan(0));
    });

    test('one bunker classified', () {
      final analysis = HoleAnalysisEngine.analyze(hole: _straightPar4());
      expect(analysis.hazards, hasLength(1));
      expect(analysis.hazards.first.type, HazardType.bunker);
      // The bunker is east of the north-pointing line — to the
      // player's right.
      expect(analysis.hazards.first.side, HazardSide.right);
    });

    test('summary mentions hole number, par, and distance', () {
      final analysis = HoleAnalysisEngine.analyze(
        hole: _straightPar4(),
        selectedTee: 'white',
      );
      expect(analysis.deterministicSummary, contains('Hole 1'));
      expect(analysis.deterministicSummary, contains('par 4'));
      expect(analysis.deterministicSummary, contains('380 yards'));
    });
  });

  group('Hole 2: dogleg left par 4', () {
    test('detects a left dogleg with bend angle ≥ 15°', () {
      final analysis = HoleAnalysisEngine.analyze(hole: _doglegLeftPar4());
      expect(analysis.dogleg, isNotNull);
      expect(analysis.dogleg!.direction, DoglegDirection.left);
      expect(analysis.dogleg!.bendAngleDegrees, greaterThanOrEqualTo(15));
    });

    test('summary mentions the dogleg', () {
      final analysis = HoleAnalysisEngine.analyze(hole: _doglegLeftPar4());
      expect(analysis.deterministicSummary, contains('doglegs left'));
    });
  });

  group('Hole 3: dogleg right par 4', () {
    test('detects a right dogleg with bend angle ≥ 15°', () {
      final analysis = HoleAnalysisEngine.analyze(hole: _doglegRightPar4());
      expect(analysis.dogleg, isNotNull);
      expect(analysis.dogleg!.direction, DoglegDirection.right);
      expect(analysis.dogleg!.bendAngleDegrees, greaterThanOrEqualTo(15));
    });
  });

  group('Hole 4: par 3', () {
    test('no dogleg, no hazards, par 3', () {
      final analysis =
          HoleAnalysisEngine.analyze(hole: _par3(), selectedTee: 'white');
      expect(analysis.par, 3);
      expect(analysis.dogleg, isNull);
      expect(analysis.hazards, isEmpty);
      expect(analysis.totalDistanceYards, 165);
    });

    test('summary names the par and the yardage', () {
      final analysis =
          HoleAnalysisEngine.analyze(hole: _par3(), selectedTee: 'white');
      expect(analysis.deterministicSummary, contains('par 3'));
      expect(analysis.deterministicSummary, contains('165 yards'));
    });
  });

  group('Hole 5: par 5 with two hazards', () {
    test('classifies water on the left and bunker greenside-right', () {
      final analysis =
          HoleAnalysisEngine.analyze(hole: _par5WithTwoHazards());
      expect(analysis.hazards, hasLength(2));
      // Water is mid-fairway on the left.
      final water = analysis.hazards.firstWhere((h) => h.type == HazardType.water);
      expect(water.side, HazardSide.left);
      // Bunker is right at the green.
      final bunker = analysis.hazards.firstWhere((h) => h.type == HazardType.bunker);
      expect(
        bunker.side,
        anyOf(HazardSide.greenside, HazardSide.frontOfGreen, HazardSide.right),
      );
    });

    test('hazards sort by distance from tee', () {
      final analysis =
          HoleAnalysisEngine.analyze(hole: _par5WithTwoHazards());
      final dists = analysis.hazards
          .map((h) => h.distanceFromTeeYards ?? 0)
          .toList();
      for (var i = 1; i < dists.length; i++) {
        expect(dists[i], greaterThanOrEqualTo(dists[i - 1]));
      }
    });

    test('summary mentions both hazards', () {
      final analysis =
          HoleAnalysisEngine.analyze(hole: _par5WithTwoHazards());
      expect(analysis.deterministicSummary.toLowerCase(), contains('water'));
      expect(analysis.deterministicSummary.toLowerCase(), contains('bunker'));
    });
  });
}
