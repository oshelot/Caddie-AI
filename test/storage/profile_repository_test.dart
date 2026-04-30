// Round-trip + edge-case tests for ProfileRepository, satisfying
// **KAN-272 AC #1** ("write profile → read profile → assert equal").

import 'dart:io';

import 'package:caddieai/core/storage/app_storage.dart';
import 'package:caddieai/core/storage/profile_repository.dart';
import 'package:caddieai/models/player_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  late Directory tempDir;
  late ProfileRepository repo;

  // A frozen clock keeps the timestamp-stamping logic deterministic.
  final fixedClock = DateTime.utc(2026, 4, 11, 12, 0, 0);

  setUp(() async {
    tempDir = makeHiveTempDir();
    await AppStorage.initForTest(tempDir.path);
    repo = ProfileRepository(clock: () => fixedClock);
  });

  tearDown(() async {
    await AppStorage.resetForTest();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('ProfileRepository', () {
    test('load() returns null on a fresh box', () {
      expect(repo.load(), isNull);
    });

    test('loadOrDefault() returns a default profile on a fresh box', () {
      expect(repo.loadOrDefault(), const PlayerProfile());
    });

    test('round-trip preserves every field (KAN-272 AC #1)', () async {
      const original = PlayerProfile(
        name: 'Round Trip',
        email: 'rt@example.com',
        phone: '+15555550100',
        handicap: 9.4,
        clubDistances: {
          'driver': 250,
          '7-iron': 155,
          'sand wedge': 80,
        },
        bagClubs: ['driver', '7-iron', 'sand wedge'],
        stockShape: 'draw',
        woodsStockShape: 'draw',
        ironsStockShape: 'fade',
        hybridsStockShape: 'straight',
        missTendency: 'right',
        aggressiveness: 'aggressive',
        bunkerConfidence: 'high',
        wedgeConfidence: 'high',
        chipStyle: 'loftedChip',
        swingTendency: 'fade',
        llmProvider: 'claude',
        llmModel: 'claude-3-5-sonnet',
        userTier: 'pro',
        includeClubAlternatives: false,
        includeWindAdjustment: true,
        includeSlopeAdjustment: false,
        caddieVoiceGender: 'male',
        caddieVoiceAccent: 'scottish',
        caddiePersona: 'mentor',
        usesMetric: true,
        voiceEnabled: false,
        hasCompletedSwingOnboarding: true,
        hasConfiguredBag: true,
        contactPromptSkipCount: 3,
        contactPromptLastShownMs: 1742054400000,
        contactOptedIn: true,
        betaImageAnalysisEnabled: true,
        telemetryEnabled: false,
        scoringEnabled: true,
        preferredTeeBox: 'blue',
        ironType: 'gameImprovement',
      );

      await repo.save(original);

      final loaded = repo.load();
      expect(loaded, isNotNull);

      // The repository stamps timestamps on save — assert separately
      // and then strip before comparing the rest of the fields.
      expect(loaded!.createdAtMs, fixedClock.millisecondsSinceEpoch);
      expect(loaded.updatedAtMs, fixedClock.millisecondsSinceEpoch);

      final stripped = loaded.copyWith(createdAtMs: 0, updatedAtMs: 0);
      expect(stripped, original);
    });

    test('save() preserves the original createdAtMs across updates',
        () async {
      // First write — both timestamps should be the fixed clock.
      final firstClock = DateTime.utc(2026, 4, 1);
      final secondClock = DateTime.utc(2026, 4, 11);

      var clock = firstClock;
      final freshRepo = ProfileRepository(clock: () => clock);

      await freshRepo.save(const PlayerProfile(name: 'Initial'));
      final firstLoad = freshRepo.load()!;
      expect(firstLoad.createdAtMs, firstClock.millisecondsSinceEpoch);
      expect(firstLoad.updatedAtMs, firstClock.millisecondsSinceEpoch);

      // Second write — createdAtMs should be preserved, updatedAtMs
      // should advance.
      clock = secondClock;
      await freshRepo.save(firstLoad.copyWith(name: 'Updated'));
      final secondLoad = freshRepo.load()!;
      expect(secondLoad.name, 'Updated');
      expect(secondLoad.createdAtMs, firstClock.millisecondsSinceEpoch);
      expect(secondLoad.updatedAtMs, secondClock.millisecondsSinceEpoch);
    });

    test('update() applies the transform and persists', () async {
      await repo.save(const PlayerProfile(handicap: 18.0));
      final next = await repo.update(
        (current) => current.copyWith(handicap: 12.0),
      );
      expect(next.handicap, 12.0);
      expect(repo.load()!.handicap, 12.0);
    });

    test('clear() removes the profile from the box', () async {
      await repo.save(const PlayerProfile(name: 'To delete'));
      expect(repo.load(), isNotNull);
      await repo.clear();
      expect(repo.load(), isNull);
    });

    test('partial JSON loads with defaults filling missing fields', () {
      // Manually inject a sparse blob (the kind an older app version
      // might have written) and verify the lenient decoder applies
      // defaults rather than throwing.
      AppStorage.profileBox.put(
        AppStorage.profileSingletonKey,
        '{"name":"Sparse","handicap":15.0}',
      );
      final loaded = repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Sparse');
      expect(loaded.handicap, 15.0);
      // Defaults should apply for everything else.
      expect(loaded.preferredTeeBox, 'white');
      expect(loaded.telemetryEnabled, true);
      expect(loaded.clubDistances, isEmpty);
    });
  });
}
