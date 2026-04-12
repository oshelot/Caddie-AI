// Widget tests for KAN-284 (S14) OnboardingScreen.
//
// Coverage:
//   1. Renders the setup-notice step on first build
//   2. Step counter (1/6) reflects current step
//   3. Next button advances through every step
//   4. Back button returns to previous step (hidden on step 1)
//   5. Skip persists whatever data the user entered AND flips
//      `hasCompletedSwingOnboarding = true` so the redirect
//      stops firing on next launch (KAN-S14 AC #2)
//   6. Finish at the end persists the full draft AND flips
//      `hasCompletedSwingOnboarding = true` (the AC #1 single-
//      source-of-truth contract)
//   7. Edits to text fields are committed on save (not just on
//      onChanged)

import 'package:caddieai/features/onboarding/presentation/onboarding_screen.dart';
import 'package:caddieai/models/player_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _firstRunProfile = PlayerProfile(
  hasCompletedSwingOnboarding: false,
  hasConfiguredBag: false,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required PlayerProfile initial,
  required Future<void> Function(PlayerProfile) onComplete,
  required Future<void> Function(PlayerProfile) onSkip,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: OnboardingScreen(
      initialProfile: initial,
      onComplete: onComplete,
      onSkip: onSkip,
    ),
  ));
  await tester.pump();
}

void main() {
  group('initial render', () {
    testWidgets('shows the setup-notice step on first build',
        (tester) async {
      await _pumpScreen(
        tester,
        initial: _firstRunProfile,
        onComplete: (_) async {},
        onSkip: (_) async {},
      );
      expect(find.text('Your AI golf caddie'), findsOneWidget);
      expect(find.textContaining('1/6'), findsOneWidget);
      // Back button is NOT visible on step 1.
      expect(
        find.byKey(const Key('onboarding-back-button')),
        findsNothing,
      );
    });

    testWidgets('Skip button is always visible from the first step',
        (tester) async {
      await _pumpScreen(
        tester,
        initial: _firstRunProfile,
        onComplete: (_) async {},
        onSkip: (_) async {},
      );
      expect(find.byKey(const Key('onboarding-skip-button')), findsOneWidget);
    });
  });

  group('step navigation', () {
    testWidgets('Next button advances through every step', (tester) async {
      await _pumpScreen(
        tester,
        initial: _firstRunProfile,
        onComplete: (_) async {},
        onSkip: (_) async {},
      );

      // Step 1: setup notice
      expect(find.text('Your AI golf caddie'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();

      // Step 2: contact
      expect(find.text('Stay in touch (optional)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();

      // Step 3: handicap
      expect(find.text('Your handicap'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();

      // Step 4: short game
      expect(find.text('Short game'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();

      // Step 5: bag
      expect(find.text('Your bag'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();

      // Step 6: tee box
      expect(find.text('Tee box'), findsOneWidget);
      // Final button label is "Finish".
      expect(find.text('Finish'), findsOneWidget);
    });

    testWidgets('Back button returns to the previous step', (tester) async {
      await _pumpScreen(
        tester,
        initial: _firstRunProfile,
        onComplete: (_) async {},
        onSkip: (_) async {},
      );
      // Advance to step 2.
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Stay in touch (optional)'), findsOneWidget);

      // Back to step 1.
      await tester.tap(find.byKey(const Key('onboarding-back-button')));
      await tester.pumpAndSettle();
      expect(find.text('Your AI golf caddie'), findsOneWidget);
    });
  });

  group('skip flow (KAN-S14 AC #2)', () {
    testWidgets(
        'tapping Skip from step 1 calls onSkip with the first-run flags '
        'flipped to true', (tester) async {
      PlayerProfile? captured;
      await _pumpScreen(
        tester,
        initial: _firstRunProfile,
        onComplete: (_) async {},
        onSkip: (p) async => captured = p,
      );
      await tester.tap(find.byKey(const Key('onboarding-skip-button')));
      await tester.pump();
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.hasCompletedSwingOnboarding, isTrue);
      expect(captured!.hasConfiguredBag, isTrue);
    });

    testWidgets(
        'Skip preserves any data the user entered before skipping '
        '(non-destructive)', (tester) async {
      PlayerProfile? captured;
      await _pumpScreen(
        tester,
        initial: _firstRunProfile,
        onComplete: (_) async {},
        onSkip: (p) async => captured = p,
      );

      // Advance to the contact step and type a name.
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('onboarding-name-field')),
        'Mid-Skip Player',
      );

      // Skip out.
      await tester.tap(find.byKey(const Key('onboarding-skip-button')));
      await tester.pump();
      await tester.pump();

      expect(captured!.name, 'Mid-Skip Player');
      // Flags still flip.
      expect(captured!.hasCompletedSwingOnboarding, isTrue);
    });
  });

  group('finish flow (KAN-S14 AC #1)', () {
    testWidgets(
        'finishing the wizard calls onComplete with all entered data + '
        'first-run flags flipped', (tester) async {
      PlayerProfile? captured;
      await _pumpScreen(
        tester,
        initial: _firstRunProfile,
        onComplete: (p) async => captured = p,
        onSkip: (_) async {},
      );

      // Advance to contact, type a name, advance through the rest.
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('onboarding-name-field')),
        'Finish Player',
      );

      // Step through to the end.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('onboarding-next-button')));
        await tester.pumpAndSettle();
      }

      expect(captured, isNotNull);
      expect(captured!.name, 'Finish Player');
      expect(captured!.hasCompletedSwingOnboarding, isTrue);
      expect(captured!.hasConfiguredBag, isTrue);
    });

    testWidgets('handicap slider value flows into the saved profile',
        (tester) async {
      PlayerProfile? captured;
      await _pumpScreen(
        tester,
        initial: _firstRunProfile,
        onComplete: (p) async => captured = p,
        onSkip: (_) async {},
      );
      // Advance to step 3 (handicap).
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();

      // Drag the slider to the right (we don't need an exact
      // value; just verify the change reaches the captured profile).
      final slider =
          find.byKey(const Key('onboarding-handicap-slider'));
      await tester.drag(slider, const Offset(200, 0));
      await tester.pump();

      // Step through to the end.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('onboarding-next-button')));
        await tester.pumpAndSettle();
      }

      expect(captured, isNotNull);
      // The captured handicap should differ from the initial 18.0.
      expect(captured!.handicap, isNot(_firstRunProfile.handicap));
    });
  });
}
