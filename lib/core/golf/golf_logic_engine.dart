// GolfLogicEngine — KAN-293 (S7.2) Flutter port of
// `ios/CaddieAI/Services/GolfLogicEngine.swift`. Per **ADR 0008**,
// this is the most divergence-heavy of the engines: iOS uses
// proportional wind factors and additive lie penalties, while
// Android uses fixed-yardage tables and multiplicative penalties.
// **The Flutter port follows iOS exclusively** — Android will be
// updated post-cutover to match.
//
// **Pure function from `(context, profile)` to
// `DeterministicAnalysis`.** The engine has no I/O, no logging
// (the iOS native logs a warning on `shotType` / `lieType`
// mismatches; we drop that side effect to keep the engine pure
// — the caller can log if it wants to). Calls into ExecutionEngine
// to populate the `executionPlan` field.
//
// **Iron type penalty:** GI / SGI irons get an additional yardage
// penalty from challenging lies (bunkers, hardpan, rough). The
// math is `multiplier × baseYards` where `multiplier = 1.5` for
// SGI and `1.0` for GI. See `ironTypeLieAdjustment` for the
// per-lie table.

import 'execution_engine.dart';
import 'golf_enums.dart';
import 'shot_context.dart';
import 'target_strategy.dart';

abstract final class GolfLogicEngine {
  GolfLogicEngine._();

  // ── Primary entry point (iOS lines 32-80) ───────────────────────

  static DeterministicAnalysis analyze({
    required ShotContext context,
    required ShotPreferences profile,
  }) {
    final effectiveDistance = calculateEffectiveDistance(
      context: context,
      ironType: profile.ironType,
    );
    final clubLimit =
        maxClubForLie(context.lieType, ironType: profile.ironType);
    final recommendedClub = selectClub(
      effectiveDistance: effectiveDistance,
      clubDistances: profile.clubDistances,
      maxAllowedClub: clubLimit,
    );
    final alternateClub = selectAlternateClub(
      effectiveDistance: effectiveDistance,
      primaryClub: recommendedClub,
      clubDistances: profile.clubDistances,
      maxAllowedClub: clubLimit,
    );
    final strategy = determineTargetStrategy(
      context: context,
      profile: profile,
      recommendedClub: recommendedClub,
    );
    final adjustments = describeAdjustments(
      context: context,
      ironType: profile.ironType,
    );
    final plan = ExecutionEngine.generateExecutionPlan(
      context: context,
      club: recommendedClub,
      effectiveDistance: effectiveDistance,
      profile: profile,
    );

    return DeterministicAnalysis(
      effectiveDistanceYards: effectiveDistance,
      recommendedClub: recommendedClub,
      alternateClub: alternateClub,
      targetStrategy: strategy,
      adjustments: adjustments,
      maxClubForLie: clubLimit,
      executionPlan: plan,
    );
  }

  // ── Effective distance (iOS lines 84-106) ───────────────────────

  static int calculateEffectiveDistance({
    required ShotContext context,
    IronType? ironType,
  }) {
    var distance = context.distanceYards.toDouble();

    distance += windAdjustment(
      strength: context.windStrength,
      direction: context.windDirection,
      baseDistance: context.distanceYards,
    );
    distance += lieAdjustment(context.lieType);
    distance += slopeAdjustment(
      slope: context.slope,
      baseDistance: context.distanceYards,
    );

    if (ironType != null) {
      distance += ironTypeLieAdjustment(
        lieType: context.lieType,
        ironType: ironType,
      );
    }

    final rounded = distance.round();
    return rounded < 1 ? 1 : rounded;
  }

  // ── Wind adjustment (iOS lines 110-131) ─────────────────────────

  /// Returns yards to ADD to the base distance. Positive = play
  /// more club. Negative (helping wind) = play less.
  static double windAdjustment({
    required WindStrength strength,
    required WindDirection direction,
    required int baseDistance,
  }) {
    final double factor;
    switch (strength) {
      case WindStrength.none:
        return 0;
      case WindStrength.light:
        factor = 0.03;
      case WindStrength.moderate:
        factor = 0.07;
      case WindStrength.strong:
        factor = 0.12;
    }

    final adjustment = baseDistance.toDouble() * factor;

    switch (direction) {
      case WindDirection.into:
        return adjustment;
      case WindDirection.helping:
        return -adjustment;
      case WindDirection.crossLeftToRight:
      case WindDirection.crossRightToLeft:
        return adjustment * 0.3;
    }
  }

  // ── Lie adjustment (iOS lines 135-147) ──────────────────────────

  /// Yards to add for the lie. Additive — see ADR 0008.
  static double lieAdjustment(LieType lie) {
    switch (lie) {
      case LieType.fairway:
        return 0;
      case LieType.firstCut:
        return 3;
      case LieType.rough:
        return 7;
      case LieType.deepRough:
        return 15;
      case LieType.greensideBunker:
        return 5;
      case LieType.fairwayBunker:
        return 10;
      case LieType.hardpan:
        return -3;
      case LieType.pineStraw:
        return 5;
      case LieType.treesObstructed:
        return 20;
    }
  }

  // ── Slope adjustment (iOS lines 151-160) ────────────────────────

  static double slopeAdjustment({
    required Slope slope,
    required int baseDistance,
  }) {
    final base = baseDistance.toDouble();
    switch (slope) {
      case Slope.level:
        return 0;
      case Slope.uphill:
        return base * 0.05;
      case Slope.downhill:
        return -(base * 0.05);
      case Slope.ballAboveFeet:
      case Slope.ballBelowFeet:
        return 3;
    }
  }

  // ── GI/SGI iron lie penalty (iOS lines 167-177) ─────────────────

  static double ironTypeLieAdjustment({
    required LieType lieType,
    required IronType ironType,
  }) {
    final multiplier =
        ironType == IronType.superGameImprovement ? 1.5 : 1.0;
    switch (lieType) {
      case LieType.fairwayBunker:
        return 8 * multiplier;
      case LieType.greensideBunker:
        return 5 * multiplier;
      case LieType.hardpan:
        return 5 * multiplier;
      case LieType.rough:
        return 3 * multiplier;
      case LieType.deepRough:
        return 5 * multiplier;
      // ignore: no_default_cases
      default:
        return 0;
    }
  }

  // ── Club selection (iOS lines 181-202) ──────────────────────────
  //
  // **Normal case** (some club covers the distance): the loop walks
  // longest → shortest, overwriting `bestClub` each time it finds
  // a club that still covers, then breaks when it hits one that
  // doesn't. The final value is the SHORTEST club whose carry ≥
  // effective distance — the right answer for golf (you don't
  // crush a 50y shot with a driver).
  //
  // **Edge case** (no club covers, e.g. 300y target with a 245y
  // driver): the loop's first iteration immediately fails the
  // `>=` check and breaks. `bestClub` stays at its default, which
  // mirrors iOS's `sorted.last?.club ?? .pitchingWedge` — the
  // shortest allowed club, or a pitching wedge for an empty bag.
  // The empty-bag wedge fallback is clearly intentional in iOS;
  // the "distance exceeds bag" path is an incidental side effect
  // of that choice rather than an explicit recommendation. Per
  // ADR 0008 we replicate iOS exactly. If product later wants a
  // "longest available club" behavior for unreachable targets,
  // that's a deliberate Flutter-side improvement that needs an
  // ADR amendment AND a matching update on the iOS side to keep
  // the byte-identical contract intact.
  static Club selectClub({
    required int effectiveDistance,
    required Map<Club, int> clubDistances,
    Club? maxAllowedClub,
  }) {
    final entries = clubDistances.entries
        .where((e) => isClubAllowed(e.key, maxAllowedClub))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) return Club.pitchingWedge;

    // Default = shortest allowed club. Mirrors iOS's
    // `sorted.last?.club ?? .pitchingWedge`. See file comment above.
    var bestClub = entries.last.key;
    for (final entry in entries) {
      if (entry.value >= effectiveDistance) {
        bestClub = entry.key;
      } else {
        break;
      }
    }
    return bestClub;
  }

  // ── Alternate club (iOS lines 206-241) ──────────────────────────

  static Club? selectAlternateClub({
    required int effectiveDistance,
    required Club primaryClub,
    required Map<Club, int> clubDistances,
    Club? maxAllowedClub,
  }) {
    final allowed = clubDistances.entries
        .where((e) => isClubAllowed(e.key, maxAllowedClub))
        .toList()
      ..sort((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder));

    final primaryIndex =
        allowed.indexWhere((e) => e.key == primaryClub);
    if (primaryIndex < 0) return null;

    final shorterIndex = primaryIndex + 1;
    final longerIndex = primaryIndex - 1;

    if (shorterIndex < allowed.length) {
      final shorter = allowed[shorterIndex];
      if ((shorter.value - effectiveDistance).abs() <= 10) {
        return shorter.key;
      }
    }

    if (longerIndex >= 0) {
      final longer = allowed[longerIndex];
      if ((longer.value - effectiveDistance).abs() <= 10) {
        return longer.key;
      }
    }

    return null;
  }

  // ── Lie-based max-club restrictions (iOS lines 245-272) ─────────

  static Club? maxClubForLie(LieType lie, {IronType? ironType}) {
    Club? limit;
    switch (lie) {
      case LieType.deepRough:
        limit = Club.iron7;
      case LieType.greensideBunker:
        limit = Club.sandWedge;
      case LieType.fairwayBunker:
        limit = Club.iron6;
      case LieType.treesObstructed:
        limit = Club.iron7;
      case LieType.pineStraw:
        limit = Club.iron5;
      // ignore: no_default_cases
      default:
        limit = null;
    }

    if (ironType != null) {
      switch (lie) {
        case LieType.fairwayBunker:
          limit = ironType == IronType.superGameImprovement
              ? Club.iron8
              : Club.iron7;
        case LieType.hardpan:
          limit = ironType == IronType.superGameImprovement
              ? Club.iron8
              : Club.iron7;
        // ignore: no_default_cases
        default:
          break;
      }
    }
    return limit;
  }

  static bool isClubAllowed(Club club, Club? maxAllowed) {
    if (maxAllowed == null) return true;
    return club.sortOrder >= maxAllowed.sortOrder;
  }

  // ── Target strategy (iOS lines 281-387) ─────────────────────────

  static TargetStrategy determineTargetStrategy({
    required ShotContext context,
    required ShotPreferences profile,
    required Club recommendedClub,
  }) {
    var target = 'Center of green';
    var miss = 'Safe side of the green';
    var reasoning = '';

    // Aggressiveness
    switch (context.aggressiveness) {
      case Aggressiveness.conservative:
        target = 'Center of the green, away from trouble';
        reasoning = 'Conservative approach favors the widest part of the green.';
      case Aggressiveness.normal:
        target = 'Center of the green';
        reasoning = 'Standard approach targeting the middle of the green.';
      case Aggressiveness.aggressive:
        target = 'Pin location';
        reasoning = 'Aggressive play targeting the flag.';
    }

    // Miss tendency
    switch (profile.missTendency) {
      case MissTendency.right:
        miss = 'Favor the left side — your miss tends right';
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'Accounting for right miss tendency.';
      case MissTendency.left:
        miss = 'Favor the right side — your miss tends left';
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'Accounting for left miss tendency.';
      case MissTendency.thin:
        miss = 'Club up to account for thin contact tendency';
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'Thin misses lose distance.';
      case MissTendency.fat:
        miss = 'Club up to account for heavy contact tendency';
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'Heavy contact loses distance.';
      case MissTendency.straight:
        miss = 'No major miss adjustment needed';
    }

    // Slope-induced shape changes
    final clubShape = profile.stockShapeFor(recommendedClub);
    switch (context.slope) {
      case Slope.ballBelowFeet:
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'Ball below feet promotes a fade.';
        if (clubShape == StockShape.fade) {
          miss = 'Favor the left side — stance will exaggerate your fade';
        }
      case Slope.ballAboveFeet:
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'Ball above feet promotes a draw.';
        if (clubShape == StockShape.draw) {
          miss = 'Favor the right side — stance will exaggerate your draw';
        }
      // ignore: no_default_cases
      default:
        break;
    }

    // Crosswind
    switch (context.windDirection) {
      case WindDirection.crossLeftToRight:
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'Crosswind L→R will push the ball right.';
        target += ', aiming slightly left to allow for wind';
      case WindDirection.crossRightToLeft:
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'Crosswind R→L will push the ball left.';
        target += ', aiming slightly right to allow for wind';
      // ignore: no_default_cases
      default:
        break;
    }

    // Hazard notes
    final hazardNotes = context.hazardNotes.trim();
    if (hazardNotes.isNotEmpty) {
      final lower = hazardNotes.toLowerCase();
      if (lower.contains('water left') || lower.contains('hazard left')) {
        miss = 'Miss right — water left';
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'Water left makes right the safe miss.';
      } else if (lower.contains('water right') ||
          lower.contains('hazard right')) {
        miss = 'Miss left — water right';
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'Water right makes left the safe miss.';
      }
      if (lower.contains('bunker short')) {
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'Bunker short of green — make sure to take enough club.';
      }
      if (lower.contains('ob') || lower.contains('out of bounds')) {
        if (reasoning.isNotEmpty) reasoning += ' ';
        reasoning += 'OB in play — favor the safe side.';
      }
    }

    return TargetStrategy(
      target: target,
      preferredMiss: miss,
      reasoning: reasoning,
    );
  }

  // ── Describe adjustments (iOS lines 391-428) ────────────────────

  static List<String> describeAdjustments({
    required ShotContext context,
    IronType? ironType,
  }) {
    final out = <String>[];

    final wind = windAdjustment(
      strength: context.windStrength,
      direction: context.windDirection,
      baseDistance: context.distanceYards,
    );
    if (wind.abs() > 0.5) {
      final sign = wind > 0 ? '+' : '';
      out.add(
        'Wind (${_displayName(context.windStrength)} ${_displayName(context.windDirection)}): $sign${wind.round()} yards',
      );
    }

    final lie = lieAdjustment(context.lieType);
    if (lie.abs() > 0.5) {
      final sign = lie > 0 ? '+' : '';
      out.add(
        'Lie (${_displayName(context.lieType)}): $sign${lie.round()} yards',
      );
    }

    final slope = slopeAdjustment(
      slope: context.slope,
      baseDistance: context.distanceYards,
    );
    if (slope.abs() > 0.5) {
      final sign = slope > 0 ? '+' : '';
      out.add(
        'Slope (${_displayName(context.slope)}): $sign${slope.round()} yards',
      );
    }

    if (ironType != null) {
      final gi = ironTypeLieAdjustment(
        lieType: context.lieType,
        ironType: ironType,
      );
      if (gi.abs() > 0.5) {
        final shortName =
            ironType == IronType.superGameImprovement ? 'SGI' : 'GI';
        out.add(
          '$shortName iron penalty (${_displayName(context.lieType)}): +${gi.round()} yards',
        );
      }
    }

    if (out.isEmpty) {
      out.add('No adjustments — clean conditions');
    }
    return out;
  }

  // ── Display-name helpers ────────────────────────────────────────
  //
  // The iOS engine pulls `displayName` off each enum. We don't want
  // to bloat `golf_enums.dart` with display strings (those belong
  // in a UI layer), so we keep a small switch here for the
  // describeAdjustments output.

  static String _displayName(Object value) {
    if (value is WindStrength) {
      switch (value) {
        case WindStrength.none:
          return 'None';
        case WindStrength.light:
          return 'Light';
        case WindStrength.moderate:
          return 'Moderate';
        case WindStrength.strong:
          return 'Strong';
      }
    }
    if (value is WindDirection) {
      switch (value) {
        case WindDirection.into:
          return 'Into';
        case WindDirection.helping:
          return 'Helping';
        case WindDirection.crossLeftToRight:
          return 'Cross L→R';
        case WindDirection.crossRightToLeft:
          return 'Cross R→L';
      }
    }
    if (value is LieType) {
      switch (value) {
        case LieType.fairway:
          return 'Fairway';
        case LieType.firstCut:
          return 'First Cut';
        case LieType.rough:
          return 'Rough';
        case LieType.deepRough:
          return 'Deep Rough';
        case LieType.greensideBunker:
          return 'Greenside Bunker';
        case LieType.fairwayBunker:
          return 'Fairway Bunker';
        case LieType.hardpan:
          return 'Hardpan';
        case LieType.pineStraw:
          return 'Pine Straw';
        case LieType.treesObstructed:
          return 'Trees / Obstructed';
      }
    }
    if (value is Slope) {
      switch (value) {
        case Slope.level:
          return 'Level';
        case Slope.uphill:
          return 'Uphill';
        case Slope.downhill:
          return 'Downhill';
        case Slope.ballAboveFeet:
          return 'Ball Above Feet';
        case Slope.ballBelowFeet:
          return 'Ball Below Feet';
      }
    }
    return value.toString();
  }
}
