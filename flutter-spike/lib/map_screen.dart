import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;

import 'course_geojson_builder.dart';
import 'models/course.dart';

/// The single spike screen. Loads the Sharp Park fixture, renders all
/// seven course overlay layers, and supports fly-to-hole + highlight.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // -------------------------------------------------------------------------
  // Layer / source IDs — match the iOS `LayerID` enum so log output and
  // regression comparisons stay readable.
  // -------------------------------------------------------------------------
  static const _sourceId = 'course-source';
  static const _boundaryLayer = 'layer-boundary';
  static const _waterLayer = 'layer-water';
  static const _bunkersLayer = 'layer-bunkers';
  static const _holeLinesLayer = 'layer-hole-lines';
  static const _greensLayer = 'layer-greens';
  static const _teesLayer = 'layer-tees';
  static const _holeLabelsLayer = 'layer-hole-labels';
  static const _tapLineSource = 'tap-line-source';
  static const _tapLineLayer = 'tap-line-layer';

  mbx.MapboxMap? _map;
  NormalizedCourse? _course;
  int? _selectedHole;
  bool _layersAdded = false;
  bool _tapLineAdded = false;

  double? _tapYards;
  // ignore: unused_field
  LngLat? _lastTap; // kept for future in-scene debugging / logging

  // Simple rolling FPS sampler fed by SchedulerBinding.addTimingsCallback.
  // Day 4 deliverable: callback wired and buffer visible in-app. Day 5
  // will drive scripted interactions and pull numbers off-device.
  final List<FrameTiming> _frameBuffer = [];
  double? _avgBuildMs;
  double? _worstBuildMs;
  int _totalFrames = 0;

  // FlyTo padding — iOS MapboxMapRepresentable.swift:337.
  static final _holePadding = mbx.MbxEdgeInsets(
    top: 80,
    left: 40,
    bottom: 200,
    right: 40,
  );

  @override
  void initState() {
    super.initState();
    _loadFixture();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    super.dispose();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    _frameBuffer.addAll(timings);
    // Cap buffer to last ~5 seconds @ 120fps ≈ 600 samples.
    if (_frameBuffer.length > 600) {
      _frameBuffer.removeRange(0, _frameBuffer.length - 600);
    }
    _totalFrames += timings.length;
    double sum = 0;
    double worst = 0;
    for (final t in _frameBuffer) {
      final buildMs = t.buildDuration.inMicroseconds / 1000.0;
      sum += buildMs;
      if (buildMs > worst) worst = buildMs;
    }
    final avg = sum / _frameBuffer.length;
    // Avoid setState thrashing every frame batch.
    if (_avgBuildMs == null ||
        (avg - (_avgBuildMs ?? 0)).abs() > 0.2 ||
        (worst - (_worstBuildMs ?? 0)).abs() > 0.5) {
      setState(() {
        _avgBuildMs = avg;
        _worstBuildMs = worst;
      });
    }
  }

  Future<void> _loadFixture() async {
    final raw = await rootBundle.loadString('assets/fixtures/sharp_park.json');
    final course = NormalizedCourse.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    setState(() {
      _course = course;
    });
    // If the map is already ready, layers can be added now.
    if (_map != null && !_layersAdded) {
      await _addCourseLayers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final course = _course;
    return Scaffold(
      body: Stack(
        children: [
          mbx.MapWidget(
            key: const ValueKey('spike-map'),
            styleUri: mbx.MapboxStyles.SATELLITE_STREETS,
            cameraOptions: mbx.CameraOptions(
              center: mbx.Point(
                coordinates: mbx.Position(
                  course?.centroid.lon ?? -122.4885,
                  course?.centroid.lat ?? 37.6244,
                ),
              ),
              zoom: 15.5,
              bearing: 0,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
            onTapListener: _onMapTap,
          ),
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: _TopBanner(course: course, selectedHole: _selectedHole),
          ),
          Positioned(
            top: 92,
            right: 16,
            child: _PerfHud(
              avgBuildMs: _avgBuildMs,
              worstBuildMs: _worstBuildMs,
              totalFrames: _totalFrames,
            ),
          ),
          if (_tapYards != null)
            Positioned(
              top: 92,
              left: 16,
              child: _DistanceHud(yards: _tapYards!),
            ),
          if (course != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _HoleSelector(
                holeCount: course.holes.length,
                selected: _selectedHole,
                onSelected: _selectHole,
              ),
            ),
        ],
      ),
    );
  }

  void _onMapCreated(mbx.MapboxMap map) {
    _map = map;
  }

  Future<void> _onStyleLoaded(mbx.StyleLoadedEventData _) async {
    if (_course != null && !_layersAdded) {
      await _addCourseLayers();
    }
  }

  // -------------------------------------------------------------------------
  // Layer setup
  // -------------------------------------------------------------------------

  /// Wraps a single `style.addLayer` call with diagnostic logging so a
  /// silent failure on one platform can be pinpointed to a specific layer.
  Future<void> _tryAddLayer(String name, mbx.Layer Function() build) async {
    final map = _map;
    if (map == null) return;
    final layer = build();
    try {
      await map.style.addLayer(layer);
      debugPrint('[spike] addLayer ok  name=$name id=${layer.id}');
    } catch (e, st) {
      debugPrint('[spike] addLayer ERR name=$name id=${layer.id} err=$e');
      debugPrint('$st');
    }
  }

  Future<void> _addCourseLayers() async {
    final map = _map;
    final course = _course;
    if (map == null || course == null) return;

    final t0 = DateTime.now();

    final fc = CourseGeoJsonBuilder.buildFeatureCollection(course);
    final geojson = jsonEncode(fc);

    await map.style.addSource(
      mbx.GeoJsonSource(id: _sourceId, data: geojson),
    );

    // 1. Boundary — #2E7D32 @ 0.08 (no data in current schema; layer stays
    //    empty but is defined for parity with iOS).
    await _tryAddLayer('boundary', () => mbx.FillLayer(
          id: _boundaryLayer,
          sourceId: _sourceId,
          filter: ['==', ['get', 'type'], CourseFeatureType.boundary],
          fillColor: 0xFF2E7D32,
          fillOpacity: 0.08,
        ));

    // 2. Water — #1565C0 @ 0.5
    await _tryAddLayer('water', () => mbx.FillLayer(
          id: _waterLayer,
          sourceId: _sourceId,
          filter: ['==', ['get', 'type'], CourseFeatureType.water],
          fillColor: 0xFF1565C0,
          fillOpacity: 0.5,
        ));

    // 3. Bunkers — #E8D5B7 @ 0.7
    await _tryAddLayer('bunkers', () => mbx.FillLayer(
          id: _bunkersLayer,
          sourceId: _sourceId,
          filter: ['==', ['get', 'type'], CourseFeatureType.bunker],
          fillColor: 0xFFE8D5B7,
          fillOpacity: 0.7,
        ));

    // 4. Hole lines — #FFFFFF @ 0.8, width 2, dasharray [4,3]
    //
    // iOS-spike note: earlier runs found this layer silently missing on
    // iOS. Dropping `lineDasharray` to isolate whether that's the cause.
    // If the layer renders as a solid line, dasharray encoding is the
    // bug. If it still fails, something else in LineLayer is.
    await _tryAddLayer('hole-lines', () => mbx.LineLayer(
          id: _holeLinesLayer,
          sourceId: _sourceId,
          filter: ['==', ['get', 'type'], CourseFeatureType.holeLine],
          lineColor: 0xFFFFFFFF,
          lineOpacity: 0.8,
          lineWidth: 2.0,
          // lineDasharray: [4.0, 3.0],  // iOS-disabled for spike diagnosis
        ));

    // 5. Greens — #4CAF50 @ 0.6
    await _tryAddLayer('greens', () => mbx.FillLayer(
          id: _greensLayer,
          sourceId: _sourceId,
          filter: ['==', ['get', 'type'], CourseFeatureType.green],
          fillColor: 0xFF4CAF50,
          fillOpacity: 0.6,
        ));

    // 6. Tees — #81C784 @ 0.5
    await _tryAddLayer('tees', () => mbx.FillLayer(
          id: _teesLayer,
          sourceId: _sourceId,
          filter: ['==', ['get', 'type'], CourseFeatureType.tee],
          fillColor: 0xFF81C784,
          fillOpacity: 0.5,
        ));

    // 7. Hole labels — white text, black halo.
    //
    // iOS-spike note: earlier runs found this layer silently missing on
    // iOS. Dropping `textFont` (DIN Pro Bold fallback chain) to isolate
    // whether that's the cause. If the layer renders in the style
    // default typeface, textFont is the bug.
    await _tryAddLayer('hole-labels', () => mbx.SymbolLayer(
          id: _holeLabelsLayer,
          sourceId: _sourceId,
          filter: ['==', ['get', 'type'], CourseFeatureType.holeLabel],
          textFieldExpression: ['get', 'label'],
          textSize: 14.0,
          textColor: 0xFFFFFFFF,
          textHaloColor: 0xFF000000,
          textHaloWidth: 1.5,
          textAllowOverlap: true,
          // textFont: const ['DIN Pro Bold', 'Arial Unicode MS Bold'], // iOS-disabled
        ));

    // Audit — which layers actually made it into the style?
    final presence = <String, bool>{};
    for (final id in <String>[
      _boundaryLayer,
      _waterLayer,
      _bunkersLayer,
      _holeLinesLayer,
      _greensLayer,
      _teesLayer,
      _holeLabelsLayer,
    ]) {
      try {
        final layer = await map.style.getLayer(id);
        presence[id] = layer != null;
      } catch (e) {
        presence[id] = false;
      }
    }
    debugPrint('[spike] layer_audit $presence');

    _layersAdded = true;

    final latencyMs = DateTime.now().difference(t0).inMilliseconds;
    debugPrint(
      '[spike] layer_render latencyMs=$latencyMs holeCount=${course.holes.length}',
    );

    // Auto-select hole 1 for the first fly-to so the spike visually
    // proves the bearing+padding camera fit from the moment the map
    // appears.
    await _selectHole(1);
  }

  // -------------------------------------------------------------------------
  // Hole selection — zoom + highlight
  // -------------------------------------------------------------------------

  Future<void> _selectHole(int? holeNumber) async {
    setState(() => _selectedHole = holeNumber);
    await _zoomToHole(holeNumber);
    await _highlightHole(holeNumber);
  }

  Future<void> _zoomToHole(int? holeNumber) async {
    final map = _map;
    final course = _course;
    if (map == null || course == null) return;

    if (holeNumber == null) {
      // North-up course overview.
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

    final hole = course.holes.firstWhere(
      (h) => h.number == holeNumber,
      orElse: () => course.holes.first,
    );
    final coords = hole.allGeometryPoints();
    if (coords.length < 2) return;

    final bearing = hole.teeToGreenBearing();
    final points = coords
        .map((p) => mbx.Point(coordinates: mbx.Position(p.lon, p.lat)))
        .toList(growable: false);

    final fitted = await map.cameraForCoordinatesPadding(
      points,
      mbx.CameraOptions(bearing: bearing),
      _holePadding,
      null, // maxZoom
      null, // offset
    );

    await map.flyTo(fitted, mbx.MapAnimationOptions(duration: 900));
  }

  // -------------------------------------------------------------------------
  // Tap → distance
  // -------------------------------------------------------------------------

  void _onMapTap(mbx.MapContentGestureContext ctx) {
    final map = _map;
    final course = _course;
    if (map == null || course == null) return;

    // MapContentGestureContext gives us the geographical Point directly —
    // no manual screen→coord conversion needed.
    final pos = ctx.point.coordinates;
    final tap = LngLat(pos.lng.toDouble(), pos.lat.toDouble());

    // Distance is measured to the currently selected hole's green
    // centroid (or the pin, as a fallback). Matches the iOS
    // tap-to-distance behavior at MapboxMapRepresentable.swift onTap.
    final holeNum = _selectedHole;
    if (holeNum == null) return;

    final hole = course.holes.firstWhere(
      (h) => h.number == holeNum,
      orElse: () => course.holes.first,
    );
    final target = hole.green?.centroid ?? hole.pin ?? hole.lineOfPlay?.endPoint;
    if (target == null) return;

    final yards = metersToYards(haversineMeters(tap, target));

    setState(() {
      _lastTap = tap;
      _tapYards = yards;
    });

    // Fire-and-forget: drawing the yellow line is a style mutation and
    // doesn't need to block the tap response.
    _drawTapLine(tap, target);
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

    if (!_tapLineAdded) {
      await map.style.addSource(
        mbx.GeoJsonSource(id: _tapLineSource, data: geojson),
      );
      await map.style.addLayer(mbx.LineLayer(
        id: _tapLineLayer,
        sourceId: _tapLineSource,
        // iOS: #FFD700, width 3.0, dasharray [2, 2]
        lineColor: 0xFFFFD700,
        lineWidth: 3.0,
        lineDasharray: [2.0, 2.0],
      ));
      _tapLineAdded = true;
    } else {
      await map.style.setStyleSourceProperty(_tapLineSource, 'data', geojson);
    }
  }

  Future<void> _highlightHole(int? holeNumber) async {
    final map = _map;
    if (map == null || !_layersAdded) return;

    // Bail out if the hole-lines layer wasn't added on this platform.
    // On iOS (see spike diagnostic), LineLayer has been observed to
    // silently fail `addLayer`; in that case the highlight is a no-op
    // rather than a loop of PlatformException traces.
    final layer = await _safeGetLayer(map, _holeLinesLayer);
    if (layer == null) {
      debugPrint('[spike] highlightHole skipped — $_holeLinesLayer missing');
      return;
    }

    try {
      if (holeNumber == null) {
        await map.style
            .setStyleLayerProperty(_holeLinesLayer, 'line-opacity', 0.8);
        await map.style
            .setStyleLayerProperty(_holeLinesLayer, 'line-width', 2.0);
        return;
      }
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
        _holeLinesLayer,
        'line-opacity',
        jsonEncode(caseOpacity),
      );
      await map.style.setStyleLayerProperty(
        _holeLinesLayer,
        'line-width',
        jsonEncode(caseWidth),
      );
    } catch (e) {
      debugPrint('[spike] highlightHole ERR $e');
    }
  }

  Future<mbx.Layer?> _safeGetLayer(mbx.MapboxMap map, String id) async {
    try {
      return await map.style.getLayer(id);
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Small presentational widgets
// ---------------------------------------------------------------------------

class _TopBanner extends StatelessWidget {
  const _TopBanner({required this.course, required this.selectedHole});
  final NormalizedCourse? course;
  final int? selectedHole;

  @override
  Widget build(BuildContext context) {
    final label = course == null
        ? 'Loading fixture…'
        : '${course!.name}'
            '${course!.city != null ? ' · ${course!.city}' : ''}'
            '${selectedHole != null ? '  ·  Hole $selectedHole' : ''}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}

class _DistanceHud extends StatelessWidget {
  const _DistanceHud({required this.yards});
  final double yards;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
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

class _PerfHud extends StatelessWidget {
  const _PerfHud({
    required this.avgBuildMs,
    required this.worstBuildMs,
    required this.totalFrames,
  });
  final double? avgBuildMs;
  final double? worstBuildMs;
  final int totalFrames;

  @override
  Widget build(BuildContext context) {
    final avg = avgBuildMs?.toStringAsFixed(1) ?? '—';
    final worst = worstBuildMs?.toStringAsFixed(1) ?? '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.greenAccent,
          fontFamily: 'monospace',
          fontSize: 11,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('avg build  $avg ms'),
            Text('worst     $worst ms'),
            Text('frames    $totalFrames'),
          ],
        ),
      ),
    );
  }
}

class _HoleSelector extends StatelessWidget {
  const _HoleSelector({
    required this.holeCount,
    required this.selected,
    required this.onSelected,
  });

  final int holeCount;
  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.55),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 56,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: holeCount + 1, // +1 for the "All" button
          itemBuilder: (context, i) {
            if (i == 0) {
              final active = selected == null;
              return _chip(
                label: 'All',
                active: active,
                onTap: () => onSelected(null),
              );
            }
            final holeNum = i;
            final active = selected == holeNum;
            return _chip(
              label: '$holeNum',
              active: active,
              onTap: () => onSelected(holeNum),
            );
          },
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onTap(),
        selectedColor: Colors.amber,
        labelStyle: TextStyle(
          color: active ? Colors.black : Colors.white,
          fontWeight: FontWeight.bold,
        ),
        backgroundColor: Colors.white24,
      ),
    );
  }
}
