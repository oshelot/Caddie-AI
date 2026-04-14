// CaddieAI app theme — Material 3, light mode default.
//
// **This is a starting point, not the final palette.** The native iOS
// app's design tokens are still in **KAN-142 (Extract iOS Design
// Tokens)** which hasn't shipped yet. When KAN-142 lands, replace the
// `seedColor` + manual color overrides below with the extracted
// tokens.
//
// For now we use `ColorScheme.fromSeed` with a golf-course green seed
// (`#2E7D32` — the same green the KAN-252 spike used for the boundary
// layer in `MapboxMapRepresentable.swift:227`). Material 3 derives a
// full palette from one seed color, which gives us a coherent theme
// without manually tuning every slot.
//
// Light vs dark: project owner explicitly chose **light mode** for the
// migration default. The native iOS and Android apps default to dark,
// but that was a baseline-of-the-time decision and not a brand
// requirement — light mode renders the line-stroked CaddieIcons better
// (dark strokes on a light background = more contrast than light
// strokes on dark) and matches the icon set's design intent.
//
// If product later wants automatic light/dark switching based on the
// OS setting, add a `dark` getter alongside `light` and pass both to
// `MaterialApp.router`'s `theme:` and `darkTheme:` slots.
//
// Convention reminder: every feature screen should pull colors from
// `Theme.of(context).colorScheme.X` rather than hardcoding hex
// literals. The `CaddieTheme` class only exposes the `light` getter
// (used in `app.dart`) plus the seed color constant for any code that
// needs to know what color "primary" derives from (e.g. tests).

import 'package:flutter/material.dart';

abstract final class CaddieTheme {
  CaddieTheme._();

  /// The seed color from which the entire Material 3 ColorScheme is
  /// generated. Picked to match the boundary-layer green from the
  /// KAN-252 spike's iOS native reference (#2E7D32). Replace with the
  /// real iOS design token when KAN-142 lands.
  static const Color seedColor = Color(0xFF2E7D32);

  /// The light Material 3 theme used by the entire app. Set this on
  /// `MaterialApp.theme` (we don't ship a separate dark theme yet —
  /// the project owner picked light as the migration default).
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    ).copyWith(
      // Force pure white surfaces — removes the green tint that
      // Material 3 derives from the seed color.
      surface: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF8F8F8),
      surfaceContainer: const Color(0xFFF2F2F2),
      surfaceContainerHigh: const Color(0xFFECECEC),
      surfaceContainerHighest: const Color(0xFFE6E6E6),
      onSurface: Colors.black,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? colorScheme.primary : colorScheme.outline,
          );
        }),
      ),
    );
  }
}
