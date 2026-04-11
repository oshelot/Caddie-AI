// SecureKeysStorage — wraps `flutter_secure_storage` for the LLM
// API keys + Mapbox token + Golf Course API key. These keys are the
// reason this story (KAN-272) bothers with a separate storage layer
// at all — they MUST NOT land in the Hive box that holds the
// PlayerProfile, because:
//
//   1. The Hive box is a plain `.hive` file in the app's documents
//      directory. On Android with `allowBackup=true`, that file
//      can be pulled out via `adb backup`. On iOS it's part of the
//      iCloud-backed app container.
//   2. Anyone reading the raw box file (a backup, a forensic dump,
//      a curious developer with USB debugging) would otherwise see
//      every API key the user typed in.
//
// `flutter_secure_storage` writes to:
//
//   - **iOS:** Keychain Services (the system password store), with
//     `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` by default
//   - **Android:** EncryptedSharedPreferences, backed by a key in
//     the Android Keystore (hardware-backed on devices with TEE)
//
// Both backends survive uninstall on iOS (intentional) but get
// wiped on uninstall on Android (default behavior). The migration
// importer (KAN-272 AC #2) is responsible for re-populating these
// keys from the native blobs on first launch of the Flutter app.
//
// **Test isolation:** the secure-keys-isolation test
// (`test/storage/secure_keys_isolation_test.dart`) writes a known
// API key via this class, then opens the raw Hive profile box file
// and asserts the key string is NOT present anywhere in the file.
// That test is the canary for the AC #3 commitment ("API keys
// stored in platform secure storage, NOT in the shared profile
// store"). Anyone who adds an API-key field to PlayerProfile will
// trip it.

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The set of secret keys this app stores. Centralized here so the
/// migration importer, the Profile/API settings screen, and the
/// LLM router all reference the same constants — no scattered string
/// literals.
abstract final class SecureKey {
  SecureKey._();

  /// OpenAI API key. iOS source: `PlayerProfile.apiKey`.
  /// Android source: `PlayerProfile.openAiApiKey`.
  static const String openAi = 'openAiApiKey';

  /// Anthropic / Claude API key. iOS source: `claudeApiKey`.
  /// Android source: `anthropicApiKey`.
  static const String claude = 'claudeApiKey';

  /// Google Gemini API key. iOS source: `geminiApiKey`.
  /// Android source: `googleApiKey`.
  static const String gemini = 'geminiApiKey';

  /// Golf Course API key. iOS-only on the native side; Android
  /// uses `BuildConfig.GOLF_COURSE_API_KEY` baked at build time.
  /// We expose it via secure storage uniformly for both platforms.
  static const String golfCourseApi = 'golfCourseApiKey';

  /// Mapbox public token. Same situation as the Golf Course API
  /// key — iOS stores per-user via PlayerProfile, Android bakes via
  /// BuildConfig. The Flutter app reads it from `--dart-define`
  /// at build time (per CONVENTIONS C-1) so this slot is currently
  /// unused in production, but we expose it so the migration
  /// importer can preserve a user-overridden token if iOS ever
  /// shipped one.
  static const String mapbox = 'mapboxAccessToken';
}

/// Thin abstraction over the secret backend so unit tests can swap
/// in an in-memory fake. Production code uses
/// `FlutterSecureStorageBackend`, which delegates to the real
/// `flutter_secure_storage` plugin (Keychain / EncryptedSharedPrefs).
/// Tests use `InMemorySecretBackend` from the test helpers.
abstract class SecretBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Default production backend — wraps the real plugin.
class FlutterSecureStorageBackend implements SecretBackend {
  FlutterSecureStorageBackend([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility:
                    KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SecureKeysStorage {
  /// Production constructor. Uses the real platform secure storage.
  SecureKeysStorage() : _backend = FlutterSecureStorageBackend();

  /// Test constructor — accepts an injected backend so unit tests
  /// can supply an in-memory fake without touching real Keychain
  /// or EncryptedSharedPreferences.
  @visibleForTesting
  SecureKeysStorage.withBackend(SecretBackend backend) : _backend = backend;

  final SecretBackend _backend;

  /// Reads a secret. Returns null if the key has never been set
  /// (or was deleted).
  Future<String?> read(String key) => _backend.read(key);

  /// Writes a secret. Pass null/empty to delete (the convention
  /// matches the underlying plugin's "write null = delete" behavior).
  Future<void> write(String key, String? value) {
    if (value == null || value.isEmpty) {
      return _backend.delete(key);
    }
    return _backend.write(key, value);
  }

  /// Bulk-writes a map of secrets. Used by the migration importer
  /// to populate every key from a native blob in one shot.
  Future<void> writeAll(Map<String, String?> values) async {
    for (final entry in values.entries) {
      await write(entry.key, entry.value);
    }
  }

  /// Wipes every secret this class manages. Used by the test suite
  /// and by a future "Reset app data" settings flow.
  Future<void> clear() async {
    for (final key in const [
      SecureKey.openAi,
      SecureKey.claude,
      SecureKey.gemini,
      SecureKey.golfCourseApi,
      SecureKey.mapbox,
    ]) {
      await _backend.delete(key);
    }
  }
}
