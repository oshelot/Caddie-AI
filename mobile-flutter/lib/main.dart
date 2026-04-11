// CaddieAI Flutter app entry point — KAN-251 migration.
//
// The only non-obvious thing this file does is `await initMapbox()`
// before `runApp()`. That's critical — see `core/mapbox/mapbox_init.dart`
// for the full explanation. TL;DR: `MapboxOptions.setAccessToken` is
// async despite its `void` signature, and skipping the await crashes
// the first `MapWidget` inflation with `MapboxConfigurationException`.

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/mapbox/mapbox_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMapbox();
  runApp(const CaddieApp());
}
