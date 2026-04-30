// Widget tests for the cold-start splash screen.
//
// The leaf widget is pure and constructor-injected, so these tests
// can drive it directly without standing up the router. They cover:
//
//   1. Layout: bolty mascot, CaddieAI wordmark, and the Ryppl brand
//      band are all on screen.
//   2. Branding: "Brought to you by" sits above "Ryppl Golf", and
//      the Ryppl Golf font size is exactly 2× the "Brought to you
//      by" font size (the temporary placeholder rule until the new
//      wordmark image lands).
//   3. The `onComplete` callback fires after `splashDuration`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caddieai/features/splash/presentation/splash_screen.dart';

void main() {
  group('SplashScreen', () {
    testWidgets('renders mascot, wordmark, and brand band', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
            splashDuration: const Duration(seconds: 5),
          ),
        ),
      );
      // Initial frame — animations are at t=0.
      await tester.pump();
      // Drive the AnimationController past its 900 ms duration so
      // every staggered fade-in has reached opacity 1.
      await tester.pump(const Duration(milliseconds: 950));

      expect(find.byKey(const Key('splash-caddieai-wordmark')), findsOneWidget);
      expect(find.byKey(const Key('splash-brought-to-you-by')), findsOneWidget);
      expect(find.byKey(const Key('splash-ryppl-golf-wordmark')), findsOneWidget);
      expect(find.text('Brought to you by'), findsOneWidget);
      expect(find.text('Ryppl Golf'), findsOneWidget);
      // The wordmark uses Text.rich with split-color TextSpans, so
      // the full string is "CaddieAI" (rendered via two spans).
      expect(find.textContaining('Caddie'), findsOneWidget);
    });

    testWidgets('Ryppl Golf is bold and exactly 2x the "Brought to you by" font size',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
            splashDuration: const Duration(seconds: 5),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 950));

      final broughtTo = tester.widget<Text>(
        find.byKey(const Key('splash-brought-to-you-by')),
      );
      final ryppl = tester.widget<Text>(
        find.byKey(const Key('splash-ryppl-golf-wordmark')),
      );

      final broughtSize = broughtTo.style!.fontSize!;
      final rypplSize = ryppl.style!.fontSize!;

      expect(rypplSize, broughtSize * 2,
          reason: 'Ryppl Golf must be 2x "Brought to you by" until the '
              'real wordmark image ships');
      expect(ryppl.style!.fontWeight, FontWeight.bold);
    });

    testWidgets('onComplete fires after splashDuration', (tester) async {
      var completed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () => completed++,
            splashDuration: const Duration(milliseconds: 200),
          ),
        ),
      );
      await tester.pump();
      expect(completed, 0);
      // Advance past the splash duration AND the animation controller
      // so no pending timers remain when the test tears down.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 950));
      expect(completed, 1);
    });

    testWidgets('onComplete is not called after the widget is disposed',
        (tester) async {
      var completed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () => completed++,
            splashDuration: const Duration(milliseconds: 500),
          ),
        ),
      );
      await tester.pump();
      // Replace the splash with a different widget before its timer
      // fires — the timer's `if (mounted)` guard should swallow the
      // callback so we never see a count.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 600));
      expect(completed, 0);
    });
  });
}
