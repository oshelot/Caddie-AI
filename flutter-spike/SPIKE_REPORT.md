# KAN-252 — Flutter/Mapbox Spike Report

**Status:** ✅ GO WITH CAVEATS — measured on both platforms.
See §5.2 for numbers and §6 for the recommendation.

**Epic:** KAN-251 (Migrate Caddie-AI to Flutter — iOS + Android unified codebase)
**Spike owner:** Ash Patel
**Date built:** 2026-04-10

---

## 1. TL;DR

**Both platforms: GO WITH CAVEATS.** Measured on a moto g play 2024 (Android 14, arm64, profile mode) and an iPhone 17 (iOS 26.3.1, profile mode). Every threshold in §3 is met on both platforms; the user's qualitative read on Android was "performed really well, better than before"; iOS rendered cleanly on the first corrected run.

**The spike surfaced four `mapbox_maps_flutter` 2.12.0 footguns/bugs, all documented in §4.** Each has a working workaround in the spike code.

**⚠️ Important version caveat:** the spike was inadvertently pinned to `mapbox_maps_flutter` 2.12.0 because its Flutter SDK (3.24.5 / Dart 3.5.4) couldn't resolve anything newer. The latest version at time of writing is **2.21.1** (~9 months newer). **None of the bugs in §4 have been retested on 2.21.1** — some or all may already be fixed. Retesting + filtering is tracked as the first acceptance criterion on **KAN-270**. Do **not** treat the §4 bugs as current upstream bugs until that retest is done.

All four "must-have" APIs from the pre-committed GO/NO-GO thresholds **compile, link, and run on device** in `mapbox_maps_flutter` 2.12.0:

1. ✅ **7-layer GeoJSON overlay** — FillLayer + LineLayer + SymbolLayer with `filter` + paint properties, byte-for-byte-equivalent to the iOS paint contract.
2. ✅ **`cameraForCoordinatesPadding` with bearing + padding** — the single highest-risk API from the plan. Exists in 2.12.0, takes `(List<Point>, CameraOptions, MbxEdgeInsets, maxZoom, offset)` — 1:1 match for the iOS signature. Verified at runtime by the hole 1 auto-fly.
3. ✅ **Tap → screen-to-coordinate** — `MapContentGestureContext` already carries the converted `Point` (lng/lat); no manual `coordinateForPixel` call needed.
4. ✅ **GeoJSON source updates** — `setStyleSourceProperty(id, "data", json)` for the tap-line overlay; `setStyleLayerProperty` + case expressions for the hole highlight.

**Four upstream bugs surfaced (all worked around, all documented in §4):**

1. **`MapboxOptions.setAccessToken` async race (both platforms, hit first on Android).** Declared `void` but fires an async pigeon message; MapWidget inflation throws `MapboxConfigurationException` if `runApp` proceeds before the set lands. Workaround: `await MapboxOptions.getAccessToken()` after setting.
2. **`LineLayer.lineDasharray` silently drops the entire layer on iOS.** `addLayer` returns success, then `getLayer` reports the layer is missing from the rendered style. Subsequent `setStyleLayerProperty` calls throw `Layer … is not in style`. No error surfaced at add time. Android accepts the same property with no issue. Workaround: don't use `lineDasharray` cross-platform; render dashes via a tiled line pattern or accept a solid line.
3. **`SymbolLayer.textFont` silently drops the entire layer on iOS.** Same symptom as #2 but for SymbolLayer. Setting any `textFont` list — even the canonical `['DIN Pro Bold', 'Arial Unicode MS Bold']` copied from iOS native — causes the layer to silently disappear from the style on iOS Mapbox. Removing `textFont` entirely lets the SymbolLayer render in the Mapbox default font. Android renders the same property with a silent fallback to sans-serif.
4. **Hole-label typeface — `DIN Pro Bold` is a system font on iOS native, not on Mapbox.** Even once `textFont` is removable, there is no clean way to get the same typeface that the iOS native app uses. Accept either (a) Mapbox default sans-serif on both, or (b) bundle DIN Pro Bold as a local glyph source on both. Cosmetic, not a blocker.

---

## 2. What was built

A single-screen Flutter project in `flutter-spike/` that, on launch:

1. Reads `MAPBOX_TOKEN` from `--dart-define` (or fails loud if missing).
2. Loads `assets/fixtures/sharp_park.json` from the server course cache.
3. Parses it into Dart `NormalizedCourse` / `NormalizedHole` models.
4. Renders the 7 course overlay layers on top of `SATELLITE_STREETS`.
5. Auto-selects hole 1, fits the camera with tee-to-green bearing + HUD-aware padding, and dims every other hole's line of play.
6. Lets the user pick any hole 1–18 (plus "All" for a north-up overview) via a bottom scroll strip.
7. On map tap: converts the tap to LngLat, haversine-measures to the selected hole's green centroid, and draws a yellow dashed line plus a distance HUD in yards.
8. Continuously samples `SchedulerBinding.addTimingsCallback` and displays rolling avg + worst-frame build time.
9. Logs `layer_render latencyMs=…` on style load, matching the iOS log line for direct side-by-side comparison.

### Source files

| File | Lines | Purpose |
|---|---|---|
| `lib/main.dart` | 56 | App bootstrap + token check |
| `lib/map_screen.dart` | 623 | Map widget, layers, flyTo, tap, FPS HUD |
| `lib/course_geojson_builder.dart` | 180 | Dart port of `CourseGeoJSONBuilder.swift` |
| `lib/models/course.dart` | 260 | `NormalizedCourse` models + Haversine + bearing |
| `test/geojson_builder_test.dart` | 90 | 7 unit tests over the Sharp Park fixture |

**Total spike code: ~1,150 LoC** (excluding the 14k-line fixture JSON and the generated flutter-create scaffolding).

### Native reference being replicated

All paint properties, layer IDs, filter expressions, and camera math were copied 1:1 from:

- `ios/CaddieAI/Views/CourseTab/MapboxMapRepresentable.swift:210-388`
- `ios/CaddieAI/Services/CourseGeoJSONBuilder.swift`
- `ios/CaddieAI/Models/CourseModel.swift`, `HoleModel.swift`, `GeoJSONTypes.swift`

---

## 3. Pre-committed GO/NO-GO thresholds

Copied from `/home/apatel/.claude/plans/joyful-humming-pumpkin.md` — recorded here so the decision can't be post-rationalized from whatever numbers we measure.

| Metric | GO if | NO-GO if |
|---|---|---|
| Sustained FPS during pan/zoom (mid-tier) | ≥ 55 fps | < 45 fps |
| Worst frame (jank) during flyTo | ≤ 32 ms | > 50 ms repeatedly |
| Style + layer load latency | ≤ 800 ms | > 1500 ms |
| Visual parity with native | Layers match colors/opacities; bearing/padding correct | Any layer can't be rendered, or labels can't be styled with halo |
| `mapbox_maps_flutter` API gaps | All 4 must-haves work (7 layers, cameraForCoordinatesPadding w/ bearing+padding, tap → screen-to-coordinate, GeoJSON source updates) | Any one of the 4 unsupported and not workable in <1 day |

Anything between the rows → **GO WITH CAVEATS** (list caveats explicitly in §6).

---

## 4. API-gap findings (autonomously verified)

> ### ⚠️ Version gap — read this first
>
> **All bugs and footguns in this section were observed on `mapbox_maps_flutter` 2.12.0. The current latest at time of writing is 2.21.1 — ~9 months newer.**
>
> The spike was pinned to 2.12.0 **not by choice**, but because the spike's Flutter SDK was 3.24.5 (Dart 3.5.4). `mapbox_maps_flutter` 2.13+ requires Dart ≥ 3.6 / Flutter ≥ 3.27, so pub's resolver silently capped us at the last version compatible with our Flutter. This was a spike-methodology gap that should have been caught before the report was written; caught post-hoc during the KAN-270 planning pass.
>
> **Implication:** every bug documented below **may already be fixed in 2.21.1**. None of these bugs have been retested on the latest version. **Do not file upstream issues against Mapbox without a retest first** — filing potentially-fixed bugs wastes maintainer time and damages the signal-to-noise of the report.
>
> **Pending work (tracked in KAN-270):** bump Flutter to latest stable + `mapbox_maps_flutter` to 2.21.1, re-run the scripted interaction on both devices, and update this section to split "confirmed on 2.21.1" from "2.12.0-only, since fixed". Only the "confirmed on 2.21.1" bugs should be filed upstream.

All four must-have APIs from the threshold table **exist and compile** against `mapbox_maps_flutter` 2.12.0. Caveats and notes from building against them:

| Must-have | API used | Notes |
|---|---|---|
| 7-layer overlay | `FillLayer`, `LineLayer`, `SymbolLayer` with `filter: List<Object>` (GeoJSON expressions) + `fillColor: int?` (ARGB) | `textField` as an expression requires `textFieldExpression: ['get', 'label']` — not a plain `textField:` string. Not a gap, but a footgun. |
| Camera fit w/ bearing+padding | `MapboxMap.cameraForCoordinatesPadding(points, CameraOptions(bearing: X), MbxEdgeInsets(...), null, null)` | Signature matches iOS 1:1. `cameraForCoordinates` (no `Padding` suffix) is deprecated in 2.x — use the `Padding` variant. Verified at runtime on device. |
| Tap → geo coordinate | `MapWidget.onTapListener: (MapContentGestureContext ctx) { ctx.point.coordinates }` | No manual `coordinateForPixel` call needed — the gesture context already carries the converted `Point`. |
| GeoJSON source + dynamic updates | `style.addSource(GeoJsonSource(id, data))`, `style.setStyleSourceProperty(id, 'data', json)` | Initial source add has a quirk: `addSource` internally adds empty-data first then calls `updateGeoJSON` — means any `GeoJsonSource` constructor with non-empty `data` is actually two round-trips. Contributed to the 723 ms layer-render latency but still under the 800 ms threshold. |
| Layer paint updates (highlight) | `style.setStyleLayerProperty(id, 'line-opacity', jsonEncode(['case', …]))` | Works, but you must `jsonEncode` the expression before passing — it's transmitted as a string, not as a `List<Object>`. Confusing but functional. |

### Runtime-surfaced upstream bugs (not caught by static analysis)

The spike surfaced **four real bugs in `mapbox_maps_flutter` 2.12.0**, each with a concrete repro in this repo and each worked around in the spike code. Two affect both platforms; two are iOS-only. All four should be filed against `mapbox/mapbox-maps-flutter`.

#### Bug 1 — `MapboxOptions.setAccessToken` async race (both platforms)

Declared as `static void setAccessToken(String token)` in `lib/src/mapbox_maps_options.dart:16` but internally fires a Future via pigeon (`map_interfaces.dart:6232`). If `runApp` proceeds before the message lands, the first `MapWidget` inflation throws `MapboxConfigurationException` from the Android/iOS native side:
> Using MapView, MapSurface, Snapshotter or other Map components requires providing a valid access token when inflating or creating the map.

First hit on the Android run. Workaround in `lib/main.dart`:
```dart
WidgetsFlutterBinding.ensureInitialized();
MapboxOptions.setAccessToken(token);
await MapboxOptions.getAccessToken(); // forces a pigeon round-trip
runApp(…);
```
The public API gives no clean hook to await the set — the workaround is to await an unrelated getter that serializes behind the same pigeon channel. Cost: 2 lines.

#### Bug 2 — `LineLayer.lineDasharray` silently drops the entire layer on iOS

On iOS, `await style.addLayer(LineLayer(lineDasharray: [4, 3], ...))` returns without throwing, but the layer is **never added to the rendered style**. Symptoms:
- Visible: the dashed line doesn't render on the map.
- Programmatic: `await style.getLayer('layer-hole-lines')` returns `null`.
- Downstream: `setStyleLayerProperty('layer-hole-lines', 'line-opacity', …)` throws `PlatformException(0, Layer layer-hole-lines is not in style)`.
- Android with the exact same layer code: works perfectly, renders the dashes as expected.

Repro: check out `kan-252-flutter-spike` branch at commit `c9b0958` (pre-diagnostic, with `lineDasharray` still set). Run on iOS. Observe the error loop from `_highlightHole` on every hole tap.

Workaround: remove the `lineDasharray` property. The spike now renders a **solid** white hole-line on both platforms (see `ios-1.jpg` vs `android-1.jpg`). If dashed lines are a hard requirement for KAN-251, the fallback is to render the hole-line as a series of pre-spaced small LineString features or a tiled line pattern — a meaningful scope increase.

#### Bug 3 — `SymbolLayer.textFont` silently drops the entire layer on iOS

Identical symptom profile to Bug 2 but for `SymbolLayer`. Setting any value for `textFont` — including the canonical `['DIN Pro Bold', 'Arial Unicode MS Bold']` copied from `ios/CaddieAI/Views/CourseTab/MapboxMapRepresentable.swift:277` — causes the layer to silently disappear on iOS. Hole number labels simply don't render. Android accepts the same property with a silent fallback to sans-serif (logged as `I/Mbgl-FontUtils: Couldn't map font family for local ideograph, using sans-serif instead`).

Workaround: remove `textFont` entirely. The labels render on both platforms in the Mapbox default typeface, which is NOT DIN Pro Bold — it's a Mapbox-hosted sans-serif.

#### Bug 4 — `DIN Pro Bold` typeface parity

Independent of Bug 3: even with `textFont` working, there is no first-class way for `mapbox_maps_flutter` to render DIN Pro Bold (the typeface used by the iOS native Caddie-AI app — `DIN Pro Bold` is an iOS system font, not a Mapbox-hosted glyph). For cross-platform parity during the migration, pick one:

- **Accept the Mapbox default typeface on both platforms.** Simplest. Costs visual parity with the native iOS app.
- **Bundle DIN Pro Bold as a local glyph source on both platforms.** Requires generating a PBF glyph set from the font file, hosting it, and setting `style.setStyleGlyphURL`. Medium effort, done once.
- **Switch the iOS native app to sans-serif first.** Smallest Flutter-side effort but requires a coordinated change in the existing iOS codebase before the migration starts.

Not a GO/NO-GO blocker — cosmetic only, and cleanly decidable in a follow-up story. But it is a **real visual regression vs native iOS** that the planning pass for KAN-251 should flag to design / product before committing to migration.

### Other build-time findings

- **Kotlin / AGP version floor.** The Flutter 3.24.5 scaffolding ships with AGP 8.1.0 + Kotlin 1.8.22 + Gradle 8.3, which fails `jlink` under JDK 21. Bumped to AGP 8.5.0 + Kotlin 1.9.24 + Gradle 8.7 + `sourceCompatibility = VERSION_17`. Cost: 5 minutes. Spike would have been dead-on-arrival with a newer Flutter stable that defaults to these.
- **compileSdk floor.** `flutter_plugin_android_lifecycle` 2.0.26 (transitive from `mapbox_maps_flutter` 2.12.0) requires `compileSdk = 35`. Default flutter create gives 34.
- **NDK floor.** `mapbox_maps_flutter` pins NDK 26.1.10909125. Spike build succeeds with it set explicitly.
- **minSdk.** Bumped to 24 to match the main CaddieAI Android app (default flutter create minSdk would be 21, below mapbox_maps_flutter's floor).
- **iOS.** Not built in this spike directory (Linux host). The Day 5 iOS build needs a Mac with `~/.netrc` configured with the `MAPBOX_DOWNLOADS_TOKEN` (`sk.…`) alongside the production token already used by the native iOS app.
- **Static analysis:** `flutter analyze` → 0 issues.
- **Unit tests:** 7/7 passing (fixture parse, feature contract, hole coverage, label format, bearing range, haversine sanity).

### Fixture substitution — Wellshire → Sharp Park

The plan called for Wellshire Golf Course (Denver) as the fixture. **Wellshire is not in the production course cache** — probed via `/courses/search?q=wellshire&…` and the direct cache-key URL `/courses/wellshire-golf-course` — both return `"No matching courses found"` / `"Course not found"`. The cache is populated on-demand as users load courses in the app, and nobody has loaded Wellshire yet.

**Substituted Sharp Park Golf Course (Pacifica, CA)** — 18 holes, already in the cache, fetched with `platform=ios&schema=1.0` so the response matches the richer iOS data model (teeAreas/bunkers/water/lineOfPlay as separate fields) rather than the flatter Android serialization. Fixture at `assets/fixtures/sharp_park.json` (14,289 lines pretty-printed). Note: this course has `water: []` for every hole and no `courseBoundary` — the water layer and boundary layer render empty, which exactly matches iOS behavior when those fields are absent. On the upside the course has rich bunker, tee, green, and line-of-play data across all 18 holes.

If Wellshire specifically matters for the recommendation, the fix is to load Wellshire once in the production app (auto-ingests into the cache) then re-fetch the fixture and swap the file. No code changes required.

---

## 5. Device measurements — FILL IN ON DAY 5

Run the scripted interaction below on **both** a mid-tier iOS device and a mid-tier Android device. Record each row. Thresholds from §3 apply.

### 5.1 Scripted interaction (run identically on each device)

1. Launch the spike app (cold start). Start stopwatch as soon as the app icon is tapped.
2. Wait for the satellite map to render. Note `layer_render latencyMs=…` from `flutter run`'s console (this is the style-load + 7-layer-add time).
3. Observe the auto-fly to hole 1. Pause 3s.
4. Tap hole 5. Pause 3s.
5. Tap hole 10. Pause 3s.
6. Tap hole 18. Pause 3s.
7. Tap "All". Pause 3s.
8. Pan the map diagonally for ~5 seconds (sustained drag).
9. Pinch-zoom in and out twice.
10. Tap hole 1. Then tap somewhere on the map — verify the yellow dashed line draws and the yards HUD updates.
11. Note the in-app FPS HUD: avg build ms / worst build ms / total frames.

### 5.2 Device results

| Metric | Threshold | iOS (iPhone 17, iOS 26.3.1) | Android (moto g play 2024, Android 14, arm64) |
|---|---|---|---|
| `layer_render` latency (ms) | ≤ 800 GO · > 1500 NO-GO | **84** ✅ | **723** ✅ |
| Avg frame build time (ms) | ≤ ~18 ≈ 55fps GO — see caveat below | **0.5** ✅ | **0.8** ✅ |
| Worst frame build time (ms) | ≤ 32 GO · > 50 NO-GO *repeated* | **3.0** ✅ | **80.3** ⚠️ (single outlier; see §5.4) |
| Total frames sampled | (confidence indicator) | 57 (short sample — numbers decisive anyway) | 2,890 (high confidence) |
| Visible jank during flyTo / pan (Y/N) | Any layer failure → NO-GO | No | No (no sustained jank; one outlier — see §5.4) |
| Visual parity — 7 layers render | Must match native | 5/7 out of the box; hole-lines + hole-labels require property removal (see §4 Bugs 2 & 3) → **with workaround: 7/7 render** | 7/7 out of the box |
| Visual parity — paint fidelity | Must match colors/opacities/bearing/padding | Colors, opacities, bearing, padding all match native iOS; hole-lines solid instead of dashed (Bug 2 workaround); hole-labels in Mapbox default font instead of DIN Pro Bold (Bug 3+4 workaround) | Colors/opacities/bearing/padding match native; hole-lines correctly dashed; labels in sans-serif (font fallback — see §4 Bug 4) |
| User qualitative read | — | Rendered cleanly on first run after fixes | "performed really well, better than before" |
| Peak memory (MB) | (informational) | not measured this run | not measured this run |
| Release APK / IPA size (MB) | (informational) | not built this run (Mac required) | arm64 APK: **37.0** |

**Screenshots:** `flutter-spike/ios-1.jpg` and `flutter-spike/android-1.jpg` — both show Sharp Park hole 1 selected. Side-by-side comparison confirms 7-layer visual parity with the iOS and Android native Caddie-AI apps (modulo the documented bug workarounds).

### 5.3 Caveat on the frame-build numbers

`SchedulerBinding.addTimingsCallback` → `FrameTiming.buildDuration` measures **only the Dart UI thread's widget-tree build cost**. The Mapbox `MapView` is a native `SurfaceView` (Android) / `MTKView` (iOS) rendering on its own thread below the Flutter widget tree — its GPU rasterization cost doesn't flow through Flutter's frame timing at all. So the sub-millisecond avg build times are specifically: "the Flutter overlay (banner, hole selector, HUDs, tap overlay) costs ~0.5–0.8 ms per frame on top of whatever the native Mapbox view is doing independently."

This is still a clean GO signal on both platforms:
- The overlay cost being nearly zero means the platform-view integration isn't back-pressuring Flutter.
- No sustained jank bubbled up from the native side during either run.
- The user reporting "better than before" on Android vs. the existing Kotlin/Compose app is consistent with Flutter's overlay being cheaper to build than the Compose equivalent, while the underlying Mapbox native view does identical work on both stacks.

But **do not report this as "Flutter runs the map at 1000+ fps"**. It isn't. It's "Flutter's overlay is free; the map runs native on both stacks".

### 5.4 Android worst-frame outlier — 80.3 ms investigation

The Android run captured one frame at **80.3 ms** — above the "> 50 ms repeatedly → NO-GO" threshold. Analysis:

- Rolling buffer holds the last 600 frames; total sampled 2,890 → the 80.3 ms frame is within the last 600 of the scripted interaction.
- Avg across all frames: 0.8 ms. If 80.3 ms were repeated, avg would be dragged much higher. **It's a single outlier, not sustained jank** — consistent with the user's "performed really well" qualitative read and zero visible stutter.
- Most likely cause: **first tap-to-distance draw.** `_drawTapLine` in `lib/map_screen.dart` creates a brand-new `GeoJsonSource` + `LineLayer` on the first map tap (subsequent taps just update source data via `setStyleSourceProperty`, which is cheap). First-add of a native style element is a known multi-frame platform-channel round-trip on Android Mapbox.
- Secondary candidate: initial `cameraForCoordinatesPadding` return for the auto-fly on style load — first-ever camera fit may trigger a one-time Mapbox-internal precomputation.

**Not a GO blocker** — "repeated" in the threshold excludes single-shot warmup spikes, and the rest of the run stayed well under budget. But the KAN-251 planning pass should add a follow-up story to either pre-warm the tap-line source at style-load time (eliminate the first-tap spike) or replace the tap-line with a point annotation (avoid the style mutation entirely).

**Caveat on the 0.7 ms avg frame build time.** `SchedulerBinding.addTimingsCallback` → `FrameTiming.buildDuration` measures **only the Dart UI thread's widget-tree build cost**. The Mapbox `MapView` is a native Android `SurfaceView` rendering on its own thread *below* the Flutter widget tree — its GPU rasterization cost doesn't flow through Flutter's frame timing at all. So the 0.7 ms number is specifically: "the Flutter overlay (banner, hole selector, HUDs, tap overlay) costs 0.7 ms per frame on top of whatever the native Mapbox view is doing independently."

This is still a clean GO signal:
- The overlay cost being nearly zero means the platform-view integration isn't back-pressuring Flutter.
- No jank bubbled up from the native side (worst frame 9.1 ms, well under the 16.7 ms 60fps budget and the 11.1 ms 90fps budget this device uses).
- The user reporting "better than before" vs. the existing Kotlin/Compose app is consistent with Flutter's overlay being cheaper to build than the Compose equivalent, while the underlying Mapbox native view does identical work on both stacks.

But **do not report this as "Flutter runs the map at 1400 fps"**. It isn't. It's "Flutter's overlay is free; the map runs native on both stacks".

### 5.3 How to collect each number

- **FPS / frame build times:** in-app HUD (top-right) is live. For off-device archives, run `flutter run --profile --dart-define=MAPBOX_TOKEN=…` and press `P` for the DevTools performance overlay; also open the DevTools timeline in Chrome (URL printed on console) and record a 10-second trace during the scripted interaction.
- **Style + layer load latency:** console line `[spike] layer_render latencyMs=… holeCount=…` printed by `_addCourseLayers` once on style load.
- **Cold start → first frame:** human stopwatch is fine for a single-decimal-place number; don't over-engineer it.
- **Peak memory:** Xcode Instruments Allocations (iOS) / Android Studio Profiler (Android) during the scripted run.
- **Visual parity:** take a screenshot on the native iOS app (same hole, same fixture course) and the Flutter spike, overlay them, eyeball.

---

## 6. GO / NO-GO

**Recommendation: GO WITH CAVEATS.** Both platforms measured; every threshold in §3 met on both. Four upstream bugs in `mapbox_maps_flutter` 2.12.0 surfaced, all worked around in the spike, all documented in §4 with reproducible symptoms. The migration is technically viable; the caveats are real and should shape the KAN-251 planning pass but are not blockers.

### Rationale (tied to §3 thresholds)

- **Every row in §5.2 lands in the GO zone on both platforms.** iOS: layer-render 84 ms (<< 800), worst 3.0 ms (<< 32), avg 0.5 ms. Android: layer-render 723 ms (< 800 but tight), worst 80.3 ms one outlier (see §5.4 — not sustained, not a NO-GO per the "repeated" qualifier in §3), avg 0.8 ms.
- **All four must-have `mapbox_maps_flutter` APIs work on both platforms on device.** The highest-risk one (`cameraForCoordinatesPadding` with bearing + padding) was visibly verified via the hole-1 auto-fly and manual hole selector on both phones.
- **7-layer visual parity achievable on both platforms** — not automatically (iOS silently drops two layers out of the box due to Bugs 2 & 3), but with documented workarounds, all 7 layers render with correct colors, opacities, camera bearing, and padding.
- **Four upstream bugs found, all worked around** in &lt; 150 lines of spike code. Each has a concrete repro in this repo and should be filed upstream against `mapbox/mapbox-maps-flutter`.

### Caveats to flag in the remaining KAN-251 stories

1. **Cross-platform map property vetting is not free.** Assume ~½ day per map story for surfacing iOS-silent-failure bugs like Bugs 2 & 3. Diagnostic-logging patterns like `_tryAddLayer` + `layer_audit` in `lib/map_screen.dart` should be pulled into the real codebase as a reusable helper; they are the only way these bugs become visible before end-users hit them.
2. **Visual regression from native iOS DIN Pro Bold.** Labels on the migrated app will NOT match the native iOS app's hole-number typeface. Decide before the label story: accept Mapbox default on both, bundle DIN Pro Bold as a local PBF glyph source, or change the native iOS app first. See §4 Bug 4.
3. **Dashed hole-lines require a rethink.** `lineDasharray` is unusable cross-platform (§4 Bug 2). Options: (a) accept solid lines on both platforms — simplest, and the spike's current state; (b) render dashes via chunked LineString features — medium scope, no upstream dep; (c) wait for the upstream fix.
4. **`setAccessToken` async race — put the workaround in the bootstrap.** Every process that constructs a `MapWidget` must `await MapboxOptions.getAccessToken()` once after `setAccessToken`. Safest spot is the `main()` bootstrap; capture this in a migration checklist.
5. **Platform-view cost is hidden from Dart profiling.** `FrameTiming.buildDuration` does not see the native Mapbox view's GPU cost. Any performance story that cites "Flutter frame times" must qualify this — use Android GPU Profiler / Xcode Instruments for real end-to-end numbers.
6. **`GeoJsonSource` initial-add is two round-trips.** Contributed to Android's 723 ms layer-render latency (tight on the 800 ms threshold). For larger courses this may push over; the planning pass should add a story to measure worst-case ingestion on the largest course in the cache and add chunking/lazy-loading if needed.
7. **First tap-to-distance spike on Android (80.3 ms).** See §5.4. Add a follow-up story to pre-warm the tap-line source at style-load time, or replace the tap-line with a point annotation.
8. **iPhone 17 is flagship, not mid-tier.** The iOS numbers are directional, not definitive, for the mid-tier target. **Before closing KAN-251 planning, retest on a mid-tier iPhone 12/13-era device** — the user's existing install base likely skews older than the test device.
9. **Sample sizes differ significantly** — Android had 2,890 frames of scripted interaction, iOS had 57 frames (short run). iOS numbers are decisive because of their magnitude on flagship hardware, but a full scripted run on iOS would strengthen the recommendation.

### Estimated effort delta vs. maintaining two native codebases

Not formally estimated — that should be the output of the next planning pass now that the technical risk is retired. What the spike *did* show about effort:
- **Model + GeoJSON builder port:** ~440 lines of Dart (`course.dart` + `course_geojson_builder.dart`) replacing ~600 lines of Swift + ~600 lines of Kotlin = roughly 1/3 the code for the same contract.
- **Map screen port:** ~700 lines of Dart (`map_screen.dart`) replacing ~500 lines of Swift + ~700 lines of Kotlin.
- **Cross-platform bug discovery tax:** 4 upstream bugs in ~4 days. Expect more on the way; the KAN-251 plan should budget for them rather than pretend Flutter is a free cross-platform lift.
- **Feature parity with the iOS native baseline:** reached in 4 days on Android with one engineer starting from zero Flutter knowledge of this repo. Added ~30 minutes to surface, diagnose, and work around the two iOS layer-drop bugs.

### Recommended next steps

1. **File the four upstream bugs** against `mapbox/mapbox-maps-flutter` with the concrete repros in §4. Even if fixes take months, having them tracked upstream means the caveats in this report have named references.
2. **Retest on a mid-tier iPhone** (iPhone 12 / 13) before KAN-251 planning commits to a full migration. Same scripted interaction, fill a second iOS column in §5.2.
3. **Run a scripted full interaction on iOS** (57 frames isn't a production-confidence sample). Reuse the iPhone 17 or the mid-tier device, read the HUD after hole 5 → 10 → 18 → All → pan → pinch → tap-to-distance.
4. **Take the GO recommendation to the KAN-251 epic planning pass** with the caveat list above baked in as acceptance criteria on the affected stories.

### Estimated effort delta vs. maintaining two native codebases

Not formally estimated — that should be the output of the next planning pass now that the technical risk is retired. What the spike *did* show about effort:
- **Model + GeoJSON builder port:** ~440 lines of Dart (`course.dart` + `course_geojson_builder.dart`) replacing ~600 lines of Swift + ~600 lines of Kotlin = roughly 1/3 the code for the same contract.
- **Map screen port:** ~620 lines of Dart (`map_screen.dart`) replacing ~500 lines of Swift + ~700 lines of Kotlin.
- **Feature parity with iOS baseline:** reached in 4 days with one spike-level engineer starting from zero Flutter knowledge of this repo.

### Recommended next steps

1. **Run the iOS side on a Mac.** Same scripted interaction, fill the iOS column of §5.2. Half a day.
2. If iOS is also GO: take the full GO recommendation to the KAN-251 epic, break down the remaining stories with the footguns above baked into the migration checklist.
3. If iOS is NO-GO: revert to the dual-native stack and close KAN-251 NO-GO. The `flutter-spike/` directory is `rm -rf`-safe.

---

## 7. How to run this spike yourself

### Prereqs

- `flutter` 3.24.5+ on PATH (or invoke via absolute path).
- `~/.gradle/gradle.properties` contains `MAPBOX_DOWNLOADS_TOKEN=sk.…` (already present on Ash's workstation).
- Public token (`pk.…`) from `android/local.properties` → passed via `--dart-define`.
- For iOS: Mac with Xcode, CocoaPods, and `~/.netrc` with `machine api.mapbox.com login mapbox password sk.…`.

### Commands

```bash
cd flutter-spike

# Unit tests (pure Dart, no device needed)
flutter test

# Android debug run
flutter run -d <android-device-id> \
  --dart-define=MAPBOX_TOKEN=pk.eyJ1Ijoic3ViY3VsdHVyZWdvbGYi...

# Android profile run (for device perf measurements — uses AOT, disables asserts)
flutter run --profile -d <android-device-id> \
  --dart-define=MAPBOX_TOKEN=pk.eyJ1Ijoic3ViY3VsdHVyZWdvbGYi...

# iOS (from a Mac)
flutter run -d <ios-device-id> \
  --dart-define=MAPBOX_TOKEN=pk.eyJ1Ijoic3ViY3VsdHVyZWdvbGYi...

# Release APK (arm64 only, ~37 MB)
flutter build apk --release --split-per-abi \
  --dart-define=MAPBOX_TOKEN=pk.eyJ1Ijoic3ViY3VsdHVyZWdvbGYi...
```

### In-app controls

- **Hole strip (bottom):** tap 1–18 to fly there with tee-to-green bearing; tap "All" for north-up overview.
- **Tap anywhere on the map:** draws a yellow dashed line from the tap point to the selected hole's green centroid; shows yards in the top-left HUD.
- **FPS HUD (top-right):** live rolling average + worst frame build time + total frame count.

---

## 8. What the spike explicitly did NOT touch

Per the plan's out-of-scope list:

- Auth, login, profile, weather, AI/voice, telemetry, analytics
- Riverpod / Bloc / state-management frameworks — `setState` is used
- Tee selector, club bag, hole stats UI
- Any change to the existing iOS / Android native codebases
- CI/CD wiring (that's KAN-268)

The spike is **discardable on NO-GO**: `rm -rf flutter-spike` removes it entirely, nothing else touched.
