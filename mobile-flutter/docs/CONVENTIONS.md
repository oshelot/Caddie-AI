# CaddieAI Flutter — Conventions

This document is the **enforceable code conventions** distilled from the
KAN-252 Mapbox Flutter spike. Every story under the KAN-251 epic is
expected to follow these rules. If a PR violates one, it should be
rejected in review with a link to the relevant section here.

The spike's original findings live in
`flutter-spike/SPIKE_REPORT.md` on branch `kan-252-flutter-spike`.
Read §4 (runtime bugs), §5 (device measurements), and §6 (GO rationale
+ caveats) before starting any map-touching story.

---

## 1. Mapbox token bootstrap — ALWAYS await

`MapboxOptions.setAccessToken(String)` is declared `void` in the public
API but internally fires an **async** pigeon message. If `runApp`
proceeds before that message lands, the first `MapWidget` inflation
throws `MapboxConfigurationException` (SPIKE_REPORT §4 Bug 1).

**Rule:** every process that ever constructs a `MapWidget` MUST call
`initMapbox()` from `lib/core/mapbox/mapbox_init.dart` and await it
before `runApp()`. Never call `MapboxOptions.setAccessToken` directly.

```dart
// lib/main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMapbox();                // ← mandatory
  runApp(const CaddieApp());
}
```

The token is read from `--dart-define=MAPBOX_TOKEN=pk.xxx` at build
time. Never hard-code it, never commit it, and never read it at runtime
from the environment or a bundled file.

## 2. Style layer adds — ALWAYS use `tryAddLayer` + `verifyLayersPresent`

On iOS, `style.addLayer(...)` has been observed to silently drop layers
for reasons that depend on which properties are set. `LineLayer` with
`lineDasharray` and `SymbolLayer` with `textFont` both reproduce the
failure on `mapbox_maps_flutter` 2.12.0. See SPIKE_REPORT §4 Bugs 2 and
3 for concrete repros.

The failure is silent: `await style.addLayer(...)` returns without
throwing, but `style.getLayer(id)` returns null and downstream property
mutations throw `PlatformException(0, "Layer ... is not in style")`.

**Rule:** never call `style.addLayer` directly. Use the two helpers in
`lib/core/mapbox/layer_helpers.dart`:

```dart
// Add every layer through tryAddLayer so silent failures get logged.
await tryAddLayer(map.style, name: 'hole-lines', build: () => LineLayer(
  id: _holeLinesLayer,
  sourceId: _sourceId,
  filter: ['==', ['get', 'type'], 'holeLine'],
  lineColor: 0xFFFFFFFF,
  lineWidth: 2.0,
));

// Immediately after a batch of adds, audit which layers actually
// landed in the style.
final presence = await verifyLayersPresent(map.style, [
  _boundaryLayer,
  _waterLayer,
  _bunkersLayer,
  _holeLinesLayer,
  _greensLayer,
  _teesLayer,
  _holeLabelsLayer,
]);
if (presence.values.any((present) => !present)) {
  // Log, degrade gracefully, or surface a dev-facing error banner —
  // but do NOT proceed as if all layers are present.
}
```

**Rule:** every style-layer property mutation (`setStyleLayerProperty`,
`updateLayer`) MUST first check the layer exists with `safeGetLayer`.
Never assume a layer is in the style just because its `addLayer` call
returned.

## 3. Performance claims — always specify the measurement method

The in-app FPS HUD that the spike built uses
`SchedulerBinding.addTimingsCallback` → `FrameTiming.buildDuration`,
which measures **only the Dart UI thread's widget-tree build cost**.
The Mapbox `MapView` is a native `SurfaceView` (Android) / `MTKView`
(iOS) rendering on its own thread below the Flutter widget tree — its
GPU rasterization cost does not flow through Flutter's frame timing.

So "Flutter overlay build avg 0.7 ms" does NOT mean "Flutter renders
Mapbox at 1400 fps". It means "the Flutter widget overlay costs 0.7 ms
on top of whatever the native Mapbox view is doing".

**Rule:** any story that makes a performance claim or asserts a
performance budget MUST specify the measurement tool:
- **Dart UI thread only:** DevTools timeline / in-app `addTimingsCallback`.
- **End-to-end including the native Mapbox view:** Android GPU Profiler
  (`adb shell dumpsys gfxinfo`) or Xcode Instruments (Time Profiler +
  Core Animation).

Never cite an `addTimingsCallback` number as an "end-to-end map
performance number". It isn't one.

## 4. `mapbox_maps_flutter` version pinning

The spike validated `mapbox_maps_flutter` **2.12.0**. The latest at time
of writing is **2.21.1**, ~9 months newer. A retest on 2.21.1 is tracked
as the first acceptance criterion on **KAN-270** and should happen
before this project bumps the version.

**Rule:** do NOT bump `mapbox_maps_flutter` without re-running the
spike's scripted interaction on both platforms and re-auditing layer
presence. Version bumps have historically introduced iOS-side silent
layer-add regressions; every bump is a full map-smoke-test event.

The current Flutter SDK pin (3.24.5 / Dart 3.5.4) caps
`mapbox_maps_flutter` at 2.12.0 because 2.13+ requires Dart ≥ 3.6.
Bumping one implies bumping the other and needs a coordinated validation
pass.

## 5. Typeface and dashed hole-lines — pending decisions

Two cosmetic gaps from the spike need project-level decisions before
the corresponding map stories can start:

- **Hole-line dashes.** `LineLayer.lineDasharray` is unusable
  cross-platform today (Bug 2). The scaffold falls back to a solid
  line. See KAN-270 AC #4 for the pending decision.
- **Hole-label typeface.** `SymbolLayer.textFont` is unusable
  cross-platform today (Bug 3), and even if it weren't, there is no
  first-class way to render the iOS native app's `DIN Pro Bold` font
  through `mapbox_maps_flutter` (Bug 4). The scaffold falls back to the
  Mapbox default font. See KAN-270 AC #5 for the pending decision.

**Rule:** stories that render hole-lines or hole-labels are blocked on
these decisions. Do not implement them until the decisions are captured
as comments on KAN-270.

## 6. Do not merge this scaffold into `main`

This directory is a working starting point for the migration, not a
production artifact. It lives on a feature branch and should stay there
until KAN-270's planning pass is complete. Merge the first real
migration story into main, not the scaffold itself.

---

## Project layout

```
mobile-flutter/
  lib/
    main.dart                          # entry point with initMapbox()
    app.dart                           # MaterialApp placeholder
    core/
      geo/
        geo.dart                       # LngLat, Polygon, LineString, haversine, bearing
      mapbox/
        mapbox_init.dart               # setAccessToken workaround
        layer_helpers.dart             # tryAddLayer, verifyLayersPresent, safeGetLayer
    models/
      normalized_course.dart           # NormalizedCourse, NormalizedHole
    services/
      course_geojson_builder.dart      # CourseFeatureType + FeatureCollection builder
  test/
    course_geojson_builder_test.dart   # pure-Dart synthetic-fixture tests
  docs/
    CONVENTIONS.md                     # this file
  pubspec.yaml                         # mapbox_maps_flutter pinned to 2.12.0
```

This structure is **minimal by design**. Feature directories
(`lib/features/<name>/data`, `lib/features/<name>/presentation`) land
only as real features are built, per story, under KAN-251. Don't
pre-create directories for stories that haven't started.

## Running

```bash
# From mobile-flutter/
flutter pub get

# Unit tests (pure Dart, no device needed)
flutter test

# Android debug run (on the moto g play)
flutter run -d ZL8325C8V3 \
  --dart-define=MAPBOX_TOKEN=pk.eyJ1Ijoic3ViY3VsdHVyZWdvbGYi...

# iOS — on a Mac with ~/.netrc configured:
# 1. Bump ios/Podfile: `platform :ios, '14.0'` (not '12.0')
# 2. cd ios && pod install && cd ..
# 3. Open ios/Runner.xcworkspace in Xcode, set signing team, close.
# 4. flutter run -d <ios-device-id> \
#      --dart-define=MAPBOX_TOKEN=pk.xxx
```
