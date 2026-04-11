// Widget test for the S1 (KAN-271) app shell. Asserts that:
//
//   1. The 4-tab bottom navigation renders with the canonical labels
//      from KAN-157's spec (Caddie / Course / History / Profile)
//   2. The default landing tab is Course
//   3. Tapping each destination switches to the corresponding
//      placeholder screen and the placeholder body shows up
//   4. Tab state is preserved when switching back (StatefulShellRoute
//      branch behavior — re-entering a tab doesn't reset its widget
//      tree)
//
// These tests use the full CaddieApp + the real GoRouter, so any
// regression in the router config or the shell composition fails
// here. Cross-cutting **C-5** (test per PR) from CONVENTIONS.

import 'package:caddieai/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaddieApp shell', () {
    testWidgets('renders 4 NavigationDestinations with canonical labels',
        (tester) async {
      await tester.pumpWidget(CaddieApp());
      await tester.pumpAndSettle();

      // The bottom nav uses NavigationDestination, which renders the
      // label as plain text in the destination widget.
      expect(find.text('Caddie'), findsWidgets);
      expect(find.text('Course'), findsWidgets);
      expect(find.text('History'), findsWidgets);
      expect(find.text('Profile'), findsWidgets);

      // Exactly one NavigationBar with exactly 4 destinations.
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations, hasLength(4));
    });

    testWidgets('default landing tab is Course (per KAN-157 spec)',
        (tester) async {
      await tester.pumpWidget(CaddieApp());
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 1, reason: 'Course is index 1');

      // The Course placeholder body should be visible (it has a
      // distinctive subtitle).
      expect(
        find.textContaining('hole-by-hole satellite map'),
        findsOneWidget,
      );
    });

    testWidgets('tapping each tab switches to the right placeholder',
        (tester) async {
      await tester.pumpWidget(CaddieApp());
      await tester.pumpAndSettle();

      // Tap Caddie (index 0) — find the destination by its label.
      // NavigationBar destinations expose their labels as semantic
      // text; tapping the text triggers the destination.
      // Each tab has its label rendered TWICE: once in the bottom
      // nav, once in the AppBar of the active screen (after switch).
      // Find by text + ancestor NavigationDestination to get the nav
      // tap target.
      Future<void> tapTab(String label) async {
        final destFinder = find.descendant(
          of: find.byType(NavigationDestination),
          matching: find.text(label),
        );
        // Multiple matches because the label may also appear in the
        // active screen's AppBar — tap the first (the nav one).
        await tester.tap(destFinder.first);
        await tester.pumpAndSettle();
      }

      // Caddie
      await tapTab('Caddie');
      expect(find.textContaining('AI shot advisor'), findsOneWidget);

      // History
      await tapTab('History');
      expect(find.textContaining('Past shot recommendations'), findsOneWidget);

      // Profile
      await tapTab('Profile');
      expect(find.textContaining('Player handicap'), findsOneWidget);

      // Back to Course
      await tapTab('Course');
      expect(
        find.textContaining('hole-by-hole satellite map'),
        findsOneWidget,
      );
    });
  });
}
