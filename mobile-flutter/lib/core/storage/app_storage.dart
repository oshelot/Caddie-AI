// AppStorage — Hive bootstrap and box registry for the KAN-272 (S2)
// storage layer.
//
// Per **ADR 0004**: hive_ce is the structured store for player
// profile + shot history + scorecards. We do NOT use SQL (per ADR
// 0003 — shot history is small enough to load in memory and filter
// with Dart collection ops).
//
// **Storage schema:** every box stores `String` values. The string is
// a JSON-encoded payload of one of the model classes in
// `lib/models/`. We deliberately do NOT use Hive's `TypeAdapter`
// codegen — see the ADR 0004 notes on hand-written serialization.
// The cost is one extra `jsonDecode` per read, which is negligible
// at the working-set sizes the spec calls for (single profile, a
// few hundred shots, a handful of scorecards).
//
// **Box names are versioned.** When the storage shape changes in a
// breaking way, bump the version suffix and write a one-shot
// migration that copies from the old box to the new one before
// deleting the old. The current version is `_v1`.
//
// **Initialization order:** `AppStorage.init()` MUST be awaited
// before `runApp()`. It's wired in `lib/main.dart` immediately after
// `initMapbox()`. The order matters because the `MainShell` tabs
// will read the profile box on first frame to render handicap and
// settings — if Hive isn't open by then, the read throws.

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

abstract final class AppStorage {
  AppStorage._();

  // Box names — versioned. See file header for the bump policy.
  static const String profileBoxName = 'caddieai_profile_v1';
  static const String shotHistoryBoxName = 'caddieai_shot_history_v1';
  static const String scorecardBoxName = 'caddieai_scorecards_v1';

  /// Course cache (KAN-275 / S5). Stores `NormalizedCourse` JSON
  /// payloads keyed by server cache key. Each value is wrapped in
  /// a small envelope that adds the persistence timestamp so the
  /// repository can serve TTL-aware reads without parsing the
  /// course payload itself.
  static const String courseCacheBoxName = 'caddieai_course_cache_v1';

  /// Course favorites set. Mirrors the iOS / Android favorites
  /// store: a set of server cache keys the user has starred from
  /// the search or saved tabs. Backed by a Hive box where each
  /// entry's KEY is the cache key and the value is just `'1'` —
  /// we use the box as a set, not a map. The Saved tab reads from
  /// this + the courseCacheBox to render the Favorites and Other
  /// Saved sections.
  static const String courseFavoritesBoxName = 'caddieai_course_favorites_v1';

  /// App-level preferences. Small key/value store for settings that
  /// don't belong to the PlayerProfile (which is user-facing domain
  /// data). Current keys: `theme_palette` (see ThemeController).
  static const String prefsBoxName = 'caddieai_prefs_v1';

  // Single key inside the profile box. The profile is a singleton —
  // there's only one player per device. The box is a key/value store
  // because Hive doesn't have a "single object" primitive, but we
  // never put more than one entry under this key.
  static const String profileSingletonKey = 'self';

  static bool _initialized = false;

  /// Idempotent. Calling this twice is a no-op so tests can re-init
  /// safely without tearing the boxes down. Tests that need a clean
  /// slate should call `Hive.deleteFromDisk()` between runs OR use
  /// `Hive.init` with a temp dir (see test/storage/_helpers.dart).
  static Future<void> init() async {
    if (_initialized) return;

    if (kIsWeb) {
      // Hive web uses IndexedDB and does NOT need a path. The
      // mobile-flutter scaffold doesn't target web for production
      // (the Mapbox spike was mobile-only) but the test suite runs
      // on the VM, which is similar to the kIsWeb=false branch
      // anyway, so this branch is mostly defensive.
      await Hive.initFlutter();
    } else {
      // path_provider gives us the platform's app-private documents
      // directory (Library/Application Support on iOS, getFilesDir
      // on Android). Hive will create a `caddieai_*.hive` file
      // alongside any other app data.
      final docs = await getApplicationDocumentsDirectory();
      Hive.init(docs.path);
    }

    await Future.wait([
      Hive.openBox<String>(profileBoxName),
      Hive.openBox<String>(shotHistoryBoxName),
      Hive.openBox<String>(scorecardBoxName),
      Hive.openBox<String>(courseCacheBoxName),
      Hive.openBox<String>(courseFavoritesBoxName),
      Hive.openBox<String>(prefsBoxName),
    ]);

    _initialized = true;
  }

  /// Test-only entry point. Opens the boxes against an in-memory or
  /// caller-supplied directory so the round-trip + migration tests
  /// don't touch the real on-device storage. Pass a `tempDir` from
  /// `Directory.systemTemp.createTemp(...)` in tests.
  ///
  /// Marked `@visibleForTesting` so production code never wires
  /// this by accident; the linter will flag any non-test caller.
  @visibleForTesting
  static Future<void> initForTest(String hivePath) async {
    if (_initialized) {
      // The previous test left state behind — close everything and
      // start fresh.
      await Hive.close();
      _initialized = false;
    }
    Hive.init(hivePath);
    await Future.wait([
      Hive.openBox<String>(profileBoxName),
      Hive.openBox<String>(shotHistoryBoxName),
      Hive.openBox<String>(scorecardBoxName),
      Hive.openBox<String>(courseCacheBoxName),
      Hive.openBox<String>(courseFavoritesBoxName),
      Hive.openBox<String>(prefsBoxName),
    ]);
    _initialized = true;
  }

  /// Test-only. Closes all boxes and resets the init flag so the
  /// next test can re-init from scratch against a different temp
  /// directory.
  @visibleForTesting
  static Future<void> resetForTest() async {
    if (!_initialized) return;
    await Hive.close();
    _initialized = false;
  }

  static Box<String> get profileBox => Hive.box<String>(profileBoxName);
  static Box<String> get shotHistoryBox =>
      Hive.box<String>(shotHistoryBoxName);
  static Box<String> get scorecardBox => Hive.box<String>(scorecardBoxName);
  static Box<String> get courseCacheBox =>
      Hive.box<String>(courseCacheBoxName);
  static Box<String> get courseFavoritesBox =>
      Hive.box<String>(courseFavoritesBoxName);
}
