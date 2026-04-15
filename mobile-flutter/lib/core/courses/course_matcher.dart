// CourseMatcher — matches spatially-clustered NormalizedCourse
// objects (from Overpass/OSM) to named GolfCourseApiResult entries
// by comparing per-hole par sequences.
//
// Used during multi-course facility discovery (e.g., Terra Lago
// North/South). The normalizer detects duplicate hole numbers and
// clusters them spatially, but doesn't know which cluster is
// "North" vs "South". This matcher correlates each cluster's par
// sequence against the Golf Course API's named course data to
// assign the correct name.

import '../../models/normalized_course.dart';
import 'golf_course_api_client.dart';

class CourseMatcher {
  const CourseMatcher._();

  /// Matches [clusters] to [apiResults] by par-sequence similarity.
  ///
  /// Returns a list parallel to [clusters] where each entry is the
  /// matched [GolfCourseApiResult], or null if no confident match
  /// was found. Uses greedy best-match assignment.
  static List<GolfCourseApiResult?> matchClusters(
    List<NormalizedCourse> clusters,
    List<GolfCourseApiResult> apiResults,
  ) {
    if (clusters.isEmpty || apiResults.isEmpty) {
      return List.filled(clusters.length, null);
    }

    // Extract par sequences.
    final clusterPars = clusters
        .map((c) => c.holes.map((h) => h.par).toList(growable: false))
        .toList(growable: false);

    final apiPars = apiResults.map((r) {
      // All tees share the same par — grab from whichever tee is available.
      if (r.tees.isEmpty) return const <int>[];
      return r.tees.values.first.holes
          .map((h) => h.par)
          .toList(growable: false);
    }).toList(growable: false);

    // Score every (cluster, apiResult) pair.
    final scores = List.generate(
      clusters.length,
      (ci) => List.generate(
        apiResults.length,
        (ai) => _parMatchScore(clusterPars[ci], apiPars[ai]),
      ),
    );

    // Greedy best-match assignment.
    final result = List<GolfCourseApiResult?>.filled(clusters.length, null);
    final usedClusters = <int>{};
    final usedApi = <int>{};

    final maxPairs = clusters.length < apiResults.length
        ? clusters.length
        : apiResults.length;

    for (var round = 0; round < maxPairs; round++) {
      double bestScore = 0;
      int bestCi = -1;
      int bestAi = -1;

      for (var ci = 0; ci < clusters.length; ci++) {
        if (usedClusters.contains(ci)) continue;
        for (var ai = 0; ai < apiResults.length; ai++) {
          if (usedApi.contains(ai)) continue;
          if (scores[ci][ai] > bestScore) {
            bestScore = scores[ci][ai];
            bestCi = ci;
            bestAi = ai;
          }
        }
      }

      // Require at least 50% par match to accept.
      if (bestCi < 0 || bestScore < 0.5) break;

      result[bestCi] = apiResults[bestAi];
      usedClusters.add(bestCi);
      usedApi.add(bestAi);
    }

    return result;
  }

  /// Returns 0.0–1.0 score: fraction of holes with matching par.
  static double _parMatchScore(List<int> clusterPars, List<int> apiPars) {
    if (clusterPars.isEmpty || apiPars.isEmpty) return 0;
    final len = clusterPars.length < apiPars.length
        ? clusterPars.length
        : apiPars.length;
    int matches = 0;
    for (var i = 0; i < len; i++) {
      if (clusterPars[i] == apiPars[i]) matches++;
    }
    final maxLen = clusterPars.length > apiPars.length
        ? clusterPars.length
        : apiPars.length;
    return matches / maxLen;
  }
}
