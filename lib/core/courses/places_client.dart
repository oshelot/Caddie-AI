// PlacesClient — Flutter wrapper around the KAN-296 Lambda routes:
//
//   GET /places/autocomplete?q=<input>
//   GET /places/search?q=<query>&lat=&lon=
//
// Both routes proxy Google Places (Autocomplete + Text Search New)
// behind the existing course-cache Lambda's `x-api-key` auth so the
// Google API key never has to live on-device. See KAN-296 and
// `infrastructure/course-cache/lambda_function.py` for the server side.
//
// **Why this exists:** the iOS course search uses Apple MapKit
// (`MKLocalSearchCompleter` for the city field, `MKLocalSearch` as one
// of three parallel search sources). Neither MapKit API has a Flutter
// equivalent, so the Flutter port replaces them with Google Places via
// this proxy. The autocomplete drives the city-field suggestions
// (KAN-29 port); the text search becomes one of the three parallel
// sources in the `CourseSearchPage` fan-out, mirroring iOS
// `CourseViewModel.searchCourses` line-for-line.
//
// **Endpoint configuration:** the same `--dart-define` values that
// configure `CourseCacheClient` work here — `COURSE_CACHE_ENDPOINT`
// and `COURSE_CACHE_API_KEY`. The page wrapper builds both clients
// from the same defines so there's only one place to set them.

import 'dart:convert';

import 'course_search_results.dart';
import 'http_transport.dart';

/// One Google Places autocomplete row. Used by the city field's
/// suggestion list. `description` is the full
/// "Denver, CO, USA"-style string used as the tap-to-fill value.
class PlaceAutocompleteSuggestion {
  const PlaceAutocompleteSuggestion({
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  final String description;
  final String mainText;
  final String secondaryText;

  factory PlaceAutocompleteSuggestion.fromJson(Map<String, dynamic> json) {
    return PlaceAutocompleteSuggestion(
      description: json['description'] as String? ?? '',
      mainText: json['mainText'] as String? ?? '',
      secondaryText: json['secondaryText'] as String? ?? '',
    );
  }
}

class PlacesClient {
  PlacesClient({
    required this.baseUrl,
    required this.apiKey,
    required this.transport,
    Duration timeout = const Duration(seconds: 5),
  }) : _timeout = timeout;

  /// Same base URL as `CourseCacheClient` (the routes live on the
  /// same Lambda + API Gateway).
  final String baseUrl;

  /// Same `x-api-key` value as `CourseCacheClient`.
  final String apiKey;

  final HttpTransport transport;
  final Duration _timeout;

  /// True when both `baseUrl` and `apiKey` are configured. Used by
  /// the page wrapper to short-circuit autocomplete + Places search
  /// in dev runs without `--dart-define`s.
  bool get isConfigured => baseUrl.isNotEmpty && apiKey.isNotEmpty;

  /// City autocomplete. Returns up to 5 suggestions, or an empty
  /// list on any failure (the screen treats empty as "no
  /// suggestions" and hides the dropdown).
  Future<List<PlaceAutocompleteSuggestion>> autocomplete(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty || !isConfigured) return const [];

    final url = Uri.parse('$baseUrl/places/autocomplete')
        .replace(queryParameters: {'q': trimmed});
    try {
      final response = await transport.send(HttpRequestLike(
        method: 'GET',
        url: url,
        headers: {
          'x-api-key': apiKey,
          'Accept': 'application/json',
        },
        timeout: _timeout,
      ));
      if (!response.isSuccess) return const [];
      return _parseAutocomplete(response.body);
    } catch (_) {
      return const [];
    }
  }

  /// Golf-course text search. Replaces the iOS `MKLocalSearch` pass.
  /// Returns an empty list on failure so the merger still has the
  /// other two sources to work with.
  Future<List<CourseSearchEntry>> searchCourses(
    String query, {
    double? latitude,
    double? longitude,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || !isConfigured) return const [];

    final params = <String, String>{'q': trimmed};
    if (latitude != null && longitude != null) {
      params['lat'] = latitude.toStringAsFixed(4);
      params['lon'] = longitude.toStringAsFixed(4);
    }
    final url =
        Uri.parse('$baseUrl/places/search').replace(queryParameters: params);

    try {
      final response = await transport.send(HttpRequestLike(
        method: 'GET',
        url: url,
        headers: {
          'x-api-key': apiKey,
          'Accept': 'application/json',
        },
        timeout: _timeout,
      ));
      if (!response.isSuccess) return const [];
      return _parseSearch(response.body);
    } catch (_) {
      return const [];
    }
  }

  List<PlaceAutocompleteSuggestion> _parseAutocomplete(String body) {
    final raw = jsonDecode(body);
    if (raw is! Map) return const [];
    final list = raw['suggestions'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => PlaceAutocompleteSuggestion.fromJson(
              m.cast<String, dynamic>(),
            ))
        .toList(growable: false);
  }

  List<CourseSearchEntry> _parseSearch(String body) {
    final raw = jsonDecode(body);
    if (raw is! Map) return const [];
    final list = raw['results'];
    if (list is! List) return const [];

    final out = <CourseSearchEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final name = map['name'] as String? ?? '';
      final lat = (map['lat'] as num?)?.toDouble();
      final lon = (map['lon'] as num?)?.toDouble();
      if (name.isEmpty || lat == null || lon == null) continue;

      final id = map['id'] as String? ?? '';
      final cacheKey = id.isNotEmpty ? 'gplaces:$id' : 'gplaces:$name';

      out.add(CourseSearchEntry(
        cacheKey: cacheKey,
        name: name,
        city: map['city'] as String? ?? '',
        state: map['state'] as String? ?? '',
        latitude: lat,
        longitude: lon,
        source: CourseSearchSource.googlePlaces,
        formattedAddress: map['formattedAddress'] as String?,
      ));
    }
    return out;
  }
}
