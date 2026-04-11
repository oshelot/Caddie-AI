// Top-level MaterialApp. For now this is a bare placeholder — real
// navigation, routing, theming, and feature screens land as KAN-251
// stories are picked up.
//
// The placeholder home screen renders a small set of CaddieIcons as a
// smoke test for the icon SVG integration (KAN-291 / ADR 0007). If
// those icons render as blank space or fail to load, the asset
// declaration in pubspec.yaml is wrong. Don't remove the smoke test
// until KAN-271 ships a real home screen that exercises CaddieIcons
// in production code paths.

import 'package:flutter/material.dart';

import 'core/icons/caddie_icons.dart';

class CaddieApp extends StatelessWidget {
  const CaddieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CaddieAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const _ScaffoldPlaceholder(),
    );
  }
}

class _ScaffoldPlaceholder extends StatelessWidget {
  const _ScaffoldPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CaddieAI',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Flutter migration scaffold (KAN-251)',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              const Text(
                'No screens wired up yet.\nSee docs/CONVENTIONS.md for migration guidelines.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 32),
              // Smoke test for the CaddieIcons SVG integration (KAN-291).
              // If any of these render as blank space or fail to load,
              // the asset declaration in pubspec.yaml is wrong — see
              // docs/design/icons.md and ADR 0007.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CaddieIcons.flag(size: 40, color: Colors.greenAccent),
                  const SizedBox(width: 24),
                  CaddieIcons.golfer(size: 40, color: Colors.white),
                  const SizedBox(width: 24),
                  CaddieIcons.distance(size: 40, color: Colors.amberAccent),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'CaddieIcons smoke test (flutter_svg)',
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
