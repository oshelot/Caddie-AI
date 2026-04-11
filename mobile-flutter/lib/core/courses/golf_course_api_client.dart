// GolfCourseApiClient — Flutter port of the iOS
// `GolfCourseAPIClient.swift` and Android `GolfCourseAPIClient.kt`.
// Wraps the third-party Golf Course API at
// `https://api.golfcourseapi.com/v1`, used as the **scorecard
// enrichment** path: given a course name (and optionally a
// course id), returns par/yardage/slope/course-rating data per
// hole and per tee box.
//
// **This is a discovery-time enrichment API, not a runtime API.**
// The course map screen (KAN-S10) renders from `NormalizedCourse`
// pulled from the server cache (`CourseCacheClient`); this
// client is only invoked during the OSM → cache pipeline (which
// runs server-side today, but the Flutter app retains the client
// so feature stories like KAN-S9 can search by course name when
// the server cache misses).
//
// **Auth:** `Authorization: Key <apiKey>` header (the provider's
// quirky scheme — note `Key` is literal, not `Bearer`). The key
// comes from a `--dart-define` at build time.
//
// **Suffix retry (KAN-248):** if the initial search returns
// nothing, both natives strip common golf-course suffixes and
// retry. We do the same — see `_retrySuffixes` for the list and
// the rationale.

import 'dart:convert';

import 'course_search_results.dart';
import 'http_transport.dart';

class GolfCourseApiClient {
  GolfCourseApiClient({
    required this.apiKey,
    required this.transport,
    String baseUrl = 'https://api.golfcourseapi.com/v1',
    Duration timeout = const Duration(seconds: 15),
  })  : _baseUrl = baseUrl,
        _timeout = timeout;

  final String apiKey;
  final HttpTransport transport;
  final String _baseUrl;
  final Duration _timeout;

  /// Suffixes the search-retry path strips, in order. Order matters
  /// — longer suffixes first so "Golf & Country Club" wins over
  /// "Country Club" if both would match. Lifted directly from
  /// `GolfCourseAPIClient.kt`'s suffix list (KAN-248).
  static const List<String> _retrySuffixes = [
    'Golf & Country Club',
    'Municipal Golf Course',
    'Public Golf Course',
    'Country Club',
    'Golf Course',
    'Golf Links',
    'Golf Club',
  ];

  // ── search ────────────────────────────────────────────────────────

  /// Searches the Golf Course API by name. If the initial query
  /// returns no results, retries with each entry from
  /// `_retrySuffixes` stripped in turn. Returns the first
  /// non-empty result list, or an empty list if every retry
  /// also misses.
  Future<List<GolfCourseApiResult>> searchCourses(String name) async {
    final initial = await _searchOnce(name);
    if (initial.isNotEmpty) return initial;

    for (final suffix in _retrySuffixes) {
      final stripped = _stripSuffix(name, suffix);
      if (stripped == name || stripped.isEmpty) continue;
      final retry = await _searchOnce(stripped);
      if (retry.isNotEmpty) return retry;
    }
    // Final fallback: strip trailing yardage digits left by some
    // OSM names (e.g. "Sharp Park 50" → "Sharp Park"). Mirrors the
    // Android `\\s+\\d{3,}\\s*$` regex.
    final trimmedDigits =
        name.replaceAll(RegExp(r'\s+\d{2,}\s*$'), '').trim();
    if (trimmedDigits != name && trimmedDigits.isNotEmpty) {
      final lastTry = await _searchOnce(trimmedDigits);
      if (lastTry.isNotEmpty) return lastTry;
    }
    return const [];
  }

  /// Fetches one course detail by its Golf Course API id.
  Future<GolfCourseApiResult?> getCourse(int id) async {
    final url = Uri.parse('$_baseUrl/courses/$id');
    final response = await _send(url);
    if (response.isNotFound) return null;
    if (!response.isSuccess) {
      throw CourseClientException(
        'Golf Course API failed for id=$id',
        statusCode: response.statusCode,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    // The detail endpoint wraps the result in a `course` field
    // (matches both the iOS `GolfCourseAPICourseWrapper` and
    // Android `GolfAPICourseDetailResponse` shapes).
    final raw = (json['course'] ?? json) as Map<String, dynamic>;
    return GolfCourseApiResult.fromJson(raw);
  }

  // ── internals ────────────────────────────────────────────────────

  Future<List<GolfCourseApiResult>> _searchOnce(String query) async {
    final url = Uri.parse('$_baseUrl/search').replace(
      queryParameters: {'search_query': query},
    );
    final response = await _send(url);
    if (response.isNotFound) return const [];
    if (!response.isSuccess) {
      throw CourseClientException(
        'Golf Course API search failed for "$query"',
        statusCode: response.statusCode,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (json['courses'] as List?) ?? const [];
    return list
        .map((c) =>
            GolfCourseApiResult.fromJson((c as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<HttpResponseLike> _send(Uri url) {
    return transport.send(HttpRequestLike(
      method: 'GET',
      url: url,
      // Note the literal `Key ` prefix — not `Bearer`. This is
      // the provider's documented auth scheme.
      headers: {'Authorization': 'Key $apiKey'},
      timeout: _timeout,
    ));
  }

  /// Case-insensitive trailing suffix strip. Trims trailing
  /// whitespace after the strip so "Bandon Dunes Golf Course"
  /// becomes "Bandon Dunes" rather than "Bandon Dunes ".
  String _stripSuffix(String name, String suffix) {
    final lower = name.toLowerCase();
    final suffixLower = suffix.toLowerCase();
    if (!lower.endsWith(suffixLower)) return name;
    return name.substring(0, name.length - suffix.length).trim();
  }
}

/// One course returned by the Golf Course API. Carries enough
/// fields for scorecard enrichment (par, yardages by tee, slope/
/// course rating). The full provider payload has many more
/// fields — we only parse what the cache pipeline actually uses.
class GolfCourseApiResult {
  const GolfCourseApiResult({
    required this.id,
    required this.clubName,
    required this.courseName,
    required this.city,
    required this.state,
    required this.country,
    required this.tees,
  });

  final int id;
  final String clubName;
  final String courseName;
  final String city;
  final String state;
  final String country;

  /// Tee boxes, deduped case-insensitively. The map key is the
  /// canonical tee name (lowercased) and the value is the tee
  /// metadata. Both natives dedupe by lowercased name (the iOS
  /// "first-seen casing wins" rule); we adopt the same.
  final Map<String, GolfCourseApiTee> tees;

  factory GolfCourseApiResult.fromJson(Map<String, dynamic> json) {
    final location = (json['location'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final tees = <String, GolfCourseApiTee>{};
    void mergeTees(dynamic raw) {
      if (raw is! List) return;
      for (final entry in raw) {
        final t = GolfCourseApiTee.fromJson((entry as Map).cast<String, dynamic>());
        final key = t.teeName.toLowerCase();
        tees.putIfAbsent(key, () => t);
      }
    }

    // Both male and female tee arrays (the provider splits them
    // for handicap-rating purposes; we merge for our use case).
    final teesObj = (json['tees'] as Map?)?.cast<String, dynamic>();
    if (teesObj != null) {
      mergeTees(teesObj['male']);
      mergeTees(teesObj['female']);
    } else {
      // Some endpoints return a flat list under `tees` instead.
      mergeTees(json['tees']);
    }

    return GolfCourseApiResult(
      id: (json['id'] as num).toInt(),
      clubName: (json['club_name'] ?? json['clubName'] ?? '') as String,
      courseName: (json['course_name'] ?? json['courseName'] ?? '') as String,
      city: location['city'] as String? ?? '',
      state: location['state'] as String? ?? '',
      country: location['country'] as String? ?? '',
      tees: tees,
    );
  }
}

class GolfCourseApiTee {
  const GolfCourseApiTee({
    required this.teeName,
    required this.totalYards,
    required this.parTotal,
    required this.courseRating,
    required this.slopeRating,
    required this.holes,
  });

  final String teeName;
  final int totalYards;
  final int parTotal;
  final double courseRating;
  final int slopeRating;
  final List<GolfCourseApiHole> holes;

  factory GolfCourseApiTee.fromJson(Map<String, dynamic> json) {
    final rawHoles = (json['holes'] as List?) ?? const [];
    return GolfCourseApiTee(
      teeName: _stripTrailingDigits(
        (json['tee_name'] ?? json['teeName'] ?? '') as String,
      ),
      totalYards: ((json['total_yards'] ?? json['totalYards']) as num?)?.toInt() ??
          0,
      parTotal: ((json['par_total'] ?? json['parTotal']) as num?)?.toInt() ?? 0,
      courseRating:
          ((json['course_rating'] ?? json['courseRating']) as num?)?.toDouble() ??
              0,
      slopeRating:
          ((json['slope_rating'] ?? json['slopeRating']) as num?)?.toInt() ?? 0,
      holes: rawHoles
          .map((h) =>
              GolfCourseApiHole.fromJson((h as Map).cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  /// Strips trailing yardage tokens like "Blue 6432" → "Blue".
  /// Mirrors the Android `\\s+\\d{3,}\\s*$` cleanup.
  static String _stripTrailingDigits(String name) =>
      name.replaceAll(RegExp(r'\s+\d{3,}\s*$'), '').trim();
}

class GolfCourseApiHole {
  const GolfCourseApiHole({
    required this.par,
    required this.yardage,
    required this.handicap,
  });

  final int par;
  final int yardage;
  final int? handicap;

  factory GolfCourseApiHole.fromJson(Map<String, dynamic> json) {
    return GolfCourseApiHole(
      par: (json['par'] as num).toInt(),
      yardage: (json['yardage'] as num?)?.toInt() ?? 0,
      handicap: (json['handicap'] as num?)?.toInt(),
    );
  }
}
