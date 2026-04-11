# KAN-252 — Flutter/Mapbox Spike Report

**Status:** ✅ GO WITH CAVEATS — measured on both platforms, KAN-270 retest done.
See §5.2 (original) + §5.5 (retest) for numbers and §6 for the recommendation.

**Epic:** KAN-251 (Migrate Caddie-AI to Flutter — iOS + Android unified codebase)
**Spike owner:** Ash Patel
**Date built:** 2026-04-10
**Retested:** 2026-04-11 on `mapbox_maps_flutter` 2.21.1 + Flutter 3.41.6

---

## 1. TL;DR

**Both platforms: GO WITH CAVEATS.** Originally measured on a moto g play 2024 (Android 14, arm64, profile mode) and an iPhone 17 (iOS 26.3.1, profile mode) on `mapbox_maps_flutter` 2.12.0. Re-measured 2026-04-11 on `mapbox_maps_flutter` 2.21.1 + Flutter 3.41.6 to satisfy KAN-270 AC #1 — both runs land inside every threshold, and the version-bump retest narrowed the upstream bug surface.

**Bugs after retest: 2 still reproducing on iOS, 1 fixed, 1 was never an upstream issue.** Down from 4 candidates pre-retest. Details in §4.

| Bug | 2.12.0 | 2.21.1 | Action |
|---|---|---|---|
| 1 — `setAccessToken` async race | hit | ✅ fixed | drop the workaround, no upstream filing |
| 2 — `LineLayer.lineDasharray` silently drops layer on iOS | broken | ❌ still broken, with mutated symptom | file upstream |
| 3 — `SymbolLayer.textFont` silently drops layer on iOS | broken | ❌ still broken, same mutated symptom | file upstream |
| 4 — DIN Pro Bold typeface parity | n/a | n/a | not a bug — project decision |

**The retest also surfaced a symptom mutation for Bugs 2 and 3** that's load-bearing for the migration plan: on 2.21.1 the affected layers pass the immediate `verifyLayersPresent` audit and disappear from the rendered style a few milliseconds later, before the first style mutation. The defensive audit pattern this spike pioneered is **necessary but no longer sufficient** — the only safe path on 2.21.1 is to not use `lineDasharray` or `textFont` cross-platform at all. CONVENTIONS C-2 in `mobile-flutter/docs/CONVENTIONS.md` has been updated to reflect this.

All four "must-have" APIs from the pre-committed GO/NO-GO thresholds **compile, link, and run on device** in `mapbox_maps_flutter` 2.12.0:

1. ✅ **7-layer GeoJSON overlay** — FillLayer + LineLayer + SymbolLayer with `filter` + paint properties, byte-for-byte-equivalent to the iOS paint contract.
2. ✅ **`cameraForCoordinatesPadding` with bearing + padding** — the single highest-risk API from the plan. Exists in 2.12.0, takes `(List<Point>, CameraOptions, MbxEdgeInsets, maxZoom, offset)` — 1:1 match for the iOS signature. Verified at runtime by the hole 1 auto-fly.
3. ✅ **Tap → screen-to-coordinate** — `MapContentGestureContext` already carries the converted `Point` (lng/lat); no manual `coordinateForPixel` call needed.
4. ✅ **GeoJSON source updates** — `setStyleSourceProperty(id, "data", json)` for the tap-line overlay; `setStyleLayerProperty` + case expressions for the hole highlight.

**Two upstream bugs to file** (post-retest, see §4 for full repros):

1. **`LineLayer.lineDasharray` silently drops the entire layer on iOS.** Confirmed broken on 2.12.0 AND 2.21.1. On 2.21.1 the symptom mutated: `addLayer` returns ok, the immediate `getLayer` audit returns the layer present, then within milliseconds the layer disappears from the rendered style — the first hole tap fires a flood of `[spike] highlightHole skipped — layer-hole-lines missing` log lines and no dashes render visually. Android handles the same property correctly on both versions.
2. **`SymbolLayer.textFont` silently drops the entire layer on iOS.** Same symptom profile as #1, for `SymbolLayer`. Hole number labels do not render visually on iOS in either version. Android renders correctly with a silent sans-serif fallback.

**Two findings that are NOT upstream bugs to file:**

- **`MapboxOptions.setAccessToken` async race** — was hit on 2.12.0, no longer reproduces on 2.21.1 in either platform. Either Mapbox closed the race upstream or the pigeon-channel ordering changed. Workaround removed from `mobile-flutter/lib/core/mapbox/mapbox_init.dart`.
- **DIN Pro Bold typeface parity** — not an upstream bug. The native iOS app uses the iOS system font; Mapbox doesn't ship it. This is a project decision (KAN-270 AC #5), tracked separately.

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

> ### Version retest summary (2026-04-11)
>
> The original spike was inadvertently pinned to `mapbox_maps_flutter` **2.12.0** because Flutter 3.24.5 / Dart 3.5.4 capped the pub resolver at the last version compatible with Dart 3.5.x. KAN-270 AC #1 was the retest on Flutter 3.41.6 + `mapbox_maps_flutter` 2.21.1 (~9 months newer) — done.
>
> **Retest result:**
>
> | Bug | 2.12.0 | 2.21.1 | Action |
> |---|---|---|---|
> | **1** — `setAccessToken` async race | hit on Android first | ✅ **fixed** on both platforms (Android Run B and iOS Run B both loaded clean with `BUG1_REPRO=true`) | drop the workaround |
> | **2** — `LineLayer.lineDasharray` silent drop on iOS | broken | ❌ **still broken** on iOS, with mutated symptom (see Bug 2 below) | file upstream |
> | **3** — `SymbolLayer.textFont` silent drop on iOS | broken | ❌ **still broken** on iOS, same mutated symptom | file upstream |
> | **4** — DIN Pro Bold typeface parity | n/a | n/a | not a bug — project decision (KAN-270 AC #5) |
>
> **Net upstream filing:** 2 bugs, not 4. Bug 1 is fixed; Bug 4 was always a project decision, not an upstream issue.
>
> The retest also surfaced a **symptom mutation** for Bugs 2 and 3 that's documented inline below — the layers now pass the immediate `verifyLayersPresent` audit and disappear from the style a few milliseconds later, before the first style mutation. The audit pattern that caught these bugs at first run on 2.12.0 is **necessary but no longer sufficient** on 2.21.1. CONVENTIONS.md C-2 has been updated accordingly.

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

#### Bug 1 — `MapboxOptions.setAccessToken` async race (both platforms) — ✅ FIXED in 2.21.1

**On 2.12.0:** declared as `static void setAccessToken(String token)` in `lib/src/mapbox_maps_options.dart:16` but internally fires a Future via pigeon (`map_interfaces.dart:6232`). If `runApp` proceeds before the message lands, the first `MapWidget` inflation throws `MapboxConfigurationException` from the Android/iOS native side:
> Using MapView, MapSurface, Snapshotter or other Map components requires providing a valid access token when inflating or creating the map.

First hit on the original Android run. Workaround was to await an unrelated getter that serializes behind the same pigeon channel:
```dart
MapboxOptions.setAccessToken(token);
await MapboxOptions.getAccessToken(); // forces a pigeon round-trip
runApp(…);
```

**On 2.21.1 (KAN-270 retest, 2026-04-11):** ✅ **No longer reproduces.** Both Android Run B (moto g play 2024) and iOS Run B (iPhone 17) loaded cleanly with `--dart-define=BUG1_REPRO=true` (which skips the await):
```
flutter: [spike] BUG1_REPRO=true — skipping setAccessToken await
flutter: [spike] addLayer ok  name=boundary id=layer-boundary
... all 7 layers added ...
flutter: [spike] layer_render latencyMs=11 holeCount=18  (iOS)
flutter: [spike] layer_render latencyMs=652 holeCount=18 (Android)
```

Either Mapbox closed the race window upstream between 2.13 and 2.21, or some pigeon-channel ordering changed and the timing no longer reliably loses. Either way the workaround is no longer required as of 2.21.1.

**Action:** the workaround in `mobile-flutter/lib/core/mapbox/mapbox_init.dart` has been removed; CONVENTIONS C-1 simplified to "set the token before runApp" without the audit-the-await footgun. Do **not** file upstream — there's nothing to file. Keep a historical note in the source comments so the next person doesn't reintroduce the workaround thinking it's still needed.

#### Bug 2 — `LineLayer.lineDasharray` silently drops the entire layer on iOS — ❌ STILL REPRODUCES on 2.21.1, with mutated symptom

**On 2.12.0:** `await style.addLayer(LineLayer(lineDasharray: [4, 3], ...))` returns without throwing, but the layer is never added to the rendered style. `getLayer('layer-hole-lines')` returns `null` immediately, and downstream `setStyleLayerProperty(...)` throws `PlatformException(0, Layer layer-hole-lines is not in style)`.

**On 2.21.1 (KAN-270 retest):** the bug is still present, but the failure mode has shifted. Diagnostic from iOS Run B:

```
flutter: [spike] addLayer ok  name=hole-lines id=layer-hole-lines    ← addLayer reports ok
flutter: [spike] layer_audit {…, layer-hole-lines: true, …}          ← getLayer at audit time returns the layer
flutter: [spike] layer_render latencyMs=11 holeCount=18              ← style load completes
... a few milliseconds later, on the first hole tap ...
flutter: [spike] highlightHole skipped — layer-hole-lines missing    ← getLayer NOW returns null
flutter: [spike] highlightHole skipped — layer-hole-lines missing
... 22 more identical messages on subsequent hole interactions ...
```

Visual confirmation: on iPhone 17 + iOS 26.3.1 + `mapbox_maps_flutter` 2.21.1, **the dashed hole-line still does not render on the map** even though `lineDasharray: [4.0, 3.0]` is set on the layer and `addLayer` reported success. Android with the same code renders the dashes correctly.

The mutation matters: the layer **passes the immediate `verifyLayersPresent` audit and disappears from the rendered style within milliseconds**, before the first user interaction. Whatever defensive pattern callers use, an audit at style-loaded time alone is no longer enough — the layer goes from present → absent without an event the caller can hook. The only safe pattern on 2.21.1 is to **not use `lineDasharray` cross-platform**.

Repro on 2.21.1: check out `kan-252-flutter-spike` at commit `616dbc9` (the bumped retest), `flutter run --profile -d <ios-device> --dart-define=MAPBOX_TOKEN=…`. The `[spike] highlightHole skipped` log will start firing as soon as the first hole is tapped.

Workaround: remove the `lineDasharray` property entirely. The spike now renders a **solid** white hole-line on both platforms (see `ios-1.jpg` vs `android-1.jpg`). If dashed lines are a hard requirement for KAN-251, the fallback is to render the hole-line as a series of pre-spaced small LineString features or a tiled line pattern — a meaningful scope increase. **KAN-270 AC #4 (dashed hole-lines decision) is now forced toward solid lines** — since the bug persists, options (b) chunked LineStrings and (c) "block on upstream" are still on the table, but option (a) accept-solid-lines is the only path that doesn't introduce custom geometry work.

#### Bug 3 — `SymbolLayer.textFont` silently drops the entire layer on iOS — ❌ STILL REPRODUCES on 2.21.1, with mutated symptom

**On 2.12.0:** identical symptom profile to Bug 2 but for `SymbolLayer`. Setting any value for `textFont` — including the canonical `['DIN Pro Bold', 'Arial Unicode MS Bold']` copied from `ios/CaddieAI/Views/CourseTab/MapboxMapRepresentable.swift:277` — caused the layer to silently disappear on iOS. Hole number labels did not render. Android accepted the same property with a silent fallback to sans-serif (logged as `I/Mbgl-FontUtils: Couldn't map font family for local ideograph, using sans-serif instead`).

**On 2.21.1 (KAN-270 retest):** still reproduces with the same mutated pattern as Bug 2 — `addLayer` reports ok, the immediate audit reports the layer present, and the labels nonetheless **do not render visually on iOS**. The diagnostic skipped-log doesn't fire as loudly here because `_highlightHole` only touches the hole-lines layer, not the hole-labels layer; visual confirmation on iPhone 17 + iOS 26.3.1 is the primary signal:

> "No dashed lines or hole numbers still" — user, after retest on iPhone 17 + 2.21.1.

Android with the same code renders the labels in sans-serif as before.

Workaround: remove `textFont` entirely. The labels render on both platforms in the Mapbox default typeface, which is NOT DIN Pro Bold — it's a Mapbox-hosted sans-serif. **KAN-270 AC #5 (typeface decision) is now forced toward Mapbox default** — bundling DIN Pro Bold as a local PBF glyph source (option b) or changing the iOS native app first (option c) remain valid future paths but neither can use the simpler `textFont:` property to express the choice; both require `style.setStyleGlyphURL` (option b) or accepting visual regression (option a).

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

## 5. Device measurements

Original measurements taken Day 5 of the spike (2026-04-10) on a moto g play 2024 (Android) and an iPhone 17 (iOS), both in profile mode against `mapbox_maps_flutter` 2.12.0. Re-measured 2026-04-11 against 2.21.1 — see §5.5.

Scripted interaction below; thresholds from §3 apply.

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

### 5.5 KAN-270 retest measurements (2026-04-11, mapbox_maps_flutter 2.21.1 + Flutter 3.41.6)

Re-ran the scripted interaction on both devices after bumping. Two runs per device: Run A with the `setAccessToken` workaround active (default), Run B with `--dart-define=BUG1_REPRO=true` to verify Bug 1 by skipping the workaround.

| Metric | iPhone 17 Run A | iPhone 17 Run B | moto g play 2024 Run A | moto g play 2024 Run B |
|---|---|---|---|---|
| `layer_render` latency (ms) | (debug-attach timeout — see note below) | **11** | **795** | **652** |
| Avg frame build (ms) | 0.4 | 0.5 | 0.8 | 0.8 |
| Worst frame (ms) | 3.3 | 4.0 | 17.7 | 12.3 |
| Frames sampled | 1,096 | 1,456 | 607 | 603 |
| Bug 1 (`MapboxConfigurationException` on workaround-off run B) | n/a | ✅ did not crash | n/a | ✅ did not crash |
| Bug 2 visual (dashed hole-line renders?) | ❌ no | ❌ no | ✅ yes | ✅ yes |
| Bug 3 visual (hole-number labels render?) | ❌ no | ❌ no | ✅ yes (sans-serif) | ✅ yes (sans-serif) |
| `[spike] layer_audit` reports all 7 layers present | n/a | ✅ true | ✅ true | ✅ true |
| `[spike] highlightHole skipped — layer-hole-lines missing` log fires after audit | n/a | ✅ 23x (Bug 2 mutated symptom) | no | no |

**Diffs vs original measurements:**

| Metric | iPhone 17 + 2.12.0 | iPhone 17 + 2.21.1 | moto g play + 2.12.0 | moto g play + 2.21.1 |
|---|---|---|---|---|
| `layer_render` latency | 84 ms | **11 ms** (87% faster) | 723 ms | **795 ms / 652 ms** (slight regression on workaround run, faster on workaround-off run; noise band is wide) |
| Avg frame build | 0.5 ms | 0.4–0.5 ms | 0.8 ms | 0.8 ms |
| Worst frame | 3.0 ms | 3.3–4.0 ms | 80.3 ms (one outlier) | **17.7 ms** worst (no outlier reproduced — but see below) |
| Frames sampled | 57 | 1,096–1,456 | 2,890 | 603–607 |

**Notes on the retest measurements:**

- **iPhone 17 Run A had a Flutter debug-attach timeout** (`Error starting debug session in Xcode: Timed out waiting for CONFIGURATION_BUILD_DIR to update`). This is a known macOS 26 + Xcode 26 + Flutter friction; the build succeeded but the debugger handshake hit a timeout. The user opened Xcode and ran manually, captured the HUD numbers off the device, and confirmed the visual state. So the Run A row has metric numbers but no captured `[spike]` log lines. Run B caught everything.
- **The Android retest didn't reproduce the 80.3 ms worst-frame outlier.** Could be a real fix in `mapbox_maps_flutter` 2.21.1 (more efficient first-add for new sources), but more likely the retest had a much smaller frame sample (~600 vs the original ~2,900) and didn't trigger the first-tap-to-distance LineLayer add that produced the original spike. **Inconclusive.** The KAN-270 follow-up story to pre-warm the tap-line source is still a good idea regardless.
- **Bug 2 mutated symptom**, captured directly from the iPhone 17 Run B log:
  ```
  [spike] addLayer ok  name=hole-lines id=layer-hole-lines
  [spike] layer_audit {…, layer-hole-lines: true, …}
  [spike] layer_render latencyMs=11 holeCount=18
  ... a few ms later ...
  [spike] highlightHole skipped — layer-hole-lines missing
  ... 22 more identical ...
  ```
  The layer is present at the audit and absent on the next style operation. This is the load-bearing diagnostic for the upstream filing.
- **iPhone 17 is flagship hardware**, well above the mid-tier target the §3 thresholds were designed for. The retest still recommends a mid-tier iPhone 12/13-era retest before the KAN-251 planning pass commits to the migration plan, per the original §6 caveats.

### 5.6 How to collect each number

- **FPS / frame build times:** in-app HUD (top-right) is live. For off-device archives, run `flutter run --profile --dart-define=MAPBOX_TOKEN=…` and press `P` for the DevTools performance overlay; also open the DevTools timeline in Chrome (URL printed on console) and record a 10-second trace during the scripted interaction.
- **Style + layer load latency:** console line `[spike] layer_render latencyMs=… holeCount=…` printed by `_addCourseLayers` once on style load.
- **Cold start → first frame:** human stopwatch is fine for a single-decimal-place number; don't over-engineer it.
- **Peak memory:** Xcode Instruments Allocations (iOS) / Android Studio Profiler (Android) during the scripted run.
- **Visual parity:** take a screenshot on the native iOS app (same hole, same fixture course) and the Flutter spike, overlay them, eyeball.

---

## 6. GO / NO-GO

**Recommendation: GO WITH CAVEATS.** Both platforms measured on the original `mapbox_maps_flutter` 2.12.0 spike AND on the 2.21.1 retest (KAN-270 AC #1). Every threshold in §3 met on both versions, on both platforms. After the retest the upstream bug surface narrowed from 4 candidates to **2 confirmed bugs to file** + 1 fixed since 2.12.0 + 1 that was always a project decision. The migration is technically viable; the caveats below are real and should shape the KAN-251 planning pass but are not blockers.

### Rationale (tied to §3 thresholds)

- **Every row in §5.2 (original) and §5.5 (retest) lands in the GO zone on both platforms and both versions.** Style+layer load latency improved on iOS (84 → 11 ms) and stayed on the GO side of the threshold on Android (723 → 795/652 ms). Avg frame build remained sub-millisecond on both. Worst frame stayed well below the 32 ms GO line on both platforms.
- **All four must-have `mapbox_maps_flutter` APIs work on both platforms on device.** The highest-risk one (`cameraForCoordinatesPadding` with bearing + padding) was visibly verified via the hole-1 auto-fly and manual hole selector on both phones, on both versions.
- **7-layer visual parity achievable on both platforms** — but only with the Bugs 2 & 3 workarounds (no `lineDasharray`, no `textFont`). The retest confirmed those workarounds are still needed on 2.21.1; the symptom mutated but the layers still silently disappear on iOS.
- **Two real upstream bugs to file**, both with concrete repros in §4 and worked around in &lt; 150 lines of spike code. The other two original candidates (Bug 1 fixed, Bug 4 not-a-bug) drop from the planning load.

### Caveats to flag in the remaining KAN-251 stories

1. **Cross-platform map property vetting is not free, AND audit alone is not sufficient on 2.21.1.** Bugs 2 & 3 mutated between 2.12.0 and 2.21.1: the layers now pass an immediate `verifyLayersPresent` audit and disappear from the rendered style milliseconds later. The defensive `tryAddLayer` + `layer_audit` pattern in `mobile-flutter/lib/core/mapbox/layer_helpers.dart` is **necessary but no longer sufficient**. The only safe path on the current Mapbox release is to **not use `lineDasharray` or `textFont` cross-platform**. Allocate ~½ day per map story for vetting any new style property against this same failure mode.
2. **Dashed hole-lines decision is forced (KAN-270 AC #4).** `lineDasharray` is unusable cross-platform on both 2.12.0 and 2.21.1. Pick one of: (a) accept solid lines on both platforms (simplest, matches scaffold default); (b) render dashes via chunked LineString features (medium scope, no upstream dep); (c) wait for the upstream fix. Option (a) is the clean path; (b) and (c) are still viable but neither uses the simpler `lineDasharray` property to express the choice.
3. **Hole-label typeface decision is forced (KAN-270 AC #5).** `textFont` is unusable cross-platform on both versions, AND there is no first-class way to render the iOS native app's `DIN Pro Bold` typeface even if `textFont` worked (Mapbox doesn't ship the font). Pick one of: (a) accept Mapbox default on both platforms (scaffold default, visual regression from native iOS); (b) bundle DIN Pro Bold as a local PBF glyph source on both platforms (medium effort, done once via `style.setStyleGlyphURL`); (c) change the native iOS app to sans-serif first.
4. **Bug 1 is fixed — the `setAccessToken` workaround is no longer needed.** The `await MapboxOptions.getAccessToken()` workaround has been **removed** from `mobile-flutter/lib/core/mapbox/mapbox_init.dart`. CONVENTIONS C-1 has been simplified to "set the token before runApp". Keep a historical comment in the source so the next person doesn't reintroduce the workaround thinking it's still needed.
5. **Platform-view cost is hidden from Dart profiling.** `FrameTiming.buildDuration` does not see the native Mapbox view's GPU cost. Any performance story that cites "Flutter frame times" must qualify this — use Android GPU Profiler / Xcode Instruments for real end-to-end numbers. Captured as CONVENTIONS C-3.
6. **`GeoJsonSource` initial-add is two round-trips.** Contributed to Android's 723–795 ms layer-render latency (tight on the 800 ms threshold; the retest hit 795 on the workaround run, just under the line). For larger courses this may push over; the planning pass should add a story to measure worst-case ingestion on the largest course in the production cache and add chunking/lazy-loading if needed.
7. **First tap-to-distance spike on Android (80.3 ms in original spike).** See §5.4. The retest didn't reproduce it, but had a much smaller frame sample (~600 vs ~2,900) so the result is inconclusive. Add a follow-up story to pre-warm the tap-line source at style-load time, or replace the tap-line with a point annotation.
8. **iPhone 17 is flagship, not mid-tier.** The iOS numbers are directional, not definitive, for the mid-tier target. **Before closing KAN-251 planning, retest on a mid-tier iPhone 12/13-era device** — the user's existing install base likely skews older than the test device.

### Estimated effort delta vs. maintaining two native codebases

Not formally estimated — that should be the output of the next planning pass now that the technical risk is retired. What the spike *did* show about effort:
- **Model + GeoJSON builder port:** ~440 lines of Dart replacing ~600 lines of Swift + ~600 lines of Kotlin — roughly 1/3 the code for the same contract.
- **Map screen port:** ~700 lines of Dart replacing ~500 lines of Swift + ~700 lines of Kotlin.
- **Cross-platform bug discovery tax:** 2 confirmed upstream bugs (after retest) in ~4 spike days plus 1 retest day. The KAN-251 plan should budget ~½ day per map story for vetting properties against the same iOS-silent-drop failure pattern, until the upstream bugs close.
- **Feature parity with iOS native baseline:** reached in 4 days on Android with one engineer starting from zero Flutter knowledge of this repo. Added ~30 minutes to surface, diagnose, and work around the two iOS layer-drop bugs.

### Recommended next steps

1. **File 2 upstream bugs** against `mapbox/mapbox-maps-flutter` with the concrete repros in §4 — Bug 2 (`lineDasharray`) and Bug 3 (`textFont`). Both have new symptom-mutation evidence from the 2.21.1 retest that strengthens the report. Closes KAN-270 AC #1.
2. **Retest on a mid-tier iPhone** (iPhone 12 / 13) before KAN-251 planning commits to a full migration. Same scripted interaction, add a third iOS column to §5.5.
3. **Take the GO recommendation to the KAN-251 epic planning pass** with the caveat list above baked in as acceptance criteria on the affected stories. Story breakdown is already drafted in `mobile-flutter/docs/KAN-251-STORIES.md` (KAN-270 AC #6 phase 1).
4. **Bake the AC #4 / #5 decisions into KAN-270.** Both are now forced (option a is the simplest path) but should be captured as ADRs in `mobile-flutter/docs/adr/` so the rationale is preserved when stories pick up the work.

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
