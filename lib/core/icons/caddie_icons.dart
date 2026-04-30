// CaddieAI custom icon set — 45 stroke-based SVGs rendered via
// flutter_svg per ADR 0007. The original ADR 0006 attempted to use a
// generated TTF icon font, which destroys stroke-based glyphs (TTF
// supports fills only); see ADR 0006 "Why this was wrong" for the
// post-mortem.
//
// Source: /home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/, mirrored
// into `mobile-flutter/assets/icons/` as the runtime asset.
//
// ## Usage
//
// ```dart
// import 'package:caddieai/core/icons/caddie_icons.dart';
//
// // Default size, default color (inherits from IconTheme via the
// // surrounding context — actually, with flutter_svg, "default color"
// // means the color baked into the SVG, which is black; pass `color:`
// // explicitly when you want the icon tinted to a theme color).
// CaddieIcons.flag()
//
// // With size + theme color
// CaddieIcons.flag(size: 32, color: Theme.of(context).colorScheme.primary)
//
// // With size + explicit color
// CaddieIcons.golfer(size: 24, color: Colors.amberAccent)
// ```
//
// ## Adding a new icon
//
// 1. Drop the SVG into `mobile-flutter/assets/icons/` as `icon-{name}.svg`
//    (also mirror into the source-of-truth dir at
//    /home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/)
// 2. Add an entry to the `_paths` map below (camelCase key → asset path)
// 3. Add a named getter that delegates to `_render('name', size, color)`
// 4. Update `docs/design/icons.md` with the new icon's name + intended use
// 5. Run `flutter test` — the registry test will fail until the entry is added

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

abstract final class CaddieIcons {
  CaddieIcons._();

  // Internal source of truth — name (camelCase) → asset path.
  // Used by the named getters below AND by the test suite to enumerate
  // all 45 icons. The asset path strings are the SOLE place asset
  // filenames live; everything else delegates here.
  static const Map<String, String> _paths = {
    // Navigation (8)
    'home': 'assets/icons/icon-home.svg',
    'course': 'assets/icons/icon-course.svg',
    'history': 'assets/icons/icon-history.svg',
    'profile': 'assets/icons/icon-profile.svg',
    'settings': 'assets/icons/icon-settings.svg',
    'back': 'assets/icons/icon-back.svg',
    'chevronLeft': 'assets/icons/icon-chevron-left.svg',
    'chevronRight': 'assets/icons/icon-chevron-right.svg',

    // Actions (11)
    'add': 'assets/icons/icon-add.svg',
    'close': 'assets/icons/icon-close.svg',
    'delete': 'assets/icons/icon-delete.svg',
    'edit': 'assets/icons/icon-edit.svg',
    'send': 'assets/icons/icon-send.svg',
    'refresh': 'assets/icons/icon-refresh.svg',
    'lock': 'assets/icons/icon-lock.svg',
    'listen': 'assets/icons/icon-listen.svg',
    'mic': 'assets/icons/icon-mic.svg',
    'camera': 'assets/icons/icon-camera.svg',
    'chat': 'assets/icons/icon-chat.svg',

    // Status (6)
    'error': 'assets/icons/icon-error.svg',
    'success': 'assets/icons/icon-success.svg',
    'warning': 'assets/icons/icon-warning.svg',
    'info': 'assets/icons/icon-info.svg',
    'loading': 'assets/icons/icon-loading.svg',
    'disabled': 'assets/icons/icon-disabled.svg',

    // Golf-specific (20)
    'flag': 'assets/icons/icon-flag.svg',
    'pinTarget': 'assets/icons/icon-pin-target.svg',
    'target': 'assets/icons/icon-target.svg',
    'dogleg': 'assets/icons/icon-dogleg.svg',
    'golfer': 'assets/icons/icon-golfer.svg',
    'club': 'assets/icons/icon-club.svg',
    'tee': 'assets/icons/icon-tee.svg',
    'fairway': 'assets/icons/icon-fairway.svg',
    'rough': 'assets/icons/icon-rough.svg',
    'bunker': 'assets/icons/icon-bunker.svg',
    'water': 'assets/icons/icon-water.svg',
    'hazard': 'assets/icons/icon-hazard.svg',
    'lie': 'assets/icons/icon-lie.svg',
    'slope': 'assets/icons/icon-slope.svg',
    'elevation': 'assets/icons/icon-elevation.svg',
    'distance': 'assets/icons/icon-distance.svg',
    'wind': 'assets/icons/icon-wind.svg',
    'stance': 'assets/icons/icon-stance.svg',
    'tempo': 'assets/icons/icon-tempo.svg',
    'green': 'assets/icons/icon-green.svg',
  };

  /// Read-only public registry — used by tests and any future icon
  /// picker / debug screen. Maps camelCase name → asset path.
  static Map<String, String> get all => _paths;

  /// Render an icon by camelCase name. Throws [ArgumentError] if the
  /// name isn't in the registry. Prefer the named getters below for
  /// compile-time safety; this is for dynamic / data-driven cases.
  static Widget byName(String name, {double size = 24, Color? color}) =>
      _render(name, size, color);

  // ---------------------------------------------------------------------
  // Internal render helper. All named getters delegate here.
  // ---------------------------------------------------------------------
  static Widget _render(String name, double size, Color? color) {
    final path = _paths[name];
    if (path == null) {
      throw ArgumentError('Unknown CaddieIcons name: "$name"');
    }
    return SvgPicture.asset(
      path,
      width: size,
      height: size,
      colorFilter:
          color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null,
    );
  }

  // ---------------------------------------------------------------------
  // Navigation (8)
  // ---------------------------------------------------------------------
  static Widget home({double size = 24, Color? color}) =>
      _render('home', size, color);
  static Widget course({double size = 24, Color? color}) =>
      _render('course', size, color);
  static Widget history({double size = 24, Color? color}) =>
      _render('history', size, color);
  static Widget profile({double size = 24, Color? color}) =>
      _render('profile', size, color);
  static Widget settings({double size = 24, Color? color}) =>
      _render('settings', size, color);
  static Widget back({double size = 24, Color? color}) =>
      _render('back', size, color);
  static Widget chevronLeft({double size = 24, Color? color}) =>
      _render('chevronLeft', size, color);
  static Widget chevronRight({double size = 24, Color? color}) =>
      _render('chevronRight', size, color);

  // ---------------------------------------------------------------------
  // Actions (11)
  // ---------------------------------------------------------------------
  static Widget add({double size = 24, Color? color}) =>
      _render('add', size, color);
  static Widget close({double size = 24, Color? color}) =>
      _render('close', size, color);
  static Widget delete({double size = 24, Color? color}) =>
      _render('delete', size, color);
  static Widget edit({double size = 24, Color? color}) =>
      _render('edit', size, color);
  static Widget send({double size = 24, Color? color}) =>
      _render('send', size, color);
  static Widget refresh({double size = 24, Color? color}) =>
      _render('refresh', size, color);
  static Widget lock({double size = 24, Color? color}) =>
      _render('lock', size, color);
  static Widget listen({double size = 24, Color? color}) =>
      _render('listen', size, color);
  static Widget mic({double size = 24, Color? color}) =>
      _render('mic', size, color);
  static Widget camera({double size = 24, Color? color}) =>
      _render('camera', size, color);
  static Widget chat({double size = 24, Color? color}) =>
      _render('chat', size, color);

  // ---------------------------------------------------------------------
  // Status (6)
  // ---------------------------------------------------------------------
  static Widget error({double size = 24, Color? color}) =>
      _render('error', size, color);
  static Widget success({double size = 24, Color? color}) =>
      _render('success', size, color);
  static Widget warning({double size = 24, Color? color}) =>
      _render('warning', size, color);
  static Widget info({double size = 24, Color? color}) =>
      _render('info', size, color);
  static Widget loading({double size = 24, Color? color}) =>
      _render('loading', size, color);
  static Widget disabled({double size = 24, Color? color}) =>
      _render('disabled', size, color);

  // ---------------------------------------------------------------------
  // Golf-specific (20)
  // ---------------------------------------------------------------------
  static Widget flag({double size = 24, Color? color}) =>
      _render('flag', size, color);
  static Widget pinTarget({double size = 24, Color? color}) =>
      _render('pinTarget', size, color);
  static Widget target({double size = 24, Color? color}) =>
      _render('target', size, color);
  static Widget dogleg({double size = 24, Color? color}) =>
      _render('dogleg', size, color);
  static Widget golfer({double size = 24, Color? color}) =>
      _render('golfer', size, color);
  static Widget club({double size = 24, Color? color}) =>
      _render('club', size, color);
  static Widget tee({double size = 24, Color? color}) =>
      _render('tee', size, color);
  static Widget fairway({double size = 24, Color? color}) =>
      _render('fairway', size, color);
  static Widget rough({double size = 24, Color? color}) =>
      _render('rough', size, color);
  static Widget bunker({double size = 24, Color? color}) =>
      _render('bunker', size, color);
  static Widget water({double size = 24, Color? color}) =>
      _render('water', size, color);
  static Widget hazard({double size = 24, Color? color}) =>
      _render('hazard', size, color);
  static Widget lie({double size = 24, Color? color}) =>
      _render('lie', size, color);
  static Widget slope({double size = 24, Color? color}) =>
      _render('slope', size, color);
  static Widget elevation({double size = 24, Color? color}) =>
      _render('elevation', size, color);
  static Widget distance({double size = 24, Color? color}) =>
      _render('distance', size, color);
  static Widget wind({double size = 24, Color? color}) =>
      _render('wind', size, color);
  static Widget stance({double size = 24, Color? color}) =>
      _render('stance', size, color);
  static Widget tempo({double size = 24, Color? color}) =>
      _render('tempo', size, color);
  static Widget green({double size = 24, Color? color}) =>
      _render('green', size, color);
}
