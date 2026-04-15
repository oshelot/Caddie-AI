// CourseMatcher — identifies individual courses within multi-course
// golf facilities by analyzing Golf Course API data.
//
// Handles two patterns:
//
// 1. **Separate courses** (e.g., Terra Lago): the API returns
//    distinct entries like "North" and "South", each with 18 holes.
//    Par sequences are used directly.
//
// 2. **Combination courses** (e.g., Kennedy Golf): the API returns
//    18-hole *pairings* of 9-hole courses like "West-Lind",
//    "West-Creek", "Lind-Creek". We decompose these into individual
//    9-hole courses (West, Lind, Creek) by splitting each combo at
//    hole 9 and deduplicating shared halves.

import 'golf_course_api_client.dart';

/// A single named 9- or 18-hole course extracted from the Golf
/// Course API data. Carries enough info for par-based hole matching
/// and enrichment.
class ExtractedCourse {
  const ExtractedCourse({
    required this.name,
    required this.pars,
    this.apiDetail,
    this.frontOrBack,
  });

  /// Display name (e.g., "West", "North").
  final String name;

  /// Per-hole par sequence (9 or 18 holes).
  final List<int> pars;

  /// The full API detail for enrichment. For combination courses,
  /// this points to one of the combos that contains this 9 (the
  /// caller uses [frontOrBack] to know which half to enrich from).
  final GolfCourseApiResult? apiDetail;

  /// For 9-hole courses decomposed from combos: 'front' if this 9
  /// is holes 1-9 of [apiDetail], 'back' if holes 10-18. Null for
  /// standalone 18-hole courses.
  final String? frontOrBack;
}

class CourseMatcher {
  const CourseMatcher._();

  /// Extracts individual named courses from Golf Course API results.
  ///
  /// If the API returns combination names like "West-Lind", decomposes
  /// them into individual 9-hole courses. Otherwise returns the API
  /// results as-is.
  static List<ExtractedCourse> extractCourses(
    List<GolfCourseApiResult> apiDetails,
  ) {
    if (apiDetails.isEmpty) return const [];

    // Check for combination pattern: names containing "-" where
    // sub-names are shared across multiple entries.
    // e.g., "West-Lind", "West-Creek", "Lind-Creek"
    final comboParts = <String, List<_ComboEntry>>{};
    var isCombos = true;

    for (final detail in apiDetails) {
      final name = detail.courseName.trim();
      final parts = name.split('-').map((p) => p.trim()).toList();
      if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
        isCombos = false;
        break;
      }
      comboParts
          .putIfAbsent(parts[0], () => [])
          .add(_ComboEntry(detail: detail, isFront: true));
      comboParts
          .putIfAbsent(parts[1], () => [])
          .add(_ComboEntry(detail: detail, isFront: false));
    }

    // Validate: each sub-name should appear in at least 2 combos
    // for the pattern to hold (e.g., "West" appears in "West-Lind"
    // and "West-Creek").
    if (isCombos && comboParts.length >= 2) {
      final validSubs = comboParts.entries
          .where((e) => e.value.length >= 2)
          .toList();
      if (validSubs.length < 2) isCombos = false;
    }

    if (isCombos && comboParts.length >= 2) {
      return _extractFromCombos(comboParts);
    }

    // Standard pattern: each API result is a standalone course.
    return apiDetails.map((d) {
      List<int> pars = const [];
      if (d.tees.isNotEmpty) {
        pars = d.tees.values.first.holes
            .map((h) => h.par)
            .toList(growable: false);
      }
      return ExtractedCourse(
        name: d.courseName,
        pars: pars,
        apiDetail: d,
      );
    }).toList();
  }

  static List<ExtractedCourse> _extractFromCombos(
    Map<String, List<_ComboEntry>> comboParts,
  ) {
    final results = <ExtractedCourse>[];

    for (final entry in comboParts.entries) {
      final subName = entry.key;
      final appearances = entry.value;

      // Extract this sub-course's 9-hole par sequence from the first
      // combo it appears in. Verify consistency across combos.
      List<int>? pars;
      GolfCourseApiResult? sourceDetail;
      String? frontOrBack;

      for (final combo in appearances) {
        final detail = combo.detail;
        if (detail.tees.isEmpty) continue;
        final fullPars = detail.tees.values.first.holes
            .map((h) => h.par)
            .toList(growable: false);
        if (fullPars.length < 18) continue;

        final half = combo.isFront
            ? fullPars.sublist(0, 9)
            : fullPars.sublist(9, 18);

        if (pars == null) {
          pars = half;
          sourceDetail = detail;
          frontOrBack = combo.isFront ? 'front' : 'back';
        }
        // If we already have pars, we could verify consistency here
        // but we trust the API data is consistent.
      }

      if (pars != null) {
        results.add(ExtractedCourse(
          name: subName,
          pars: pars,
          apiDetail: sourceDetail,
          frontOrBack: frontOrBack,
        ));
      }
    }

    return results;
  }
}

class _ComboEntry {
  const _ComboEntry({required this.detail, required this.isFront});
  final GolfCourseApiResult detail;
  final bool isFront;
}
