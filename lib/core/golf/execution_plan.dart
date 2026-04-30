// ExecutionPlan — output shape of the AI caddie's deterministic
// shot setup recommendation. Direct port of `ExecutionPlan.swift`.
//
// **Field shape is non-negotiable.** Per ADR 0008, the iOS native
// is the authoritative source for the engine port, and the iOS
// `ExecutionPlan` struct has these 13 string fields with these
// exact names. The caddie screen UI will bind cards to each field
// individually (e.g. a `setupSummary` row, a `swingThought` row,
// a `mistakeToAvoid` row), so renaming or merging fields would
// break the UI binding.
//
// **Why a class with mutable copies instead of `freezed`:** the
// engine applies adjustments by mutating fields one at a time
// (e.g. `plan.tempo = "smooth — do not swing harder into wind"`).
// In Swift this is just a `var plan = template; plan.tempo = ...`
// pattern. We mirror that with a `copyWith` method on each
// adjustment, but the engine itself uses local mutable instances
// to keep the math readable.

import 'golf_enums.dart';

class ExecutionPlan {
  ExecutionPlan({
    required this.archetype,
    required this.setupSummary,
    required this.ballPosition,
    required this.weightDistribution,
    required this.stanceWidth,
    required this.alignment,
    required this.clubface,
    required this.shaftLean,
    required this.backswingLength,
    required this.followThrough,
    required this.tempo,
    required this.strikeIntention,
    required this.swingThought,
    required this.mistakeToAvoid,
  });

  final ExecutionArchetype archetype;

  String setupSummary;
  String ballPosition;
  String weightDistribution;
  String stanceWidth;
  String alignment;
  String clubface;
  String shaftLean;
  String backswingLength;
  String followThrough;
  String tempo;
  String strikeIntention;
  String swingThought;
  String mistakeToAvoid;

  /// Used by tests for stable equality assertions. Two plans are
  /// equal if every field matches. The archetype is part of the
  /// equality check because two adjusted plans from different
  /// archetypes might end up with the same string fields by
  /// coincidence and we want to catch that as a bug.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExecutionPlan &&
        archetype == other.archetype &&
        setupSummary == other.setupSummary &&
        ballPosition == other.ballPosition &&
        weightDistribution == other.weightDistribution &&
        stanceWidth == other.stanceWidth &&
        alignment == other.alignment &&
        clubface == other.clubface &&
        shaftLean == other.shaftLean &&
        backswingLength == other.backswingLength &&
        followThrough == other.followThrough &&
        tempo == other.tempo &&
        strikeIntention == other.strikeIntention &&
        swingThought == other.swingThought &&
        mistakeToAvoid == other.mistakeToAvoid;
  }

  @override
  int get hashCode => Object.hash(
        archetype,
        setupSummary,
        ballPosition,
        weightDistribution,
        stanceWidth,
        alignment,
        clubface,
        shaftLean,
        backswingLength,
        followThrough,
        tempo,
        strikeIntention,
        swingThought,
        mistakeToAvoid,
      );

  Map<String, dynamic> toJson() => {
        'archetype': archetype.name,
        'setupSummary': setupSummary,
        'ballPosition': ballPosition,
        'weightDistribution': weightDistribution,
        'stanceWidth': stanceWidth,
        'alignment': alignment,
        'clubface': clubface,
        'shaftLean': shaftLean,
        'backswingLength': backswingLength,
        'followThrough': followThrough,
        'tempo': tempo,
        'strikeIntention': strikeIntention,
        'swingThought': swingThought,
        'mistakeToAvoid': mistakeToAvoid,
      };
}
