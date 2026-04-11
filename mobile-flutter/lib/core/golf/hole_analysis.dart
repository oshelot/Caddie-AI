// HoleAnalysis output types — KAN-293 (S7.2). Direct port of the
// supporting structs in `ios/CaddieAI/Services/HoleAnalysisEngine.swift`.
//
// `HoleAnalysis` is the deterministic geometric analysis of a
// single hole: total length, dogleg info (if any), fairway width,
// green dimensions, classified hazards, and a short text summary
// the LLM router (KAN-294) consumes as prompt context.

enum DoglegDirection { left, right }

enum HazardType { bunker, water }

enum HazardSide { left, right, frontOfGreen, greenside, crossing }

class DoglegInfo {
  const DoglegInfo({
    required this.direction,
    required this.distanceFromTeeYards,
    required this.bendAngleDegrees,
  });

  final DoglegDirection direction;
  final int distanceFromTeeYards;
  final double bendAngleDegrees;
}

class GreenDimensions {
  const GreenDimensions({required this.depth, required this.width});

  /// Yards front-to-back along the approach axis.
  final int depth;

  /// Yards perpendicular to the approach axis.
  final int width;
}

class HoleHazardInfo {
  const HoleHazardInfo({
    required this.type,
    required this.side,
    required this.distanceFromTeeYards,
    required this.description,
  });

  final HazardType type;
  final HazardSide side;
  final int? distanceFromTeeYards;
  final String description;
}

class HoleAnalysis {
  const HoleAnalysis({
    required this.holeNumber,
    required this.par,
    required this.totalDistanceYards,
    required this.dogleg,
    required this.fairwayWidthAtLandingYards,
    required this.greenDepthYards,
    required this.greenWidthYards,
    required this.hazards,
    required this.deterministicSummary,
  });

  final int holeNumber;
  final int? par;
  final int? totalDistanceYards;
  final DoglegInfo? dogleg;
  final int? fairwayWidthAtLandingYards;
  final int? greenDepthYards;
  final int? greenWidthYards;
  final List<HoleHazardInfo> hazards;

  /// Short, plain-text summary the LLM router uses as additional
  /// context. Built by `HoleAnalysisEngine._buildSummary`.
  final String deterministicSummary;
}
