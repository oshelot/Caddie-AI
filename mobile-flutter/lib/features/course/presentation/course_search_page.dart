// CourseSearchPage — KAN-279 (S9), updated for the KAN-296 / KAN-29
// 3-source search rewrite.
//
// **What changed in the rewrite:** the page wrapper now mirrors the
// iOS `CourseViewModel.searchCourses` flow exactly. On Search:
//
//   1. Fans out to three sources in parallel:
//      - `NominatimClient.searchCourses(query+city)` (OSM geocoder)
//      - `PlacesClient.searchCourses(query+city)` (Google Places via
//        the KAN-296 Lambda proxy — replaces iOS MKLocalSearch)
//      - `CourseCacheClient.searchManifest(query)` (server cache
//        manifest metadata, KAN-275)
//   2. Merges the three lists via `CourseSearchMerger`:
//      Nominatim first, then non-duplicate Places rows, then overlay
//      Google-Places-corrected city/state from the manifest.
//   3. Returns the merged outcome to the screen.
//
// On result tap, the page wrapper resolves the entry into a full
// `NormalizedCourse`:
//   - **manifest source:** the row's cacheKey IS a server cache key,
//     fetch directly via `cacheClient.fetchCourse(cacheKey)`.
//   - **nominatim / googlePlaces source:** synthesize the server
//     cache key from the row's name (same rule as iOS
//     `NormalizedCourse.serverCacheKey`) and try the cache. If 404,
//     show a "not yet cached" snackbar — the Overpass ingestion
//     pipeline that builds new cache entries is iOS-only today and
//     will land in a future Flutter story.
//
// The city autocomplete is wired to `PlacesClient.autocomplete`. The
// screen owns the debounce; this page just hands over the callback.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';

import '../../../core/courses/course_cache_client.dart';
import '../../../core/courses/course_search_merger.dart';
import '../../../core/courses/course_search_results.dart';
import '../../../core/courses/http_transport.dart';
import '../../../core/courses/nominatim_client.dart';
import '../../../core/courses/places_client.dart';
import '../../../core/location/geolocator_location_service.dart';
import '../../../core/location/location_service.dart';
import '../../../core/logging/logging_service.dart';
import '../../../core/routing/app_router.dart';
import '../../../main.dart' show logger;
import '../../../models/normalized_course.dart';
import 'course_search_screen.dart';

/// Sentinel cache key the route uses to detect "open the bundled
/// fixture" instead of fetching from the server cache.
const String kLocalFixtureCacheKey = '__local_fixture_sharp_park__';

/// Demo entry surfaced in the idle state. Visible in dev runs without
/// a configured course-cache endpoint so the map screen is still
/// reachable.
const CourseSearchEntry kSharpParkDemoEntry = CourseSearchEntry(
  cacheKey: kLocalFixtureCacheKey,
  name: 'Sharp Park Golf Course (demo)',
  city: 'Pacifica',
  state: 'CA',
  latitude: 37.6244,
  longitude: -122.4885,
);

class CourseSearchPage extends StatefulWidget {
  const CourseSearchPage({
    super.key,
    this.locationService,
    this.cacheClient,
    this.nominatimClient,
    this.placesClient,
    this.merger,
    this.loggerOverride,
  });

  /// Optional injection seams for tests / Riverpod-future. Production
  /// builds the real implementations from `--dart-define`s + the
  /// shared `DartIoHttpTransport`.
  final LocationService? locationService;
  final CourseCacheClient? cacheClient;
  final NominatimClient? nominatimClient;
  final PlacesClient? placesClient;
  final CourseSearchMerger? merger;
  final LoggingService? loggerOverride;

  @override
  State<CourseSearchPage> createState() => _CourseSearchPageState();
}

class _CourseSearchPageState extends State<CourseSearchPage> {
  late final HttpTransport _transport = DartIoHttpTransport();
  late final LocationService _locationService =
      widget.locationService ?? GeolocatorLocationService();
  late final CourseCacheClient _cacheClient =
      widget.cacheClient ?? _buildDefaultCacheClient();
  late final NominatimClient _nominatimClient =
      widget.nominatimClient ?? NominatimClient(transport: _transport);
  late final PlacesClient _placesClient =
      widget.placesClient ?? _buildDefaultPlacesClient();
  late final CourseSearchMerger _merger =
      widget.merger ?? const CourseSearchMerger();
  late final LoggingService _logger = widget.loggerOverride ?? logger;

  bool _locationGranted = false;
  bool _checkingLocation = true;
  bool _navigatingToMap = false;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    try {
      final status = await _locationService.permissionStatus();
      if (!mounted) return;
      setState(() {
        _locationGranted = status == LocationPermission.granted;
        _checkingLocation = false;
      });
    } catch (_) {
      // Platform plugin unavailable (e.g. unit tests). Treat as
      // not-granted; the search-by-name path still works.
      if (mounted) {
        setState(() {
          _locationGranted = false;
          _checkingLocation = false;
        });
      }
    }
  }

  CourseCacheClient _buildDefaultCacheClient() {
    const endpoint =
        String.fromEnvironment('COURSE_CACHE_ENDPOINT', defaultValue: '');
    const apiKey =
        String.fromEnvironment('COURSE_CACHE_API_KEY', defaultValue: '');
    return CourseCacheClient(
      baseUrl: endpoint,
      apiKey: apiKey,
      transport: _transport,
    );
  }

  PlacesClient _buildDefaultPlacesClient() {
    const endpoint =
        String.fromEnvironment('COURSE_CACHE_ENDPOINT', defaultValue: '');
    const apiKey =
        String.fromEnvironment('COURSE_CACHE_API_KEY', defaultValue: '');
    return PlacesClient(
      baseUrl: endpoint,
      apiKey: apiKey,
      transport: _transport,
    );
  }

  /// The 3-source fan-out. Mirrors iOS `CourseViewModel.searchCourses`.
  Future<CourseSearchOutcome> _onSearch(String query, String city) async {
    // Dev-mode short-circuit: when the cache client is unconfigured,
    // every source is unreachable. Surface the Sharp Park demo entry
    // so engineers without --dart-define values can still reach the
    // map screen.
    if (_cacheClient.baseUrl.isEmpty || _cacheClient.apiKey.isEmpty) {
      final lower = query.toLowerCase();
      if (lower.contains('sharp') || lower.contains('park')) {
        return const CourseSearchOutcome(entries: [kSharpParkDemoEntry]);
      }
      return const CourseSearchOutcome(entries: []);
    }

    // The iOS code concatenates the city onto the query string for
    // both Nominatim and MapKit (CourseViewModel.swift:78-79). The
    // manifest search uses the bare query — name-only is what the
    // server-side fuzzy-name index is built for.
    final searchTerm = city.isEmpty ? query : '$query $city';

    try {
      final results = await Future.wait([
        _nominatimClient.searchCourses(searchTerm),
        _placesClient.searchCourses(searchTerm),
        _cacheClient.searchManifest(query: query),
      ]);
      final nominatim = results[0];
      final places = results[1];
      final manifest = results[2];

      final merged = _merger.merge(
        nominatim: nominatim,
        googlePlaces: places,
        manifestEntries: manifest,
      );
      if (merged.isEmpty) return CourseSearchOutcome.empty;
      return CourseSearchOutcome(entries: merged);
    } on CourseClientException catch (e) {
      return CourseSearchOutcome(entries: const [], error: e.message);
    } catch (e) {
      return CourseSearchOutcome(entries: const [], error: '$e');
    }
  }

  Future<List<PlaceAutocompleteSuggestion>> _onCityAutocomplete(
      String input) async {
    if (!_placesClient.isConfigured) return const [];
    return _placesClient.autocomplete(input);
  }

  Future<void> _onSelectCourse(CourseSearchEntry entry) async {
    if (_navigatingToMap) return;
    setState(() => _navigatingToMap = true);

    NormalizedCourse? course;
    String? errorMessage;
    try {
      if (entry.cacheKey == kLocalFixtureCacheKey) {
        // Bundled fixture path — no network required.
        final raw =
            await rootBundle.loadString('assets/fixtures/sharp_park.json');
        course = NormalizedCourse.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } else if (entry.source == CourseSearchSource.manifest) {
        // Manifest entries carry a real server cache key — fetch directly.
        course = await _cacheClient.fetchCourse(entry.cacheKey);
        if (course == null) {
          errorMessage = 'Course not found in cache.';
        }
      } else {
        // Nominatim / Google Places entry. The cacheKey is synthesized;
        // derive a real server cache key from the name and try the
        // cache. If it's a miss, the course hasn't been ingested yet —
        // the Overpass ingestion pipeline that builds new cache entries
        // is iOS-only today; the user has to use a manifest result.
        final cacheKey = NormalizedCourse.serverCacheKey(entry.name);
        course = await _cacheClient.fetchCourse(cacheKey);
        if (course == null) {
          errorMessage =
              '${entry.name} isn\u2019t in the shared cache yet. '
              'Pick a result that already shows in the cache, or check '
              'back later.';
        }
      }
    } catch (e) {
      errorMessage = '$e';
    }

    if (!mounted) return;
    setState(() => _navigatingToMap = false);

    if (course != null) {
      // ignore: use_build_context_synchronously
      context.push(AppRoutes.courseMap, extra: course);
      return;
    }

    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorMessage ?? 'Failed to open course')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingLocation) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return CourseSearchScreen(
      onSearch: _onSearch,
      onSelectCourse: _onSelectCourse,
      onCityAutocomplete: _onCityAutocomplete,
      logger: _logger,
      locationGranted: _locationGranted,
      initialDemoEntry: kSharpParkDemoEntry,
    );
  }
}
