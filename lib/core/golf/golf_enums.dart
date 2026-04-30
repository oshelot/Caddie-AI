// Golf domain enums shared by the AI caddie engines (KAN-292/293/295).
//
// **Source of truth:** `ios/CaddieAI/Models/GolfEnums.swift` per
// **ADR 0008** (iOS-as-authoritative). Wire values match the Swift
// `rawValue` casing exactly so the Profile screen (KAN-S13), the
// caddie screen (KAN-S11), and the persistence layer in
// `lib/models/shot_history_entry.dart` can round-trip strings
// without translation.
//
// **Scope:** only the enums used by the engines I'm porting in S7.
// The full iOS file has ~30 enums; many of those (LLM provider,
// caddie persona, voice gender/accent) are owned by other layers
// and don't need to live in `lib/core/golf/`. Add them here only
// when an engine in this directory needs them.

/// Club identifier. The full iOS bag (~30 clubs) is ported because
/// `Club.defaultCarryYards` is the fallback distance map when the
/// player profile doesn't have a custom carry distance for a club,
/// and `Club.category` drives the woods/irons/hybrids stock-shape
/// branching in `ExecutionEngine.adjustForPlayerPreferences`.
enum Club {
  driver,
  twoWood,
  threeWood,
  fourWood,
  fiveWood,
  sevenWood,
  nineWood,
  hybrid2,
  hybrid3,
  hybrid4,
  hybrid5,
  hybrid6,
  iron2,
  iron3,
  iron4,
  iron5,
  iron6,
  iron7,
  iron8,
  iron9,
  pitchingWedge,
  wedge46,
  wedge48,
  wedge50,
  gapWedge,
  wedge54,
  sandWedge,
  wedge58,
  lobWedge,
  wedge64,
  putter;

  /// Wire string — matches the iOS Swift `rawValue` casing exactly.
  String get wireName => name;

  /// Human-readable name for UI display.
  String get displayName {
    switch (this) {
      case Club.driver: return 'Driver';
      case Club.twoWood: return '2-Wood';
      case Club.threeWood: return '3-Wood';
      case Club.fourWood: return '4-Wood';
      case Club.fiveWood: return '5-Wood';
      case Club.sevenWood: return '7-Wood';
      case Club.nineWood: return '9-Wood';
      case Club.hybrid2: return '2-Hybrid';
      case Club.hybrid3: return '3-Hybrid';
      case Club.hybrid4: return '4-Hybrid';
      case Club.hybrid5: return '5-Hybrid';
      case Club.hybrid6: return '6-Hybrid';
      case Club.iron2: return '2-Iron';
      case Club.iron3: return '3-Iron';
      case Club.iron4: return '4-Iron';
      case Club.iron5: return '5-Iron';
      case Club.iron6: return '6-Iron';
      case Club.iron7: return '7-Iron';
      case Club.iron8: return '8-Iron';
      case Club.iron9: return '9-Iron';
      case Club.pitchingWedge: return 'PW';
      case Club.wedge46: return '46°';
      case Club.wedge48: return '48°';
      case Club.wedge50: return '50°';
      case Club.gapWedge: return 'GW';
      case Club.wedge54: return '54°';
      case Club.sandWedge: return 'SW';
      case Club.wedge58: return '58°';
      case Club.lobWedge: return 'LW';
      case Club.wedge64: return '64°';
      case Club.putter: return 'Putter';
    }
  }

  /// Lifted from iOS `Club.defaultCarryYards` for the same enum
  /// case. Used by GolfLogicEngine when the player profile is
  /// missing a custom carry distance for this club.
  int get defaultCarryYards {
    switch (this) {
      case Club.driver:
        return 235;
      case Club.twoWood:
        return 228;
      case Club.threeWood:
        return 220;
      case Club.fourWood:
        return 212;
      case Club.fiveWood:
        return 205;
      case Club.sevenWood:
        return 195;
      case Club.nineWood:
        return 185;
      case Club.hybrid2:
        return 210;
      case Club.hybrid3:
        return 200;
      case Club.hybrid4:
        return 195;
      case Club.hybrid5:
        return 185;
      case Club.hybrid6:
        return 175;
      case Club.iron2:
        return 205;
      case Club.iron3:
        return 195;
      case Club.iron4:
        return 190;
      case Club.iron5:
        return 185;
      case Club.iron6:
        return 175;
      case Club.iron7:
        return 165;
      case Club.iron8:
        return 155;
      case Club.iron9:
        return 143;
      case Club.pitchingWedge:
        return 132;
      case Club.wedge46:
        return 125;
      case Club.wedge48:
        return 120;
      case Club.wedge50:
        return 115;
      case Club.gapWedge:
        return 110;
      case Club.wedge54:
        return 102;
      case Club.sandWedge:
        return 96;
      case Club.wedge58:
        return 85;
      case Club.lobWedge:
        return 78;
      case Club.wedge64:
        return 65;
      case Club.putter:
        return 0;
    }
  }

  /// Sort order — lower index = longer club. Used for "next club
  /// up / down" lookups in the alternate-club selection in
  /// GolfLogicEngine.
  int get sortOrder => Club.values.indexOf(this);

  ClubCategory get category {
    switch (this) {
      case Club.driver:
      case Club.twoWood:
      case Club.threeWood:
      case Club.fourWood:
      case Club.fiveWood:
      case Club.sevenWood:
      case Club.nineWood:
        return ClubCategory.woods;
      case Club.hybrid2:
      case Club.hybrid3:
      case Club.hybrid4:
      case Club.hybrid5:
      case Club.hybrid6:
        return ClubCategory.hybrids;
      default:
        return ClubCategory.irons;
    }
  }
}

enum ClubCategory { woods, hybrids, irons }

/// What kind of shot the player is hitting. Drives archetype
/// selection in ExecutionEngine and validates lie-type pickers in
/// the UI (the latter not in scope for S7.1).
enum ShotType {
  tee,
  approach,
  chip,
  pitch,
  bunker,
  punchRecovery,
  layup;

  String get displayName {
    switch (this) {
      case ShotType.tee: return 'Tee Shot';
      case ShotType.approach: return 'Approach';
      case ShotType.chip: return 'Chip';
      case ShotType.pitch: return 'Pitch';
      case ShotType.bunker: return 'Bunker';
      case ShotType.punchRecovery: return 'Punch / Recovery';
      case ShotType.layup: return 'Layup';
    }
  }
}

enum LieType {
  fairway,
  firstCut,
  rough,
  deepRough,
  greensideBunker,
  fairwayBunker,
  hardpan,
  pineStraw,
  treesObstructed;

  String get wireName => name;

  String get displayName {
    switch (this) {
      case LieType.fairway: return 'Fairway';
      case LieType.firstCut: return 'First Cut';
      case LieType.rough: return 'Rough';
      case LieType.deepRough: return 'Deep Rough';
      case LieType.greensideBunker: return 'Greenside Bunker';
      case LieType.fairwayBunker: return 'Fairway Bunker';
      case LieType.hardpan: return 'Hardpan';
      case LieType.pineStraw: return 'Pine Straw';
      case LieType.treesObstructed: return 'Trees / Obstructed';
    }
  }
}

enum WindStrength {
  none,
  light,
  moderate,
  strong;

  String get displayName {
    switch (this) {
      case WindStrength.none: return 'None';
      case WindStrength.light: return 'Light';
      case WindStrength.moderate: return 'Moderate';
      case WindStrength.strong: return 'Strong';
    }
  }
}

enum WindDirection {
  /// Wind blowing INTO the player (head-on).
  into,

  /// Wind blowing WITH the player (tail).
  helping,

  /// Cross wind from the player's left, pushing ball right.
  crossLeftToRight,

  /// Cross wind from the player's right, pushing ball left.
  crossRightToLeft;

  String get displayName {
    switch (this) {
      case WindDirection.into: return 'Into';
      case WindDirection.helping: return 'Helping';
      case WindDirection.crossLeftToRight: return 'Cross Left-to-Right';
      case WindDirection.crossRightToLeft: return 'Cross Right-to-Left';
    }
  }
}

enum Slope {
  level,
  uphill,
  downhill,
  ballAboveFeet,
  ballBelowFeet;

  String get displayName {
    switch (this) {
      case Slope.level: return 'Level';
      case Slope.uphill: return 'Uphill';
      case Slope.downhill: return 'Downhill';
      case Slope.ballAboveFeet: return 'Ball Above Feet';
      case Slope.ballBelowFeet: return 'Ball Below Feet';
    }
  }
}

enum Aggressiveness { conservative, normal, aggressive }

enum StockShape { straight, fade, draw }

enum MissTendency { straight, left, right, thin, fat }

enum ChipStyle { bumpAndRun, lofted, noPreference }

enum SwingTendency { steep, shallow, neutral }

enum SelfConfidence { low, average, high }

enum IronType { gameImprovement, superGameImprovement }

/// All 15 archetype templates the iOS ExecutionEngine ships. Each
/// case has a corresponding entry in
/// `ExecutionEngine._template(for:)` — adding a new case here
/// without adding the matching template will trip the analyzer
/// (the switch is exhaustive).
enum ExecutionArchetype {
  bumpAndRunChip,
  standardChip,
  softPitch,
  standardPitch,
  partialWedge,
  bunkerExplosion,
  fairwayBunkerShot,
  stockFullSwing,
  knockdownApproach,
  punchShot,
  layupSwing,
  teeDriver,
  teeFairwayWood,
  recoveryFromRough,
  recoveryUnderTrees,
}
