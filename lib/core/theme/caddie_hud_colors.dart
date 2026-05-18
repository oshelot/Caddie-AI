// HUD / map-overlay color tokens — KAN-432 (UI redesign Phase 1).
//
// These sit *outside* the Material [ColorScheme] on purpose: the map
// HUD is its own visual surface — dark glass pills over satellite
// imagery, read in bright sun — and shouldn't be regenerated when the
// seed-driven ColorScheme changes. See the redesign plan §5,
// "Map overlays — the HUD vocabulary".
//
// Registered in `caddie_theme_builder.dart` as a [ThemeExtension].
// Consume via `context.hud` (extension getter below) or
// `Theme.of(context).extension<CaddieHudColors>()`.

import 'package:flutter/material.dart';

@immutable
class CaddieHudColors extends ThemeExtension<CaddieHudColors> {
  const CaddieHudColors({
    required this.hudGlass,
    required this.hudStroke,
    required this.hudOnGlass,
    required this.caddieAccent,
    required this.hazard,
  });

  /// Dark glass behind yardage numbers — ~72% opacity over satellite.
  final Color hudGlass;

  /// 1px inner stroke on glass pills, for crispness against imagery.
  final Color hudStroke;

  /// Text / icon color on [hudGlass].
  final Color hudOnGlass;

  /// The AI caddie's identity color — Fairway green. Club badges,
  /// "decision confirmed" states. Deliberately *not* the brand
  /// primary (Ryppl Blue) — green is reserved for caddie output.
  final Color caddieAccent;

  /// Risk / hazard warnings — bunker & water labels, the Risk line.
  final Color hazard;

  /// Tokens for light palettes (Ryppl Blue, Fairway, High Contrast…).
  static const light = CaddieHudColors(
    hudGlass: Color(0xB80F1820), // rgba(15,24,32,0.72)
    hudStroke: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
    hudOnGlass: Color(0xFFFFFFFF),
    caddieAccent: Color(0xFF2F7D4A), // Fairway
    hazard: Color(0xFFB7541C),
  );

  /// Tokens for dark palettes (Midnight) — a deeper glass so the HUD
  /// still separates from already-dark chrome, and lifted accent /
  /// hazard hues that hold contrast on dark surfaces.
  static const dark = CaddieHudColors(
    hudGlass: Color(0xC8060A0F), // rgba(6,10,15,0.78)
    hudStroke: Color(0x1FFFFFFF), // rgba(255,255,255,0.12)
    hudOnGlass: Color(0xFFF1F5F9),
    caddieAccent: Color(0xFF4FA76C),
    hazard: Color(0xFFD9743C),
  );

  /// Picks the light or dark token set for [brightness].
  static CaddieHudColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  CaddieHudColors copyWith({
    Color? hudGlass,
    Color? hudStroke,
    Color? hudOnGlass,
    Color? caddieAccent,
    Color? hazard,
  }) {
    return CaddieHudColors(
      hudGlass: hudGlass ?? this.hudGlass,
      hudStroke: hudStroke ?? this.hudStroke,
      hudOnGlass: hudOnGlass ?? this.hudOnGlass,
      caddieAccent: caddieAccent ?? this.caddieAccent,
      hazard: hazard ?? this.hazard,
    );
  }

  @override
  CaddieHudColors lerp(ThemeExtension<CaddieHudColors>? other, double t) {
    if (other is! CaddieHudColors) return this;
    return CaddieHudColors(
      hudGlass: Color.lerp(hudGlass, other.hudGlass, t)!,
      hudStroke: Color.lerp(hudStroke, other.hudStroke, t)!,
      hudOnGlass: Color.lerp(hudOnGlass, other.hudOnGlass, t)!,
      caddieAccent: Color.lerp(caddieAccent, other.caddieAccent, t)!,
      hazard: Color.lerp(hazard, other.hazard, t)!,
    );
  }
}

extension CaddieHudColorsX on BuildContext {
  /// HUD color tokens for the active theme. Falls back to the light
  /// token set if the extension somehow isn't registered.
  CaddieHudColors get hud =>
      Theme.of(this).extension<CaddieHudColors>() ?? CaddieHudColors.light;
}
