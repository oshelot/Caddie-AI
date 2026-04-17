// CourseCacheClient — Flutter port of the iOS
// `CourseCacheAPIClient.swift` and Android `ServerCacheClient.kt`.
//
// **Endpoints (all on the same base URL):**
//
//   GET /courses/search?q=<name>&lat=<lat>&lon=<lon>&platform=ios&schema=1.0
//       → list of full NormalizedCourse payloads matching the query
//
//   GET /courses/search?q=<name>&mode=metadata&platform=ios&schema=1.0
//       → lightweight CourseSearchEntry list (name + city + state + lat/lon)
//
//   GET /courses/{cacheKey}?platform=ios&schema=1.0
//       → single full NormalizedCourse payload (404 on miss)
//
//   PUT /courses/{cacheKey}?platform=ios&schema=1.0
//       → uploads a freshly-discovered course so other users can
//         pull it from the cache. Fire-and-forget.
//
// **Mandatory query params** (KAN-275 AC #1):
//   `platform=ios&schema=1.0` MUST be passed on every call. The
//   server's iOS-platform serialization uses GeoJSON-shaped
//   `coordinates` arrays which `NormalizedCourse.fromJson` can
//   parse; the Android-platform serialization uses a flatter
//   shape (`teeBox`, `fairwayCenterLine.points`) and is NOT
//   compatible with the lifted models. Tests assert these params
//   appear on every outbound request.
//
// **Auth:** `x-api-key` header, sourced from a `--dart-define`
// at build time. The client takes the key in its constructor so
// tests can pass an arbitrary value.

import 'dart:convert';

import '../geo/geo.dart';
import '../../models/normalized_course.dart';
import 'course_search_results.dart';
import 'http_transport.dart';

/// Constants used as query-param values. Centralized so the test
/// suite asserts against the same strings the client sends.
abstract final class CourseCacheParams {
  CourseCacheParams._();

  /// **REQUIRED** on every request. The server's `platform=ios`
  /// branch produces JSON that maps cleanly onto NormalizedCourse.
  /// `platform=android` produces an incompatible flat shape we
  /// cannot parse — see file header for the rationale.
  static const String platform = 'ios';

  /// **REQUIRED** on every request. The current schema version of
  /// `NormalizedCourse`. Bumping this constant means the lifted
  /// models have changed shape and the cache must serve a fresh
  /// copy of every course.
  static const String schemaVersion = '1.0';

  /// Used as `mode=metadata` on search calls when the caller only
  /// wants the lightweight CourseSearchEntry list (no full
  /// course payloads).
  static const String metadataMode = 'metadata';
}

class CourseCacheClient {
  CourseCacheClient({
    required this.baseUrl,
    required this.apiKey,
    required this.transport,
    Duration timeout = const Duration(seconds: 10),
  }) : _timeout = timeout;

  /// Base URL of the server cache (e.g. `https://cache.caddieai.app`).
  /// Sourced from a `--dart-define` in production.
  final String baseUrl;

  /// API key sent as the `x-api-key` header. Sourced from a
  /// `--dart-define` in production.
  final String apiKey;

  /// Injected HTTP transport — `DartIoHttpTransport` in production,
  /// `FakeHttpTransport` in unit tests.
  final HttpTransport transport;

  final Duration _timeout;

  // ── search ────────────────────────────────────────────────────────

  /// Searches the server cache by free-text query, optionally
  /// biased toward a lat/lon. Returns the matching courses as a
  /// list of lightweight CourseSearchEntry rows.
  ///
  /// Pass `mode = SearchMode.metadata` (the default) to get just
  /// the manifest entries; `mode = SearchMode.full` returns the
  /// full course payloads alongside the entries (more bandwidth,
  /// fewer round-trips for the picker → map flow).
  Future<List<CourseSearchEntry>> searchManifest({
    required String query,
    double? latitude,
    double? longitude,
  }) async {
    final url = _buildSearchUrl(
      query: query,
      latitude: latitude,
      longitude: longitude,
      metadataOnly: true,
    );
    final response = await _send('GET', url);
    if (response.isNotFound) return const [];
    if (!response.isSuccess) {
      throw CourseClientException(
        'Search failed for "$query"',
        statusCode: response.statusCode,
      );
    }
    return _parseManifestList(response.body);
  }

  /// Fuzzy-searches the server cache and returns the FULL
  /// `NormalizedCourse` payload of the best match. This is the
  /// same endpoint as `searchManifest` but WITHOUT `mode=metadata`,
  /// so the server returns the complete course JSON (geometry,
  /// holes, tee data) instead of just the manifest entry.
  ///
  /// Mirrors iOS `CourseCacheAPIClient.searchCourse()` — the
  /// primary "download a course" path when the user taps a search
  /// result. Returns null on 404 (no match in the server cache).
  Future<NormalizedCourse?> searchFullCourse({
    required String query,
    double? latitude,
    double? longitude,
  }) async {
    final url = _buildSearchUrl(
      query: query,
      latitude: latitude,
      longitude: longitude,
      metadataOnly: false,
    );
    final response = await _send('GET', url);
    if (response.isNotFound) return null;
    if (!response.isSuccess) {
      throw CourseClientException(
        'Full search failed for "$query"',
        statusCode: response.statusCode,
      );
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return NormalizedCourse.fromJson(json);
    } catch (e) {
      throw CourseClientException('Malformed course payload: $e');
    }
  }

  // ── single course fetch ──────────────────────────────────────────

  /// Fetches one course by server cache key. Returns null on a
  /// 404 (the canonical "not in cache" response). Throws on any
  /// other failure.
  Future<NormalizedCourse?> fetchCourse(String cacheKey) async {
    final url = _buildCourseUrl(cacheKey);
    final response = await _send('GET', url);
    if (response.isNotFound) return null;
    if (!response.isSuccess) {
      throw CourseClientException(
        'Fetch failed for "$cacheKey"',
        statusCode: response.statusCode,
      );
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return NormalizedCourse.fromJson(json);
    } catch (e) {
      throw CourseClientException('Malformed course payload: $e');
    }
  }

  // ── upload ────────────────────────────────────────────────────────

  /// Fire-and-forget upload of a freshly-discovered course. The
  /// server cache treats this as upsert. Returns true on success,
  /// false on any error (the caller should NOT retry — discovery
  /// will happen again on the next miss).
  Future<bool> putCourse(String cacheKey, NormalizedCourse course) async {
    final url = _buildCourseUrl(cacheKey);
    try {
      final response = await _send(
        'PUT',
        url,
        body: jsonEncode(_serializeCourse(course)),
        contentType: 'application/json',
      );
      return response.isSuccess;
    } catch (_) {
      return false;
    }
  }

  // ── async ingestion ──────────────────────────────────────────────

  /// Requests async backend processing for a multi-course facility.
  /// The backend will split, enrich, and cache each sub-course.
  /// Returns true if the request was accepted (202), false on error.
  Future<bool> requestIngestion(
    String name,
    NormalizedCourse course,
  ) async {
    final url = Uri.parse('$baseUrl/courses/ingest');
    try {
      final response = await _send(
        'POST',
        url,
        body: jsonEncode({
          'name': name,
          'courseJson': _serializeCourse(course),
        }),
        contentType: 'application/json',
      );
      return response.statusCode == 202;
    } catch (_) {
      return false;
    }
  }

  /// Fire-and-forget request to refine a cached course's geometry
  /// using satellite vision on the backend. The backend fetches the
  /// course from S3, identifies holes with no geometry, uses Nova Pro
  /// on satellite imagery to locate them, and saves the refined
  /// version back. Subsequent downloads get the refined data.
  Future<bool> refineCourse(String cacheKey, String facilityName) async {
    final url = Uri.parse('$baseUrl/courses/refine');
    try {
      final response = await _send(
        'POST',
        url,
        body: jsonEncode({
          'cacheKey': cacheKey,
          'facilityName': facilityName,
        }),
        contentType: 'application/json',
      );
      return response.statusCode == 202;
    } catch (_) {
      return false;
    }
  }

  // ── corrections queue ────────────────────────────────────────────

  /// Submit a geometry correction for human review. Fire-and-forget.
  Future<bool> submitCorrection(Map<String, dynamic> correction) async {
    final url = Uri.parse('$baseUrl/corrections');
    try {
      final response = await _send(
        'POST',
        url,
        body: jsonEncode(correction),
        contentType: 'application/json',
      );
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ── url builders ─────────────────────────────────────────────────

  Uri _buildSearchUrl({
    required String query,
    double? latitude,
    double? longitude,
    required bool metadataOnly,
  }) {
    final params = <String, String>{
      'q': query,
      // CRITICAL — both params on every call. AC #1.
      'platform': CourseCacheParams.platform,
      'schema': CourseCacheParams.schemaVersion,
    };
    if (latitude != null) {
      params['lat'] = latitude.toStringAsFixed(4);
    }
    if (longitude != null) {
      params['lon'] = longitude.toStringAsFixed(4);
    }
    if (metadataOnly) {
      params['mode'] = CourseCacheParams.metadataMode;
    }
    return Uri.parse('$baseUrl/courses/search').replace(
      queryParameters: params,
    );
  }

  Uri _buildCourseUrl(String cacheKey) {
    return Uri.parse('$baseUrl/courses/${Uri.encodeComponent(cacheKey)}')
        .replace(
      queryParameters: {
        // CRITICAL — both params on every call. AC #1.
        'platform': CourseCacheParams.platform,
        'schema': CourseCacheParams.schemaVersion,
      },
    );
  }

  // ── transport wrapper ────────────────────────────────────────────

  Future<HttpResponseLike> _send(
    String method,
    Uri url, {
    String? body,
    String? contentType,
  }) {
    final headers = <String, String>{
      'x-api-key': apiKey,
      'Accept': 'application/json',
      if (contentType != null) 'Content-Type': contentType,
    };
    return transport.send(HttpRequestLike(
      method: method,
      url: url,
      headers: headers,
      body: body,
      timeout: _timeout,
    ));
  }

  // ── parsing ──────────────────────────────────────────────────────

  List<CourseSearchEntry> _parseManifestList(String body) {
    final raw = jsonDecode(body);
    // The server may return either a bare array or {"results": […]}.
    // Both natives accept both shapes, so we mirror that.
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['results'] ?? raw['courses']) as List : const []);
    return list
        .map((entry) => CourseSearchEntry.fromJson(
              (entry as Map).cast<String, dynamic>(),
            ))
        .toList(growable: false);
  }

  /// Re-serialization for `putCourse`. The model only round-trips
  /// the fields it parses (the lifted NormalizedCourse intentionally
  /// drops everything that isn't used by rendering — see the file
  /// header in `lib/models/normalized_course.dart`). For the upload
  /// path the server tolerates the lean shape; the receiving Lambda
  /// re-fills any missing optional fields with defaults.
  Map<String, dynamic> _serializeCourse(NormalizedCourse course) {
    return {
      'id': course.id,
      'name': course.name,
      'city': course.city,
      'state': course.state,
      'centroid': {
        'latitude': course.centroid.lat,
        'longitude': course.centroid.lon,
      },
      'teeNames': course.teeNames,
      'teeYardageTotals': course.teeYardageTotals,
      'holes': course.holes.map(_serializeHole).toList(),
    };
  }

  Map<String, dynamic> _serializeHole(NormalizedHole hole) {
    return {
      'number': hole.number,
      'par': hole.par,
      'strokeIndex': hole.strokeIndex,
      'yardages': hole.yardages,
      'lineOfPlay': hole.lineOfPlay != null
          ? {
              'coordinates': hole.lineOfPlay!.points
                  .map((p) => [p.lon, p.lat])
                  .toList(growable: false)
            }
          : null,
      'green': hole.green != null
          ? {
              'coordinates': [
                _closedRing(hole.green!.outerRing)
                    .map((p) => [p.lon, p.lat])
                    .toList(growable: false)
              ]
            }
          : null,
      'pin': hole.pin != null
          ? {'latitude': hole.pin!.lat, 'longitude': hole.pin!.lon}
          : null,
      'teeAreas': hole.teeAreas
          .map((t) => {
                'coordinates': [
                  _closedRing(t.outerRing)
                      .map((p) => [p.lon, p.lat])
                      .toList(growable: false)
                ]
              })
          .toList(growable: false),
      'bunkers': hole.bunkers
          .map((b) => {
                'coordinates': [
                  _closedRing(b.outerRing)
                      .map((p) => [p.lon, p.lat])
                      .toList(growable: false)
                ]
              })
          .toList(growable: false),
      'water': hole.water
          .map((w) => {
                'coordinates': [
                  _closedRing(w.outerRing)
                      .map((p) => [p.lon, p.lat])
                      .toList(growable: false)
                ]
              })
          .toList(growable: false),
    };
  }

  static List<LngLat> _closedRing(List<LngLat> ring) {
    if (ring.length < 3) return ring;
    final first = ring.first;
    final last = ring.last;
    if (first.lon == last.lon && first.lat == last.lat) return ring;
    return [...ring, first];
  }
}
