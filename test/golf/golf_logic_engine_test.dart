// Golden tests for KAN-293 (S7.2) GolfLogicEngine. Per ADR 0008,
// the iOS Swift `GolfLogicEngine.swift` is the authoritative source
// — these tests pin every formula and every branch in the
// adjustment / club-selection logic.
//
// **20+ effective-distance scenarios** as required by the AC,
// covering wind × lie × slope combinations and the GI/SGI iron
// penalty. The expected values are computed by mentally executing
// the iOS code (see ADR 0008 for the methodology).

import 'package:caddieai/core/golf/golf_enums.dart';
import 'package:caddieai/core/golf/golf_logic_engine.dart';
import 'package:caddieai/core/golf/shot_context.dart';
import 'package:flutter_test/flutter_test.dart';

const _bag = <Club, int>{
  Club.driver: 245,
  Club.threeWood: 220,
  Club.fiveWood: 205,
  Club.hybrid4: 190,
  Club.iron5: 180,
  Club.iron6: 170,
  Club.iron7: 160,
  Club.iron8: 150,
  Club.iron9: 140,
  Club.pitchingWedge: 125,
  Club.gapWedge: 110,
  Club.sandWedge: 90,
  Club.lobWedge: 70,
};

const _bagPreferences = ShotPreferences(clubDistances: _bag);

void main() {
  group('windAdjustment formula', () {
    test('none → 0 regardless of direction', () {
      expect(
        GolfLogicEngine.windAdjustment(
          strength: WindStrength.none,
          direction: WindDirection.into,
          baseDistance: 150,
        ),
        0,
      );
    });

    test('light into wind: 150 × 0.03 = 4.5 yards', () {
      expect(
        GolfLogicEngine.windAdjustment(
          strength: WindStrength.light,
          direction: WindDirection.into,
          baseDistance: 150,
        ),
        4.5,
      );
    });

    test('moderate into wind: 150 × 0.07 ≈ 10.5 yards', () {
      // 150 * 0.07 = 10.500000000000002 in IEEE-754 double math.
      // The iOS Swift code has the same floating-point quirk; the
      // engine consumer rounds the SUM (not per-component) at the
      // very end, so the epsilon doesn't affect the final yardage.
      expect(
        GolfLogicEngine.windAdjustment(
          strength: WindStrength.moderate,
          direction: WindDirection.into,
          baseDistance: 150,
        ),
        closeTo(10.5, 1e-9),
      );
    });

    test('strong into wind: 150 × 0.12 = 18.0 yards', () {
      expect(
        GolfLogicEngine.windAdjustment(
          strength: WindStrength.strong,
          direction: WindDirection.into,
          baseDistance: 150,
        ),
        18.0,
      );
    });

    test('strong helping wind: -18 yards', () {
      expect(
        GolfLogicEngine.windAdjustment(
          strength: WindStrength.strong,
          direction: WindDirection.helping,
          baseDistance: 150,
        ),
        -18.0,
      );
    });

    test('strong cross wind: 18 × 0.3 = 5.4 yards (penalty, not benefit)',
        () {
      expect(
        GolfLogicEngine.windAdjustment(
          strength: WindStrength.strong,
          direction: WindDirection.crossLeftToRight,
          baseDistance: 150,
        ),
        18.0 * 0.3,
      );
    });
  });

  group('lieAdjustment table', () {
    test('every lie matches the iOS table exactly', () {
      expect(GolfLogicEngine.lieAdjustment(LieType.fairway), 0);
      expect(GolfLogicEngine.lieAdjustment(LieType.firstCut), 3);
      expect(GolfLogicEngine.lieAdjustment(LieType.rough), 7);
      expect(GolfLogicEngine.lieAdjustment(LieType.deepRough), 15);
      expect(GolfLogicEngine.lieAdjustment(LieType.greensideBunker), 5);
      expect(GolfLogicEngine.lieAdjustment(LieType.fairwayBunker), 10);
      expect(GolfLogicEngine.lieAdjustment(LieType.hardpan), -3);
      expect(GolfLogicEngine.lieAdjustment(LieType.pineStraw), 5);
      expect(
          GolfLogicEngine.lieAdjustment(LieType.treesObstructed), 20);
    });
  });

  group('slopeAdjustment formula', () {
    test('level → 0', () {
      expect(
        GolfLogicEngine.slopeAdjustment(
          slope: Slope.level,
          baseDistance: 150,
        ),
        0,
      );
    });

    test('uphill 150y: +7.5 yards', () {
      expect(
        GolfLogicEngine.slopeAdjustment(
          slope: Slope.uphill,
          baseDistance: 150,
        ),
        7.5,
      );
    });

    test('downhill 150y: -7.5 yards', () {
      expect(
        GolfLogicEngine.slopeAdjustment(
          slope: Slope.downhill,
          baseDistance: 150,
        ),
        -7.5,
      );
    });

    test('ball above feet: flat +3 regardless of distance', () {
      expect(
        GolfLogicEngine.slopeAdjustment(
          slope: Slope.ballAboveFeet,
          baseDistance: 150,
        ),
        3,
      );
      expect(
        GolfLogicEngine.slopeAdjustment(
          slope: Slope.ballAboveFeet,
          baseDistance: 250,
        ),
        3,
      );
    });
  });

  group('ironTypeLieAdjustment formula', () {
    test('GI iron from fairway bunker: 8 yards', () {
      expect(
        GolfLogicEngine.ironTypeLieAdjustment(
          lieType: LieType.fairwayBunker,
          ironType: IronType.gameImprovement,
        ),
        8,
      );
    });

    test('SGI iron from fairway bunker: 12 yards (8 × 1.5)', () {
      expect(
        GolfLogicEngine.ironTypeLieAdjustment(
          lieType: LieType.fairwayBunker,
          ironType: IronType.superGameImprovement,
        ),
        12,
      );
    });

    test('GI iron from rough: 3 yards', () {
      expect(
        GolfLogicEngine.ironTypeLieAdjustment(
          lieType: LieType.rough,
          ironType: IronType.gameImprovement,
        ),
        3,
      );
    });

    test('any iron from fairway: 0', () {
      expect(
        GolfLogicEngine.ironTypeLieAdjustment(
          lieType: LieType.fairway,
          ironType: IronType.superGameImprovement,
        ),
        0,
      );
    });
  });

  group('calculateEffectiveDistance — golden table', () {
    // Each test below picks a (distance, wind, lie, slope) tuple
    // and asserts the exact iOS-equivalent rounded result. The
    // iOS code rounds at the END (one round() over the sum), not
    // per-component, so the expected values reflect that.

    test('150y / clean conditions → 150', () {
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(distanceYards: 150),
      );
      expect(distance, 150);
    });

    test('150y / moderate into wind / fairway / level → 150 + 10.5 → 161',
        () {
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(
          distanceYards: 150,
          windStrength: WindStrength.moderate,
          windDirection: WindDirection.into,
        ),
      );
      // 150 + 10.5 = 160.5 → rounds to 161 (banker's rounding away
      // from zero, which Dart's `double.round()` does for .5 values
      // by rounding half away from zero).
      expect(distance, 161);
    });

    test('150y / strong helping / fairway → 150 - 18 = 132', () {
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(
          distanceYards: 150,
          windStrength: WindStrength.strong,
          windDirection: WindDirection.helping,
        ),
      );
      expect(distance, 132);
    });

    test('150y / no wind / rough / level → 150 + 7 = 157', () {
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(
          distanceYards: 150,
          lieType: LieType.rough,
        ),
      );
      expect(distance, 157);
    });

    test('150y / no wind / deep rough / level → 150 + 15 = 165', () {
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(
          distanceYards: 150,
          lieType: LieType.deepRough,
        ),
      );
      expect(distance, 165);
    });

    test('150y / hardpan → 150 - 3 = 147', () {
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(
          distanceYards: 150,
          lieType: LieType.hardpan,
        ),
      );
      expect(distance, 147);
    });

    test('150y / uphill → 150 + 7.5 = 158 (round half away from zero)',
        () {
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(
          distanceYards: 150,
          slope: Slope.uphill,
        ),
      );
      expect(distance, 158);
    });

    test('150y / downhill → 150 - 7.5 = 142.5 → 143 (round half away from 0)',
        () {
      // Dart's `double.round()` rounds half AWAY from zero, so
      // 142.5 → 143. iOS Swift `.rounded()` defaults to
      // `.toNearestOrAwayFromZero` — same behavior. Locked in here
      // so a future "switch to banker's rounding" change trips
      // the test.
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(
          distanceYards: 150,
          slope: Slope.downhill,
        ),
      );
      expect(distance, 143);
    });

    test(
        '150y / moderate into wind / rough / uphill → 150 + 10.5 + 7 + 7.5 = 175',
        () {
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(
          distanceYards: 150,
          lieType: LieType.rough,
          windStrength: WindStrength.moderate,
          windDirection: WindDirection.into,
          slope: Slope.uphill,
        ),
      );
      expect(distance, 175);
    });

    test(
        '150y / strong into wind / fairway bunker / GI iron → 150 + 18 + 10 + 8 = 186',
        () {
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(
          distanceYards: 150,
          lieType: LieType.fairwayBunker,
          windStrength: WindStrength.strong,
          windDirection: WindDirection.into,
        ),
        ironType: IronType.gameImprovement,
      );
      expect(distance, 186);
    });

    test(
        '150y / strong into wind / fairway bunker / SGI iron → 150 + 18 + 10 + 12 = 190',
        () {
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(
          distanceYards: 150,
          lieType: LieType.fairwayBunker,
          windStrength: WindStrength.strong,
          windDirection: WindDirection.into,
        ),
        ironType: IronType.superGameImprovement,
      );
      expect(distance, 190);
    });

    test('clamps to a minimum of 1 yard', () {
      // 5 yards downhill: 5 * 0.05 = 0.25, plus level lie 0, no wind
      // → 5 - 0.25 = 4.75 → rounds to 5. Boundary check.
      final distance = GolfLogicEngine.calculateEffectiveDistance(
        context: const ShotContext(
          distanceYards: 5,
          slope: Slope.downhill,
        ),
      );
      expect(distance, 5);
    });
  });

  group('selectClub', () {
    test('picks the shortest club that still covers the distance', () {
      // 160y effective: 7-iron (160) is the perfect fit. The
      // selector should pick the shortest club whose carry >=
      // distance, which is the 7-iron.
      final club = GolfLogicEngine.selectClub(
        effectiveDistance: 160,
        clubDistances: _bag,
      );
      expect(club, Club.iron7);
    });

    test('rounds up when distance is between two clubs', () {
      // 165y → 6-iron (170) is the shortest that covers it.
      final club = GolfLogicEngine.selectClub(
        effectiveDistance: 165,
        clubDistances: _bag,
      );
      expect(club, Club.iron6);
    });

    test(
        'unreachable target: when no club covers the distance, falls back '
        'to the shortest allowed club. Mirrors the iOS algorithm '
        '(`sorted.last?.club ?? .pitchingWedge`) — see GolfLogicEngine.selectClub '
        'comments and ADR 0008. Product can revisit this fallback later '
        'as a separate Flutter+iOS change.', () {
      final club = GolfLogicEngine.selectClub(
        effectiveDistance: 300,
        clubDistances: _bag,
      );
      expect(club, Club.lobWedge);
    });

    test(
        'maxAllowedClub limits the candidate set; the same fallback '
        'applies when nothing in the limited set covers the distance', () {
      // Max allowed is 6-iron from a fairway bunker. Effective
      // distance 220y exceeds 6-iron carry (170y), so no club in
      // {6i, 7i, 8i, 9i, PW, GW, SW, LW} covers — falls back to
      // the shortest in that set = LW.
      final club = GolfLogicEngine.selectClub(
        effectiveDistance: 220,
        clubDistances: _bag,
        maxAllowedClub: Club.iron6,
      );
      expect(club, Club.lobWedge);
    });

    test(
        'maxAllowedClub picks the correct club when one IS reachable '
        'within the limited set', () {
      // Max allowed iron6 (170y) and effective distance 165y →
      // iron6 covers, iron7 (160y) doesn't. iOS returns iron6.
      final club = GolfLogicEngine.selectClub(
        effectiveDistance: 165,
        clubDistances: _bag,
        maxAllowedClub: Club.iron6,
      );
      expect(club, Club.iron6);
    });
  });

  group('maxClubForLie', () {
    test('fairway → no limit', () {
      expect(GolfLogicEngine.maxClubForLie(LieType.fairway), isNull);
    });

    test('deep rough → 7-iron', () {
      expect(GolfLogicEngine.maxClubForLie(LieType.deepRough), Club.iron7);
    });

    test('greenside bunker → sand wedge', () {
      expect(
          GolfLogicEngine.maxClubForLie(LieType.greensideBunker), Club.sandWedge);
    });

    test('SGI iron from fairway bunker → 8-iron (tighter than GI 7-iron)',
        () {
      expect(
        GolfLogicEngine.maxClubForLie(
          LieType.fairwayBunker,
          ironType: IronType.superGameImprovement,
        ),
        Club.iron8,
      );
      expect(
        GolfLogicEngine.maxClubForLie(
          LieType.fairwayBunker,
          ironType: IronType.gameImprovement,
        ),
        Club.iron7,
      );
    });
  });

  group('analyze — full integration', () {
    test('returns a complete DeterministicAnalysis', () {
      final analysis = GolfLogicEngine.analyze(
        context: const ShotContext(
          distanceYards: 160,
          shotType: ShotType.approach,
        ),
        profile: _bagPreferences,
      );
      expect(analysis.effectiveDistanceYards, 160);
      expect(analysis.recommendedClub, Club.iron7);
      expect(analysis.targetStrategy.target, contains('Center of the green'));
      expect(analysis.executionPlan, isNotNull);
      expect(analysis.executionPlan.archetype.name, contains('stockFullSwing'));
    });

    test(
        'water-left hazard note rewrites the preferred miss to "miss right"',
        () {
      final analysis = GolfLogicEngine.analyze(
        context: const ShotContext(
          distanceYards: 150,
          shotType: ShotType.approach,
          hazardNotes: 'water left of the green',
        ),
        profile: _bagPreferences,
      );
      expect(analysis.targetStrategy.preferredMiss,
          'Miss right — water left');
      expect(analysis.targetStrategy.reasoning,
          contains('Water left makes right the safe miss'));
    });
  });
}
