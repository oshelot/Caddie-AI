// CaddieAI Flutter app entry point — KAN-251 migration.
//
// The only non-obvious thing this file does is `await initMapbox()`
// before `runApp()`. That's critical — see `core/mapbox/mapbox_init.dart`
// for the historical context (KAN-252 SPIKE_REPORT §4 Bug 1, fixed in
// mapbox_maps_flutter 2.13+ but the await is kept as a safety belt
// per CONVENTIONS C-1).
//
// CaddieApp is non-const because it owns a `GoRouter` instance built
// in its constructor (see lib/app.dart) — that's why `runApp` doesn't
// take a `const` here.

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/mapbox/mapbox_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMapbox();
  runApp(CaddieApp());
}
