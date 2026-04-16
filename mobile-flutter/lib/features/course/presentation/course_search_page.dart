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

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
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

  GolfCourseApiClient? _buildGolfApi() {
    if (_golfApiKey.isEmpty) return null;
    return GolfCourseApiClient(apiKey: _golfApiKey, transport: _transport);
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
    setState(() => _navigatingToMap = true);

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

            // Check if all sub-courses are already cached locally.
            final repo = _cacheRepository;
            final cachedSubCourses = <String, NormalizedCourse>{};
            if (repo != null) {
              for (final ext in extracted) {
                final subKey = NormalizedCourse.serverCacheKey(
                    '${entry.name} - ${ext.name}');
                final cached = repo.load(subKey);
                if (cached != null) {
                  cachedSubCourses[ext.name] = cached.course;
                }
              }
            }

            final allCached =
                cachedSubCourses.length == extracted.length;
            _debugLog('MULTI: ${cachedSubCourses.length}/${extracted.length} cached locally');

            if (!allCached) {
              // Download ALL sub-courses. Try Overpass for geometry.
              ParsedFeatures? osmFeatures;
              try {
                final overpass = OverpassClient(_transport);
                const buffer = 0.015;
                final resp = await overpass.fetchCourseFeatures(
                  entry.latitude - buffer,
                  entry.longitude - buffer,
                  entry.latitude + buffer,
                  entry.longitude + buffer,
                );
                osmFeatures = OsmParser.parse(resp);
                _debugLog('MULTI: Overpass returned ${resp.elements.length} elements');
              } catch (e) {
                _debugLog('MULTI: Overpass failed (geometry will be missing): $e');
              }

              // Normalize OSM holes into spatial clusters. Each
              // cluster is a group of holes that are near each
              // other — likely belonging to the same course.
              // Then match each cluster to a sub-course by
              // comparing par sequences.
              List<NormalizedCourse>? osmClusters;
              if (osmFeatures != null) {
                final normalizer = CourseNormalizer();
                osmClusters = normalizer.normalizeAll(
                  features: osmFeatures,
                  courseName: entry.name,
                  osmCourseId: 'osm_${entry.latitude}_${entry.longitude}',
                  city: entry.city.isNotEmpty ? entry.city : null,
                  state: entry.state.isNotEmpty ? entry.state : null,
                  facilityPoint: LngLat(entry.longitude, entry.latitude),
                );
                _debugLog('MULTI: ${osmClusters.length} OSM clusters, '
                    '${osmClusters.map((c) => c.holes.length).toList()} holes each');
                // Log each cluster's hole details
                for (var ci = 0; ci < osmClusters.length; ci++) {
                  final c = osmClusters[ci];
                  final holeSummary = c.holes.map((h) {
                    final hasGeom = h.lineOfPlay != null ? 'G' : '-';
                    return 'H${h.number}p${h.par}$hasGeom';
                  }).join(', ');
                  _debugLog('MULTI: cluster $ci: [$holeSummary]');
                }
                // Log expected pars for each sub-course
                for (final ext in extracted) {
                  _debugLog('MULTI: expected ${ext.name}: pars=${ext.pars}');
                }
              }

              // Match each OSM cluster to a sub-course by par
              // sequence similarity (count of matching pars at
              // each hole position).
              final clusterAssignment = <int, int>{}; // clusterIdx → extractedIdx
              if (osmClusters != null) {
                final usedExt = <int>{};
                for (var ci = 0; ci < osmClusters.length; ci++) {
                  final cluster = osmClusters[ci];
                  final clusterPars = cluster.holes
                      .map((h) => h.par)
                      .toList(growable: false);
                  int bestExt = -1;
                  int bestScore = 0;
                  for (var ei = 0; ei < extracted.length; ei++) {
                    if (usedExt.contains(ei)) continue;
                    final extPars = extracted[ei].pars;
                    int score = 0;
                    final len = clusterPars.length < extPars.length
                        ? clusterPars.length
                        : extPars.length;
                    for (var h = 0; h < len; h++) {
                      if (clusterPars[h] == extPars[h]) score++;
                    }
                    if (score > bestScore) {
                      bestScore = score;
                      bestExt = ei;
                    }
                  }
                  if (bestExt >= 0 && bestScore >= 3) {
                    clusterAssignment[ci] = bestExt;
                    usedExt.add(bestExt);
                    _debugLog('MULTI: OSM cluster $ci → '
                        '${extracted[bestExt].name} (score $bestScore)');
                  }
                }
              }

              // Build and cache each individual sub-course.
              for (var extIdx = 0; extIdx < extracted.length; extIdx++) {
                final ext = extracted[extIdx];
                final subName = '${entry.name} - ${ext.name}';
                final subKey = NormalizedCourse.serverCacheKey(subName);

                // Find the OSM cluster assigned to this sub-course.
                NormalizedCourse? matchedCluster;
                for (final e in clusterAssignment.entries) {
                  if (e.value == extIdx && osmClusters != null) {
                    matchedCluster = osmClusters[e.key];
                    break;
                  }
                }

                final subHoles = <NormalizedHole>[];
                for (var i = 0; i < ext.pars.length; i++) {
                  final holeNum = i + 1;
                  final par = ext.pars[i];

                  // Find matching OSM hole from the assigned cluster
                  // by hole number.
                  NormalizedHole? osmMatch;
                  if (matchedCluster != null) {
                    for (final oh in matchedCluster.holes) {
                      if (oh.number == holeNum &&
                          (oh.lineOfPlay != null || oh.green != null)) {
                        osmMatch = oh;
                        break;
                      }
                    }
                  }

                  subHoles.add(NormalizedHole(
                    number: holeNum,
                    par: par,
                    strokeIndex: osmMatch?.strokeIndex,
                    yardages: osmMatch?.yardages ?? const {},
                    teeAreas: osmMatch?.teeAreas ?? const [],
                    lineOfPlay: osmMatch?.lineOfPlay,
                    green: osmMatch?.green,
                    pin: osmMatch?.pin,
                    bunkers: osmMatch?.bunkers ?? const [],
                    water: osmMatch?.water ?? const [],
                  ));
                }
                var subCourse = NormalizedCourse(
                  id: 'multi_${entry.latitude}_${entry.longitude}_${ext.name}',
                  name: subName,
                  city: entry.city.isNotEmpty ? entry.city : null,
                  state: entry.state.isNotEmpty ? entry.state : null,
                  centroid: LngLat(entry.longitude, entry.latitude),
                  holes: subHoles,
                );
                // Enrich with tee/yardage data.
                if (ext.apiDetail != null) {
                  subCourse = await _enrichWithScorecardData(
                    subCourse,
                    entry.name,
                    preMatchedDetail: ext.apiDetail,
                  );
                }

                final holesWithGeom = subHoles
                    .where((h) => h.lineOfPlay != null || h.green != null)
                    .length;

                // Cache locally + server.
                if (repo != null) {
                  try { await repo.save(subKey, subCourse); } catch (_) {}
                }
                // Upload to server. Only request vision refinement
                // when we have SOME OSM geometry to anchor against —
                // refining from zero produces inaccurate LLM guesses.
                final missingHoles =
                    subHoles.length - holesWithGeom;
                final shouldRefine =
                    missingHoles > 0 && holesWithGeom > 0;
                () async {
                  await _cacheClient.putCourse(subKey, subCourse);
                  if (shouldRefine) {
                    final accepted = await _cacheClient.refineCourse(
                      subKey, entry.name,
                    );
                    _debugLog('MULTI: refine for ${ext.name}: '
                        '${accepted ? "accepted" : "failed"} '
                        '($missingHoles missing holes, '
                        '$holesWithGeom anchors)');
                  } else if (missingHoles > 0) {
                    _debugLog('MULTI: skipping refine for ${ext.name} '
                        '— no OSM anchors (all $missingHoles holes missing)');
                  }
                }().ignore();

                cachedSubCourses[ext.name] = subCourse;
                final holeDetail = subHoles.map((h) {
                  final hasGeom = h.lineOfPlay != null ? 'G' : 'X';
                  return 'H${h.number}p${h.par}$hasGeom';
                }).join(', ');
                _debugLog('MULTI: ${ext.name}: $holesWithGeom/${subHoles.length} with geometry [$holeDetail]');
              }
            }

            // Show picker — user picks 1 or 2.
            if (!mounted) return;
            final picks = await showCoursePickerDialog(
              context: context,
              courses: extracted,
            );
            if (picks == null || picks.isEmpty || !mounted) {
              setState(() {
                _navigatingToMap = false;
                _downloadComplete = false;
              });
              return;
            }

            // Combine selected sub-courses into one for the map.
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
              id: 'multi_${entry.latitude}_${entry.longitude}',
              name: combinedName,
              city: entry.city.isNotEmpty ? entry.city : null,
              state: entry.state.isNotEmpty ? entry.state : null,
              centroid: LngLat(entry.longitude, entry.latitude),
              holes: combinedHoles,
            );
            source = 'golf_api';
            cacheKeyForSave = null; // don't cache the combo
            _debugLog('MULTI: combined "${combinedName}" — ${combinedHoles.length} holes');
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
      _cacheClient.putCourse(cacheKeyForSave, course).ignore();
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
            color: Colors.black54,
            child: Center(
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
                ],
              ),
            ),
          ),
      ],
    );
  }
}
