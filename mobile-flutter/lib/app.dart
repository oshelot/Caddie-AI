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
              // White card + untinted (source-color, i.e. black) icons
              // to match how the SVGs were designed: black strokes on
              // a light background. This isolates "is flutter_svg
              // rendering the SVGs correctly" from "are my smoke-test
              // colors right". If these don't show recognizable line
              // drawings, the issue is flutter_svg or the SVGs
              // themselves — not the smoke test.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CaddieIcons.flag(size: 48),
                    const SizedBox(width: 24),
                    CaddieIcons.golfer(size: 48),
                    const SizedBox(width: 24),
                    // `distance` swapped out — design is being redone.
                    // `target` picked because it's simple geometry
                    // (circle + 4 crosshair lines) with no transforms,
                    // so it's a clean smoke-test sample.
                    CaddieIcons.target(size: 48),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'CaddieIcons smoke test — black on white, untinted',
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
