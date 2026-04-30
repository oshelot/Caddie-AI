// Backwards-compat shim around the new palette-based theme builder.
// All actual theme construction lives in `caddie_theme_builder.dart`,
// driven by `theme_controller.dart` (a ValueNotifier<ThemePalette>).
//
// The app itself no longer reads `CaddieTheme.light` directly —
// `lib/app.dart` wraps MaterialApp in a ValueListenableBuilder that
// calls `buildCaddieTheme(themeController.value)`. This class is
// kept so tests or debugging tools that import it don't have to
// change.
//
// Convention reminder: every feature screen should pull colors from
// `Theme.of(context).colorScheme.X` rather than hardcoding hex
// literals or referencing CaddieTheme directly.

import 'package:flutter/material.dart';

import 'caddie_theme_builder.dart';
import 'theme_controller.dart';

abstract final class CaddieTheme {
  CaddieTheme._();

  /// Back-compat: returns the default (Ryppl Blue) palette's
  /// ThemeData. Prefer [current] in any code that should honor the
  /// user's dev-mode palette choice.
  static ThemeData get light =>
      buildCaddieTheme(ThemeController.defaultPalette);

  /// The theme the app is *currently* rendering with, based on the
  /// active palette in [themeController]. Not constant — callers
  /// that need to rebuild when the palette changes should listen to
  /// [themeController] directly and rebuild their own subtree.
  static ThemeData get current => buildCaddieTheme(themeController.value);

  /// Seed color of the currently-active palette. Kept for any code
  /// that used the old `CaddieTheme.seedColor` constant (tests,
  /// boundary overlays, etc.).
  static Color get seedColor => themeController.value.seedColor;
}
