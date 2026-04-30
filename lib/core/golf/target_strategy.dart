// Output types for GolfLogicEngine — a `TargetStrategy` (where to
// aim, where to miss, why) and a `DeterministicAnalysis` (the full
// pre-LLM recommendation that gets handed to the LLM router as
// context, or rendered directly when the LLM is offline).
//
// Direct port of the Swift structs at the top of
// `ios/CaddieAI/Services/GolfLogicEngine.swift`.

import 'execution_plan.dart';
import 'golf_enums.dart';

class TargetStrategy {
  const TargetStrategy({
    required this.target,
    required this.preferredMiss,
    required this.reasoning,
  });

  final String target;
  final String preferredMiss;
  final String reasoning;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TargetStrategy &&
          target == other.target &&
          preferredMiss == other.preferredMiss &&
          reasoning == other.reasoning);

  @override
  int get hashCode => Object.hash(target, preferredMiss, reasoning);
}

class DeterministicAnalysis {
  const DeterministicAnalysis({
    required this.effectiveDistanceYards,
    required this.recommendedClub,
    required this.alternateClub,
    required this.targetStrategy,
    required this.adjustments,
    required this.maxClubForLie,
    required this.executionPlan,
  });

  final int effectiveDistanceYards;
  final Club recommendedClub;
  final Club? alternateClub;
  final TargetStrategy targetStrategy;
  final List<String> adjustments;
  final Club? maxClubForLie;
  final ExecutionPlan executionPlan;
}
