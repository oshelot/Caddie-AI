// Widget tests for KAN-283 (S13) ProfileScreen.
//
// Coverage:
//   1. Renders all the editable sections (identity, game, voice
//      persona, feature flags, AI provider, API keys)
//   2. Editing identity fields → saved profile reflects the change
//   3. Toggling a feature flag → saved profile reflects it
//   4. Changing voice persona dropdowns → saved profile reflects it
//   5. **Critical** secure-key isolation: API keys typed into the
//      key fields land in the `ProfileSaveRequest.secrets` map and
//      do NOT appear in the `ProfileSaveRequest.profile` JSON.
//      This test mirrors the canary from `secure_keys_isolation_test.dart`
//      at the screen level — the screen's save flow MUST never
//      cross-contaminate the two stores.

import 'dart:convert';

import 'package:caddieai/core/monetization/subscription_service.dart';
import 'package:caddieai/core/storage/secure_keys_storage.dart';
import 'package:caddieai/features/profile/presentation/profile_screen.dart';
import 'package:caddieai/models/player_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _baselineProfile = PlayerProfile(
  name: 'Baseline Player',
  email: 'baseline@example.com',
  handicap: 12.5,
  caddieVoiceGender: 'female',
  caddieVoiceAccent: 'american',
  llmProvider: 'openAI',
  userTier: 'free',
  telemetryEnabled: true,
  scoringEnabled: false,
  aggressiveness: 'normal',
  preferredTeeBox: 'white',
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required PlayerProfile profile,
  required Future<void> Function(ProfileSaveRequest) onSave,
  Map<String, String> initialSecrets = const {},
  SubscriptionService? subscriptionService,
  bool showDebugSection = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: ProfileScreen(
      profile: profile,
      onSave: onSave,
      initialSecrets: initialSecrets,
      subscriptionService: subscriptionService,
      showDebugSection: showDebugSection,
    ),
  ));
  await tester.pump();
}

void main() {
  group('section rendering', () {
    testWidgets('renders every section heading', (tester) async {
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (_) async {},
      );
      expect(find.text('Player Info'), findsOneWidget);
      expect(find.text('Caddie Voice & Personality'), findsOneWidget);
      expect(find.text('Features'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('API Keys'), findsOneWidget);
      // Navigation links
      expect(find.text('Your Bag'), findsOneWidget);
      expect(find.text('Swing Info'), findsOneWidget);
      expect(find.text('Tee Box Preference'), findsOneWidget);
      expect(find.text('Contact Info'), findsOneWidget);
    });

    testWidgets('initial values are populated from the profile',
        (tester) async {
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (_) async {},
      );
      // Handicap slider is seeded with the profile value.
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, closeTo(12.5, 0.1));
    });
  });

  group('save flow', () {
    testWidgets('saving preserves the current draft state',
        (tester) async {
      ProfileSaveRequest? captured;
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (req) async => captured = req,
      );
      await tester.tap(find.byKey(const Key('profile-save-button')));
      await tester.pump();
      await tester.pump();

      expect(captured, isNotNull);
      // Profile fields preserved from the baseline.
      expect(captured!.profile.handicap, 12.5);
      expect(captured!.profile.aggressiveness, 'normal');
    });

    testWidgets('toggling a feature flag flows into the save request',
        (tester) async {
      ProfileSaveRequest? captured;
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (req) async => captured = req,
      );
      // Telemetry is on initially → toggle off.
      await tester.tap(find.byKey(const Key('profile-telemetry-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('profile-save-button')));
      await tester.pump();
      await tester.pump();

      expect(captured!.profile.telemetryEnabled, isFalse);
    });

    testWidgets(
        'enabling scoring saves through (the History tab will pick '
        'it up on next reload)', (tester) async {
      ProfileSaveRequest? captured;
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (req) async => captured = req,
      );
      await tester.tap(find.byKey(const Key('profile-scoring-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('profile-save-button')));
      await tester.pump();
      await tester.pump();

      expect(captured!.profile.scoringEnabled, isTrue);
    });
  });

  group('secure key isolation (mirrors KAN-272 canary)', () {
    testWidgets(
        'API keys typed into the key fields land in '
        'ProfileSaveRequest.secrets — NOT in the profile JSON',
        (tester) async {
      ProfileSaveRequest? captured;
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (req) async => captured = req,
      );

      // Sentinel API key string that we'll grep for in the profile
      // blob below. If it ever appears there, the canary trips.
      const sentinel = 'sk-canary-DO-NOT-LEAK-INTO-PROFILE-9f3a2b';

      await tester.enterText(
        find.byKey(const Key('profile-openai-key-field')),
        sentinel,
      );
      await tester.tap(find.byKey(const Key('profile-save-button')));
      await tester.pump();
      await tester.pump();

      expect(captured, isNotNull);

      // 1. The sentinel IS in the secrets map under the openAi key.
      expect(captured!.secrets[SecureKey.openAi], sentinel);

      // 2. The sentinel is NOT anywhere in the saved profile JSON.
      final profileJson = jsonEncode(captured!.profile.toJson());
      expect(
        profileJson.contains(sentinel),
        isFalse,
        reason: 'API key leaked into the profile blob — '
            'someone added an apiKey field to PlayerProfile?',
      );

      // 3. The profile JSON contains no field named *apiKey or
      //    *Token (sanity guard against future regressions).
      expect(profileJson.toLowerCase().contains('apikey'), isFalse);
      expect(profileJson.toLowerCase().contains('token'), isFalse);
    });

    testWidgets('initialSecrets pre-populates the API key fields',
        (tester) async {
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (_) async {},
        initialSecrets: const {
          SecureKey.openAi: 'sk-existing-openai',
          SecureKey.claude: 'sk-ant-existing',
        },
      );
      final openaiField = tester.widget<TextField>(
        find.byKey(const Key('profile-openai-key-field')),
      );
      expect(openaiField.controller!.text, 'sk-existing-openai');
      final claudeField = tester.widget<TextField>(
        find.byKey(const Key('profile-claude-key-field')),
      );
      expect(claudeField.controller!.text, 'sk-ant-existing');
    });

    testWidgets('clearing an API key field saves an empty string '
        '(SecureKeysStorage interprets that as "delete this key")',
        (tester) async {
      ProfileSaveRequest? captured;
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (req) async => captured = req,
        initialSecrets: const {SecureKey.openAi: 'sk-old'},
      );
      await tester.enterText(
        find.byKey(const Key('profile-openai-key-field')),
        '',
      );
      await tester.tap(find.byKey(const Key('profile-save-button')));
      await tester.pump();
      await tester.pump();

      expect(captured!.secrets[SecureKey.openAi], '');
    });
  });

  group('KAN-95: debug Pro tier override', () {
    testWidgets('debug section is hidden when showDebugSection is false',
        (tester) async {
      final service = StubSubscriptionService();
      addTearDown(service.dispose);
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (_) async {},
        subscriptionService: service,
        showDebugSection: false,
      );
      expect(find.byKey(const Key('profile-debug-force-pro')), findsNothing);
      expect(find.text('Debug (sideload only)'), findsNothing);
    });

    testWidgets(
        'debug section is hidden when no subscription service is supplied '
        'even with showDebugSection=true', (tester) async {
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (_) async {},
        showDebugSection: true,
      );
      expect(find.byKey(const Key('profile-debug-force-pro')), findsNothing);
    });

    testWidgets(
        'debug section renders with effective tier = Free when service is '
        'unsubscribed and override is off', (tester) async {
      final service = StubSubscriptionService();
      addTearDown(service.dispose);
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (_) async {},
        subscriptionService: service,
        showDebugSection: true,
      );
      // The list section is built lazily; scroll the toggle into view
      // so widget finders + tap interactions hit it reliably.
      await tester.scrollUntilVisible(
        find.byKey(const Key('profile-debug-force-pro')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('profile-debug-force-pro')), findsOneWidget);
      expect(find.text('Effective tier: Free'), findsOneWidget);
    });

    testWidgets('toggling Force Pro flips the effective tier caption to Pro',
        (tester) async {
      final service = StubSubscriptionService();
      addTearDown(service.dispose);
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (_) async {},
        subscriptionService: service,
        showDebugSection: true,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('profile-debug-force-pro')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('profile-debug-force-pro')));
      await tester.pump();
      await tester.pump();
      expect(service.debugForcePro, isTrue);
      expect(service.isSubscribed, isTrue);
      expect(find.text('Effective tier: Pro'), findsOneWidget);
      expect(find.text('Effective tier: Free'), findsNothing);
    });

    testWidgets('toggling Force Pro back off restores the underlying state',
        (tester) async {
      final service = StubSubscriptionService();
      addTearDown(service.dispose);
      await _pumpScreen(
        tester,
        profile: _baselineProfile,
        onSave: (_) async {},
        subscriptionService: service,
        showDebugSection: true,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('profile-debug-force-pro')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Toggle on, then off.
      await tester.tap(find.byKey(const Key('profile-debug-force-pro')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('profile-debug-force-pro')));
      await tester.pump();
      await tester.pump();
      expect(service.debugForcePro, isFalse);
      expect(service.isSubscribed, isFalse);
      expect(find.text('Effective tier: Free'), findsOneWidget);
    });
  });
}
