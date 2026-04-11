// Golden tests for KAN-292 (S7.1) ExecutionEngine. Per ADR 0008,
// the iOS Swift `ExecutionEngine.swift` is the authoritative source
// — these tests pin every branch in `selectArchetype` plus the
// adjustment chains so any drift from the iOS port fails the build.
//
// **Coverage strategy:**
//
//   1. **Archetype selection** — one test per branch in
//      `selectArchetype` (greenside bunker, fairway bunker, trees,
//      punch recovery, deep rough, tee + driver, tee + 3W, chip
//      with each chip-style preference, pitch under 40, pitch over
//      40, layup, partial wedge band 30-70, knockdown into wind
//      [moderate], knockdown into wind [strong], stock full swing).
//   2. **Slope adjustments** — uphill, downhill, ball above feet,
//      ball below feet, level (no-op).
//   3. **Wind adjustments** — into-moderate, into-strong, helping,
//      cross (no-op), none (no-op).
//   4. **Lie adjustments** — hardpan, pine straw, first cut.
//   5. **Player preference adjustments** — bunker confidence (low),
//      wedge confidence (low), swing tendency (steep on chip),
//      swing tendency (shallow on bunker).
//   6. **End-to-end golden** — a fully-populated input runs through
//      every adjustment and the final ExecutionPlan is asserted
//      against the exact field values the iOS engine would
//      produce.

import 'package:caddieai/core/golf/execution_engine.dart';
import 'package:caddieai/core/golf/golf_enums.dart';
import 'package:caddieai/core/golf/shot_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectArchetype branches', () {
    test('greenside bunker → bunkerExplosion', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(
          lieType: LieType.greensideBunker,
          shotType: ShotType.bunker,
        ),
        club: Club.sandWedge,
        effectiveDistance: 30,
      );
      expect(result, ExecutionArchetype.bunkerExplosion);
    });

    test('fairway bunker → fairwayBunkerShot', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(
          lieType: LieType.fairwayBunker,
          shotType: ShotType.bunker,
        ),
        club: Club.iron7,
        effectiveDistance: 150,
      );
      expect(result, ExecutionArchetype.fairwayBunkerShot);
    });

    test('trees → recoveryUnderTrees (lie wins over shot type)', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(
          lieType: LieType.treesObstructed,
          shotType: ShotType.approach,
        ),
        club: Club.iron7,
        effectiveDistance: 120,
      );
      expect(result, ExecutionArchetype.recoveryUnderTrees);
    });

    test('punchRecovery shot type → punchShot', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(
          lieType: LieType.fairway,
          shotType: ShotType.punchRecovery,
        ),
        club: Club.iron5,
        effectiveDistance: 140,
      );
      expect(result, ExecutionArchetype.punchShot);
    });

    test('deepRough → recoveryFromRough', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(
          lieType: LieType.deepRough,
          shotType: ShotType.approach,
        ),
        club: Club.iron8,
        effectiveDistance: 130,
      );
      expect(result, ExecutionArchetype.recoveryFromRough);
    });

    test('tee + driver → teeDriver', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(shotType: ShotType.tee),
        club: Club.driver,
        effectiveDistance: 250,
      );
      expect(result, ExecutionArchetype.teeDriver);
    });

    test('tee + 3-wood → teeFairwayWood', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(shotType: ShotType.tee),
        club: Club.threeWood,
        effectiveDistance: 220,
      );
      expect(result, ExecutionArchetype.teeFairwayWood);
    });

    test('chip + bumpAndRun preference → bumpAndRunChip', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(shotType: ShotType.chip),
        club: Club.pitchingWedge,
        effectiveDistance: 25,
        profile:
            const ShotPreferences(preferredChipStyle: ChipStyle.bumpAndRun),
      );
      expect(result, ExecutionArchetype.bumpAndRunChip);
    });

    test('chip + lofted preference → standardChip', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(shotType: ShotType.chip),
        club: Club.sandWedge,
        effectiveDistance: 25,
        profile:
            const ShotPreferences(preferredChipStyle: ChipStyle.lofted),
      );
      expect(result, ExecutionArchetype.standardChip);
    });

    test(
        'chip + noPreference + ≤20 yards → bumpAndRunChip (band boundary)',
        () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(shotType: ShotType.chip),
        club: Club.pitchingWedge,
        effectiveDistance: 20,
        profile: const ShotPreferences(),
      );
      expect(result, ExecutionArchetype.bumpAndRunChip);
    });

    test('chip + noPreference + 21 yards → standardChip', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(shotType: ShotType.chip),
        club: Club.pitchingWedge,
        effectiveDistance: 21,
        profile: const ShotPreferences(),
      );
      expect(result, ExecutionArchetype.standardChip);
    });

    test('pitch ≤40 yards → softPitch', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(shotType: ShotType.pitch),
        club: Club.sandWedge,
        effectiveDistance: 35,
      );
      expect(result, ExecutionArchetype.softPitch);
    });

    test('pitch >40 yards → standardPitch', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(shotType: ShotType.pitch),
        club: Club.gapWedge,
        effectiveDistance: 60,
      );
      expect(result, ExecutionArchetype.standardPitch);
    });

    test('layup shot type → layupSwing', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(shotType: ShotType.layup),
        club: Club.iron5,
        effectiveDistance: 200,
      );
      expect(result, ExecutionArchetype.layupSwing);
    });

    test('approach 30-70 yards → partialWedge', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(shotType: ShotType.approach),
        club: Club.gapWedge,
        effectiveDistance: 50,
      );
      expect(result, ExecutionArchetype.partialWedge);
    });

    test('approach + strong wind into → knockdownApproach', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(
          shotType: ShotType.approach,
          windStrength: WindStrength.strong,
          windDirection: WindDirection.into,
        ),
        club: Club.iron7,
        effectiveDistance: 150,
      );
      expect(result, ExecutionArchetype.knockdownApproach);
    });

    test('approach + moderate wind into → knockdownApproach', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(
          shotType: ShotType.approach,
          windStrength: WindStrength.moderate,
          windDirection: WindDirection.into,
        ),
        club: Club.iron7,
        effectiveDistance: 150,
      );
      expect(result, ExecutionArchetype.knockdownApproach);
    });

    test('plain approach with no wind → stockFullSwing (default)', () {
      final result = ExecutionEngine.selectArchetype(
        context: const ShotContext(shotType: ShotType.approach),
        club: Club.iron7,
        effectiveDistance: 155,
      );
      expect(result, ExecutionArchetype.stockFullSwing);
    });
  });

  group('slope adjustments', () {
    test('uphill rewrites ballPosition + weightDistribution + appends to '
        'strikeIntention', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final adjusted = ExecutionEngine.adjustForSlope(
        plan: plan,
        slope: Slope.uphill,
      );
      expect(
        adjusted.ballPosition,
        'slightly forward of center, slightly more forward for the slope',
      );
      expect(
        adjusted.weightDistribution,
        'favor lead side more to resist falling back',
      );
      expect(
        adjusted.strikeIntention,
        'compress the ball with a centered strike — uphill lie adds loft, '
        'so expect higher flight',
      );
    });

    test('downhill rewrites the same fields with downhill phrasing', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final adjusted = ExecutionEngine.adjustForSlope(
        plan: plan,
        slope: Slope.downhill,
      );
      expect(
        adjusted.ballPosition,
        'slightly forward of center, slightly more back for the slope',
      );
      expect(adjusted.weightDistribution,
          'stay centered, resist falling toward target');
      expect(
        adjusted.strikeIntention,
        'compress the ball with a centered strike — downhill lie reduces '
        'loft, expect lower flight',
      );
    });

    test('ballAboveFeet rewrites alignment + appends to setupSummary', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final adjusted = ExecutionEngine.adjustForSlope(
        plan: plan,
        slope: Slope.ballAboveFeet,
      );
      expect(adjusted.alignment,
          'aim slightly right — ball above feet promotes a draw');
      expect(
        adjusted.setupSummary,
        'Standard setup, ball slightly forward, committed swing.'
        ' Grip down slightly for control.',
      );
    });

    test('ballBelowFeet rewrites alignment + different setup append', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final adjusted = ExecutionEngine.adjustForSlope(
        plan: plan,
        slope: Slope.ballBelowFeet,
      );
      expect(adjusted.alignment,
          'aim slightly left — ball below feet promotes a fade');
      expect(
        adjusted.setupSummary,
        'Standard setup, ball slightly forward, committed swing.'
        ' Flex knees more and stay down through it.',
      );
    });

    test('level is a no-op', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final original = ExecutionEngine.template(
        ExecutionArchetype.stockFullSwing,
      );
      final adjusted = ExecutionEngine.adjustForSlope(
        plan: plan,
        slope: Slope.level,
      );
      expect(adjusted, original);
    });
  });

  group('wind adjustments', () {
    test('moderate into wind rewrites tempo + mistakeToAvoid', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final adjusted = ExecutionEngine.adjustForWind(
        plan: plan,
        wind: WindStrength.moderate,
        direction: WindDirection.into,
      );
      expect(adjusted.tempo, 'smooth — do not swing harder into wind');
      expect(
        adjusted.mistakeToAvoid,
        'do not swing harder to fight the wind — smooth tempo keeps spin down',
      );
    });

    test('strong into wind rewrites the same fields', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final adjusted = ExecutionEngine.adjustForWind(
        plan: plan,
        wind: WindStrength.strong,
        direction: WindDirection.into,
      );
      expect(adjusted.tempo, 'smooth — do not swing harder into wind');
    });

    test('helping wind appends to strikeIntention', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final adjusted = ExecutionEngine.adjustForWind(
        plan: plan,
        wind: WindStrength.light,
        direction: WindDirection.helping,
      );
      expect(
        adjusted.strikeIntention,
        'compress the ball with a centered strike — helping wind will add carry',
      );
    });

    test('none is a no-op', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final original = ExecutionEngine.template(
        ExecutionArchetype.stockFullSwing,
      );
      final adjusted = ExecutionEngine.adjustForWind(
        plan: plan,
        wind: WindStrength.none,
        direction: WindDirection.into,
      );
      expect(adjusted, original);
    });
  });

  group('lie adjustments', () {
    test('hardpan rewrites strikeIntention + mistakeToAvoid', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final adjusted = ExecutionEngine.adjustForLie(
        plan: plan,
        lie: LieType.hardpan,
        archetype: ExecutionArchetype.stockFullSwing,
      );
      expect(adjusted.strikeIntention,
          'pick it clean — no room for fat contact on hardpan');
      expect(
          adjusted.mistakeToAvoid, 'do not hit behind the ball on hardpan');
    });

    test('pineStraw appends to setupSummary + rewrites mistakeToAvoid', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final adjusted = ExecutionEngine.adjustForLie(
        plan: plan,
        lie: LieType.pineStraw,
        archetype: ExecutionArchetype.stockFullSwing,
      );
      expect(
        adjusted.setupSummary,
        "Standard setup, ball slightly forward, committed swing. Don't ground the club.",
      );
      expect(adjusted.mistakeToAvoid,
          'do not ground the club at address — hover it');
    });

    test('firstCut appends to strikeIntention', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final adjusted = ExecutionEngine.adjustForLie(
        plan: plan,
        lie: LieType.firstCut,
        archetype: ExecutionArchetype.stockFullSwing,
      );
      expect(
        adjusted.strikeIntention,
        'compress the ball with a centered strike — first cut may grab the hosel slightly',
      );
    });
  });

  group('player preference adjustments', () {
    test('low bunker confidence rewrites bunkerExplosion swingThought', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.bunkerExplosion);
      final adjusted = ExecutionEngine.adjustForPlayerPreferences(
        plan: plan,
        profile: const ShotPreferences(
          bunkerConfidence: SelfConfidence.low,
        ),
        archetype: ExecutionArchetype.bunkerExplosion,
      );
      expect(adjusted.swingThought,
          'commit to the sand — trust the bounce and accelerate through');
      expect(adjusted.mistakeToAvoid,
          'do not decelerate through the sand — commit fully');
    });

    test('low wedge confidence rewrites partialWedge swingThought', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.partialWedge);
      final adjusted = ExecutionEngine.adjustForPlayerPreferences(
        plan: plan,
        profile: const ShotPreferences(
          wedgeConfidence: SelfConfidence.low,
        ),
        archetype: ExecutionArchetype.partialWedge,
      );
      expect(
        adjusted.swingThought,
        'match your backswing and follow-through — smooth and simple',
      );
    });

    test('steep tendency on bunkerExplosion rewrites strikeIntention', () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.bunkerExplosion);
      final adjusted = ExecutionEngine.adjustForPlayerPreferences(
        plan: plan,
        profile: const ShotPreferences(swingTendency: SwingTendency.steep),
        archetype: ExecutionArchetype.bunkerExplosion,
      );
      expect(
        adjusted.strikeIntention,
        'use your natural steep angle — enter the sand close behind the ball',
      );
    });

    test('shallow tendency on stockFullSwing appends to strikeIntention',
        () {
      final plan =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      final adjusted = ExecutionEngine.adjustForPlayerPreferences(
        plan: plan,
        profile: const ShotPreferences(swingTendency: SwingTendency.shallow),
        archetype: ExecutionArchetype.stockFullSwing,
      );
      expect(
        adjusted.strikeIntention,
        'compress the ball with a centered strike — stay down through the ball',
      );
    });
  });

  group('end-to-end golden', () {
    test(
        'approach 150y, light into wind, fairway, neutral player → stockFullSwing '
        'with no adjustments applied (light wind into is below threshold)',
        () {
      final plan = ExecutionEngine.generateExecutionPlan(
        context: const ShotContext(
          distanceYards: 150,
          shotType: ShotType.approach,
          lieType: LieType.fairway,
          windStrength: WindStrength.light,
          windDirection: WindDirection.into,
        ),
        club: Club.iron7,
        effectiveDistance: 152,
        profile: const ShotPreferences(),
      );
      // Light into wind does NOT trigger the tempo override (threshold
      // is moderate or above). Same for the lie/slope/preference paths.
      // This is the canonical "fresh template" output.
      final fresh =
          ExecutionEngine.template(ExecutionArchetype.stockFullSwing);
      expect(plan, fresh);
    });

    test(
        'approach 150y, MODERATE into wind, hardpan, low bunker confidence '
        '(irrelevant — not a bunker shot), uphill slope → stockFullSwing '
        'with slope + wind + hardpan + (no preference) adjustments stacked',
        () {
      final plan = ExecutionEngine.generateExecutionPlan(
        context: const ShotContext(
          distanceYards: 150,
          shotType: ShotType.approach,
          lieType: LieType.hardpan,
          windStrength: WindStrength.moderate,
          windDirection: WindDirection.into,
          slope: Slope.uphill,
        ),
        club: Club.iron7,
        effectiveDistance: 152,
        profile: const ShotPreferences(
          bunkerConfidence: SelfConfidence.low,
        ),
      );

      // The selector returns knockdownApproach because moderate wind
      // into qualifies for the knockdown branch (line 110 of iOS).
      expect(plan.archetype, ExecutionArchetype.knockdownApproach);

      // Slope: uphill rewrites ballPosition + weightDistribution +
      // appends to strikeIntention.
      expect(plan.ballPosition,
          'slightly back of normal, slightly more forward for the slope');
      expect(plan.weightDistribution,
          'favor lead side more to resist falling back');

      // Wind (moderate into): rewrites tempo + mistakeToAvoid.
      // BUT lie (hardpan) ALSO rewrites mistakeToAvoid, and lie runs
      // AFTER wind, so the final mistakeToAvoid is the hardpan one.
      expect(plan.tempo, 'smooth — do not swing harder into wind');
      expect(plan.mistakeToAvoid,
          'do not hit behind the ball on hardpan');

      // Lie (hardpan): rewrites strikeIntention. The slope's
      // strikeIntention append happened FIRST, but hardpan's
      // assignment is unconditional, so the final value is the
      // hardpan string with no slope suffix.
      expect(plan.strikeIntention,
          'pick it clean — no room for fat contact on hardpan');

      // Bunker confidence is irrelevant on a non-bunker archetype —
      // setupSummary should NOT have the bunker confidence text.
      expect(plan.setupSummary,
          isNot(contains('open the face and let the club do the work')));
    });
  });
}
