// Tests for the CaddieIcons registry and helper API. These are
// pure-Dart unit tests — they don't actually load the SVG assets at
// runtime (that requires a widget test with the Flutter test binding,
// which is overkill for asserting the registry shape). The smoke test
// in `lib/app.dart` plus a manual `flutter run` is the runtime check.

import 'package:caddieai/core/icons/caddie_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaddieIcons registry', () {
    test('contains exactly 45 icons', () {
      expect(CaddieIcons.all, hasLength(45));
    });

    test('every key is camelCase, no kebab-case leakage', () {
      for (final name in CaddieIcons.all.keys) {
        expect(
          name,
          isNot(contains('-')),
          reason: 'icon name "$name" must be camelCase, not kebab-case',
        );
      }
    });

    test('every value is an asset path under assets/icons/', () {
      for (final entry in CaddieIcons.all.entries) {
        expect(
          entry.value,
          startsWith('assets/icons/'),
          reason: 'icon "${entry.key}" must reference an asset under assets/icons/',
        );
        expect(
          entry.value,
          endsWith('.svg'),
          reason: 'icon "${entry.key}" must reference an .svg file',
        );
      }
    });

    test('every asset path is unique (no duplicate file references)', () {
      final paths = <String, String>{};
      for (final entry in CaddieIcons.all.entries) {
        expect(
          paths,
          isNot(contains(entry.value)),
          reason:
              'asset path "${entry.value}" is duplicated between '
              '"${paths[entry.value]}" and "${entry.key}"',
        );
        paths[entry.value] = entry.key;
      }
    });

    test('asset path follows the icon-{kebab-name}.svg convention', () {
      // Convert camelCase key → kebab-case → expected filename, then
      // assert the registered path matches.
      String camelToKebab(String s) =>
          s.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m.group(0)!.toLowerCase()}');
      for (final entry in CaddieIcons.all.entries) {
        final kebab = camelToKebab(entry.key);
        final expected = 'assets/icons/icon-$kebab.svg';
        expect(
          entry.value,
          expected,
          reason:
              'icon "${entry.key}" should map to "$expected" but is "${entry.value}"',
        );
      }
    });
  });

  group('CaddieIcons.byName', () {
    test('returns a non-null Widget for every registered name', () {
      for (final name in CaddieIcons.all.keys) {
        final widget = CaddieIcons.byName(name);
        expect(widget, isA<Widget>(), reason: 'byName("$name") must return a Widget');
      }
    });

    test('throws ArgumentError for an unknown name', () {
      expect(
        () => CaddieIcons.byName('definitely-not-a-real-icon'),
        throwsArgumentError,
      );
    });

    test('accepts size parameter', () {
      // We can't easily inspect the rendered widget tree without a
      // widget test, but we can at least verify the call doesn't throw
      // for a representative sample of sizes.
      for (final size in [16.0, 20.0, 24.0, 32.0]) {
        expect(() => CaddieIcons.byName('flag', size: size), returnsNormally);
      }
    });

    test('accepts color parameter', () {
      expect(
        () => CaddieIcons.byName('flag', color: const Color(0xFFFF0000)),
        returnsNormally,
      );
    });
  });

  group('CaddieIcons named getters', () {
    // Spot-check a representative icon from each category. The
    // exhaustive enumeration is via the registry tests above.
    test('Navigation: home returns a Widget', () {
      expect(CaddieIcons.home(), isA<Widget>());
    });

    test('Actions: send returns a Widget', () {
      expect(CaddieIcons.send(), isA<Widget>());
    });

    test('Status: error returns a Widget', () {
      expect(CaddieIcons.error(), isA<Widget>());
    });

    test('Golf-specific: flag returns a Widget', () {
      expect(CaddieIcons.flag(), isA<Widget>());
    });

    test('named getter accepts size + color named args', () {
      expect(
        CaddieIcons.flag(size: 32, color: const Color(0xFF00FF00)),
        isA<Widget>(),
      );
    });
  });
}
