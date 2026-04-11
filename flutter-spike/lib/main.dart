import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'map_screen.dart';

/// KAN-252 Flutter/Mapbox spike — entry point.
Future<void> main() async {
  // Read the Mapbox public token from --dart-define=MAPBOX_TOKEN=pk.xxx.
  // Never hard-coded, never committed.
  const token = String.fromEnvironment('MAPBOX_TOKEN');
  if (token.isEmpty) {
    runApp(const _MissingTokenApp());
    return;
  }

  // `setAccessToken` is declared void but internally fires an async pigeon
  // message. If runApp proceeds before that message lands, the native
  // MapView throws MapboxConfigurationException on inflation. Force a
  // round-trip by awaiting getAccessToken — it can't resolve until the
  // set has propagated to the native side.
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken(token);
  await MapboxOptions.getAccessToken();

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
