// Mapbox bootstrap — call this once, very early in `main()`, BEFORE any
// `MapWidget` is constructed.
//
// ## Usage
//
// ```dart
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await initMapbox();
//   runApp(const App());
// }
// ```
//
// ## Token source
//
// The public token is read from the `MAPBOX_TOKEN` compile-time
// environment variable. Pass it via `--dart-define` at build time:
//
//   flutter run --dart-define=MAPBOX_TOKEN=pk.xxx
//
// The token is NEVER hard-coded or committed. If the variable is
// missing, `initMapbox` throws a `StateError` with a clear message
// rather than letting the app render a silently-blank map.
//
// ## Historical note — `setAccessToken` async race (KAN-252 SPIKE_REPORT §4 Bug 1)
//
// On `mapbox_maps_flutter` 2.12.0, `MapboxOptions.setAccessToken(String)`
// was declared `static void` but internally fired an **async** pigeon
// message. If `runApp()` proceeded before that message landed and a
// `MapWidget` tried to inflate, the native MapView threw:
//
//   com.mapbox.maps.MapboxConfigurationException:
//   Using MapView, MapSurface, Snapshotter or other Map components
//   requires providing a valid access token when inflating or creating
//   the map.
//
// The workaround was to force a channel round-trip by awaiting an
// unrelated getter behind the same pigeon channel:
//
//     MapboxOptions.setAccessToken(token);
//     await MapboxOptions.getAccessToken(); // forces a round-trip
//
// **Verified fixed in `mapbox_maps_flutter` 2.21.1** (KAN-270 AC #1
// retest, 2026-04-11). Both Android (moto g play 2024) and iOS
// (iPhone 17) loaded cleanly with the workaround disabled. The
// workaround has been removed from this function.
//
// **Do not reintroduce the `await getAccessToken()` line** thinking
// it's still needed — verify against the current pinned version
// (`pubspec.yaml`) before changing this. If the bug ever resurfaces,
// the symptom is `MapboxConfigurationException` on the first
// `MapWidget` inflation, repeatable from a cold start.

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Compile-time constant read from `--dart-define=MAPBOX_TOKEN=pk.xxx`.
/// `String.fromEnvironment` only evaluates at compile time, so the token
/// is baked into the AOT binary; no runtime env lookup is performed.
const String _kMapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

/// Initializes the Mapbox SDK on the native side. Must be called
/// (and awaited, for safety) before any `MapWidget` is constructed
/// anywhere in the app.
///
/// Throws [StateError] if `MAPBOX_TOKEN` was not passed at build time.
Future<void> initMapbox() async {
  if (_kMapboxToken.isEmpty) {
    throw StateError(
      'MAPBOX_TOKEN not set. Run with '
      '`--dart-define=MAPBOX_TOKEN=pk.xxx`. See docs/CONVENTIONS.md.',
    );
  }
  MapboxOptions.setAccessToken(_kMapboxToken);
}
