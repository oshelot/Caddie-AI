// Top-level MaterialApp. For now this is a bare placeholder — real
// navigation, routing, theming, and feature screens land as KAN-251
// stories are picked up.
//
// The placeholder home screen renders a small set of CaddieIcons as a
// smoke test for the icon font integration (KAN-291). If those icons
// render as boxes or "?" glyphs at runtime, the font wiring is broken
// and the rest of the migration's UI work will be visually wrong.
// Don't remove the smoke test until KAN-271 ships a real home screen
// that exercises CaddieIcons in production code paths.

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
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CaddieAI',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Flutter migration scaffold (KAN-251)',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              SizedBox(height: 24),
              Text(
                'No screens wired up yet.\nSee docs/CONVENTIONS.md for migration guidelines.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              SizedBox(height: 32),
              // Smoke test for the CaddieIcons font integration (KAN-291).
              // If any of these render as a box or "?" glyph at runtime,
              // the font wiring is broken — see docs/design/icons.md.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CaddieIcons.flag, size: 32, color: Colors.greenAccent),
                  SizedBox(width: 24),
                  Icon(CaddieIcons.golfer, size: 32, color: Colors.white),
                  SizedBox(width: 24),
                  Icon(CaddieIcons.distance, size: 32, color: Colors.amberAccent),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'CaddieIcons smoke test',
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
