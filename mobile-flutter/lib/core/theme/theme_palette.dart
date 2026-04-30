// Theme palette presets. Each entry is a self-contained visual
// identity — its own seed color AND its own brightness (dark vs
// light). The user picks one palette from the dev-only Theme
// Playground; the selection is persisted to Hive and hot-swapped
// across the running app via [ThemeController].
//
// Design rationale (long-form in the conversation thread that
// introduced this, 2026-04-24):
//
//   - The original migration theme used seedColor=#2E7D32 (golf
//     green). Feedback was that it read "spa / clinical" rather
//     than "confident caddie". These presets were curated to give
//     the owner a few directions to try on-device before
//     committing to one canonical palette.
//
//   - Ryppl Blue is the most on-brand option — mirrors the royal
//     blue + red + white of the launcher icon (see KAN-64 /
//     `assets/branding/app_icon.png`).
//
//   - Midnight is the outdoor-round answer: dark surfaces survive
//     bright sun with sunglasses better than anything else.
//
//   - Fairway is the current theme kept as a baseline for A/B
//     feel.
//
//   - High Contrast and Clinical exist to probe the ends of the
//     design space ("what if we went maximally-utilitarian?").
//
// To add a palette: append a new enum value with seed + brightness,
// then add a `switch (palette)` case in `caddie_theme_builder.dart`
// if you want surface overrides beyond what `ColorScheme.fromSeed`
// produces. Nothing else needs to change — the playground picks up
// the new entry automatically.

import 'package:flutter/material.dart';

enum ThemePalette {
  rypplBlue(
    label: 'Ryppl Blue',
    description:
        'Royal blue primary, white surfaces, red for destructive actions. '
        'Matches the launcher icon and brand.',
    seedColor: Color(0xFF1D4ED8),
    brightness: Brightness.light,
  ),
  midnight(
    label: 'Midnight',
    description:
        'Dark mode. Charcoal surfaces, soft white text, warm amber accent. '
        'Best for outdoor rounds in bright sun with sunglasses.',
    seedColor: Color(0xFF3B82F6),
    brightness: Brightness.dark,
  ),
  fairway(
    label: 'Fairway',
    description:
        'Desaturated forest green. Closest to the original migration theme '
        '(tweaked slightly for saturation).',
    seedColor: Color(0xFF2E7D32),
    brightness: Brightness.light,
  ),
  highContrast(
    label: 'High Contrast',
    description:
        'Near-black text on near-white surfaces with saturated blue accent. '
        'Maximum legibility, minimal vibe.',
    seedColor: Color(0xFF1E3A8A),
    brightness: Brightness.light,
  ),
  clinical(
    label: 'Clinical',
    description:
        'Slate neutrals with a blue accent. Minimal, professional, '
        'Apple-app-adjacent.',
    seedColor: Color(0xFF475569),
    brightness: Brightness.light,
  );

  const ThemePalette({
    required this.label,
    required this.description,
    required this.seedColor,
    required this.brightness,
  });

  final String label;
  final String description;
  final Color seedColor;
  final Brightness brightness;
}
