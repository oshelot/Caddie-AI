// Generated from /home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/ via
// fantasticon (see ADR 0006). Do NOT edit by hand — see KAN-291 and the
// regeneration instructions in `mobile-flutter/docs/design/icons.md`.
//
// To add a new icon:
//   1. Drop the SVG into `mobile-flutter/assets/icons-source/`
//      (and into the source-of-truth dir at
//      /home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/)
//   2. Re-run fantasticon (command in docs/design/icons.md)
//   3. Replace this file from the new CaddieIcons.json
//   4. Add a unit test entry in `test/caddie_icons_test.dart`
//
// 45 icons total. Codepoints 0xF101..0xF12D, private-use area.

import 'package:flutter/widgets.dart';

/// Type-safe constants for the CaddieAI custom icon set.
///
/// Always use these instead of `Icons.material_*` per CONVENTIONS C-6.
/// Render via the standard Flutter `Icon` widget:
///
/// ```dart
/// Icon(CaddieIcons.flag, size: 24, color: Theme.of(context).colorScheme.primary)
/// ```
///
/// Standard sizes (per `docs/design/icons.md`):
///   - 16 dp — compact (inline with body text, dense lists)
///   - 20 dp — default (most icon-button uses)
///   - 24 dp — prominent (primary CTAs, tab bar)
///   - 32 dp — hero (empty states, splash)
abstract final class CaddieIcons {
  CaddieIcons._();

  static const String _family = 'CaddieIcons';

  // ---------------------------------------------------------------------
  // Navigation (8)
  // ---------------------------------------------------------------------
  static const IconData home = IconData(0xF116, fontFamily: _family);
  static const IconData course = IconData(0xF124, fontFamily: _family);
  static const IconData history = IconData(0xF117, fontFamily: _family);
  static const IconData profile = IconData(0xF10E, fontFamily: _family);
  static const IconData settings = IconData(0xF10A, fontFamily: _family);
  static const IconData back = IconData(0xF12C, fontFamily: _family);
  static const IconData chevronLeft = IconData(0xF128, fontFamily: _family);
  static const IconData chevronRight = IconData(0xF127, fontFamily: _family);

  // ---------------------------------------------------------------------
  // Actions (11)
  // ---------------------------------------------------------------------
  static const IconData add = IconData(0xF12D, fontFamily: _family);
  static const IconData close = IconData(0xF126, fontFamily: _family);
  static const IconData delete = IconData(0xF123, fontFamily: _family);
  static const IconData edit = IconData(0xF11F, fontFamily: _family);
  static const IconData send = IconData(0xF10B, fontFamily: _family);
  static const IconData refresh = IconData(0xF10D, fontFamily: _family);
  static const IconData lock = IconData(0xF111, fontFamily: _family);
  static const IconData listen = IconData(0xF113, fontFamily: _family);
  static const IconData mic = IconData(0xF110, fontFamily: _family);
  static const IconData camera = IconData(0xF12A, fontFamily: _family);
  static const IconData chat = IconData(0xF129, fontFamily: _family);

  // ---------------------------------------------------------------------
  // Status (6)
  // ---------------------------------------------------------------------
  static const IconData error = IconData(0xF11D, fontFamily: _family);
  static const IconData success = IconData(0xF107, fontFamily: _family);
  static const IconData warning = IconData(0xF103, fontFamily: _family);
  static const IconData info = IconData(0xF115, fontFamily: _family);
  static const IconData loading = IconData(0xF112, fontFamily: _family);
  static const IconData disabled = IconData(0xF122, fontFamily: _family);

  // ---------------------------------------------------------------------
  // Golf-specific (20)
  // ---------------------------------------------------------------------
  static const IconData flag = IconData(0xF11B, fontFamily: _family);
  static const IconData pinTarget = IconData(0xF10F, fontFamily: _family);
  static const IconData target = IconData(0xF106, fontFamily: _family);
  static const IconData dogleg = IconData(0xF120, fontFamily: _family);
  static const IconData golfer = IconData(0xF11A, fontFamily: _family);
  static const IconData club = IconData(0xF125, fontFamily: _family);
  static const IconData tee = IconData(0xF105, fontFamily: _family);
  static const IconData fairway = IconData(0xF11C, fontFamily: _family);
  static const IconData rough = IconData(0xF10C, fontFamily: _family);
  static const IconData bunker = IconData(0xF12B, fontFamily: _family);
  static const IconData water = IconData(0xF102, fontFamily: _family);
  static const IconData hazard = IconData(0xF118, fontFamily: _family);
  static const IconData lie = IconData(0xF114, fontFamily: _family);
  static const IconData slope = IconData(0xF109, fontFamily: _family);
  static const IconData elevation = IconData(0xF11E, fontFamily: _family);
  static const IconData distance = IconData(0xF121, fontFamily: _family);
  static const IconData wind = IconData(0xF101, fontFamily: _family);
  static const IconData stance = IconData(0xF108, fontFamily: _family);
  static const IconData tempo = IconData(0xF104, fontFamily: _family);
  static const IconData green = IconData(0xF119, fontFamily: _family);

  // ---------------------------------------------------------------------
  // All-icons map — used by the test suite to enumerate every icon and
  // assert it has a non-null IconData with the right font family. Also
  // useful for any in-app icon picker / debug screen.
  // ---------------------------------------------------------------------
  static const Map<String, IconData> all = {
    // Navigation
    'home': home,
    'course': course,
    'history': history,
    'profile': profile,
    'settings': settings,
    'back': back,
    'chevronLeft': chevronLeft,
    'chevronRight': chevronRight,
    // Actions
    'add': add,
    'close': close,
    'delete': delete,
    'edit': edit,
    'send': send,
    'refresh': refresh,
    'lock': lock,
    'listen': listen,
    'mic': mic,
    'camera': camera,
    'chat': chat,
    // Status
    'error': error,
    'success': success,
    'warning': warning,
    'info': info,
    'loading': loading,
    'disabled': disabled,
    // Golf-specific
    'flag': flag,
    'pinTarget': pinTarget,
    'target': target,
    'dogleg': dogleg,
    'golfer': golfer,
    'club': club,
    'tee': tee,
    'fairway': fairway,
    'rough': rough,
    'bunker': bunker,
    'water': water,
    'hazard': hazard,
    'lie': lie,
    'slope': slope,
    'elevation': elevation,
    'distance': distance,
    'wind': wind,
    'stance': stance,
    'tempo': tempo,
    'green': green,
  };
}
