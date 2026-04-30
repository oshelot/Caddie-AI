// Tests for NativeMigrationImporter against the captured iOS and
// Android fixture payloads in `test/fixtures/migration/`. Satisfies
// **KAN-272 AC #2**:
//
// > Migration importer produces correct profile for a captured set
// > of native-format fixtures (commit a few sample payloads in
// > `test/fixtures/migration/`)

import 'dart:convert';
import 'dart:io';

import 'package:caddieai/core/storage/app_storage.dart';
import 'package:caddieai/core/storage/native_migration_importer.dart';
import 'package:caddieai/core/storage/profile_repository.dart';
import 'package:caddieai/core/storage/secure_keys_storage.dart';
import 'package:caddieai/core/storage/shot_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  late Directory tempDir;
  late InMemorySecretBackend secrets;
  late NativeMigrationImporter importer;
  late ProfileRepository profileRepo;
  late ShotHistoryRepository historyRepo;

  setUp(() async {
    tempDir = makeHiveTempDir();
    await AppStorage.initForTest(tempDir.path);
    secrets = InMemorySecretBackend();
    profileRepo = ProfileRepository();
    historyRepo = ShotHistoryRepository();
    importer = NativeMigrationImporter(
      profileRepository: profileRepo,
      shotHistoryRepository: historyRepo,
      secureKeysStorage: SecureKeysStorage.withBackend(secrets),
    );
  });

  tearDown(() async {
    await AppStorage.resetForTest();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Map<String, dynamic> readJsonMap(String relativePath) {
    final file = File(relativePath);
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  List<dynamic> readJsonList(String relativePath) {
    final file = File(relativePath);
    return jsonDecode(file.readAsStringSync()) as List<dynamic>;
  }

  group('iOS profile import', () {
    test('translates contact + handicap + clubs from the fixture', () {
      final raw = readJsonMap('test/fixtures/migration/ios_player_profile.json');
      final imported = importer.importIosProfile(raw);

      expect(imported.profile.name, 'Sam Iron');
      expect(imported.profile.email, 'sam@example.com');
      expect(imported.profile.phone, '+15555550101');
      expect(imported.profile.handicap, 12.5);

      // iOS clubDistances is a list-of-objects; importer collapses to a map.
      expect(imported.profile.clubDistances['driver'], 245);
      expect(imported.profile.clubDistances['7-iron'], 150);
      expect(imported.profile.clubDistances['sand wedge'], 80);

      // bagClubs gets synthesized from clubDistances.keys for iOS.
      expect(imported.profile.bagClubs, contains('driver'));
      expect(imported.profile.bagClubs.length, 9);
    });

    test('translates renamed fields (defaultAggressiveness, contactName, etc.)',
        () {
      final raw = readJsonMap('test/fixtures/migration/ios_player_profile.json');
      final imported = importer.importIosProfile(raw);

      // iOS `defaultAggressiveness` → Flutter `aggressiveness`
      expect(imported.profile.aggressiveness, 'normal');
      // iOS `preferredChipStyle` → Flutter `chipStyle`
      expect(imported.profile.chipStyle, 'loftedChip');
      // iOS `betaImageAnalysis` → Flutter `betaImageAnalysisEnabled`
      expect(imported.profile.betaImageAnalysisEnabled, false);
    });

    test('parses ISO8601 contactPromptLastShown into epoch ms', () {
      final raw = readJsonMap('test/fixtures/migration/ios_player_profile.json');
      final imported = importer.importIosProfile(raw);

      expect(imported.profile.contactPromptLastShownMs,
          DateTime.parse('2026-03-15T18:42:11Z').millisecondsSinceEpoch);
    });

    test('routes API keys to the secrets map, not the profile', () {
      final raw = readJsonMap('test/fixtures/migration/ios_player_profile.json');
      final imported = importer.importIosProfile(raw);

      expect(imported.secrets[SecureKey.openAi],
          'sk-fixture-openai-ios-DO-NOT-USE');
      expect(imported.secrets[SecureKey.claude],
          'sk-ant-fixture-ios-DO-NOT-USE');
      expect(imported.secrets[SecureKey.gemini],
          'AIza-fixture-ios-DO-NOT-USE');
      expect(imported.secrets[SecureKey.golfCourseApi],
          'gc-fixture-ios-DO-NOT-USE');
      expect(imported.secrets[SecureKey.mapbox],
          'pk.fixture.ios.DO-NOT-USE');

      // None of the API key strings appear anywhere on the profile.
      final profileJson = jsonEncode(imported.profile.toJson());
      for (final secret in imported.secrets.values) {
        if (secret == null) continue;
        expect(profileJson, isNot(contains(secret)),
            reason: 'API key leaked into the profile JSON');
      }
    });
  });

  group('Android profile import', () {
    test('translates name/email/phone + handicap + clubs', () {
      final raw =
          readJsonMap('test/fixtures/migration/android_player_profile.json');
      final imported = importer.importAndroidProfile(raw);

      expect(imported.profile.name, 'Pat Fairway');
      expect(imported.profile.email, 'pat@example.com');
      expect(imported.profile.phone, '+15555550202');
      expect(imported.profile.handicap, 18.0);

      // Android clubDistances is already a map; keys are enum names.
      expect(imported.profile.clubDistances['DRIVER'], 230);
      expect(imported.profile.clubDistances['SEVEN_IRON'], 150);
      expect(imported.profile.clubDistances['LOB_WEDGE'], 60);

      expect(imported.profile.bagClubs, contains('DRIVER'));
      expect(imported.profile.bagClubs.length, 13);
    });

    test('preserves android-only fields (userTier, voiceEnabled, usesMetric)',
        () {
      final raw =
          readJsonMap('test/fixtures/migration/android_player_profile.json');
      final imported = importer.importAndroidProfile(raw);

      expect(imported.profile.userTier, 'PRO');
      expect(imported.profile.voiceEnabled, true);
      expect(imported.profile.usesMetric, false);
      expect(imported.profile.includeClubAlternatives, true);
    });

    test('translates renamed Android fields', () {
      final raw =
          readJsonMap('test/fixtures/migration/android_player_profile.json');
      final imported = importer.importAndroidProfile(raw);

      // caddieGender → caddieVoiceGender
      expect(imported.profile.caddieVoiceGender, 'MALE');
      // caddieAccent → caddieVoiceAccent
      expect(imported.profile.caddieVoiceAccent, 'AMERICAN');
      // setupNoticeSeen → hasCompletedSwingOnboarding
      expect(imported.profile.hasCompletedSwingOnboarding, true);
      // contactPromptCount → contactPromptSkipCount
      expect(imported.profile.contactPromptSkipCount, 1);
      // lastContactPromptMs → contactPromptLastShownMs
      expect(imported.profile.contactPromptLastShownMs, 1742054400000);
      // imageAnalysisBetaEnabled → betaImageAnalysisEnabled
      expect(imported.profile.betaImageAnalysisEnabled, false);
    });

    test('Android profiles default hasConfiguredBag to true', () {
      // Android doesn't track bag-configured separately; the importer
      // sets the flag so the migrated user doesn't get pushed back
      // through bag setup.
      final raw =
          readJsonMap('test/fixtures/migration/android_player_profile.json');
      final imported = importer.importAndroidProfile(raw);
      expect(imported.profile.hasConfiguredBag, true);
    });

    test('routes API keys to the secrets map, not the profile', () {
      final raw =
          readJsonMap('test/fixtures/migration/android_player_profile.json');
      final imported = importer.importAndroidProfile(raw);

      expect(imported.secrets[SecureKey.openAi],
          'sk-fixture-openai-android-DO-NOT-USE');
      expect(imported.secrets[SecureKey.claude],
          'sk-ant-fixture-android-DO-NOT-USE');
      expect(imported.secrets[SecureKey.gemini],
          'AIza-fixture-android-DO-NOT-USE');

      final profileJson = jsonEncode(imported.profile.toJson());
      for (final secret in imported.secrets.values) {
        if (secret == null) continue;
        expect(profileJson, isNot(contains(secret)),
            reason: 'API key leaked into the profile JSON');
      }
    });
  });

  group('iOS shot history import', () {
    test('translates ISO8601 dates into epoch ms', () {
      final raw =
          readJsonList('test/fixtures/migration/ios_shot_history.json');
      final entries = importer.importIosShotHistory(raw);

      expect(entries, hasLength(2));
      expect(entries[0].id, '11111111-1111-1111-1111-111111111111');
      expect(entries[0].timestampMs,
          DateTime.parse('2026-04-05T14:23:00Z').millisecondsSinceEpoch);
      expect(entries[0].context.distanceYards, 152);
      expect(entries[0].recommendedClub, '7-iron');
      expect(entries[0].actualClubUsed, '6-iron');
      expect(entries[0].outcome, 'good');

      // The second entry has actualClubUsed: null in the fixture —
      // make sure that round-trips through the importer.
      expect(entries[1].actualClubUsed, isNull);
    });
  });

  group('Android shot history import', () {
    test('passes through epoch ms and pulls clubName from recommendation', () {
      final raw =
          readJsonList('test/fixtures/migration/android_shot_history.json');
      final entries = importer.importAndroidShotHistory(raw);

      expect(entries, hasLength(1));
      expect(entries[0].id, '33333333-3333-3333-3333-333333333333');
      expect(entries[0].timestampMs, 1743862980000);
      expect(entries[0].courseId, 'wellshire-denver');
      expect(entries[0].courseName, 'Wellshire Golf Course');
      expect(entries[0].context.distanceYards, 165);
      expect(entries[0].recommendedClub, '6-iron');
      expect(entries[0].actualClubUsed, '6-iron');
      expect(entries[0].outcome, 'GOOD');
    });
  });

  group('persistImportedProfile', () {
    test('writes profile to repo and secrets to backend', () async {
      final raw = readJsonMap('test/fixtures/migration/ios_player_profile.json');
      final imported = importer.importIosProfile(raw);

      await importer.persistImportedProfile(imported);

      final loadedProfile = profileRepo.load();
      expect(loadedProfile, isNotNull);
      expect(loadedProfile!.name, 'Sam Iron');

      expect(secrets.entries[SecureKey.openAi],
          'sk-fixture-openai-ios-DO-NOT-USE');
      expect(secrets.entries[SecureKey.claude],
          'sk-ant-fixture-ios-DO-NOT-USE');
    });
  });

  group('persistImportedShotHistory', () {
    test('writes every entry into the shot history box', () async {
      final raw =
          readJsonList('test/fixtures/migration/ios_shot_history.json');
      final entries = importer.importIosShotHistory(raw);

      await importer.persistImportedShotHistory(entries);

      final loaded = historyRepo.loadAll();
      expect(loaded, hasLength(2));
      // loadAll sorts newest-first by timestamp.
      expect(loaded.first.id, '22222222-2222-2222-2222-222222222222');
    });
  });
}
