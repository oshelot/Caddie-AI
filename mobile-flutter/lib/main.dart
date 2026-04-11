// CaddieAI Flutter app entry point — KAN-251 migration.
//
// Two things must complete before `runApp()`:
//
//   1. `await initMapbox()` — see `core/mapbox/mapbox_init.dart`
//      for the historical context (KAN-252 SPIKE_REPORT §4 Bug 1).
//      Per CONVENTIONS C-1, every process that constructs a
//      `MapWidget` must await this first.
//   2. `await AppStorage.init()` — opens the Hive boxes used by
//      the KAN-272 (S2) storage layer. The MainShell tabs read
//      the profile box on first frame, so the boxes have to be
//      open by the time the first widget renders. The migration
//      importer (KAN-272 AC #2) is run lazily by the screens that
//      need profile data — not here, to keep cold-start latency
//      bounded.
//
// CaddieApp is non-const because it owns a `GoRouter` instance built
// in its constructor (see lib/app.dart) — that's why `runApp` doesn't
// take a `const` here.

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/mapbox/mapbox_init.dart';
import 'core/storage/app_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMapbox();
  await AppStorage.init();
  runApp(CaddieApp());
}
