// Global theme controller. Hot-swaps the running app's theme via a
// ValueNotifier wired above MaterialApp in `lib/app.dart`. Persists
// the user's choice to Hive so it survives cold starts.
//
// The persistence is always-on (not dev-gated). The UI surface to
// *change* the theme is gated on `isDevMode` — in a production
// build without the playground, the user stays on whatever palette
// they had when they last opened a dev build, or on the default if
// they've never picked one.

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import '../storage/app_storage.dart';
import 'theme_palette.dart';

class ThemeController extends ValueNotifier<ThemePalette> {
  ThemeController() : super(defaultPalette);

  /// Fallback used when nothing has been persisted (first run) or
  /// when Hive isn't initialized (unit tests).
  static const ThemePalette defaultPalette = ThemePalette.rypplBlue;

  static const String _prefKey = 'theme_palette';

  /// Read the persisted palette from Hive and replace [value] if
  /// found. Call this after `AppStorage.init()` has completed,
  /// before `runApp()`. Silently no-ops if the prefs box isn't open
  /// (so unit tests that skip AppStorage.init() still work).
  Future<void> load() async {
    try {
      final box = Hive.box<String>(AppStorage.prefsBoxName);
      final raw = box.get(_prefKey);
      if (raw == null) return;
      final found = ThemePalette.values.firstWhere(
        (p) => p.name == raw,
        orElse: () => defaultPalette,
      );
      value = found;
    } catch (_) {
      // Box not open (tests) — keep the default. Not a real failure.
    }
  }

  /// Hot-swap the active palette and persist the choice. Triggers a
  /// rebuild of the whole MaterialApp via the ValueListenableBuilder
  /// in `lib/app.dart`.
  Future<void> set(ThemePalette palette) async {
    value = palette;
    try {
      final box = Hive.box<String>(AppStorage.prefsBoxName);
      await box.put(_prefKey, palette.name);
    } catch (_) {
      // Persistence unavailable — the in-memory swap still worked,
      // the user just won't keep the choice across cold start.
    }
  }
}

/// Process-global singleton. Read by `app.dart` (ValueListenableBuilder
/// above MaterialApp.router) and written from the dev Theme Playground.
/// Not const — it holds mutable state.
final themeController = ThemeController();
