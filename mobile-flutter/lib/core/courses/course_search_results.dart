// Lightweight result types for the KAN-275 (S5) course discovery
// clients. The full `NormalizedCourse` model lives in
// `lib/models/normalized_course.dart` (lifted from the KAN-252
// spike); this file just adds the search-result and manifest
// shapes that the cache layer needs.
//
// **Why a separate manifest type from NormalizedCourse:** the
// `/courses/search?mode=metadata` endpoint returns a flat list
// of {name, city, state, lat, lon, courseId, cacheKey} entries
// that's far smaller than the full course payloads. The Course
// search screen (KAN-S9) lists results from this manifest before
// the user picks one — only then do we fetch the full course
// payload via `/courses/{cacheKey}`.

import '../../models/normalized_course.dart';

/// Provenance of a `CourseSearchEntry` — which of the three parallel
/// search sources produced it. The page wrapper uses this to decide
/// how to resolve a tap into a `NormalizedCourse`:
///   - `manifest`: `cacheKey` is a real server cache key; fetch directly
///   - `nominatim` / `googlePlaces`: `cacheKey` is synthesized; the page
///     wrapper has to derive a server cache key from the name and try
///     the cache; if 404, the course isn't in the shared cache yet.
enum CourseSearchSource {
  manifest,
  nominatim,
  googlePlaces,
}

/// One row in a search response. Used by the Course search screen
/// (KAN-S9) to render the result list before the user commits to
/// fetching a full course.
class CourseSearchEntry {
  const CourseSearchEntry({
    required this.cacheKey,
    required this.name,
    required this.city,
    required this.state,
    required this.latitude,
    required this.longitude,
    this.courseId,
    this.source = CourseSearchSource.manifest,
    this.formattedAddress,
    this.isFavorite = false,
    this.cachedAtMs,
  });

  /// Server cache key when [source] is `manifest`. For Nominatim and
  /// Google Places sources this is synthesized from the OSM id or the
  /// Google Place id, not a real server cache key — the page wrapper
  /// short-circuits on a non-manifest source and resolves the entry
  /// via name-based cache lookup instead.
  final String cacheKey;

  /// Display name (e.g. "Wellshire Golf Course").
  final String name;

  /// City — may be empty for partial entries.
  final String city;

  /// State / region — may be empty for partial entries.
  final String state;

  /// Course centroid latitude (4 decimal precision in the wire
  /// format, ~11 m accuracy).
  final double latitude;

  /// Course centroid longitude.
  final double longitude;

  /// Optional opaque server identifier (for endpoints that key
  /// by id rather than cacheKey).
  final String? courseId;

  /// Which search source produced this entry. Defaults to
  /// `manifest` so existing manifest-only callers (and tests written
  /// before the 3-source merge) keep the same shape.
  final CourseSearchSource source;

  /// Google Places-formatted address ("1 Sharp Park Rd, Pacifica, CA
  /// 94044, USA"). Only set for `googlePlaces` source entries — the
  /// merge step uses it as a tie-breaker for ambiguous fuzzy matches.
  final String? formattedAddress;

  /// True when the user has starred this course. Defaulted to false
  /// for live search results; the page wrapper overlays the real
  /// value from `CourseCacheRepository.isFavorite` before handing
  /// the list to the screen, and entries returned by
  /// `CourseCacheRepository.listSaved` carry the real value.
  final bool isFavorite;

  /// Epoch milliseconds when this course was last written to the
  /// disk cache. Only set for entries returned by
  /// `CourseCacheRepository.listSaved`; live search results leave
  /// this null. The Saved tab uses it to render "Saved 2d ago"
  /// captions matching the iOS / Android format.
  final int? cachedAtMs;

  /// Returns a copy of this entry with the supplied fields replaced.
  /// Used by the merger step to overlay manifest city/state onto
  /// Nominatim/Places results, and by the page wrapper to overlay
  /// the favorite flag onto live search results.
  CourseSearchEntry copyWith({
    String? city,
    String? state,
    bool? isFavorite,
  }) {
    return CourseSearchEntry(
      cacheKey: cacheKey,
      name: name,
      city: city ?? this.city,
      state: state ?? this.state,
      latitude: latitude,
      longitude: longitude,
      courseId: courseId,
      source: source,
      formattedAddress: formattedAddress,
      isFavorite: isFavorite ?? this.isFavorite,
      cachedAtMs: cachedAtMs,
    );
  }

  factory CourseSearchEntry.fromJson(Map<String, dynamic> json) {
    return CourseSearchEntry(
      cacheKey: (json['cacheKey'] ?? json['id'] ?? json['serverCacheKey'])
          as String,
      name: json['name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      latitude: (json['lat'] ?? json['latitude'] as num).toDouble(),
      longitude: (json['lon'] ?? json['longitude'] as num).toDouble(),
      courseId: json['courseId'] as String?,
    );
  }
}

/// Result of a `CourseCacheClient.fetchCourse` call. Wraps the
/// `NormalizedCourse` with provenance info so the UI can show
/// "from disk cache" / "from server" indicators in dev builds.
class CourseFetchResult {
  const CourseFetchResult({
    required this.course,
    required this.source,
    required this.cachedAtMs,
  });

  final NormalizedCourse course;
  final CourseFetchSource source;

  /// Epoch milliseconds when this copy of the course was last
  /// written to disk. For `network` sources, this is "now"; for
  /// `disk` sources, the persisted timestamp.
  final int cachedAtMs;
}

enum CourseFetchSource {
  /// Returned from the in-memory or on-disk cache without hitting
  /// the network.
  disk,

  /// Fetched fresh from the server cache endpoint.
  network,
}

/// Thrown by the cache clients on transport / parsing errors.
/// Caller is expected to handle gracefully (e.g. fall back to a
/// "search again" UI affordance).
class CourseClientException implements Exception {
  const CourseClientException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'CourseClientException: $message'
      : 'CourseClientException ($statusCode): $message';
}
