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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/courses/course_cache_client.dart';
import '../../../core/courses/course_cache_repository.dart';
import '../../../core/courses/course_matcher.dart';
import '../../../core/courses/course_normalizer.dart';
import 'course_picker_dialog.dart';
import '../../../core/courses/course_search_merger.dart';
import '../../../core/courses/course_search_results.dart';
import '../../../core/courses/golf_course_api_client.dart';
import '../../../core/courses/http_transport.dart';
import '../../../core/courses/nominatim_client.dart';
import '../../../core/courses/osm_parser.dart';
import '../../../core/courses/overpass_client.dart';
import '../../../core/courses/places_client.dart';

import '../../../core/logging/log_event.dart';
import '../../../main.dart' show adService;
import '../../../core/geo/geo.dart';
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

/// Debug log file for multi-course diagnostics. Written to the
/// app's documents directory so it can be pulled from the device
/// via `adb pull /data/data/com.caddieai.mobile/app_flutter/multi_course_debug.log`.
File? _debugLogFile;

Future<void> _debugLog(String message) async {
  // ignore: avoid_print
  print(message);
  try {
    _debugLogFile ??= File(
      '${(await getApplicationDocumentsDirectory()).path}/multi_course_debug.log',
    );
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    await _debugLogFile!.writeAsString(
      '[$timestamp] $message\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

class CourseSearchPage extends StatefulWidget {
  const CourseSearchPage({
    super.key,
    this.locationService,
    this.cacheClient,
    this.nominatimClient,
    this.placesClient,
    this.merger,
    this.loggerOverride,
    this.cacheRepository,
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

  /// Optional disk-cache repository. Production builds the default
  /// `CourseCacheRepository()` which talks to the open Hive boxes.
  /// The Saved tab + Favorites quick-list both consume this.
  final CourseCacheRepository? cacheRepository;

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
  late final CourseCacheRepository? _cacheRepository =
      widget.cacheRepository ?? _safeBuildRepository();
  late final FavoritesController? _favoritesController = (() {
    final repo = _cacheRepository;
    if (repo == null) return null;
    return FavoritesController(
      listSaved: repo.listSaved,
      isFavorite: repo.isFavorite,
      toggleFavorite: repo.toggleFavorite,
      deleteCourse: repo.evict,
    );
  })();

  /// Defensive constructor that returns null if Hive isn't open
  /// (unit-test runtime). Production always has the boxes open by
  /// the time the route builds — see main.dart's startup sequence.
  static CourseCacheRepository? _safeBuildRepository() {
    try {
      return CourseCacheRepository();
    } catch (_) {
      return null;
    }
  }

  bool _locationGranted = false;
  bool _checkingLocation = true;
  bool _navigatingToMap = false;
  bool _downloadComplete = false;
  String? _loadingJoke;
  Timer? _pendingCheckTimer;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    // Poll for pending multi-course ingestions every 10 seconds.
    _pendingCheckTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _resolvePendingEntries(),
    );
  }

  @override
  void dispose() {
    _pendingCheckTimer?.cancel();
    super.dispose();
  }

  /// Checks the server cache for any pending multi-course
  /// facilities. If the backend has finished processing, clears
  /// the pending marker so the Saved tab updates automatically.
  Future<void> _resolvePendingEntries() async {
    final repo = _cacheRepository;
    if (repo == null) return;

    final saved = repo.listSaved();
    final pending = saved.where((e) => e.isPending).toList();
    if (pending.isEmpty) return;

    for (final entry in pending) {
      try {
        final manifest = await _cacheClient.searchManifest(
          query: entry.name,
        );
        final facilityPrefix = '${entry.name} - ';
        final subEntries = manifest
            .where((e) => e.name.startsWith(facilityPrefix))
            .toList();
        if (subEntries.length >= 2) {
          await repo.removePending(entry.name);
          _debugLog('PENDING: resolved ${entry.name} — '
              '${subEntries.length} sub-courses ready');
        }
      } catch (_) {}
    }

    // Refresh UI if anything changed.
    if (mounted) setState(() {});
  }

  Future<void> _checkLocationPermission() async {
    try {
      var status = await _locationService.permissionStatus();
      // If not yet determined, request permission now so the iOS
      // system prompt fires and the app appears in Settings.
      if (status == LocationPermission.notDetermined ||
          status == LocationPermission.denied) {
        status = await _locationService.requestPermission();
      }
      if (!mounted) return;
      setState(() {
        _locationGranted = status == LocationPermission.granted;
        _checkingLocation = false;
      });
    } catch (_) {
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
    // KAN-195: preload interstitial ad so it's ready when user taps
    // a search result.
    adService.loadInterstitial();

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

  static const _golfApiKey =
      String.fromEnvironment('GOLF_COURSE_API_KEY', defaultValue: '');

  static const _llmProxyEndpoint =
      String.fromEnvironment('LLM_PROXY_ENDPOINT', defaultValue: '');
  static const _llmProxyApiKey =
      String.fromEnvironment('LLM_PROXY_API_KEY', defaultValue: '');

  Future<void> _fetchJoke(String courseName) async {
    if (_llmProxyEndpoint.isEmpty) return;
    try {
      final response = await _transport.send(HttpRequestLike(
        method: 'POST',
        url: Uri.parse('${_llmProxyEndpoint}joke'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _llmProxyApiKey,
        },
        body: jsonEncode({
          'courseName': courseName,
        }),
        timeout: const Duration(seconds: 5),
      ));
      if (response.isSuccess) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final joke = data['joke'] as String? ?? '';
        if (joke.isNotEmpty && mounted) {
          setState(() => _loadingJoke = joke);
        }
      }
    } catch (_) {
      // Joke fetch failed — no big deal, spinner continues.
    }
  }

  GolfCourseApiClient? _buildGolfApi() {
    if (_golfApiKey.isEmpty) return null;
    return GolfCourseApiClient(apiKey: _golfApiKey, transport: _transport);
  }

  /// Sanity-check each hole's lineOfPlay against its expected
  /// yardage (from Golf Course API). If the OSM line is obviously
  /// too short (< 50% of expected, or fewer than 2 points), replace
  /// it with a straight line from the tee polygon's centroid to
  /// the green polygon's centroid.
  ///
  /// Straight tee→green isn't perfect for dogleg holes, but it's
  /// always in the correct general direction, and vastly better
  /// than a bogus fragment of OSM geometry that doesn't reach the
  /// green.
  NormalizedCourse _repairShortLinesOfPlay(NormalizedCourse course) {
    final repairedHoles = <NormalizedHole>[];
    var repairs = 0;
    for (final hole in course.holes) {
      final tees = hole.teeAreas;
      final green = hole.green;
      final lop = hole.lineOfPlay;

      // We can only synthesize a line if we have both a tee and
      // a green. Without those, leave the hole alone.
      if (tees.isEmpty || green == null) {
        repairedHoles.add(hole);
        continue;
      }

      // Longest yardage across tees is our expected hole length.
      int expectedYards = 0;
      for (final y in hole.yardages.values) {
        if (y > expectedYards) expectedYards = y;
      }
      if (expectedYards == 0) {
        repairedHoles.add(hole);
        continue;
      }

      // Measure the OSM line's length (haversine segment sum → yards).
      double measuredMeters = 0;
      if (lop != null && lop.points.length >= 2) {
        for (var i = 1; i < lop.points.length; i++) {
          measuredMeters += haversineMeters(lop.points[i - 1], lop.points[i]);
        }
      }
      final measuredYards = metersToYards(measuredMeters);

      // Flag as bad if no line, too few points, or < 50% expected
      // length.
      final tooShort = measuredYards < expectedYards * 0.5;
      final tooFewPoints = lop == null || lop.points.length < 2;
      if (!tooShort && !tooFewPoints) {
        repairedHoles.add(hole);
        continue;
      }

      // Synthesize: longest-yardage tee → green centroid.
      final greenCentroid = green.centroid;
      // Pick the tee farthest from the green that's still within a
      // plausible distance (1.5x expected yardage). Tees farther
      // than that are misassociated (e.g., combined-scorecard tees
      // from the other end of the property).
      final maxTeeDist = expectedYards > 0
          ? expectedYards * 0.9144 * 1.5  // yards → meters × 1.5
          : 600.0;
      LngLat? bestTee;
      double bestDist = 0;
      for (final tee in tees) {
        final c = tee.centroid;
        if (c == null || greenCentroid == null) continue;
        final d = haversineMeters(c, greenCentroid);
        if (d > bestDist && d <= maxTeeDist) {
          bestDist = d;
          bestTee = c;
        }
      }
      if (bestTee == null || greenCentroid == null) {
        repairedHoles.add(hole);
        continue;
      }

      repairedHoles.add(NormalizedHole(
        number: hole.number,
        par: hole.par,
        strokeIndex: hole.strokeIndex,
        yardages: hole.yardages,
        teeAreas: hole.teeAreas,
        lineOfPlay: LineString([bestTee, greenCentroid]),
        green: hole.green,
        pin: hole.pin,
        bunkers: hole.bunkers,
        water: hole.water,
      ));
      repairs++;

      // Queue for human review → eventual OSM contribution.
      _cacheClient.submitCorrection({
        'facilityName': course.name.split(' - ').first,
        'courseName': course.name.contains(' - ')
            ? course.name.split(' - ').last
            : course.name,
        'holeNumber': hole.number,
        'par': hole.par,
        'expectedYards': expectedYards,
        'measuredYards': measuredYards.round(),
        'original': {
          'lineOfPlay': lop?.points
              .map((p) => [p.lon, p.lat])
              .toList(growable: false),
        },
        'corrected': {
          'lineOfPlay': [
            [bestTee.lon, bestTee.lat],
            [greenCentroid.lon, greenCentroid.lat],
          ],
        },
        'greenCentroid': [greenCentroid.lon, greenCentroid.lat],
        'teeCentroid': [bestTee.lon, bestTee.lat],
      }).ignore();
    }

    if (repairs > 0) {
      _debugLog('MULTI: repaired $repairs short line(s)-of-play '
          'in ${course.name}');
    }

    return NormalizedCourse(
      id: course.id,
      name: course.name,
      city: course.city,
      state: course.state,
      centroid: course.centroid,
      holes: repairedHoles,
      teeNames: course.teeNames,
      teeYardageTotals: course.teeYardageTotals,
    );
  }

  /// Enriches a course with tee/yardage data from the Golf Course
  /// API. Mirrors iOS enrichWithScorecardData(). Returns the
  /// enriched course, or the original if enrichment fails.
  ///
  /// When [preMatchedDetail] is provided (multi-course matching),
  /// skips the search call and uses the pre-matched result directly.
  Future<NormalizedCourse> _enrichWithScorecardData(
    NormalizedCourse course,
    String searchName, {
    GolfCourseApiResult? preMatchedDetail,
  }) async {
    try {
      GolfCourseApiResult? detail = preMatchedDetail;
      if (detail == null) {
        final golfApi = _buildGolfApi();
        if (golfApi == null) return course;
        // ignore: avoid_print
        print('ENRICH: searching Golf Course API for "$searchName"');
        final results = await golfApi.searchCourses(searchName);
        if (results.isEmpty) {
          // ignore: avoid_print
          print('ENRICH: no results');
          return course;
        }

        // Get the detail for the first match (has full tee data).
        detail = await golfApi.getCourse(results.first.id);
      }
      if (detail == null || detail.tees.isEmpty) {
        // ignore: avoid_print
        print('ENRICH: no tee data');
        return course;
      }

      // Build teeNames + teeYardageTotals + per-hole yardages.
      final teeNames = <String>[];
      final teeYardageTotals = <String, int>{};
      for (final entry in detail.tees.entries) {
        final tee = entry.value;
        teeNames.add(tee.teeName);
        if (tee.totalYards > 0) {
          teeYardageTotals[tee.teeName] = tee.totalYards;
        }
      }
      // Sort by total yardage descending (longest first).
      teeNames.sort((a, b) =>
          (teeYardageTotals[b] ?? 0).compareTo(teeYardageTotals[a] ?? 0));

      // Merge per-hole yardages + par + stroke index.
      final enrichedHoles = <NormalizedHole>[];
      for (final hole in course.holes) {
        final yardages = <String, int>{...hole.yardages};
        var par = hole.par;
        int? strokeIndex = hole.strokeIndex;

        for (final teeEntry in detail.tees.entries) {
          final tee = teeEntry.value;
          if (hole.number - 1 < tee.holes.length) {
            final apiHole = tee.holes[hole.number - 1];
            yardages[tee.teeName] = apiHole.yardage;
            if (par == 0) par = apiHole.par;
            strokeIndex ??= apiHole.handicap;
          }
        }

        enrichedHoles.add(NormalizedHole(
          number: hole.number,
          par: par,
          strokeIndex: strokeIndex,
          yardages: yardages,
          teeAreas: hole.teeAreas,
          lineOfPlay: hole.lineOfPlay,
          green: hole.green,
          pin: hole.pin,
          bunkers: hole.bunkers,
          water: hole.water,
        ));
      }

      // ignore: avoid_print
      print('ENRICH: found ${teeNames.length} tees: $teeNames');

      return NormalizedCourse(
        id: course.id,
        name: course.name,
        city: course.city,
        state: course.state,
        centroid: course.centroid,
        holes: enrichedHoles,
        teeNames: teeNames,
        teeYardageTotals: teeYardageTotals,
      );
    } catch (e) {
      // ignore: avoid_print
      print('ENRICH: failed: $e');
      return course;
    }
  }

  Future<List<PlaceAutocompleteSuggestion>> _onCityAutocomplete(
      String input) async {
    if (!_placesClient.isConfigured) return const [];
    return _placesClient.autocomplete(input);
  }

  Future<void> _onSelectCourse(CourseSearchEntry entry) async {
    if (_navigatingToMap) return;

    // Handle tapping a pending multi-course entry from Saved.
    // Check the server cache — if the RAG backend finished,
    // clear the pending marker and proceed normally.
    if (entry.isPending) {
      setState(() => _navigatingToMap = true);
      final manifest = await _cacheClient.searchManifest(
        query: entry.name,
      );
      final facilityPrefix = '${entry.name} - ';
      final subEntries = manifest
          .where((e) => e.name.startsWith(facilityPrefix))
          .toList();
      if (subEntries.length >= 2) {
        // Ready! Download sub-courses locally so they appear in Saved,
        // THEN clear pending and re-run as a normal tap.
        final repo = _cacheRepository;
        if (repo != null) {
          for (final sub in subEntries) {
            final subKey = NormalizedCourse.serverCacheKey(sub.name);
            if (repo.load(subKey) == null) {
              final subCourse = await _cacheClient.fetchCourse(sub.cacheKey);
              if (subCourse != null) {
                try { await repo.save(subKey, subCourse); } catch (_) {}
              }
            }
          }
        }
        repo?.removePending(entry.name);
        setState(() => _navigatingToMap = false);
        _onSelectCourse(CourseSearchEntry(
          cacheKey: entry.cacheKey.replaceFirst('pending:', ''),
          name: entry.name,
          city: entry.city,
          state: entry.state,
          latitude: entry.latitude,
          longitude: entry.longitude,
        ));
        return;
      }
      // Not ready yet.
      setState(() => _navigatingToMap = false);
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still preparing — try again in a moment.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _navigatingToMap = true;
      _loadingJoke = null;
    });

    // KAN-195: Pro tier gets a joke, Free tier gets an interstitial
    // ad. Both run in parallel with the course download. The joke
    // is fetched from the LLM proxy; the ad was preloaded earlier.
    final isPro = !adService.bannerVisible;
    if (isPro) {
      _fetchJoke(entry.name).ignore();
    } else {
      adService.showInterstitialIfReady();
    }

    final totalSw = Stopwatch()..start();
    String source = 'overpass';
    NormalizedCourse? course;
    String? cacheKeyForSave;
    String? errorMessage;
    GolfCourseApiResult? matchedApiDetail;
    try {
      if (entry.cacheKey == kLocalFixtureCacheKey) {
        // Bundled fixture path — no network required, no save.
        final raw =
            await rootBundle.loadString('assets/fixtures/sharp_park.json');
        course = NormalizedCourse.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } else {
        // Step 1: Check local disk cache (instant, no network).
        cacheKeyForSave = NormalizedCourse.serverCacheKey(entry.name);
        final repo = _cacheRepository;
        if (repo != null) {
          final localSw = Stopwatch()..start();
          final cached = repo.load(cacheKeyForSave);
          localSw.stop();
          final localHit = cached != null;
          _logger.info(LogCategory.map, 'cache_check', metadata: {
            'latency': '${localSw.elapsedMilliseconds}',
            'cacheHit': '$localHit',
            'source': 'local',
            'courseName': entry.name,
          });
          if (cached != null) {
            course = cached.course;
            source = 'local';
            // ignore: avoid_print
            print('DOWNLOAD: local cache HIT for ${entry.name}');
          }
        }

        // Step 2: Fuzzy-search the server cache.
        if (course == null) {
          // ignore: avoid_print
          print('DOWNLOAD: trying server cache for ${entry.name}');
          final serverSw = Stopwatch()..start();
          course = await _cacheClient.searchFullCourse(
            query: entry.name,
            latitude: entry.latitude,
            longitude: entry.longitude,
          );
          serverSw.stop();
          final serverHit = course != null;
          _logger.info(LogCategory.map, 'cache_check', metadata: {
            'latency': '${serverSw.elapsedMilliseconds}',
            'cacheHit': '$serverHit',
            'source': 'server',
            'courseName': entry.name,
          });
          if (serverHit) {
            // If the server returned a sub-course (name contains " - "),
            // don't use it directly — let Step 2b handle multi-course.
            if (course!.name.contains(' - ') &&
                course.name.startsWith(entry.name)) {
              // ignore: avoid_print
              print('DOWNLOAD: server returned sub-course "${course.name}" — deferring to Step 2b');
              course = null;
            } else {
              source = 'server';
              // ignore: avoid_print
              print('DOWNLOAD: server cache HIT — ${course.holes.length} holes');
            }
          } else {
            // ignore: avoid_print
            print('DOWNLOAD: server cache MISS');
          }
        }

        // Step 2b: Check if server manifest has multiple sub-courses
        // for this facility (e.g., "Kennedy Golf Course - West",
        // "- Lind", "- Creek"). If so, load them all from the server
        // cache and show the picker — no Golf API call needed.
        if (course == null) {
          final manifest = await _cacheClient.searchManifest(
            query: entry.name,
          );
          // Find entries that look like sub-courses of this facility
          // (name starts with facility name + " - ").
          final facilityPrefix = '${entry.name} - ';
          final subEntries = manifest
              .where((e) => e.name.startsWith(facilityPrefix))
              .toList();
          if (subEntries.length >= 2) {
            _debugLog('MULTI: found ${subEntries.length} sub-courses in server cache');

            // Load each sub-course from server cache.
            final repo = _cacheRepository;
            final cachedSubCourses = <String, NormalizedCourse>{};
            final extractedCourses = <ExtractedCourse>[];
            for (final sub in subEntries) {
              final subName = sub.name.substring(facilityPrefix.length);
              // Try local cache first, then server.
              NormalizedCourse? subCourse;
              final subKey = NormalizedCourse.serverCacheKey(sub.name);
              if (repo != null) {
                final cached = repo.load(subKey);
                if (cached != null) subCourse = cached.course;
              }
              if (subCourse == null) {
                subCourse = await _cacheClient.fetchCourse(sub.cacheKey);
                // Save to local cache for next time.
                if (subCourse != null && repo != null) {
                  try { await repo.save(subKey, subCourse); } catch (_) {}
                }
              }
              if (subCourse != null) {
                cachedSubCourses[subName] = subCourse;
                extractedCourses.add(ExtractedCourse(
                  name: subName,
                  pars: subCourse.holes
                      .map((h) => h.par)
                      .toList(growable: false),
                ));
              }
            }

            if (extractedCourses.length >= 2) {
              // Show picker.
              if (!mounted) return;
              final picks = await showCoursePickerDialog(
                context: context,
                courses: extractedCourses,
              );
              if (picks == null || picks.isEmpty || !mounted) {
                setState(() {
                  _navigatingToMap = false;
                  _downloadComplete = false;
                });
                return;
              }

              // Combine selected sub-courses.
              final combinedHoles = <NormalizedHole>[];
              for (final pick in picks) {
                final sub = cachedSubCourses[pick.name];
                if (sub != null) {
                  for (final h in sub.holes) {
                    combinedHoles.add(NormalizedHole(
                      number: combinedHoles.length + 1,
                      par: h.par,
                      strokeIndex: h.strokeIndex,
                      yardages: h.yardages,
                      teeAreas: h.teeAreas,
                      lineOfPlay: h.lineOfPlay,
                      green: h.green,
                      pin: h.pin,
                      bunkers: h.bunkers,
                      water: h.water,
                    ));
                  }
                }
              }
              final combinedName = picks.length == 1
                  ? '${entry.name} - ${picks.first.name}'
                  : '${entry.name} - ${picks.map((p) => p.name).join(" + ")}';
              course = NormalizedCourse(
                id: 'multi_cached',
                name: combinedName,
                city: entry.city.isNotEmpty ? entry.city : null,
                state: entry.state.isNotEmpty ? entry.state : null,
                centroid: LngLat(entry.longitude, entry.latitude),
                holes: combinedHoles,
              );
              source = 'server';
              cacheKeyForSave = null;
              _debugLog('MULTI: combined from cache — ${combinedHoles.length} holes');
            }
          }
        }

        // Step 3: Check Golf API for multi-course facility.
        // Only runs if server cache didn't have sub-courses.
        // If 2+ courses, download ALL individually (with geometry
        // attempt), cache each, then show picker. The user's combo
        // selection is NOT cached — picker always re-prompts.
        if (course == null) {
          final golfApi = _buildGolfApi();
          List<ExtractedCourse>? extracted;
          if (golfApi != null) {
            final apiResults = await golfApi.searchCourses(entry.name);
            if (apiResults.length >= 2) {
              final details = await Future.wait(
                apiResults.take(6).map((r) => golfApi.getCourse(r.id)),
              );
              final apiDetails = details
                  .whereType<GolfCourseApiResult>()
                  .toList(growable: false);
              if (apiDetails.length >= 2) {
                extracted = CourseMatcher.extractCourses(apiDetails);
                if (extracted.length < 2) extracted = null;
              }
            }
          }

          if (extracted != null) {
            _debugLog('MULTI: ${extracted.length} courses: '
                '${extracted.map((e) => e.name).toList()}');

            // Check if sub-courses are in the server cache (from
            // a previous RAG ingestion). If so, show the picker.
            final manifest = await _cacheClient.searchManifest(
              query: entry.name,
            );
            final facilityPrefix = '${entry.name} - ';
            final subEntries = manifest
                .where((e) => e.name.startsWith(facilityPrefix))
                .toList();

            if (subEntries.length >= extracted.length) {
              // All sub-courses in server cache — load + picker.
              _debugLog('MULTI: ${subEntries.length} sub-courses in server cache');
              final repo = _cacheRepository;
              final cachedSubCourses = <String, NormalizedCourse>{};
              final extractedCourses = <ExtractedCourse>[];
              for (final sub in subEntries) {
                final subName = sub.name.substring(facilityPrefix.length);
                NormalizedCourse? subCourse;
                final subKey = NormalizedCourse.serverCacheKey(sub.name);
                if (repo != null) {
                  final cached = repo.load(subKey);
                  if (cached != null) subCourse = cached.course;
                }
                subCourse ??= await _cacheClient.fetchCourse(sub.cacheKey);
                if (subCourse != null) {
                  if (repo != null) {
                    try { await repo.save(subKey, subCourse); } catch (_) {}
                  }
                  cachedSubCourses[subName] = subCourse;
                  extractedCourses.add(ExtractedCourse(
                    name: subName,
                    pars: subCourse.holes
                        .map((h) => h.par)
                        .toList(growable: false),
                  ));
                }
              }

              // Remove pending marker if it exists.
              repo?.removePending(entry.name);

              if (extractedCourses.length >= 2) {
                if (!mounted) return;
                final picks = await showCoursePickerDialog(
                  context: context,
                  courses: extractedCourses,
                );
                if (picks == null || picks.isEmpty || !mounted) {
                  setState(() {
                    _navigatingToMap = false;
                    _downloadComplete = false;
                  });
                  return;
                }
                final combinedHoles = <NormalizedHole>[];
                for (final pick in picks) {
                  final sub = cachedSubCourses[pick.name];
                  if (sub != null) {
                    for (final h in sub.holes) {
                      combinedHoles.add(NormalizedHole(
                        number: combinedHoles.length + 1,
                        par: h.par,
                        strokeIndex: h.strokeIndex,
                        yardages: h.yardages,
                        teeAreas: h.teeAreas,
                        lineOfPlay: h.lineOfPlay,
                        green: h.green,
                        pin: h.pin,
                        bunkers: h.bunkers,
                        water: h.water,
                      ));
                    }
                  }
                }
                final combinedName = picks.length == 1
                    ? '${entry.name} - ${picks.first.name}'
                    : '${entry.name} - ${picks.map((p) => p.name).join(" + ")}';
                // Use teeNames/teeYardageTotals from the first picked
                // sub-course so the enrichment guard sees them and
                // doesn't re-enrich with the wrong Golf API result.
                final firstSub = cachedSubCourses[picks.first.name];
                course = NormalizedCourse(
                  id: 'multi_cached',
                  name: combinedName,
                  city: entry.city.isNotEmpty ? entry.city : null,
                  state: entry.state.isNotEmpty ? entry.state : null,
                  centroid: LngLat(entry.longitude, entry.latitude),
                  holes: combinedHoles,
                  teeNames: firstSub?.teeNames ?? const [],
                  teeYardageTotals: firstSub?.teeYardageTotals ?? const {},
                );
                source = 'server';
                cacheKeyForSave = null;
                _debugLog('MULTI: loaded from cache — ${combinedHoles.length} holes');
              }
            } else {
              // Not cached. Fire RAG ingestion (GPT-4o). The
              // backend handles EVERYTHING: Overpass, Golf API,
              // scorecard PDF search, satellite imagery, GPT-4o.
              // App just sends name + coordinates.
              _debugLog('MULTI: not cached — sending to RAG backend');

              // Save pending marker in local cache.
              final repo = _cacheRepository;
              repo?.savePending(
                entry.name,
                entry.city,
                entry.state,
                entry.latitude,
                entry.longitude,
              );

              // Fire RAG ingestion (fire-and-forget).
              _cacheClient
                  .requestRagIngestion(
                    entry.name,
                    entry.latitude,
                    entry.longitude,
                  )
                  .then((ok) => _debugLog(
                      'RAG: ingestion ${ok ? "accepted" : "failed"}'))
                  .ignore();

              if (!mounted) return;
              setState(() {
                _navigatingToMap = false;
                _downloadComplete = false;
              });
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'This is a multi-course facility. We\'re preparing '
                    'the course maps — check Saved in about 30 seconds.',
                  ),
                  duration: Duration(seconds: 5),
                ),
              );
              return;
            }
          }
        }

        // Step 3b: Standard single-course Overpass discovery.
        if (course == null) {
          // ignore: avoid_print
          print('DOWNLOAD: starting Overpass ingestion for ${entry.name}');
          try {
            final overpass = OverpassClient(_transport);
            const buffer = 0.015;
            final overpassResponse = await overpass.fetchCourseFeatures(
              entry.latitude - buffer,
              entry.longitude - buffer,
              entry.latitude + buffer,
              entry.longitude + buffer,
            );
            // ignore: avoid_print
            print('DOWNLOAD: Overpass returned ${overpassResponse.elements.length} elements');
            final features = OsmParser.parse(overpassResponse);
            // ignore: avoid_print
            print('DOWNLOAD: parsed ${features.holeLines.length} holes, '
                '${features.greens.length} greens, '
                '${features.tees.length} tees, '
                '${features.pins.length} pins');
            final normalizer = CourseNormalizer();
            course = normalizer.normalize(
              features: features,
              courseName: entry.name,
              osmCourseId: 'osm_${entry.latitude}_${entry.longitude}',
              city: entry.city.isNotEmpty ? entry.city : null,
              state: entry.state.isNotEmpty ? entry.state : null,
              facilityPoint: LngLat(entry.longitude, entry.latitude),
            );
            if (course != null && course.holes.isNotEmpty) {
              // ignore: avoid_print
              print('DOWNLOAD: normalized ${course.holes.length} holes');
            } else {
              course = null;
              // ignore: avoid_print
              print('DOWNLOAD: normalizer returned empty');
            }
          } catch (e, st) {
            // ignore: avoid_print
            print('DOWNLOAD: Overpass failed: $e');
            // ignore: avoid_print
            print('DOWNLOAD: stack: $st');
          }
        }

        if (course == null) {
          errorMessage =
              'Could not load ${entry.name}. The course may not '
              'have detailed mapping data in OpenStreetMap yet.';
        }
      }
    } catch (e) {
      errorMessage = '$e';
    }

    // Step 4: Enrich with Golf Course API tee/yardage data.
    // Mirrors iOS CourseViewModel.swift:978-1095
    // enrichWithScorecardData(). Non-blocking — if the API is
    // unavailable or the course isn't found, we proceed with
    // whatever data we have (geometry-only is still useful).
    if (course != null && course.teeNames.isEmpty) {
      course = await _enrichWithScorecardData(
        course,
        entry.name,
        preMatchedDetail: matchedApiDetail,
      );
    }

    // Step 5: Save to local disk cache AND upload to server cache.
    // Both happen AFTER enrichment so geometry + tee data are
    // included. The server upload is fire-and-forget so the next
    // user gets an instant cache hit with full data.
    final repo = _cacheRepository;
    if (course != null && cacheKeyForSave != null) {
      if (repo != null) {
        try {
          await repo.save(cacheKeyForSave, course);
        } catch (_) {}
      }
      // Upload enriched course to server cache (fire-and-forget).
      // Skip if zero holes have geometry — don't pollute the cache
      // with skeleton-only courses that would block future Overpass
      // downloads for every subsequent user.
      final hasAnyGeometry = course.holes.any(
        (h) => h.lineOfPlay != null || h.green != null,
      );
      if (hasAnyGeometry) {
        _cacheClient.putCourse(cacheKeyForSave, course).ignore();
      }
    }

    if (!mounted) return;

    if (course != null) {
      totalSw.stop();
      _logger.info(LogCategory.map, 'total_ingestion', metadata: {
        'latency': '${totalSw.elapsedMilliseconds}',
        'courseName': entry.name,
        'source': source,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      // Flash the green checkmark before navigating.
      setState(() => _downloadComplete = true);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() {
        _navigatingToMap = false;
        _downloadComplete = false;
      });
      // ignore: use_build_context_synchronously
      context.push(AppRoutes.courseMap, extra: course);
      return;
    }

    setState(() => _navigatingToMap = false);
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
    return Stack(
      children: [
        CourseSearchScreen(
          onSearch: _onSearch,
          onSelectCourse: _onSelectCourse,
          onCityAutocomplete: _onCityAutocomplete,
          logger: _logger,
          locationGranted: _locationGranted,
          initialDemoEntry: kSharpParkDemoEntry,
          favoritesController: _favoritesController,
          adService: adService,
        ),
        if (_navigatingToMap)
          Container(
            color: Colors.black87,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_downloadComplete)
                      const Icon(Icons.check_circle, color: Colors.green, size: 64)
                    else
                      const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      _downloadComplete ? 'Ready!' : 'Loading course\u2026',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Pro tier: show a golf joke while loading
                    if (_loadingJoke != null) ...[
                      const SizedBox(height: 24),
                      const Text(
                        '\u26f3',  // golf flag emoji
                        style: TextStyle(fontSize: 32),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _loadingJoke!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
