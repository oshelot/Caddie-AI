// ActiveRound — KAN-382 MVP — the single in-flight round of golf
// the user is currently playing.
//
// Persisted as JSON in the `caddieai_active_round_v1` Hive box
// under the singleton key `current` (see ActiveRoundRepository).
// Mirrors the storage pattern used by PlayerProfile.
//
// **At most one active round at a time** — KAN-382 MVP scope.
// Multi-round (e.g., resume an abandoned round) is a future
// extension; the singleton key encodes that constraint today.

import 'dart:convert';

class ActiveRound {
  ActiveRound({
    required this.courseId,
    required this.courseName,
    required this.totalHoles,
    required this.currentHoleNumber,
    required this.startedAtMs,
    this.subCourseSlug,
    this.city,
    this.state,
  });

  /// Stable course identifier — typically the cache file's `id`
  /// (e.g. `walnut-creek-golf-preserve`). The app uses this to
  /// detect "is the round on the course currently displayed?".
  final String courseId;

  /// Display name shown in the active-round panel.
  final String courseName;

  /// Optional sub-course slug for multi-course facilities (e.g.
  /// Kennedy `creek` / `lind` / `west`). Null for single-course
  /// facilities. KAN-373.
  final String? subCourseSlug;

  /// City + state, for display + telemetry. Optional because some
  /// older cache files don't carry them.
  final String? city;
  final String? state;

  /// Hole count on this course/sub-course (9, 18, 27, …). Drives
  /// the upper bound for `currentHoleNumber`.
  final int totalHoles;

  /// 1-based current hole. Manual Next/Prev mutate this.
  final int currentHoleNumber;

  /// Epoch-ms timestamp when StartRound fired. Used for round
  /// duration display + future post-round recap.
  final int startedAtMs;

  ActiveRound copyWith({
    String? courseId,
    String? courseName,
    String? subCourseSlug,
    String? city,
    String? state,
    int? totalHoles,
    int? currentHoleNumber,
    int? startedAtMs,
  }) {
    return ActiveRound(
      courseId: courseId ?? this.courseId,
      courseName: courseName ?? this.courseName,
      subCourseSlug: subCourseSlug ?? this.subCourseSlug,
      city: city ?? this.city,
      state: state ?? this.state,
      totalHoles: totalHoles ?? this.totalHoles,
      currentHoleNumber: currentHoleNumber ?? this.currentHoleNumber,
      startedAtMs: startedAtMs ?? this.startedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'courseId': courseId,
        'courseName': courseName,
        if (subCourseSlug != null) 'subCourseSlug': subCourseSlug,
        if (city != null) 'city': city,
        if (state != null) 'state': state,
        'totalHoles': totalHoles,
        'currentHoleNumber': currentHoleNumber,
        'startedAtMs': startedAtMs,
      };

  factory ActiveRound.fromJson(Map<String, dynamic> j) => ActiveRound(
        courseId: j['courseId'] as String,
        courseName: j['courseName'] as String,
        subCourseSlug: j['subCourseSlug'] as String?,
        city: j['city'] as String?,
        state: j['state'] as String?,
        totalHoles: (j['totalHoles'] as num).toInt(),
        currentHoleNumber: (j['currentHoleNumber'] as num).toInt(),
        startedAtMs: (j['startedAtMs'] as num).toInt(),
      );

  String encode() => jsonEncode(toJson());
  static ActiveRound decode(String raw) =>
      ActiveRound.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
