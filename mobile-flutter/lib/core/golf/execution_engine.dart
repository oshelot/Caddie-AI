// ExecutionEngine — KAN-292 (S7.1) Flutter port of
// `ios/CaddieAI/Services/ExecutionEngine.swift`. Per **ADR 0008**,
// the iOS native is the authoritative source for this engine; the
// Android `ShotExecutionEngine.kt` uses a leaner functional style
// that we are NOT porting (it'll be aligned to the Flutter port
// post-cutover).
//
// **Pure function from `(context, club, distance, profile)` to
// `ExecutionPlan`.** No I/O, no logging, no random, no clock. The
// engine is fully deterministic and the golden tests in
// `test/golf/execution_engine_test.dart` lock in that determinism
// for 25+ permutations.
//
// **How to read this file:** every method has a `// iOS line N` or
// `// iOS lines N-M` comment pointing back at the canonical Swift
// source. If a future bug report says "the Flutter recommendation
// differs from iOS", reading the Swift file at those line numbers
// is the diff strategy.

import 'execution_plan.dart';
import 'golf_enums.dart';
import 'shot_context.dart';

abstract final class ExecutionEngine {
  ExecutionEngine._();

  /// Primary entry point. Mirrors iOS
  /// `ExecutionEngine.generateExecutionPlan(context:club:effectiveDistance:profile:)`
  /// (lines 12-37 of the Swift file). Order of operations is
  /// non-negotiable: archetype → template → slope → wind → lie →
  /// player preferences. Don't reorder without re-running the
  /// golden tests; some adjustments append to fields written by
  /// earlier adjustments and the order matters.
  static ExecutionPlan generateExecutionPlan({
    required ShotContext context,
    required Club club,
    required int effectiveDistance,
    ShotPreferences? profile,
  }) {
    final archetype = selectArchetype(
      context: context,
      club: club,
      effectiveDistance: effectiveDistance,
      profile: profile,
    );
    var plan = template(archetype);

    plan = adjustForSlope(plan: plan, slope: context.slope);
    plan = adjustForWind(
      plan: plan,
      wind: context.windStrength,
      direction: context.windDirection,
    );
    plan = adjustForLie(
      plan: plan,
      lie: context.lieType,
      archetype: archetype,
    );

    if (profile != null) {
      plan = adjustForPlayerPreferences(
        plan: plan,
        profile: profile,
        archetype: archetype,
      );
    }

    return plan;
  }

  // ── Archetype selection (iOS lines 41-116) ──────────────────────

  static ExecutionArchetype selectArchetype({
    required ShotContext context,
    required Club club,
    required int effectiveDistance,
    ShotPreferences? profile,
  }) {
    // Bunker shots
    if (context.lieType == LieType.greensideBunker) {
      return ExecutionArchetype.bunkerExplosion;
    }
    if (context.lieType == LieType.fairwayBunker) {
      return ExecutionArchetype.fairwayBunkerShot;
    }

    // Recovery shots
    if (context.lieType == LieType.treesObstructed) {
      return ExecutionArchetype.recoveryUnderTrees;
    }
    if (context.shotType == ShotType.punchRecovery) {
      return ExecutionArchetype.punchShot;
    }
    if (context.lieType == LieType.deepRough) {
      return ExecutionArchetype.recoveryFromRough;
    }

    // Tee shots
    if (context.shotType == ShotType.tee) {
      if (club == Club.driver) {
        return ExecutionArchetype.teeDriver;
      } else {
        return ExecutionArchetype.teeFairwayWood;
      }
    }

    // Short game by shot type — factor in player chip style preference
    if (context.shotType == ShotType.chip) {
      final chipPref = profile?.preferredChipStyle;
      if (chipPref != null) {
        switch (chipPref) {
          case ChipStyle.bumpAndRun:
            return ExecutionArchetype.bumpAndRunChip;
          case ChipStyle.lofted:
            return ExecutionArchetype.standardChip;
          case ChipStyle.noPreference:
            return effectiveDistance <= 20
                ? ExecutionArchetype.bumpAndRunChip
                : ExecutionArchetype.standardChip;
        }
      }
      return effectiveDistance <= 20
          ? ExecutionArchetype.bumpAndRunChip
          : ExecutionArchetype.standardChip;
    }

    if (context.shotType == ShotType.pitch) {
      if (effectiveDistance <= 40) {
        return ExecutionArchetype.softPitch;
      }
      return ExecutionArchetype.standardPitch;
    }

    // Layup
    if (context.shotType == ShotType.layup) {
      return ExecutionArchetype.layupSwing;
    }

    // Partial wedge (30-70 yards)
    if (effectiveDistance >= 30 && effectiveDistance <= 70) {
      return ExecutionArchetype.partialWedge;
    }

    // Knockdown (into wind)
    if (context.windStrength == WindStrength.strong &&
        context.windDirection == WindDirection.into) {
      return ExecutionArchetype.knockdownApproach;
    }
    if (context.windStrength == WindStrength.moderate &&
        context.windDirection == WindDirection.into) {
      return ExecutionArchetype.knockdownApproach;
    }

    // Default: stock full swing
    return ExecutionArchetype.stockFullSwing;
  }

  // ── Archetype templates (iOS lines 120-378) ─────────────────────
  //
  // Every string below is a verbatim copy of the iOS template. Do
  // NOT edit them without updating ADR 0008 and the golden tests.

  static ExecutionPlan template(ExecutionArchetype archetype) {
    switch (archetype) {
      case ExecutionArchetype.bumpAndRunChip:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Ball back, weight left, narrow stance.',
          ballPosition: 'back of center',
          weightDistribution: '60-70% lead side',
          stanceWidth: 'narrow',
          alignment: 'slightly open',
          clubface: 'square',
          shaftLean: 'forward',
          backswingLength: 'short',
          followThrough: 'short controlled finish',
          tempo: 'quiet and controlled',
          strikeIntention: 'clip the ball cleanly and let it roll',
          swingThought: 'putting stroke with loft',
          mistakeToAvoid: 'do not try to help the ball into the air',
        );
      case ExecutionArchetype.standardChip:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Ball center, lean toward target, compact motion.',
          ballPosition: 'center',
          weightDistribution: '60% lead side',
          stanceWidth: 'narrow',
          alignment: 'slightly open',
          clubface: 'square',
          shaftLean: 'slight forward lean',
          backswingLength: 'short to quarter',
          followThrough: 'short, matching backswing length',
          tempo: 'smooth and steady',
          strikeIntention: 'brush the turf lightly after the ball',
          swingThought: 'keep your hands ahead through impact',
          mistakeToAvoid: 'do not flip the wrists at impact',
        );
      case ExecutionArchetype.softPitch:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Ball center-forward, soft hands, use the loft.',
          ballPosition: 'center to slightly forward of center',
          weightDistribution: 'slightly favor lead side',
          stanceWidth: 'narrow',
          alignment: 'slightly open',
          clubface: 'slightly open for more loft',
          shaftLean: 'minimal forward lean',
          backswingLength: 'waist high',
          followThrough: 'full soft finish',
          tempo: 'smooth with acceleration through',
          strikeIntention: 'brush the turf and use the loft',
          swingThought: 'let the club slide under with speed',
          mistakeToAvoid: 'do not decelerate or quit on it',
        );
      case ExecutionArchetype.standardPitch:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary:
              'Ball center-forward, controlled backswing, full release.',
          ballPosition: 'center to slightly forward',
          weightDistribution: 'slightly favor lead side',
          stanceWidth: 'narrow to medium',
          alignment: 'slightly open',
          clubface: 'square to slightly open',
          shaftLean: 'minimal',
          backswingLength: 'chest high',
          followThrough: 'full soft finish',
          tempo: 'smooth with acceleration through',
          strikeIntention: 'brush the turf and use the bounce',
          swingThought: 'match the backswing and follow-through length',
          mistakeToAvoid: 'do not scoop or try to lift the ball',
        );
      case ExecutionArchetype.partialWedge:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Ball center, controlled motion, commit to distance.',
          ballPosition: 'center',
          weightDistribution: 'balanced to slightly lead',
          stanceWidth: 'medium',
          alignment: 'square to slightly open',
          clubface: 'square',
          shaftLean: 'slight forward lean',
          backswingLength: 'half to three-quarter',
          followThrough: 'controlled finish matching backswing',
          tempo: 'smooth and rhythmic',
          strikeIntention: 'ball-first contact, consistent strike',
          swingThought: 'control the length, commit to the swing',
          mistakeToAvoid: 'do not try to add distance by swinging harder',
        );
      case ExecutionArchetype.bunkerExplosion:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary:
              'Ball forward, open stance, open face, splash the sand.',
          ballPosition: 'forward of center',
          weightDistribution: 'favor lead side and keep it there',
          stanceWidth: 'stable, slightly wider than chip',
          alignment: 'open stance, body left of target',
          clubface: 'open',
          shaftLean: 'neutral to slight backward feel',
          backswingLength: 'half to three-quarter',
          followThrough: 'full splash-through finish',
          tempo: 'committed with speed through the sand',
          strikeIntention: 'enter sand behind the ball and use the bounce',
          swingThought: 'splash the sand, not the ball',
          mistakeToAvoid: 'do not try to pick the ball clean',
        );
      case ExecutionArchetype.fairwayBunkerShot:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Ball center, dig feet in, pick it clean.',
          ballPosition: 'center',
          weightDistribution: 'balanced, stable lower body',
          stanceWidth: 'medium, dig feet slightly into sand',
          alignment: 'square',
          clubface: 'square',
          shaftLean: 'slight forward lean',
          backswingLength: 'three-quarter',
          followThrough: 'controlled finish',
          tempo: 'smooth and stable',
          strikeIntention: 'pick the ball clean, ball first',
          swingThought: 'quiet lower body, pick it clean',
          mistakeToAvoid:
              'do not hit behind the ball or take too much sand',
        );
      case ExecutionArchetype.stockFullSwing:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary:
              'Standard setup, ball slightly forward, committed swing.',
          ballPosition: 'slightly forward of center',
          weightDistribution: 'balanced to slightly lead side',
          stanceWidth: 'shoulder width',
          alignment: 'square to target line',
          clubface: 'square',
          shaftLean: 'natural athletic address',
          backswingLength: 'full',
          followThrough: 'full balanced finish',
          tempo: 'committed and even',
          strikeIntention: 'compress the ball with a centered strike',
          swingThought: 'commit to the target and finish balanced',
          mistakeToAvoid: 'do not decelerate through impact',
        );
      case ExecutionArchetype.knockdownApproach:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Ball slightly back, favor lead side, shorter finish.',
          ballPosition: 'slightly back of normal',
          weightDistribution: 'favor lead side',
          stanceWidth: 'slightly narrower than full',
          alignment: 'square to slightly open',
          clubface: 'square',
          shaftLean: 'slight forward lean',
          backswingLength: 'three-quarter',
          followThrough: 'abbreviated chest-high finish',
          tempo: 'controlled and stable',
          strikeIntention: 'flight it down with a compressed strike',
          swingThought: 'shorter finish, hold the flight down',
          mistakeToAvoid:
              'do not try to swing harder to compensate for wind',
        );
      case ExecutionArchetype.punchShot:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Ball back, hands ahead, low finish.',
          ballPosition: 'back of center',
          weightDistribution: '60-65% lead side',
          stanceWidth: 'medium',
          alignment: 'square to escape route',
          clubface: 'square to slightly closed',
          shaftLean: 'forward lean',
          backswingLength: 'half to three-quarter',
          followThrough: 'hold-off finish, hands stay low',
          tempo: 'firm and controlled',
          strikeIntention: 'trap the ball and keep it low',
          swingThought: 'hands low through and past impact',
          mistakeToAvoid: 'do not let the club release and add loft',
        );
      case ExecutionArchetype.layupSwing:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Controlled swing to a specific yardage.',
          ballPosition: 'center to slightly forward',
          weightDistribution: 'balanced',
          stanceWidth: 'shoulder width',
          alignment: 'square to layup target',
          clubface: 'square',
          shaftLean: 'natural',
          backswingLength: 'three-quarter to full',
          followThrough: 'full balanced finish',
          tempo: 'smooth and controlled',
          strikeIntention: 'solid contact to the safe zone',
          swingThought: 'pick a specific target and commit',
          mistakeToAvoid: 'do not try to squeeze extra distance',
        );
      case ExecutionArchetype.teeDriver:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Ball forward, wide stance, swing through it.',
          ballPosition: 'inside lead heel',
          weightDistribution: 'balanced, slight tilt away from target',
          stanceWidth: 'wider than shoulders',
          alignment: 'square to target line',
          clubface: 'square',
          shaftLean: 'neutral, shaft and lead arm form a line',
          backswingLength: 'full',
          followThrough: 'full finish, belt buckle to target',
          tempo: 'smooth and powerful',
          strikeIntention: 'sweep the ball off the tee on the upswing',
          swingThought: 'wide takeaway, full turn, trust the swing',
          mistakeToAvoid: 'do not try to kill it — tempo wins',
        );
      case ExecutionArchetype.teeFairwayWood:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Ball forward, tee it low, sweep it off the tee.',
          ballPosition: 'forward of center, just inside lead heel',
          weightDistribution: 'balanced',
          stanceWidth: 'shoulder width',
          alignment: 'square to target',
          clubface: 'square',
          shaftLean: 'natural',
          backswingLength: 'full',
          followThrough: 'full balanced finish',
          tempo: 'smooth and rhythmic',
          strikeIntention: 'sweep the ball off the low tee',
          swingThought: 'smooth tempo, let the loft work',
          mistakeToAvoid: 'do not try to help it up — trust the club',
        );
      case ExecutionArchetype.recoveryFromRough:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Ball center, grip down, commit to the strike.',
          ballPosition: 'center',
          weightDistribution: 'slightly favor lead side',
          stanceWidth: 'medium',
          alignment: 'square to escape line',
          clubface: 'slightly closed to fight the grass',
          shaftLean: 'forward lean to reduce grab',
          backswingLength: 'three-quarter',
          followThrough: 'firm finish, fight through the grass',
          tempo: 'firm and committed',
          strikeIntention: 'drive through the rough, ball first',
          swingThought: 'grip it firm and commit through impact',
          mistakeToAvoid:
              'do not take too much club — the rough kills distance',
        );
      case ExecutionArchetype.recoveryUnderTrees:
        return ExecutionPlan(
          archetype: archetype,
          setupSummary: 'Ball back, keep it low, punch to safety.',
          ballPosition: 'back of center',
          weightDistribution: '60% lead side',
          stanceWidth: 'medium',
          alignment: 'toward the opening',
          clubface: 'square to slightly closed',
          shaftLean: 'strong forward lean',
          backswingLength: 'half',
          followThrough: 'hold-off finish, keep hands low',
          tempo: 'controlled and firm',
          strikeIntention: 'trap it low under the branches',
          swingThought: 'low hands, low ball, find the fairway',
          mistakeToAvoid: 'do not get greedy — take the safe line out',
        );
    }
  }

  // ── Slope adjustments (iOS lines 382-403) ───────────────────────

  static ExecutionPlan adjustForSlope({
    required ExecutionPlan plan,
    required Slope slope,
  }) {
    switch (slope) {
      case Slope.uphill:
        plan.ballPosition =
            _adjustBallPosition(plan.ballPosition, 'slightly more forward');
        plan.weightDistribution =
            'favor lead side more to resist falling back';
        plan.strikeIntention +=
            ' — uphill lie adds loft, so expect higher flight';
      case Slope.downhill:
        plan.ballPosition =
            _adjustBallPosition(plan.ballPosition, 'slightly more back');
        plan.weightDistribution =
            'stay centered, resist falling toward target';
        plan.strikeIntention +=
            ' — downhill lie reduces loft, expect lower flight';
      case Slope.ballAboveFeet:
        plan.alignment =
            'aim slightly right — ball above feet promotes a draw';
        plan.setupSummary += ' Grip down slightly for control.';
      case Slope.ballBelowFeet:
        plan.alignment =
            'aim slightly left — ball below feet promotes a fade';
        plan.setupSummary +=
            ' Flex knees more and stay down through it.';
      case Slope.level:
        break;
    }
    return plan;
  }

  // ── Wind adjustments (iOS lines 405-417) ────────────────────────

  static ExecutionPlan adjustForWind({
    required ExecutionPlan plan,
    required WindStrength wind,
    required WindDirection direction,
  }) {
    if (wind == WindStrength.none) return plan;

    if (direction == WindDirection.into &&
        (wind == WindStrength.moderate || wind == WindStrength.strong)) {
      plan.tempo = 'smooth — do not swing harder into wind';
      plan.mistakeToAvoid =
          'do not swing harder to fight the wind — smooth tempo keeps spin down';
    }
    if (direction == WindDirection.helping) {
      plan.strikeIntention += ' — helping wind will add carry';
    }
    return plan;
  }

  // ── Lie adjustments (iOS lines 419-434) ─────────────────────────

  static ExecutionPlan adjustForLie({
    required ExecutionPlan plan,
    required LieType lie,
    required ExecutionArchetype archetype,
  }) {
    switch (lie) {
      case LieType.hardpan:
        plan.strikeIntention =
            'pick it clean — no room for fat contact on hardpan';
        plan.mistakeToAvoid =
            'do not hit behind the ball on hardpan';
      case LieType.pineStraw:
        plan.setupSummary += " Don't ground the club.";
        plan.mistakeToAvoid =
            'do not ground the club at address — hover it';
      case LieType.firstCut:
        plan.strikeIntention +=
            ' — first cut may grab the hosel slightly';
      // ignore: no_default_cases
      default:
        break;
    }
    return plan;
  }

  // ── Player preference adjustments (iOS lines 438-495) ───────────

  static ExecutionPlan adjustForPlayerPreferences({
    required ExecutionPlan plan,
    required ShotPreferences profile,
    required ExecutionArchetype archetype,
  }) {
    // Bunker confidence
    if (archetype == ExecutionArchetype.bunkerExplosion) {
      switch (profile.bunkerConfidence) {
        case SelfConfidence.low:
          plan.swingThought =
              'commit to the sand — trust the bounce and accelerate through';
          plan.setupSummary +=
              ' Stay confident: open the face and let the club do the work.';
          plan.mistakeToAvoid =
              'do not decelerate through the sand — commit fully';
        case SelfConfidence.high:
          break;
        case SelfConfidence.average:
          break;
      }
    }

    // Wedge confidence (partial wedges and pitches)
    if (archetype == ExecutionArchetype.partialWedge ||
        archetype == ExecutionArchetype.softPitch ||
        archetype == ExecutionArchetype.standardPitch) {
      switch (profile.wedgeConfidence) {
        case SelfConfidence.low:
          plan.swingThought =
              'match your backswing and follow-through — smooth and simple';
          plan.mistakeToAvoid =
              'do not get too cute — pick a comfortable swing length and commit';
        case SelfConfidence.high:
          break;
        case SelfConfidence.average:
          break;
      }
    }

    // Swing tendency
    switch (profile.swingTendency) {
      case SwingTendency.steep:
        if (archetype == ExecutionArchetype.bunkerExplosion) {
          plan.strikeIntention =
              'use your natural steep angle — enter the sand close behind the ball';
          plan.mistakeToAvoid =
              'do not dig too deep — let the bounce glide through';
        }
        if (archetype == ExecutionArchetype.bumpAndRunChip ||
            archetype == ExecutionArchetype.standardChip) {
          plan.strikeIntention +=
              ' — your steep angle helps with clean contact';
        }
      case SwingTendency.shallow:
        if (archetype == ExecutionArchetype.bunkerExplosion) {
          plan.setupSummary +=
              ' Open the face extra to use your shallow path.';
          plan.strikeIntention =
              'splash wide and shallow — use the bounce of the club';
        }
        if (archetype == ExecutionArchetype.stockFullSwing ||
            archetype == ExecutionArchetype.knockdownApproach) {
          plan.strikeIntention += ' — stay down through the ball';
        }
      case SwingTendency.neutral:
        break;
    }

    return plan;
  }

  // ── Helpers (iOS lines 499-501) ─────────────────────────────────

  static String _adjustBallPosition(String current, String direction) {
    return '$current, $direction for the slope';
  }
}
