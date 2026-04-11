// ShotContext — typed input shape for the AI caddie engines
// (KAN-292/293/295). Direct port of `ShotContext.swift`.
//
// **Not the same as the persistence layer's `ShotContext`** in
// `lib/models/shot_history_entry.dart`. The persistence layer
// stores everything as untyped strings (so older shot history
// blobs decode without breaking on enum casing changes); this
// engine layer uses typed enums so the engines can branch on
// them without parsing strings on every call. The KAN-S11 caddie
// screen will need a small bridge function to convert between
// the two when persisting an engine result to history — that
// bridge lives outside this directory and is not in S7.1 scope.

import 'golf_enums.dart';

class ShotContext {
  const ShotContext({
    this.distanceYards = 150,
    this.shotType = ShotType.approach,
    this.lieType = LieType.fairway,
    this.windStrength = WindStrength.none,
    this.windDirection = WindDirection.into,
    this.slope = Slope.level,
    this.aggressiveness = Aggressiveness.normal,
    this.hazardNotes = '',
  });

  final int distanceYards;
  final ShotType shotType;
  final LieType lieType;
  final WindStrength windStrength;
  final WindDirection windDirection;
  final Slope slope;
  final Aggressiveness aggressiveness;
  final String hazardNotes;

  ShotContext copyWith({
    int? distanceYards,
    ShotType? shotType,
    LieType? lieType,
    WindStrength? windStrength,
    WindDirection? windDirection,
    Slope? slope,
    Aggressiveness? aggressiveness,
    String? hazardNotes,
  }) {
    return ShotContext(
      distanceYards: distanceYards ?? this.distanceYards,
      shotType: shotType ?? this.shotType,
      lieType: lieType ?? this.lieType,
      windStrength: windStrength ?? this.windStrength,
      windDirection: windDirection ?? this.windDirection,
      slope: slope ?? this.slope,
      aggressiveness: aggressiveness ?? this.aggressiveness,
      hazardNotes: hazardNotes ?? this.hazardNotes,
    );
  }
}

/// Subset of `PlayerProfile` (from `lib/models/player_profile.dart`)
/// that the engines actually consume. Defined as a separate type so
/// the engines don't drag the entire 38-field PlayerProfile into
/// every call signature, and so engine tests can construct minimal
/// fixtures without populating fields that don't affect the math.
///
/// **Why a separate type instead of taking PlayerProfile directly:**
/// PlayerProfile lives in `lib/models/` (the persistence layer)
/// and uses untyped string values for the enum-shaped fields. The
/// engines need typed enums. A bridge function in S7.1 would have
/// to parse the strings on every call — instead, we accept the
/// already-typed `ShotPreferences` and let the bridge happen once
/// at the call site (in KAN-S11).
class ShotPreferences {
  const ShotPreferences({
    this.handicap = 18.0,
    this.preferredChipStyle = ChipStyle.noPreference,
    this.bunkerConfidence = SelfConfidence.average,
    this.wedgeConfidence = SelfConfidence.average,
    this.swingTendency = SwingTendency.neutral,
    this.stockShape = StockShape.straight,
    this.woodsStockShape = StockShape.straight,
    this.ironsStockShape = StockShape.straight,
    this.hybridsStockShape = StockShape.straight,
    this.missTendency = MissTendency.straight,
    this.defaultAggressiveness = Aggressiveness.normal,
    this.ironType,
    this.clubDistances = const {},
  });

  final double handicap;
  final ChipStyle preferredChipStyle;
  final SelfConfidence bunkerConfidence;
  final SelfConfidence wedgeConfidence;
  final SwingTendency swingTendency;
  final StockShape stockShape;
  final StockShape woodsStockShape;
  final StockShape ironsStockShape;
  final StockShape hybridsStockShape;
  final MissTendency missTendency;
  final Aggressiveness defaultAggressiveness;
  final IronType? ironType;

  /// Per-club carry distances. Falls back to `Club.defaultCarryYards`
  /// when a club isn't in the map.
  final Map<Club, int> clubDistances;

  /// Returns the carry distance the player has configured for this
  /// club, or the default for the club if no per-player override
  /// is set. Used by GolfLogicEngine when picking a club for a
  /// given effective distance.
  int carryYardsFor(Club club) =>
      clubDistances[club] ?? club.defaultCarryYards;

  /// Stock shape for this club's category. Mirrors the iOS
  /// `PlayerProfile.stockShapeForClub(_:)` helper.
  StockShape stockShapeFor(Club club) {
    switch (club.category) {
      case ClubCategory.woods:
        return woodsStockShape;
      case ClubCategory.hybrids:
        return hybridsStockShape;
      case ClubCategory.irons:
        return ironsStockShape;
    }
  }
}
