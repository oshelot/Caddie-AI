// ShotHistoryEntry — append-only log of every AI shot recommendation
// the player has seen (and optionally how it played out). Replaces:
//
//   - iOS:     `ShotRecord` in `ios/CaddieAI/Models/ShotHistory.swift`
//              (persisted via UserDefaults key `shotHistory` as a
//              JSON-encoded `[ShotRecord]`)
//   - Android: `ShotHistoryEntry` in
//              `android/app/src/main/java/com/caddieai/android/data/model/ShotHistoryEntry.kt`
//              (persisted via DataStore Preferences key
//              `shot_history_v1` as a JSON-encoded list)
//
// **Storage strategy:** per ADR 0003, shot history is loaded into
// memory in full at app start and queried/filtered with Dart
// collection ops. We do NOT use SQL — the working set is bounded
// (a few hundred entries even for active players) and there's no
// query that needs an index. The Hive box stores one entry per key,
// where the key is the entry id (a UUID v4 string). On read, the
// repository iterates the box and returns a `List<ShotHistoryEntry>`
// sorted descending by timestamp.
//
// **Field shape:** the iOS native `ShotRecord` and Android native
// `ShotHistoryEntry` have *different* shapes (iOS uses a Swift `Date`,
// Android uses `timestampMs: Long`; iOS nests `ShotContext` while
// Android nests both `ShotContext` and `ShotRecommendation`). The
// Flutter representation is the union — every field that exists in
// either native model. The migration importer normalizes timestamps
// to epoch milliseconds and fills missing nested fields with nulls.
//
// **Why a flat ShotContext sub-record instead of a freezed union:**
// the ShotContext fields are all primitives (string enums + ints).
// There's no discriminated union here — every shot has the same
// context shape, just with different values. A nested class with
// hand-written toJson/fromJson is the right tool.

import 'package:flutter/foundation.dart';

@immutable
class ShotHistoryEntry {
  /// UUID v4 string. Generated on the device when the entry is first
  /// created. Used as the Hive box key (so writes are idempotent on
  /// id collision — re-saving an entry overwrites in place).
  final String id;

  /// Epoch milliseconds. iOS-migrated entries get the Date converted
  /// to ms; Android-migrated entries pass through.
  final int timestampMs;

  final String? courseId;
  final String courseName;

  final ShotContext context;

  /// String name of the recommended club (e.g. "7-iron"). Hand-written
  /// strings on both natives — no enum.
  final String recommendedClub;

  /// String name of the club the player actually used. Null = the
  /// player accepted the recommendation. Empty string from older
  /// blobs is normalized to null on import.
  final String? actualClubUsed;

  /// Effective distance to target in yards (after wind/slope
  /// adjustments). iOS field; Android-migrated entries default to 0.
  final int effectiveDistance;

  /// Free-text target description ("front of green", "left side
  /// fairway"). iOS field.
  final String target;

  /// String enum: great | good | okay | poor | mishit | unknown.
  /// Stored as string so future values don't break old data.
  final String outcome;

  /// Free-text notes from the player.
  final String notes;

  const ShotHistoryEntry({
    required this.id,
    required this.timestampMs,
    this.courseId,
    this.courseName = '',
    required this.context,
    this.recommendedClub = '',
    this.actualClubUsed,
    this.effectiveDistance = 0,
    this.target = '',
    this.outcome = 'unknown',
    this.notes = '',
  });

  ShotHistoryEntry copyWith({
    String? id,
    int? timestampMs,
    String? courseId,
    String? courseName,
    ShotContext? context,
    String? recommendedClub,
    String? actualClubUsed,
    int? effectiveDistance,
    String? target,
    String? outcome,
    String? notes,
  }) {
    return ShotHistoryEntry(
      id: id ?? this.id,
      timestampMs: timestampMs ?? this.timestampMs,
      courseId: courseId ?? this.courseId,
      courseName: courseName ?? this.courseName,
      context: context ?? this.context,
      recommendedClub: recommendedClub ?? this.recommendedClub,
      actualClubUsed: actualClubUsed ?? this.actualClubUsed,
      effectiveDistance: effectiveDistance ?? this.effectiveDistance,
      target: target ?? this.target,
      outcome: outcome ?? this.outcome,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestampMs': timestampMs,
        'courseId': courseId,
        'courseName': courseName,
        'context': context.toJson(),
        'recommendedClub': recommendedClub,
        'actualClubUsed': actualClubUsed,
        'effectiveDistance': effectiveDistance,
        'target': target,
        'outcome': outcome,
        'notes': notes,
      };

  factory ShotHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ShotHistoryEntry(
      id: json['id'] as String,
      timestampMs: (json['timestampMs'] as num).toInt(),
      courseId: json['courseId'] as String?,
      courseName: json['courseName'] as String? ?? '',
      context: ShotContext.fromJson(
        (json['context'] as Map).cast<String, dynamic>(),
      ),
      recommendedClub: json['recommendedClub'] as String? ?? '',
      actualClubUsed: json['actualClubUsed'] as String?,
      effectiveDistance: (json['effectiveDistance'] as num?)?.toInt() ?? 0,
      target: json['target'] as String? ?? '',
      outcome: json['outcome'] as String? ?? 'unknown',
      notes: json['notes'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShotHistoryEntry &&
        id == other.id &&
        timestampMs == other.timestampMs &&
        courseId == other.courseId &&
        courseName == other.courseName &&
        context == other.context &&
        recommendedClub == other.recommendedClub &&
        actualClubUsed == other.actualClubUsed &&
        effectiveDistance == other.effectiveDistance &&
        target == other.target &&
        outcome == other.outcome &&
        notes == other.notes;
  }

  @override
  int get hashCode => Object.hash(
        id,
        timestampMs,
        courseId,
        courseName,
        context,
        recommendedClub,
        actualClubUsed,
        effectiveDistance,
        target,
        outcome,
        notes,
      );
}

/// Snapshot of the shot setup at the moment the AI made its
/// recommendation. All enum-shaped fields are stored as strings to
/// keep the storage layer untyped — feature code can map to typed
/// enums when it needs to.
@immutable
class ShotContext {
  final int distanceYards;
  final String shotType;
  final String lieType;
  final String windStrength;
  final String windDirection;
  final String slope;
  final String aggressiveness;
  final String hazardNotes;

  const ShotContext({
    this.distanceYards = 150,
    this.shotType = 'approach',
    this.lieType = 'fairway',
    this.windStrength = 'none',
    this.windDirection = 'into',
    this.slope = 'level',
    this.aggressiveness = 'normal',
    this.hazardNotes = '',
  });

  Map<String, dynamic> toJson() => {
        'distanceYards': distanceYards,
        'shotType': shotType,
        'lieType': lieType,
        'windStrength': windStrength,
        'windDirection': windDirection,
        'slope': slope,
        'aggressiveness': aggressiveness,
        'hazardNotes': hazardNotes,
      };

  factory ShotContext.fromJson(Map<String, dynamic> json) {
    return ShotContext(
      distanceYards: (json['distanceYards'] as num?)?.toInt() ?? 150,
      shotType: json['shotType'] as String? ?? 'approach',
      lieType: json['lieType'] as String? ?? 'fairway',
      windStrength: json['windStrength'] as String? ?? 'none',
      windDirection: json['windDirection'] as String? ?? 'into',
      slope: json['slope'] as String? ?? 'level',
      aggressiveness: json['aggressiveness'] as String? ?? 'normal',
      hazardNotes: json['hazardNotes'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShotContext &&
        distanceYards == other.distanceYards &&
        shotType == other.shotType &&
        lieType == other.lieType &&
        windStrength == other.windStrength &&
        windDirection == other.windDirection &&
        slope == other.slope &&
        aggressiveness == other.aggressiveness &&
        hazardNotes == other.hazardNotes;
  }

  @override
  int get hashCode => Object.hash(
        distanceYards,
        shotType,
        lieType,
        windStrength,
        windDirection,
        slope,
        aggressiveness,
        hazardNotes,
      );
}
