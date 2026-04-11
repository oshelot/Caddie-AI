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

## 1. Mapbox token bootstrap — call `initMapbox()` before `runApp`

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

### Historical note — the old async-race workaround (do not reintroduce)

On `mapbox_maps_flutter` 2.12.0, `setAccessToken` was async-under-the-
hood and the first `MapWidget` could inflate before the token landed,
throwing `MapboxConfigurationException`. The workaround was to await
`MapboxOptions.getAccessToken()` after setting, to force a pigeon
round-trip (SPIKE_REPORT §4 Bug 1).

**That bug is fixed in `mapbox_maps_flutter` 2.21.1** (KAN-270 AC #1
retest, 2026-04-11). Both Android and iOS now load cleanly without the
await. The workaround has been removed from `initMapbox()` accordingly.

**Do not reintroduce `await MapboxOptions.getAccessToken()`** in
`initMapbox()` unless you've verified the bug has resurfaced in a newer
`mapbox_maps_flutter` version. If it has, the symptom is
`MapboxConfigurationException` on the first `MapWidget` inflation,
repeatable from a cold start.

## 2. Style layer adds — ALWAYS use `tryAddLayer` + `verifyLayersPresent`, AND avoid known-broken properties

On iOS, `style.addLayer(...)` silently drops layers when certain
properties are set. Confirmed broken on **both** `mapbox_maps_flutter`
2.12.0 AND 2.21.1 (KAN-270 AC #1 retest):

- **`LineLayer.lineDasharray`** — SPIKE_REPORT §4 Bug 2.
- **`SymbolLayer.textFont`** — SPIKE_REPORT §4 Bug 3.

Setting either property on the corresponding layer type causes that
layer to silently disappear from the rendered style on iOS. Android
handles both properties correctly.

### The symptom mutated between 2.12.0 and 2.21.1 — the audit alone is no longer enough

**On 2.12.0**, the bug was easy to detect: `addLayer` returned ok,
`getLayer` returned `null` immediately after, and downstream property
mutations threw `PlatformException(0, "Layer ... is not in style")`.
A single `verifyLayersPresent` audit at style-loaded time caught it.

**On 2.21.1**, the failure mode changed: `addLayer` returns ok, the
**immediate audit reports the layer present**, and the layer
disappears from the rendered style **a few milliseconds later**,
before the first style mutation. Captured directly from the iPhone 17
retest log:

```
[spike] addLayer ok  name=hole-lines id=layer-hole-lines
[spike] layer_audit {…, layer-hole-lines: true, …}
[spike] layer_render latencyMs=11 holeCount=18
... a few ms later, on first hole tap ...
[spike] highlightHole skipped — layer-hole-lines missing
... 22 more identical ...
```

The defensive audit pattern this convention used to recommend is
**necessary but no longer sufficient**. The audit can no longer be
trusted as a "layer is committed" signal — it's only a "layer was
present at the moment we checked" signal.

### Rule

1. **Never use `LineLayer.lineDasharray` or `SymbolLayer.textFont`
   cross-platform.** Both are confirmed silently-dropped on iOS in
   the current pinned `mapbox_maps_flutter` version. If a new map
   story needs dashed lines or a custom font, use one of the
   workarounds documented in §5 — do not just set the property and
   hope.
2. **Never call `style.addLayer` directly.** Use `tryAddLayer` from
   `lib/core/mapbox/layer_helpers.dart` so silent failures get logged
   with a clear `name` tag.
3. **Always call `verifyLayersPresent` immediately after a batch of
   adds.** It's no longer a sufficient guarantee, but it still
   catches Bug 2/3-class failures fast enough to fail the build in
   debug mode and warn the developer, AND it catches any future
   silent-add bugs that haven't yet mutated to the audit-passing
   pattern.
4. **Every style-layer property mutation** (`setStyleLayerProperty`,
   `updateLayer`) MUST first check the layer exists with
   `safeGetLayer` and degrade gracefully if it returns null. The
   pattern lives in the spike's `_highlightHole` for reference.

```dart
// Add every layer through tryAddLayer so silent failures get logged.
await tryAddLayer(map.style, name: 'hole-lines', build: () => LineLayer(
  id: _holeLinesLayer,
  sourceId: _sourceId,
  filter: ['==', ['get', 'type'], 'holeLine'],
  lineColor: 0xFFFFFFFF,
  lineWidth: 2.0,
  // ⚠️  DO NOT set lineDasharray here — see §5 for the dashed-line
  //     workaround. SPIKE_REPORT §4 Bug 2.
));

// Audit immediately, then again before each significant mutation
// batch. The audit catches some failures but is no longer sufficient
// on its own (see header comment above).
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
  // Log, degrade gracefully, surface a dev-facing error banner
  // (kDebugMode only) — but do NOT proceed as if all layers are
  // present.
}
```

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

This project pins `mapbox_maps_flutter` to a specific tested version.
The current pin is in `pubspec.yaml`. The KAN-252 spike validated
**2.12.0** originally and **2.21.1** in the KAN-270 retest — both have
the same iOS layer-drop bugs (Bugs 2 and 3 in SPIKE_REPORT §4), with
the symptom mutated between versions.

**Rule:** do NOT bump `mapbox_maps_flutter` without:
1. Re-running the spike's scripted interaction on both platforms.
2. Auditing layer presence with `verifyLayersPresent` AND visually
   confirming all 7 course overlay layers render after a few seconds
   of interaction.
3. Re-checking whether Bugs 2 and 3 still reproduce. If they're
   finally fixed upstream, this convention can relax — but only after
   visual confirmation.

Version bumps have historically introduced iOS-side silent layer-add
regressions and silent symptom mutations; **every bump is a full
map-smoke-test event**.

## 5. Typeface and dashed hole-lines — decisions are FORCED post-retest

Two cosmetic gaps from the spike used to be open project decisions.
After the KAN-270 retest confirmed both bugs persist on `mapbox_maps_
flutter` 2.21.1, the simplest path is now the only safe-by-default
path. Stories that render hole-lines or hole-labels can proceed using
the defaults below; stories that want anything fancier must take on
the workaround scope explicitly.

### Hole-line dashes (KAN-270 AC #4)

**Default: solid white hole-lines on both platforms.** This is what
the scaffold uses today. `LineLayer.lineDasharray` is silently dropped
on iOS (SPIKE_REPORT §4 Bug 2), so any layer that sets it is
guaranteed to render incorrectly on iOS regardless of how the audit
reports.

If a future story needs dashed hole-lines:
- **(b) Render dashes via chunked LineString features** — split each
  hole's line of play into many small alternating segments inside the
  GeoJSON builder. Medium scope. No upstream dependency. **This is the
  only known workaround.**
- **(c) Wait for the upstream fix.** Not recommended — Bug 2 has
  persisted across at least 9 months of releases (2.12.0 → 2.21.1).

### Hole-label typeface (KAN-270 AC #5)

**Default: Mapbox-hosted sans-serif on both platforms** (the Mapbox
default font for the SATELLITE_STREETS style). This is what the
scaffold uses today. `SymbolLayer.textFont` is silently dropped on
iOS (SPIKE_REPORT §4 Bug 3), so any layer that sets it is guaranteed
to render incorrectly on iOS.

This is a **visual regression from the iOS native app**, which
renders hole-number labels in `DIN Pro Bold` (an iOS system font that
Mapbox does not bundle, SPIKE_REPORT §4 Bug 4). Document the
regression in design / product before committing to migration.

If matching the native iOS typeface matters:
- **(b) Bundle DIN Pro Bold as a local PBF glyph source on both
  platforms.** Generate a glyph PBF set from the font file, host it,
  and call `style.setStyleGlyphURL` at style-load time. Medium effort,
  done once. **This bypasses both Bug 3 (don't set `textFont`, change
  the glyph URL instead) and Bug 4 (the URL hosts whatever font you
  want).**
- **(c) Switch the iOS native app to sans-serif first.** Smallest
  Flutter-side effort but requires a coordinated change in the
  existing iOS codebase before the migration starts. Probably a
  separate ticket on the native team.

**Rule:** stories that render hole-lines or hole-labels can use the
defaults above without further sign-off. Stories that pick option (b)
must reference a captured ADR in `docs/adr/` before merging.

## 6. Icons — always use `CaddieIcons`, never Material defaults

The CaddieAI app has a custom 45-icon set that's part of the brand
identity. Source SVGs live in `/home/apatel/Caddie-AI-Iconagraphy/
caddieai-icons/` and are mirrored into `mobile-flutter/assets/icons/`
as the runtime asset. They're rendered via `flutter_svg` per
**ADR 0007** (which superseded the failed icon-font attempt in
ADR 0006 — see the ADR for the post-mortem).

**Rule:** every icon in feature code MUST be rendered via a named
helper from `CaddieIcons`. Never use:

- `Icon(Icons.material_icon_name, ...)` — Flutter's bundled Material set
- `SvgPicture.asset('assets/icons/icon-foo.svg', ...)` — bypasses the registry
- `Image.asset('assets/icons/...')` — raw bitmap fallback
- Inline `IconData(0xXXXX, fontFamily: ...)` constants

```dart
// ✅ correct — named helper, type-safe at call site
CaddieIcons.flag(size: 24)
CaddieIcons.flag(size: 32, color: Theme.of(context).colorScheme.primary)

// ❌ wrong — Material default
Icon(Icons.flag, size: 24)

// ❌ wrong — bypasses the registry, no type safety
SvgPicture.asset('assets/icons/icon-flag.svg', width: 24)

// ❌ wrong — defunct icon-font path from rejected ADR 0006
Icon(IconData(0xF11B, fontFamily: 'CaddieIcons'))
```

For dynamic / data-driven cases where the icon name comes from a
variable (e.g. an icon picker, a config-driven menu item), use
`CaddieIcons.byName('flag', size: 24)`. Throws `ArgumentError` if the
name isn't in the registry — fail loud, not silent.

If a UI story needs an icon that isn't in the set, **add it to the
set first** via a separate ticket that:

1. Drops the new SVG into `/home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/`
   (the source-of-truth dir) AND mirrors it into
   `mobile-flutter/assets/icons/` (the runtime asset)
2. Adds an entry to the `_paths` map in `lib/core/icons/caddie_icons.dart`
3. Adds a named getter that delegates to `_render('newName', size, color)`
4. Updates `docs/design/icons.md` with the new icon's name + intended use
5. Runs `flutter test` — the registry test will fail with a count
   mismatch until the entry is added (intentional canary)

Don't ad-hoc a Material icon "just for now". The whole point of the
icon set is brand consistency; one Material fallback in feature code
breaks the contract.

### Sizes and tinting

Use the standard `CaddieIcons` sizes:

- **16 dp** — compact (inline with body text, dense lists)
- **20 dp** — default (most icon-button uses)
- **24 dp** — prominent (primary CTAs, tab bar)
- **32 dp** — hero (empty states, splash)

Tint by passing `color:` to the named getter. Pull theme colors from
`Theme.of(context).colorScheme.X` rather than hardcoding hex literals
at the call site. Note: unlike Material's `Icon` widget, `flutter_svg`
does NOT automatically inherit from `IconTheme` — you must pass
`color:` explicitly when you want tinting.

## 7. Do not merge this scaffold into `main`

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
  pubspec.yaml                         # mapbox_maps_flutter version pin (see §4)
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
