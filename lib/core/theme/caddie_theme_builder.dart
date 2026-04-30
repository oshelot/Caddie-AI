// Builds [ThemeData] from a [ThemePalette]. All palette-specific
// surface overrides live here so the enum stays a plain data class
// and the rest of the app doesn't hardcode hex literals.
//
// Design convention (carries over from the original CaddieTheme):
// feature screens should read colors via `Theme.of(context).colorScheme.X`,
// never from this file directly. That's what makes the hot-swap work
// — swap the ThemeData at the root, every consumer rebuilds.

import 'package:flutter/material.dart';

import 'theme_palette.dart';

ThemeData buildCaddieTheme(ThemePalette palette) {
  final isDark = palette.brightness == Brightness.dark;

  final baseScheme = ColorScheme.fromSeed(
    seedColor: palette.seedColor,
    brightness: palette.brightness,
  );

  // Per-palette surface tuning. `ColorScheme.fromSeed` tints the
  // surfaces slightly with the seed color, which can look muddy on
  // white-background designs. Forcing pure white / pure charcoal
  // gives a cleaner appearance for most presets.
  final colorScheme = switch (palette) {
    ThemePalette.rypplBlue => baseScheme.copyWith(
        surface: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFFAFAFA),
        surfaceContainer: const Color(0xFFF5F5F5),
        surfaceContainerHigh: const Color(0xFFEEEEEE),
        surfaceContainerHighest: const Color(0xFFE5E5E5),
        onSurface: const Color(0xFF1A1A1A),
        error: const Color(0xFFDC2626),
      ),
    ThemePalette.midnight => baseScheme.copyWith(
        surface: const Color(0xFF0F172A),
        surfaceContainerLowest: const Color(0xFF020617),
        surfaceContainerLow: const Color(0xFF0F172A),
        surfaceContainer: const Color(0xFF1E293B),
        surfaceContainerHigh: const Color(0xFF334155),
        surfaceContainerHighest: const Color(0xFF475569),
        onSurface: const Color(0xFFF1F5F9),
        secondary: const Color(0xFFF59E0B),
      ),
    ThemePalette.fairway => baseScheme.copyWith(
        surface: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF8F8F8),
        surfaceContainer: const Color(0xFFF2F2F2),
        surfaceContainerHigh: const Color(0xFFECECEC),
        surfaceContainerHighest: const Color(0xFFE6E6E6),
        onSurface: Colors.black,
      ),
    ThemePalette.highContrast => baseScheme.copyWith(
        surface: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFFAFAFA),
        surfaceContainer: const Color(0xFFF0F0F0),
        surfaceContainerHigh: const Color(0xFFE0E0E0),
        surfaceContainerHighest: const Color(0xFFD0D0D0),
        onSurface: Colors.black,
        outline: const Color(0xFF212121),
      ),
    ThemePalette.clinical => baseScheme.copyWith(
        surface: const Color(0xFFFAFAFA),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF5F5F5),
        surfaceContainer: const Color(0xFFEEEEEE),
        surfaceContainerHigh: const Color(0xFFE0E0E0),
        surfaceContainerHighest: const Color(0xFFBDBDBD),
        onSurface: const Color(0xFF1F2937),
      ),
  };

  final scaffoldBg = isDark ? colorScheme.surface : colorScheme.surface;
  final chromeFg = colorScheme.onSurface;

  return ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBg,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 20,
        color: chromeFg,
      ),
      iconTheme: IconThemeData(color: chromeFg),
    ),
    cardTheme: CardThemeData(
      color: isDark ? colorScheme.surfaceContainer : Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: selected ? colorScheme.primary : colorScheme.outline,
        );
      }),
    ),
  );
}
