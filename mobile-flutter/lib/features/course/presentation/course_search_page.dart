// CourseSearchPage — KAN-279 (S9). The route-level widget that
// wires production dependencies into `CourseSearchScreen` and
// handles navigation to the map screen on result tap.
//
// **Why a separate file from `course_search_screen.dart`:** the
// screen widget is unit-testable in isolation because every
// dependency is constructor-injected. The page wires the real
// `CourseCacheClient` (KAN-S5), the real `LocationService`
// (KAN-S4), the real `logger`, and the `LocalFixtureSearchSource`
// fallback for offline development. Splitting the wiring out keeps
// the screen test free of go_router and platform-channel
// dependencies.
//
// **Production behavior:**
// 1. The route loads location permission status from
//    `LocationService`. The "Use my location" toggle is enabled
//    only when permission is granted.
// 2. The search callback first hits `CourseCacheClient.searchManifest`.
//    If the configured endpoint is empty (no `--dart-define`s),
//    or the call returns empty, the search falls back to a
//    locally-defined demo entry pointing at the Sharp Park
//    fixture so engineers without a real cache endpoint can
//    still tap into the map.
// 3. On result tap, `CourseCacheClient.fetchCourse(cacheKey)`
//    fetches the full `NormalizedCourse`. The result is passed
//    to the `/course/map` route via go_router's `extra` param —
//    no global state, no router-level data store.
// 4. The Sharp Park demo entry uses a sentinel `cacheKey` of
//    `__local_fixture_sharp_park__`. The page short-circuits on
//    that value and loads the asset directly instead of going
//    through `CourseCacheClient`.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';

import '../../../core/courses/course_cache_client.dart';
import '../../../core/courses/course_search_results.dart';
import '../../../core/courses/http_transport.dart';
import '../../../core/location/geolocator_location_service.dart';
import '../../../core/location/location_service.dart';
import '../../../core/logging/logging_service.dart';
import '../../../core/routing/app_router.dart';
import '../../../main.dart' show logger;
import '../../../models/normalized_course.dart';
import 'course_search_screen.dart';

/// Sentinel cache key the route uses to detect "open the
/// bundled fixture" instead of fetching from the server cache.
/// Documented as a constant so the page widget and the route
/// handler reference the same value.
const String kLocalFixtureCacheKey = '__local_fixture_sharp_park__';

/// Demo entry surfaced in the idle state. Visible in dev runs
/// without a configured course-cache endpoint so the map screen
/// is still reachable.
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
    this.loggerOverride,
  });

  /// Optional injection seam for tests / Riverpod-future. The
  /// route uses `GeolocatorLocationService()` and a default
  /// `CourseCacheClient` built from `--dart-define`s.
  final LocationService? locationService;
  final CourseCacheClient? cacheClient;
  final LoggingService? loggerOverride;

  @override
  State<CourseSearchPage> createState() => _CourseSearchPageState();
}

class _CourseSearchPageState extends State<CourseSearchPage> {
  late final LocationService _locationService =
      widget.locationService ?? GeolocatorLocationService();
  late final CourseCacheClient _cacheClient =
      widget.cacheClient ?? _buildDefaultClient();
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

  static CourseCacheClient _buildDefaultClient() {
    const endpoint =
        String.fromEnvironment('COURSE_CACHE_ENDPOINT', defaultValue: '');
    const apiKey =
        String.fromEnvironment('COURSE_CACHE_API_KEY', defaultValue: '');
    return CourseCacheClient(
      baseUrl: endpoint,
      apiKey: apiKey,
      transport: DartIoHttpTransport(),
    );
  }

  Future<CourseSearchOutcome> _onSearch(String query) async {
    // If the cache client is unconfigured, short-circuit to the
    // demo entry only when the query roughly matches Sharp Park.
    // Anything else returns "no results" so the user sees the
    // proper empty state instead of a misleading single result.
    if (_cacheClient.baseUrl.isEmpty || _cacheClient.apiKey.isEmpty) {
      final lower = query.toLowerCase();
      if (lower.contains('sharp') || lower.contains('park')) {
        return const CourseSearchOutcome(entries: [kSharpParkDemoEntry]);
      }
      return const CourseSearchOutcome(entries: []);
    }

    try {
      final results = await _cacheClient.searchManifest(query: query);
      if (results.isEmpty) return CourseSearchOutcome.empty;
      return CourseSearchOutcome(entries: results);
    } on CourseClientException catch (e) {
      return CourseSearchOutcome(entries: const [], error: e.message);
    } catch (e) {
      return CourseSearchOutcome(entries: const [], error: '$e');
    }
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
      } else {
        course = await _cacheClient.fetchCourse(entry.cacheKey);
        if (course == null) {
          errorMessage = 'Course not found in cache.';
        }
      }
    } catch (e) {
      errorMessage = '$e';
    }

    if (!mounted) return;
    setState(() => _navigatingToMap = false);

    if (course != null) {
      // Navigate to the map route with the course as `extra`.
      // The map route reads it from `GoRouterState.extra`.
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
      logger: _logger,
      locationGranted: _locationGranted,
      initialDemoEntry: kSharpParkDemoEntry,
    );
  }
}
