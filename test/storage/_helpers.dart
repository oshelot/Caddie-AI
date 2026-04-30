// Shared helpers for the KAN-272 storage tests.
//
// Hive needs a real directory to write its `.hive` files to. The
// Flutter unit-test runner doesn't have platform channels, so we
// can't use `path_provider`. Instead, every test creates a fresh
// `Directory.systemTemp.createTempSync('caddieai_test_')`, hands it
// to `AppStorage.initForTest`, and tears it down after the test.
//
// The `InMemorySecretBackend` swaps in for `flutter_secure_storage`
// in tests so we don't depend on Keychain / EncryptedSharedPrefs
// (also unavailable in unit tests).

import 'dart:io';

import 'package:caddieai/core/storage/secure_keys_storage.dart';

/// Pure in-memory secret store. Behaves like a `Map<String, String>`
/// behind the same interface as the real `flutter_secure_storage`
/// backend. Tests assert against `.entries` directly when they need
/// to verify what was written.
class InMemorySecretBackend implements SecretBackend {
  final Map<String, String> entries = {};

  @override
  Future<String?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, String value) async {
    entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    entries.remove(key);
  }
}

/// Creates a fresh temp directory for one test's Hive boxes. Caller
/// is responsible for deleting it in tearDown.
Directory makeHiveTempDir() =>
    Directory.systemTemp.createTempSync('caddieai_storage_test_');
