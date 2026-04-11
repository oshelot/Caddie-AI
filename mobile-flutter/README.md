# CaddieAI — Flutter unified mobile codebase

KAN-251 Flutter migration. Replaces the existing Swift/SwiftUI iOS app
(`ios/`) and Kotlin/Compose Android app (`android/`) with a single
Flutter codebase that consumes the existing LLM proxy, course cache,
and logging backends without changing them.

**Status: scaffolding.** This directory contains:

- Flutter project created from `flutter create` and patched with the
  Day-1 version fixes from the KAN-252 spike (Gradle 8.7, AGP 8.5.0,
  Kotlin 1.9.24, compileSdk 35, NDK 26.1, Java 17, minSdk 24,
  iOS deployment target 14).
- `mapbox_maps_flutter` 2.12.0 pinned (see `docs/CONVENTIONS.md §4`).
- The spike's validated Dart ports of `NormalizedCourse`,
  `NormalizedHole`, and `CourseGeoJSONBuilder`, restructured into
  `lib/core/geo/`, `lib/models/`, and `lib/services/`.
- The spike's two load-bearing Mapbox helpers: `initMapbox()` (the
  `setAccessToken` async-race workaround) and `tryAddLayer` +
  `verifyLayersPresent` (the iOS silent-layer-drop detector).
- A placeholder home screen that says "scaffold".

Nothing user-facing is implemented yet. Real feature stories land
under KAN-251 once **KAN-270** (the planning pass) is complete.

## Before you write any code

**Read `docs/CONVENTIONS.md`.** It's distilled from the KAN-252 spike
and captures four enforceable rules that every story must follow —
skipping them will cost you a half-day of debugging the same issues
the spike already found.

**Read `flutter-spike/SPIKE_REPORT.md`** on branch
`kan-252-flutter-spike` for the full context behind those rules.
Particularly §4 (runtime bugs with repros) and §6 (GO rationale +
caveats).

## Running

See `docs/CONVENTIONS.md` for the current commands. TL;DR:

```bash
flutter pub get
flutter test
flutter run --profile -d <device-id> \
  --dart-define=MAPBOX_TOKEN=pk.xxx
```

`MAPBOX_TOKEN` is in `../android/local.properties` (key
`MAPBOX_API_KEY`). Never commit the token.

## Do not merge to `main` yet

This scaffold lives on branch `kan-251-mobile-flutter-scaffold` and
stays there until KAN-270 closes. The first real migration story is
what merges, not the scaffold itself.
