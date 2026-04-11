import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'map_screen.dart';

/// KAN-252 Flutter/Mapbox spike — entry point.
///
/// KAN-270 AC #1 retest (2026-04-11): the `setAccessToken` async race
/// (SPIKE_REPORT §4 Bug 1) was confirmed broken on mapbox_maps_flutter
/// 2.12.0. This entry point now lets us test both scenarios in one
/// build by gating the workaround on `--dart-define=BUG1_REPRO=true`.
///
/// To repro Bug 1 (no workaround):
///   flutter run --profile -d <id> \
///     --dart-define=MAPBOX_TOKEN=pk.xxx \
///     --dart-define=BUG1_REPRO=true
///
/// To run normally (with workaround):
///   flutter run --profile -d <id> \
///     --dart-define=MAPBOX_TOKEN=pk.xxx
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const token = String.fromEnvironment('MAPBOX_TOKEN');
  if (token.isEmpty) {
    runApp(const _MissingTokenApp());
    return;
  }

  const bug1Repro = bool.fromEnvironment('BUG1_REPRO');
  MapboxOptions.setAccessToken(token);
  if (!bug1Repro) {
    // Workaround: force a pigeon round-trip so the set lands before
    // any MapWidget tries to inflate. See SPIKE_REPORT §4 Bug 1.
    await MapboxOptions.getAccessToken();
  } else {
    debugPrint('[spike] BUG1_REPRO=true — skipping setAccessToken await');
  }

  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CaddieAI Flutter Spike',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const MapScreen(),
    );
  }
}

class _MissingTokenApp extends StatelessWidget {
  const _MissingTokenApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'MAPBOX_TOKEN missing.\n\n'
              'Run with:\n'
              'flutter run --dart-define=MAPBOX_TOKEN=pk.xxx',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.amber.shade200, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}
