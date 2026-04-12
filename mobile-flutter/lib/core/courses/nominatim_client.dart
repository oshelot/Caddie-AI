// NominatimClient — Flutter port of `ios/CaddieAI/Services/NominatimClient.swift`.
//
// Hits the public OpenStreetMap Nominatim geocoder for fast golf-course
// name search (~200–500 ms vs the 5–30 s that the full Overpass pipeline
// takes). Used as one of the three parallel sources in the
// `CourseSearchPage` fan-out (alongside Google Places via the
// `caddieai-course-cache` Lambda and the server-cache manifest metadata).
//
// **Nominatim TOS:** the public endpoint requires a non-default
// User-Agent identifying the app, and bans heavy/abusive query patterns.
// We pass `CaddieAI/1.0 (Flutter golf caddie app)` to satisfy that
// requirement and rely on the search-screen debounce (350 ms) to keep
// volume reasonable. iOS has been hitting this same endpoint with the
// same query pattern since KAN-29 with no rate-limit issues.
//
// **Result shape:** returns a list of `CourseSearchEntry` whose
// `source = CourseSearchSource.nominatim` and whose `cacheKey` is
// synthesized from the OSM type/id pair so the screen has a stable
// identifier. The page wrapper interprets a non-manifest `cacheKey`
// as "synthesize the server cacheKey from the name on tap and try the
// cache; if 404, fall through to a snackbar".
//
// **Filtering:** mirrors `NominatimClient.swift:99-111` — keeps only
// results whose OSM type is `golf_course` OR whose display name
// contains "golf course / golf club / golf links" (catches the
// stragglers that aren't tagged correctly in OSM).

import 'dart:convert';

import 'course_search_results.dart';
import 'http_transport.dart';

class NominatimClient {
  NominatimClient({
    required this.transport,
    this.endpoint = 'https://nominatim.openstreetmap.org/search',
    this.userAgent = 'CaddieAI/1.0 (Flutter golf caddie app)',
    Duration timeout = const Duration(seconds: 10),
  }) : _timeout = timeout;

  final HttpTransport transport;
  final String endpoint;
  final String userAgent;
  final Duration _timeout;

  /// Fast golf-course name search via Nominatim. Returns an empty
  /// list on any failure — the page wrapper merges this with the
  /// other two sources, so a Nominatim outage shouldn't take down
  /// the whole search.
  Future<List<CourseSearchEntry>> searchCourses(
    String query, {
    String? countryCode,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final params = <String, String>{
      'q': 'golf course $trimmed',
      'format': 'json',
      'limit': '15',
      'addressdetails': '1',
      'extratags': '1',
    };
    if (countryCode != null && countryCode.isNotEmpty) {
      params['countrycodes'] = countryCode;
    }
    final url = Uri.parse(endpoint).replace(queryParameters: params);

    try {
      final response = await transport.send(HttpRequestLike(
        method: 'GET',
        url: url,
        headers: {
          'User-Agent': userAgent,
          'Accept': 'application/json',
        },
        timeout: _timeout,
      ));
      if (!response.isSuccess) return const [];
      return _parse(response.body);
    } catch (_) {
      return const [];
    }
  }

  List<CourseSearchEntry> _parse(String body) {
    final raw = jsonDecode(body);
    if (raw is! List) return const [];

    final out = <CourseSearchEntry>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      if (!_isGolfCourse(map)) continue;

      final lat = double.tryParse('${map['lat']}');
      final lon = double.tryParse('${map['lon']}');
      if (lat == null || lon == null) continue;

      final name = _extractCourseName(map['display_name'] as String? ?? '');
      if (name.isEmpty) continue;

      final address = (map['address'] as Map?)?.cast<String, dynamic>();
      final city = _extractCity(address);
      final state = (address?['state'] as String?) ?? '';

      final osmType = map['osm_type'] as String? ?? 'node';
      final osmId = '${map['osm_id'] ?? ''}';
      final cacheKey = 'nominatim:$osmType$osmId';

      out.add(CourseSearchEntry(
        cacheKey: cacheKey,
        name: name,
        city: city,
        state: state,
        latitude: lat,
        longitude: lon,
        source: CourseSearchSource.nominatim,
      ));
    }
    return out;
  }

  static bool _isGolfCourse(Map<String, dynamic> result) {
    if (result['type'] == 'golf_course') return true;
    if (result['class'] == 'leisure' && result['type'] == 'golf_course') {
      return true;
    }
    final display = (result['display_name'] as String? ?? '').toLowerCase();
    return display.contains('golf course') ||
        display.contains('golf club') ||
        display.contains('golf links');
  }

  /// Use the first comma-separated component of `display_name`, then
  /// strip trailing digits that Nominatim sometimes concatenates
  /// (e.g. "Sharp Park Golf Course50" → "Sharp Park Golf Course").
  /// Mirrors `NominatimClient.swift:113-129`.
  static String _extractCourseName(String displayName) {
    if (displayName.isEmpty) return '';
    final commaIdx = displayName.indexOf(',');
    var name = (commaIdx >= 0
            ? displayName.substring(0, commaIdx)
            : displayName)
        .trim();
    while (name.isNotEmpty &&
        RegExp(r'\d').hasMatch(name[name.length - 1])) {
      name = name.substring(0, name.length - 1);
    }
    return name.trim();
  }

  /// Nominatim's address data for golf courses is unreliable — Sharp
  /// Park reports "San Francisco" instead of "Pacifica", for example.
  /// The course-cache manifest's Google-Places-validated city/state
  /// overrides this in the merger step (see iOS
  /// `CourseViewModel.swift:108-129`).
  static String _extractCity(Map<String, dynamic>? address) {
    if (address == null) return '';
    return (address['city'] as String?) ??
        (address['town'] as String?) ??
        (address['village'] as String?) ??
        '';
  }
}
