// Mapbox bootstrap — call this once, very early in `main()`, BEFORE any
// `MapWidget` is constructed. Encapsulates the workaround for a known
// upstream bug in mapbox_maps_flutter 2.12.0 (see KAN-252 SPIKE_REPORT
// §4 Bug 1).
//
// ## The bug
//
// `MapboxOptions.setAccessToken(String)` is declared `static void` in
// the public API, but internally fires an **async** pigeon message that
// takes a platform-channel round-trip to land on the native side.
//
// If `runApp()` proceeds before that message lands and a `MapWidget`
// tries to inflate, the native MapView throws:
//
//   com.mapbox.maps.MapboxConfigurationException:
//   Using MapView, MapSurface, Snapshotter or other Map components
//   requires providing a valid access token when inflating or creating
//   the map.
//
// The public API gives no clean hook to await the set — so we force a
// channel round-trip by awaiting an unrelated getter that serializes
// behind the same pigeon channel. When `getAccessToken()` resolves,
// we know the set has landed.
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

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Compile-time constant read from `--dart-define=MAPBOX_TOKEN=pk.xxx`.
/// `String.fromEnvironment` only evaluates at compile time, so the token
/// is baked into the AOT binary; no runtime env lookup is performed.
const String _kMapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

/// Initializes the Mapbox SDK on the native side. Must be awaited
/// before any `MapWidget` is constructed anywhere in the app.
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
  // Force the async pigeon message to land before returning.
  // See the header comment for why this is necessary.
  await MapboxOptions.getAccessToken();
}
