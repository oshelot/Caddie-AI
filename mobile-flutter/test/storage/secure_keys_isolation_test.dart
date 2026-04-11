// Canary test for **KAN-272 AC #3**:
//
// > API keys stored in platform secure storage (iOS Keychain /
// > Android EncryptedSharedPreferences via `flutter_secure_storage`),
// > NOT in the shared profile store
//
// The test writes a known sentinel API key via SecureKeysStorage,
// writes a fully-populated PlayerProfile via ProfileRepository, then
// reads the raw bytes of the Hive `.hive` file and asserts the
// sentinel string does NOT appear anywhere in those bytes.
//
// If anyone ever adds an API-key field to PlayerProfile (and the
// migration importer routes a key into it), the sentinel will leak
// into the JSON-encoded profile blob and this test will fail. That
// is the intended canary behavior.

import 'dart:io';

import 'package:caddieai/core/storage/app_storage.dart';
import 'package:caddieai/core/storage/profile_repository.dart';
import 'package:caddieai/core/storage/secure_keys_storage.dart';
import 'package:caddieai/models/player_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  late Directory tempDir;
  late InMemorySecretBackend secrets;
  late SecureKeysStorage secureStorage;
  late ProfileRepository profileRepo;

  // A distinctive sentinel that should only ever appear in the
  // SecureKeysStorage backend, never in the Hive box file.
  const sentinelApiKey = 'sk-canary-DO-NOT-LEAK-INTO-HIVE-1f3e9b';

  setUp(() async {
    tempDir = makeHiveTempDir();
    await AppStorage.initForTest(tempDir.path);
    secrets = InMemorySecretBackend();
    secureStorage = SecureKeysStorage.withBackend(secrets);
    profileRepo = ProfileRepository();
  });

  tearDown(() async {
    await AppStorage.resetForTest();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
      'API key written via SecureKeysStorage does NOT appear in the '
      'Hive profile box file (KAN-272 AC #3)', () async {
    // 1. Write the sentinel via the secure path.
    await secureStorage.write(SecureKey.openAi, sentinelApiKey);
    await secureStorage.write(SecureKey.claude, sentinelApiKey);
    await secureStorage.write(SecureKey.gemini, sentinelApiKey);
    await secureStorage.write(SecureKey.golfCourseApi, sentinelApiKey);
    await secureStorage.write(SecureKey.mapbox, sentinelApiKey);

    // 2. Write a richly-populated profile via the public API. This
    //    is the realistic worst case — every field is set, so any
    //    accidental leak point would be exercised.
    await profileRepo.save(const PlayerProfile(
      name: 'Canary Player',
      email: 'canary@example.com',
      phone: '+15555550000',
      handicap: 7.5,
      clubDistances: {'driver': 260, '7-iron': 160},
      stockShape: 'draw',
      llmProvider: 'openAI',
      llmModel: 'gpt-4o',
      caddieVoiceGender: 'female',
      caddieVoiceAccent: 'american',
      telemetryEnabled: true,
    ));

    // 3. Sanity-check the secret backend has the sentinel.
    expect(secrets.entries[SecureKey.openAi], sentinelApiKey);

    // 4. Find the profile box file Hive wrote to disk and read its
    //    raw bytes. Hive names files `<box_name>.hive` in the
    //    initialized directory.
    final hiveFile = File(
      '${tempDir.path}/${AppStorage.profileBoxName}.hive',
    );
    expect(hiveFile.existsSync(), isTrue,
        reason: 'Hive should have written the profile box file');

    final bytes = hiveFile.readAsBytesSync();
    // Decode bytes as latin-1 (one byte per char) so any embedded
    // ASCII string the sentinel would land as is searchable.
    final asString = String.fromCharCodes(bytes);

    expect(
      asString.contains(sentinelApiKey),
      isFalse,
      reason: 'Sentinel API key leaked into the Hive profile box file. '
          'Did someone add an API-key field to PlayerProfile? '
          'Per ADR 0004, API keys must live in SecureKeysStorage only.',
    );
  });

  test(
      'reading the profile back does NOT expose any API key field on '
      'the model surface', () async {
    await secureStorage.write(SecureKey.openAi, sentinelApiKey);
    await profileRepo.save(const PlayerProfile(name: 'Canary'));

    final loaded = profileRepo.load();
    expect(loaded, isNotNull);

    // Round-trip the loaded profile to JSON and assert no API key
    // shows up. (PlayerProfile.toJson is the canonical surface for
    // serialization — if a future field appears here that contains
    // a key, this assertion fails.)
    final json = loaded!.toJson().toString();
    expect(json.contains(sentinelApiKey), isFalse);
    expect(json.contains('apiKey'), isFalse,
        reason: 'PlayerProfile should never expose any *apiKey field');
    expect(json.contains('Token'), isFalse,
        reason: 'PlayerProfile should never expose any *Token field');
  });
}
