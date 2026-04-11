// ScorecardEntry — round-by-round score persistence. Replaces:
//
//   - iOS:     `Scorecard` in `ios/CaddieAI/Models/Scorecard.swift`
//              (persisted as one JSON file per scorecard under
//              `Documents/scorecards/<uuid>.json`)
//   - Android: `Scorecard` in
//              `android/app/src/main/java/com/caddieai/android/data/model/Scorecard.kt`
//              (persisted via DataStore Preferences key
//              `scorecards_v1` as a JSON-encoded list)
//
// **Per ADR 0004**, scorecards land in a Hive box keyed by id. The
// per-scorecard file layout from iOS is collapsed into one box on
// the Flutter side — there's no good reason to keep N files when
// Hive's box-of-strings is just as fast.
//
// **Status enum:** stored as a string ("inProgress" or "completed")
// to match the iOS Codable raw value. Older blobs that omit the
// field default to "inProgress".

import 'package:flutter/foundation.dart';

@immutable
class ScorecardEntry {
  /// UUID v4 string. Used as the Hive box key.
  final String id;

  final String courseId;
  final String courseName;

  /// Epoch milliseconds when the round was started. iOS-migrated
  /// scorecards convert their `Date` field; Android-migrated ones
  /// pass through their `dateMs`.
  final int dateMs;

  /// Phone or email from the player profile at the time the round
  /// was started — used to attribute the round to a player when the
  /// profile changes later.
  final String playerIdentity;

  /// Tee name played (e.g. "white", "blue"). Null = unspecified.
  final String? teePlayed;

  /// Per-hole scores. Empty = round started but no holes scored yet.
  final List<HoleScore> holeScores;

  /// "inProgress" or "completed". String to match iOS Codable shape.
  final String status;

  const ScorecardEntry({
    required this.id,
    required this.courseId,
    this.courseName = '',
    required this.dateMs,
    this.playerIdentity = '',
    this.teePlayed,
    this.holeScores = const [],
    this.status = 'inProgress',
  });

  int get totalScore =>
      holeScores.fold(0, (sum, h) => sum + h.score);

  int get totalPar => holeScores.fold(0, (sum, h) => sum + h.par);

  int get relativeToPar => totalScore - totalPar;

  ScorecardEntry copyWith({
    String? id,
    String? courseId,
    String? courseName,
    int? dateMs,
    String? playerIdentity,
    String? teePlayed,
    List<HoleScore>? holeScores,
    String? status,
  }) {
    return ScorecardEntry(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      courseName: courseName ?? this.courseName,
      dateMs: dateMs ?? this.dateMs,
      playerIdentity: playerIdentity ?? this.playerIdentity,
      teePlayed: teePlayed ?? this.teePlayed,
      holeScores: holeScores ?? this.holeScores,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'courseName': courseName,
        'dateMs': dateMs,
        'playerIdentity': playerIdentity,
        'teePlayed': teePlayed,
        'holeScores': holeScores.map((h) => h.toJson()).toList(),
        'status': status,
      };

  factory ScorecardEntry.fromJson(Map<String, dynamic> json) {
    final rawHoles = json['holeScores'] as List? ?? const [];
    return ScorecardEntry(
      id: json['id'] as String,
      courseId: json['courseId'] as String? ?? '',
      courseName: json['courseName'] as String? ?? '',
      dateMs: (json['dateMs'] as num).toInt(),
      playerIdentity: json['playerIdentity'] as String? ?? '',
      teePlayed: json['teePlayed'] as String?,
      holeScores: rawHoles
          .map((h) => HoleScore.fromJson((h as Map).cast<String, dynamic>()))
          .toList(growable: false),
      status: json['status'] as String? ?? 'inProgress',
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ScorecardEntry) return false;
    if (id != other.id) return false;
    if (courseId != other.courseId) return false;
    if (courseName != other.courseName) return false;
    if (dateMs != other.dateMs) return false;
    if (playerIdentity != other.playerIdentity) return false;
    if (teePlayed != other.teePlayed) return false;
    if (status != other.status) return false;
    if (holeScores.length != other.holeScores.length) return false;
    for (var i = 0; i < holeScores.length; i++) {
      if (holeScores[i] != other.holeScores[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        courseId,
        courseName,
        dateMs,
        playerIdentity,
        teePlayed,
        Object.hashAll(holeScores),
        status,
      );
}

@immutable
class HoleScore {
  final int holeNumber;
  final int par;
  final int score;
  final int? putts;

  /// "hit" | "missed" | "skipped" | null. String to match iOS shape.
  final String? fairwayHit;

  const HoleScore({
    required this.holeNumber,
    required this.par,
    required this.score,
    this.putts,
    this.fairwayHit,
  });

  Map<String, dynamic> toJson() => {
        'holeNumber': holeNumber,
        'par': par,
        'score': score,
        'putts': putts,
        'fairwayHit': fairwayHit,
      };

  factory HoleScore.fromJson(Map<String, dynamic> json) {
    return HoleScore(
      holeNumber: (json['holeNumber'] as num).toInt(),
      par: (json['par'] as num).toInt(),
      score: (json['score'] as num).toInt(),
      putts: (json['putts'] as num?)?.toInt(),
      fairwayHit: json['fairwayHit'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HoleScore &&
          holeNumber == other.holeNumber &&
          par == other.par &&
          score == other.score &&
          putts == other.putts &&
          fairwayHit == other.fairwayHit);

  @override
  int get hashCode => Object.hash(holeNumber, par, score, putts, fairwayHit);
}
