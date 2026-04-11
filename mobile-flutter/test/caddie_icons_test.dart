// Tests for the CaddieIcons constants class. These tests assert that
// every named icon resolves to a non-null IconData and references the
// correct font family. They do NOT verify the font file is on disk —
// that's a runtime concern, not a unit-test concern (the runtime check
// happens in `lib/app.dart` smoke-test rendering).

import 'package:caddieai/core/icons/caddie_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaddieIcons', () {
    test('all 45 icons are present in the registry', () {
      expect(CaddieIcons.all, hasLength(45));
    });

    test('every icon resolves to a non-null IconData', () {
      for (final entry in CaddieIcons.all.entries) {
        expect(
          entry.value,
          isA<IconData>(),
          reason: 'icon "${entry.key}" should resolve to an IconData',
        );
      }
    });

    test('every icon uses the CaddieIcons font family', () {
      for (final entry in CaddieIcons.all.entries) {
        expect(
          entry.value.fontFamily,
          'CaddieIcons',
          reason: 'icon "${entry.key}" must use the CaddieIcons font family',
        );
      }
    });

    test('every icon has a unique codepoint', () {
      final codepoints = <int, String>{};
      for (final entry in CaddieIcons.all.entries) {
        final cp = entry.value.codePoint;
        expect(
          codepoints,
          isNot(contains(cp)),
          reason:
              'codepoint 0x${cp.toRadixString(16)} is duplicated between '
              '"${codepoints[cp]}" and "${entry.key}"',
        );
        codepoints[cp] = entry.key;
      }
    });

    test('all codepoints land in the Unicode private-use area', () {
      // PUA: U+E000..U+F8FF (Basic Multilingual Plane).
      // fantasticon assigns from 0xF101 upward by default.
      const puaStart = 0xE000;
      const puaEnd = 0xF8FF;
      for (final entry in CaddieIcons.all.entries) {
        final cp = entry.value.codePoint;
        expect(
          cp,
          inInclusiveRange(puaStart, puaEnd),
          reason:
              'codepoint 0x${cp.toRadixString(16)} for icon "${entry.key}" '
              'must be in the Unicode private-use area '
              '(U+E000..U+F8FF)',
        );
      }
    });

    test('icon names are camelCase, no kebab-case leakage from JSON', () {
      // The fantasticon JSON uses kebab-case (e.g. "icon-pin-target") but
      // the Dart constants must be camelCase (e.g. `pinTarget`). This
      // test guards against accidentally re-exposing the JSON shape.
      for (final name in CaddieIcons.all.keys) {
        expect(
          name,
          isNot(contains('-')),
          reason: 'icon name "$name" must be camelCase, not kebab-case',
        );
      }
    });
  });
}
