// CourseMapScreen — KAN-280 (S10) production port of the KAN-252
// spike's `map_screen.dart`. Renders a `NormalizedCourse` as a
// 7-layer Mapbox overlay with bearing-aware flyTo, hole selection,
// tap-to-distance, and layer-presence telemetry.
//
// **Key differences from the spike:**
//
// 1. Every `addLayer` call goes through `tryAddLayer` from
//    `core/mapbox/layer_helpers.dart` (CONVENTIONS C-2). The spike
//    had its own private `_tryAddLayer`; we use the shared one so
//    the diagnostic logging stays consistent.
// 2. Layer presence is verified via `verifyLayersPresent` and the
//    result is BOTH logged to `LoggingService.events.layerRender`
//    and surfaced to the user as a `kDebugMode`-only error banner
//    if any layer is missing.
// 3. **No `LineLayer.lineDasharray`** anywhere on this screen, per
//    CONVENTIONS §5 + the KAN-270 retest. Hole-lines render solid;
//    the tap-to-distance overlay renders solid yellow. Bug 2 is
//    still broken on `mapbox_maps_flutter` 2.21.1 (filed at
//    mapbox/mapbox-maps-flutter#1121) so any layer that sets
//    `lineDasharray` is silently dropped on iOS.
// 4. **No `SymbolLayer.textFont`** on the hole-labels layer, per
//    CONVENTIONS §5 + the same retest. Labels render in the
//    Mapbox SATELLITE_STREETS default font. Bug 3 (filed at
//    mapbox/mapbox-maps-flutter#1122) makes any layer with a
//    custom `textFont` silently disappear on iOS.
// 5. The tap-to-distance source is **pre-warmed at style-load
//    time** with an empty FeatureCollection. The spike added the
//    source on the first tap, which contributed an 80.3 ms outlier
//    to the first-tap latency on the iPhone retest run
//    (`SPIKE_REPORT.md §5.4`). Pre-warming moves that work to the
//    cold-start path where it's hidden by other initialization.
// 6. **Re-audits before the first hole-tap** to catch the Bug 2/3
//    mutated symptom on 2.21.1 (audit-passing-then-disappearing).
//    A layer that's present at style-load and missing on first
//    interaction emits a distinct `layer_drop_post_audit` event
//    so the CloudWatch dashboard can graph the two failure modes
//    separately.
// 7. The screen accepts a `NormalizedCourse` constructor argument.
//    The spike loaded the fixture from `rootBundle` directly; we
//    leave that to the caller (the Course tab will eventually pass
//    a course fetched via `CourseCacheClient`, but for now the
//    `CoursePlaceholder` loads the fallback fixture).
// 8. The `LocationGate` from S4 wraps this screen at the
//    `CoursePlaceholder` level, so by the time `CourseMapScreen`
//    builds, location permission is already granted (AC #1 from
//    S4 — "first-run prompt fires BEFORE the map renders").

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;

import '../../../core/geo/geo.dart';
import '../../../core/icons/caddie_icons.dart';
import '../../../core/logging/log_event.dart';
import '../../../core/logging/logging_service.dart';
import '../../../core/courses/http_transport.dart';
import '../../../core/mapbox/layer_helpers.dart';
import '../../../core/location/location_service.dart';
import 'ask_caddie_sheet.dart';
import 'hole_analysis_sheet.dart';
import '../../../core/weather/weather_data.dart';
import '../../../core/weather/weather_service.dart';
import '../../../models/normalized_course.dart';
import '../../../services/course_geojson_builder.dart';

/// Layer + source IDs. Match the iOS native `LayerID` enum so
/// log output and dashboard filters stay consistent across the
/// two platforms.
class CourseMapLayers {
  CourseMapLayers._();

  static const String sourceId = 'course-source';
  static const String boundaryLayer = 'layer-boundary';
  static const String waterLayer = 'layer-water';
  static const String bunkersLayer = 'layer-bunkers';
  static const String holeLinesLayer = 'layer-hole-lines';
  static const String greensLayer = 'layer-greens';
  static const String teesLayer = 'layer-tees';
  static const String holeLabelsLayer = 'layer-hole-labels';

  /// Tap-to-distance overlay — separate source so the per-tap
  /// data update doesn't churn the main course source.
  static const String tapLineSource = 'tap-line-source';
  static const String tapLineLayer = 'tap-line-layer';

  /// Canonical 7-layer set in iOS draw order. Used by the
  /// post-add audit and the re-audit-before-first-tap check.
  static const List<String> all = [
    boundaryLayer,
    waterLayer,
    bunkersLayer,
    holeLinesLayer,
    greensLayer,
    teesLayer,
    holeLabelsLayer,
  ];
}

class CourseMapScreen extends StatefulWidget {
  const CourseMapScreen({
    super.key,
    required this.course,
    required this.logger,
    this.onAskCaddie,
    this.onAnalyze,
    this.locationService,
  });

  /// The course to render. Caller is responsible for fetching
  /// from `CourseCacheClient` (KAN-275) or loading a fallback
  /// fixture from `assets/fixtures/`.
  final NormalizedCourse course;

  /// Injected logger.
  final LoggingService logger;

  /// Called when the user taps "Ask Caddie". The caller typically
  /// navigates to the Caddie tab with hole context.
  final VoidCallback? onAskCaddie;

  /// Called when the user taps "Analyze". If null, the screen
  /// shows the built-in hole analysis bottom sheet.
  final VoidCallback? onAnalyze;

  /// Location service for on-course GPS. Used by Ask Caddie to
  /// calculate distance to green from the user's position.
  final LocationService? locationService;

  @override
  State<CourseMapScreen> createState() => _CourseMapScreenState();
}

class _CourseMapScreenState extends State<CourseMapScreen> {
  // FlyTo padding — lifted from iOS
  // `MapboxMapRepresentable.swift:337`. Top inset leaves room for
  // the title bar; bottom inset leaves room for the hole selector
  // strip + (eventually) the caddie HUD.
  static final mbx.MbxEdgeInsets _holePadding = mbx.MbxEdgeInsets(
    top: 80,
    left: 40,
    bottom: 260, // room for the bottom info panel
    right: 40,
  );

  mbx.MapboxMap? _map;
  int? _selectedHole;
  String? _selectedTee;
  bool _layersAdded = false;
  int _styleLoadStart = 0;
  bool _firstTapAuditDone = false;

  /// Set of layer ids that failed the post-add audit.
  Set<String> _missingLayers = const {};

  double? _tapYards;
  // ignore: unused_field
  LngLat? _lastTap;

  WeatherData? _weather;
  late final WeatherService _weatherService =
      WeatherService(transport: DartIoHttpTransport());

  /// Deduped tee entries: [{displayName, canonicalTee}].
  /// Computed once in initState per KAN-182 algorithm.
  late final List<_DeduplicatedTee> _dedupedTees =
      _deduplicateTees(widget.course);

  @override
  void initState() {
    super.initState();
    if (_dedupedTees.isNotEmpty) {
      _selectedTee = _dedupedTees.first.canonicalTee;
    }
    _fetchWeather();
  }

  /// KAN-182 dedup algorithm (mirrors iOS CourseViewModel.swift:691-728):
  /// Step 0: Filter combo tees (e.g. "Bronze/Gold") when BOTH standalone
  ///         components exist — the combo is redundant.
  /// Step 1: Group remaining tees by their full yardage array across all
  ///         holes — identical arrays collapse into one display entry.
  /// Step 2: Join groups with " / " for display.
  /// Step 3: Sort by total yardage descending (longest first).
  /// Step 4: Store mapping from display name → canonical tee.
  static List<_DeduplicatedTee> _deduplicateTees(NormalizedCourse course) {
    var teeNames = course.teeNames.toList();
    if (teeNames.isEmpty) return const [];

    // Step 0: Filter combo tees whose standalone components both exist.
    // E.g. "Bronze/Gold" is removed if both "Bronze" and "Gold" exist.
    final standaloneNames =
        teeNames.where((t) => !t.contains('/')).map((t) => t.toLowerCase()).toSet();
    teeNames = teeNames.where((tee) {
      if (!tee.contains('/')) return true; // standalone — keep
      final parts = tee.split('/').map((p) => p.trim().toLowerCase());
      // Keep the combo only if at least one component is NOT standalone.
      return !parts.every((p) => standaloneNames.contains(p));
    }).toList();

    if (teeNames.isEmpty) return const [];

    // Step 1: Group by per-hole yardage signature.
    final signatures = <String, List<String>>{};
    for (final tee in teeNames) {
      final sig = <int>[];
      for (final hole in course.holes) {
        sig.add(hole.yardages[tee] ?? 0);
      }
      final key = sig.join(',');
      signatures.putIfAbsent(key, () => []).add(tee);
    }

    // Step 2+3: Build deduped entries sorted by total yardage descending.
    final entries = signatures.values.map((group) {
      final displayName = group.join(' / ');
      final canonical = group.first;
      final total = course.teeYardageTotals[canonical] ?? 0;
      return _DeduplicatedTee(
        displayName: displayName,
        canonicalTee: canonical,
        totalYardage: total,
      );
    }).toList()
      ..sort((a, b) => b.totalYardage.compareTo(a.totalYardage));

    return entries;
  }

  Future<void> _fetchWeather() async {
    final c = widget.course.centroid;
    final weather = await _weatherService.fetchWeather(
      latitude: c.lat,
      longitude: c.lon,
    );
    if (mounted && weather != null) {
      setState(() => _weather = weather);
    }
  }

  // ── lifecycle ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    final centroid = course.centroid;

    // Find display name for the currently selected canonical tee.
    final selectedDisplay = _dedupedTees
        .cast<_DeduplicatedTee?>()
        .firstWhere((t) => t!.canonicalTee == _selectedTee, orElse: () => null)
        ?.displayName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Course Map'),
        actions: [
          // Tee box selector — KAN-182 deduped, matches iOS top-right chip
          if (_dedupedTees.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PopupMenuButton<String>(
                initialValue: _selectedTee,
                onSelected: (canonical) =>
                    setState(() => _selectedTee = canonical),
                itemBuilder: (_) => _dedupedTees.map((entry) {
                  return PopupMenuItem(
                    value: entry.canonicalTee,
                    child: Row(
                      children: [
                        if (entry.canonicalTee == _selectedTee)
                          const Icon(Icons.check, size: 18)
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Text(entry.displayName),
                        if (entry.totalYardage > 0) ...[
                          const Spacer(),
                          Text('${entry.totalYardage} yds',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ],
                      ],
                    ),
                  );
                }).toList(),
                child: Chip(
                  avatar: CaddieIcons.tee(size: 16),
                  label: Text(selectedDisplay ?? 'Tees'),
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                ),
              ),
            ),
          // Single tee — show as a static label, no dropdown
          if (_dedupedTees.length == 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: CaddieIcons.tee(size: 16),
                label: Text(_dedupedTees.first.displayName),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          mbx.MapWidget(
            key: const ValueKey('caddieai-course-map'),
            styleUri: mbx.MapboxStyles.SATELLITE_STREETS,
            cameraOptions: mbx.CameraOptions(
              center: mbx.Point(
                coordinates: mbx.Position(centroid.lon, centroid.lat),
              ),
              zoom: 15.5,
              bearing: 0,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
            onTapListener: _onMapTap,
          ),
          // Weather badge — top-left, matches iOS placement
          if (_weather != null)
            Positioned(
              top: 12,
              left: 12,
              child: _WeatherBadge(weather: _weather!),
            ),
          if (_tapYards != null)
            Positioned(
              top: _weather != null ? 56 : 16,
              left: 12,
              child: _DistanceHud(yards: _tapYards!),
            ),
          if (kDebugMode && _missingLayers.isNotEmpty)
            Positioned(
              top: 12,
              right: 12,
              child: _LayerDiagnosticBanner(
                missing: _missingLayers,
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomPanel(
              course: course,
              selectedHole: _selectedHole,
              selectedTee: _selectedTee,
              onHoleSelected: _selectHole,
              onAskCaddie: widget.onAskCaddie ?? (widget.locationService != null ? () => _showAskCaddie() : null),
              onAnalyze: widget.onAnalyze ?? () => _showHoleAnalysis(),
            ),
          ),
        ],
      ),
    );
  }

  void _showAskCaddie() {
    final holeNum = _selectedHole;
    if (holeNum == null) return;
    final hole = widget.course.holes.cast<NormalizedHole?>().firstWhere(
          (h) => h!.number == holeNum,
          orElse: () => null,
        );
    if (hole == null) return;
    final locService = widget.locationService;
    if (locService == null) return;
    showAskCaddieSheet(
      context: context,
      course: widget.course,
      hole: hole,
      selectedTee: _selectedTee,
      weather: _weather,
      locationService: locService,
    );
  }

  void _showHoleAnalysis() {
    final holeNum = _selectedHole;
    if (holeNum == null) return;
    final hole = widget.course.holes.cast<NormalizedHole?>().firstWhere(
          (h) => h!.number == holeNum,
          orElse: () => null,
        );
    if (hole == null) return;
    showHoleAnalysisSheet(
      context: context,
      course: widget.course,
      hole: hole,
      selectedTee: _selectedTee,
      weather: _weather,
    );
  }

  void _onMapCreated(mbx.MapboxMap map) {
    _map = map;
    _styleLoadStart = DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> _onStyleLoaded(mbx.StyleLoadedEventData _) async {
    if (_layersAdded) return;
    final ms = DateTime.now().millisecondsSinceEpoch - _styleLoadStart;
    widget.logger.info(LogCategory.map, 'map_style_load', metadata: {
      'latency': '$ms',
    });
    await _addCourseLayers();
  }

  // ── Layer setup ──────────────────────────────────────────────────

  Future<void> _addCourseLayers() async {
    final map = _map;
    if (map == null) return;

    final t0 = DateTime.now();

    final fc = CourseGeoJsonBuilder.buildFeatureCollection(widget.course);
    final geojson = jsonEncode(fc);

    await map.style.addSource(
      mbx.GeoJsonSource(id: CourseMapLayers.sourceId, data: geojson),
    );

    // Pre-warm the tap-to-distance source with an empty
    // FeatureCollection at style-load time. The spike added this
    // source lazily on the first tap, which contributed an
    // 80.3 ms outlier to the first-tap latency on the iPhone
    // retest. Adding it up-front amortizes the cost into the
    // cold-start path. See SPIKE_REPORT §5.4.
    await map.style.addSource(
      mbx.GeoJsonSource(
        id: CourseMapLayers.tapLineSource,
        data: jsonEncode({'type': 'FeatureCollection', 'features': []}),
      ),
    );
    await tryAddLayer(
      map.style,
      name: 'tap-line',
      build: () => mbx.LineLayer(
        id: CourseMapLayers.tapLineLayer,
        sourceId: CourseMapLayers.tapLineSource,
        // Solid yellow — NO lineDasharray. The iOS native used a
        // [2,2] dash but Bug 2 (filed upstream as
        // mapbox/mapbox-maps-flutter#1121) silently drops any
        // LineLayer that sets the property. CONVENTIONS §5 takes
        // option (a) defaults — solid only.
        lineColor: 0xFFFFD700,
        lineWidth: 3.0,
      ),
    );

    // The 7 course layers in iOS draw order.
    await tryAddLayer(
      map.style,
      name: 'boundary',
      build: () => mbx.FillLayer(
        id: CourseMapLayers.boundaryLayer,
        sourceId: CourseMapLayers.sourceId,
        filter: ['==', ['get', 'type'], CourseFeatureType.boundary],
        fillColor: 0xFF2E7D32,
        fillOpacity: 0.08,
      ),
    );
    await tryAddLayer(
      map.style,
      name: 'water',
      build: () => mbx.FillLayer(
        id: CourseMapLayers.waterLayer,
        sourceId: CourseMapLayers.sourceId,
        filter: ['==', ['get', 'type'], CourseFeatureType.water],
        fillColor: 0xFF1565C0,
        fillOpacity: 0.5,
      ),
    );
    await tryAddLayer(
      map.style,
      name: 'bunkers',
      build: () => mbx.FillLayer(
        id: CourseMapLayers.bunkersLayer,
        sourceId: CourseMapLayers.sourceId,
        filter: ['==', ['get', 'type'], CourseFeatureType.bunker],
        fillColor: 0xFFE8D5B7,
        fillOpacity: 0.7,
      ),
    );
    await tryAddLayer(
      map.style,
      name: 'hole-lines',
      build: () => mbx.LineLayer(
        id: CourseMapLayers.holeLinesLayer,
        sourceId: CourseMapLayers.sourceId,
        filter: ['==', ['get', 'type'], CourseFeatureType.holeLine],
        lineColor: 0xFFFFFFFF,
        lineOpacity: 0.8,
        lineWidth: 2.0,
        // ⚠️  DO NOT set lineDasharray here — it's silently
        //     dropped on iOS in mapbox_maps_flutter 2.21.1.
        //     CONVENTIONS §5 / SPIKE_REPORT §4 Bug 2 / GitHub
        //     issue mapbox/mapbox-maps-flutter#1121.
      ),
    );
    await tryAddLayer(
      map.style,
      name: 'greens',
      build: () => mbx.FillLayer(
        id: CourseMapLayers.greensLayer,
        sourceId: CourseMapLayers.sourceId,
        filter: ['==', ['get', 'type'], CourseFeatureType.green],
        fillColor: 0xFF4CAF50,
        fillOpacity: 0.6,
      ),
    );
    await tryAddLayer(
      map.style,
      name: 'tees',
      build: () => mbx.FillLayer(
        id: CourseMapLayers.teesLayer,
        sourceId: CourseMapLayers.sourceId,
        filter: ['==', ['get', 'type'], CourseFeatureType.tee],
        fillColor: 0xFF81C784,
        fillOpacity: 0.5,
      ),
    );
    await tryAddLayer(
      map.style,
      name: 'hole-labels',
      build: () => mbx.SymbolLayer(
        id: CourseMapLayers.holeLabelsLayer,
        sourceId: CourseMapLayers.sourceId,
        filter: ['==', ['get', 'type'], CourseFeatureType.holeLabel],
        textFieldExpression: ['get', 'label'],
        textSize: 14.0,
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.5,
        textAllowOverlap: true,
        // ⚠️  DO NOT set textFont here — it's silently dropped on
        //     iOS in mapbox_maps_flutter 2.21.1. CONVENTIONS §5 /
        //     SPIKE_REPORT §4 Bug 3 / GitHub issue
        //     mapbox/mapbox-maps-flutter#1122. Labels render in
        //     the SATELLITE_STREETS default font.
      ),
    );

    // Audit which layers actually made it into the rendered
    // style. Logs to LoggingService AND records the missing set
    // for the in-app banner.
    final presence = await verifyLayersPresent(
      map.style,
      CourseMapLayers.all,
    );
    final missing = presence.entries
        .where((e) => !e.value)
        .map((e) => e.key)
        .toSet();

    final latencyMs = DateTime.now().difference(t0).inMilliseconds;
    widget.logger.info(
      LogCategory.map,
      LoggingService.events.layerRender,
      metadata: {
        'latencyMs': '$latencyMs',
        'holeCount': '${widget.course.holes.length}',
      },
    );

    // Per-layer failure events for the CloudWatch dashboard.
    for (final layerId in missing) {
      widget.logger.warning(
        LogCategory.map,
        LoggingService.events.layerAddFailure,
        metadata: {'layerId': layerId},
      );
    }

    if (mounted) {
      setState(() {
        _layersAdded = true;
        _missingLayers = missing;
      });
    } else {
      _layersAdded = true;
      _missingLayers = missing;
    }

    // Start on "All" (zoomed out, north up) — matches iOS behavior.
    // The user taps a hole number to zoom into a specific hole.
    await _selectHole(null);
  }

  // ── Hole selection ──────────────────────────────────────────────

  Future<void> _selectHole(int? holeNumber) async {
    if (mounted) {
      setState(() => _selectedHole = holeNumber);
    } else {
      _selectedHole = holeNumber;
    }
    await _zoomToHole(holeNumber);
    await _highlightHole(holeNumber);
  }

  Future<void> _zoomToHole(int? holeNumber) async {
    final map = _map;
    if (map == null) return;
    final course = widget.course;

    if (holeNumber == null) {
      // Course overview — north up, default zoom.
      await map.flyTo(
        mbx.CameraOptions(
          center: mbx.Point(
            coordinates: mbx.Position(
              course.centroid.lon,
              course.centroid.lat,
            ),
          ),
          zoom: 15.5,
          bearing: 0,
        ),
        mbx.MapAnimationOptions(duration: 900),
      );
      return;
    }

    final matches = course.holes.where((h) => h.number == holeNumber);
    if (matches.isEmpty) return;
    final hole = matches.first;
    final coords = hole.allGeometryPoints();
    if (coords.length < 2) {
      // Hole has no geometry. Keep camera where it is — don't let
      // the map zoom to course overview or to the wrong hole.
      return;
    }

    final bearing = hole.teeToGreenBearing();
    final points = coords
        .map((p) => mbx.Point(coordinates: mbx.Position(p.lon, p.lat)))
        .toList(growable: false);

    final fitted = await map.cameraForCoordinatesPadding(
      points,
      mbx.CameraOptions(bearing: bearing),
      _holePadding,
      null,
      null,
    );

    await map.flyTo(fitted, mbx.MapAnimationOptions(duration: 900));
  }

  Future<void> _highlightHole(int? holeNumber) async {
    final map = _map;
    if (map == null || !_layersAdded) return;

    // Per CONVENTIONS C-2: every property mutation MUST first
    // verify the layer exists. The "audit was clean but layer
    // disappeared" mutated symptom of Bug 2/3 means we can't
    // trust `_layersAdded` alone.
    final layer = await safeGetLayer(map.style, CourseMapLayers.holeLinesLayer);
    if (layer == null) {
      _logPostAuditDrop(CourseMapLayers.holeLinesLayer);
      return;
    }

    try {
      if (holeNumber == null) {
        await map.style.setStyleLayerProperty(
          CourseMapLayers.holeLinesLayer,
          'line-opacity',
          0.8,
        );
        await map.style.setStyleLayerProperty(
          CourseMapLayers.holeLinesLayer,
          'line-width',
          2.0,
        );
        return;
      }
      // Case expression: highlight the selected hole, fade the rest.
      final caseOpacity = [
        'case',
        ['==', ['get', 'holeNumber'], holeNumber],
        1.0,
        0.4,
      ];
      final caseWidth = [
        'case',
        ['==', ['get', 'holeNumber'], holeNumber],
        3.5,
        1.5,
      ];
      await map.style.setStyleLayerProperty(
        CourseMapLayers.holeLinesLayer,
        'line-opacity',
        jsonEncode(caseOpacity),
      );
      await map.style.setStyleLayerProperty(
        CourseMapLayers.holeLinesLayer,
        'line-width',
        jsonEncode(caseWidth),
      );
    } catch (e) {
      debugPrint('[course-map] highlightHole ERR $e');
    }
  }

  // ── Tap → distance ───────────────────────────────────────────────

  void _onMapTap(mbx.MapContentGestureContext ctx) {
    // First-tap re-audit. Catches the Bug 2/3 mutated symptom
    // (audit-passing-then-disappearing) on mapbox_maps_flutter
    // 2.21.1. We do this BEFORE handling the tap so the user
    // doesn't get a confusing "tap-to-distance worked once"
    // experience while the map is missing layers.
    if (!_firstTapAuditDone) {
      _firstTapAuditDone = true;
      _runFirstTapReaudit();
    }

    final map = _map;
    if (map == null) return;
    final course = widget.course;

    final pos = ctx.point.coordinates;
    final tap = LngLat(pos.lng.toDouble(), pos.lat.toDouble());

    // Distance is measured to the currently selected hole's green
    // centroid (or the pin / line-of-play end as fallback).
    final holeNum = _selectedHole;
    if (holeNum == null) return;

    final hole = course.holes.firstWhere(
      (h) => h.number == holeNum,
      orElse: () => course.holes.first,
    );
    final target =
        hole.green?.centroid ?? hole.pin ?? hole.lineOfPlay?.endPoint;
    if (target == null) return;

    final yards = metersToYards(haversineMeters(tap, target));

    if (mounted) {
      setState(() {
        _lastTap = tap;
        _tapYards = yards;
      });
    }

    // Fire-and-forget — drawing the line is a style mutation
    // that doesn't need to block the tap response.
    _drawTapLine(tap, target);
  }

  Future<void> _runFirstTapReaudit() async {
    final map = _map;
    if (map == null) return;
    final presence = await verifyLayersPresent(
      map.style,
      CourseMapLayers.all,
    );
    final droppedSinceAudit = <String>{};
    for (final entry in presence.entries) {
      if (!entry.value && !_missingLayers.contains(entry.key)) {
        // Layer was present at the post-add audit and is missing
        // now — that's the Bug 2/3 mutated symptom.
        droppedSinceAudit.add(entry.key);
      }
    }
    for (final layerId in droppedSinceAudit) {
      widget.logger.warning(
        LogCategory.map,
        LoggingService.events.layerDropPostAudit,
        metadata: {'layerId': layerId},
      );
    }
    if (droppedSinceAudit.isNotEmpty && mounted) {
      setState(() {
        _missingLayers = {..._missingLayers, ...droppedSinceAudit};
      });
    }
  }

  Future<void> _drawTapLine(LngLat from, LngLat to) async {
    final map = _map;
    if (map == null) return;

    final geojson = jsonEncode({
      'type': 'Feature',
      'properties': <String, dynamic>{},
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [from.lon, from.lat],
          [to.lon, to.lat],
        ],
      },
    });
    // The source was pre-warmed at style-load time, so this is
    // an update — not an add.
    try {
      await map.style.setStyleSourceProperty(
        CourseMapLayers.tapLineSource,
        'data',
        geojson,
      );
    } catch (e) {
      debugPrint('[course-map] drawTapLine ERR $e');
    }
  }

  void _logPostAuditDrop(String layerId) {
    widget.logger.warning(
      LogCategory.map,
      LoggingService.events.layerDropPostAudit,
      metadata: {'layerId': layerId},
    );
    if (mounted) {
      setState(() {
        _missingLayers = {..._missingLayers, layerId};
      });
    }
  }
}

// ── Presentational widgets ─────────────────────────────────────────

/// Weather badge matching iOS CourseMapView.swift:871-893.
/// Black capsule with temp + wind speed, positioned top-left.
class _WeatherBadge extends StatelessWidget {
  const _WeatherBadge({required this.weather});
  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final temp = '${weather.temperatureF.round()}\u00B0F';
    final wind = '${weather.windSpeedMph.round()}mph';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_weatherIcon(weather.weatherCode),
              color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(temp,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          if (weather.windSpeedMph >= 1) ...[
            const SizedBox(width: 8),
            CaddieIcons.wind(size: 14, color: Colors.white),
            const SizedBox(width: 3),
            Text(wind,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  static IconData _weatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code <= 3) return Icons.cloud;
    if (code <= 48) return Icons.foggy;
    if (code <= 67) return Icons.grain; // rain/drizzle
    if (code <= 77) return Icons.ac_unit; // snow
    return Icons.thunderstorm;
  }
}

/// One entry in the deduped tee list per KAN-182.
class _DeduplicatedTee {
  const _DeduplicatedTee({
    required this.displayName,
    required this.canonicalTee,
    required this.totalYardage,
  });

  /// Merged display name, e.g. "Black / Silver".
  final String displayName;

  /// First tee name in the group — used as the key for yardage lookups.
  final String canonicalTee;

  /// Total yardage for sorting (longest first).
  final int totalYardage;
}

class _DistanceHud extends StatelessWidget {
  const _DistanceHud({required this.yards});
  final double yards;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
      ),
      child: Text(
        '${yards.round()} yds',
        style: const TextStyle(
          color: Color(0xFFFFD700),
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _LayerDiagnosticBanner extends StatelessWidget {
  const _LayerDiagnosticBanner({required this.missing});
  final Set<String> missing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      constraints: const BoxConstraints(maxWidth: 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Layer audit failed',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            missing.join('\n'),
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom panel matching iOS CourseMapScreen bottom sheet:
/// course name, hole info (par + yardage + SI), action buttons,
/// and the hole selector strip.
class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.course,
    required this.selectedHole,
    required this.onHoleSelected,
    this.selectedTee,
    this.onAskCaddie,
    this.onAnalyze,
  });

  final NormalizedCourse course;
  final int? selectedHole;
  final String? selectedTee;
  final ValueChanged<int?> onHoleSelected;
  final VoidCallback? onAskCaddie;
  final VoidCallback? onAnalyze;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hole = selectedHole == null
        ? null
        : course.holes.cast<NormalizedHole?>().firstWhere(
              (h) => h!.number == selectedHole,
              orElse: () => null,
            );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Course name + hole info
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        _holeInfoText(hole, theme),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Ask Caddie + Analyze buttons
            if (selectedHole != null && (onAskCaddie != null || onAnalyze != null))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    if (onAskCaddie != null)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onAskCaddie,
                          icon: CaddieIcons.golfer(size: 18),
                          label: const Text('Ask Caddie'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                    if (onAskCaddie != null && onAnalyze != null)
                      const SizedBox(width: 12),
                    if (onAnalyze != null)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onAnalyze,
                          icon: CaddieIcons.target(size: 18),
                          label: const Text('Analyze'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            // Hole selector strip
            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: course.holes.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _chip(
                      label: 'All',
                      active: selectedHole == null,
                      onTap: () => onHoleSelected(null),
                    );
                  }
                  final num = i;
                  final hole = course.holes[i - 1];
                  final hasGeometry = hole.lineOfPlay != null ||
                      hole.green != null ||
                      hole.pin != null;
                  return _chip(
                    label: '$num',
                    active: selectedHole == num,
                    onTap: () => onHoleSelected(num),
                    noGeometry: !hasGeometry,
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _holeInfoText(NormalizedHole? hole, ThemeData theme) {
    if (hole == null) {
      return Text(
        '${course.holes.length} holes',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }
    final parts = <String>[
      'Hole ${hole.number}',
      if (hole.par > 0) 'Par ${hole.par}',
    ];
    // Show yardage for the selected tee, or first available
    if (hole.yardages.isNotEmpty) {
      final yds = (selectedTee != null && hole.yardages.containsKey(selectedTee))
          ? hole.yardages[selectedTee]!
          : hole.yardages.values.first;
      parts.add('$yds yds');
    }
    if (hole.strokeIndex != null) {
      parts.add('SI ${hole.strokeIndex}');
    }
    final hasGeometry = hole.lineOfPlay != null ||
        hole.green != null ||
        hole.pin != null;
    if (!hasGeometry) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            parts.join('  '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 14, color: theme.colorScheme.error),
              const SizedBox(width: 4),
              Text(
                "This hole isn't mapped yet — we're working on it",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Text(
      parts.join('  '),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool noGeometry = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onTap(),
        selectedColor: noGeometry ? Colors.red.shade300 : Colors.blue,
        labelStyle: TextStyle(
          color: active
              ? Colors.white
              : noGeometry
                  ? Colors.red
                  : null,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        backgroundColor:
            noGeometry ? Colors.red.shade50 : Colors.grey.shade200,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
