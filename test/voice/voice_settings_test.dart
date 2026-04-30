// Tests for KAN-278 (S8) voice settings — locale mapping, pitch
// table, and the all-personas catalog the AC requires.

import 'package:caddieai/core/voice/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaddieVoiceAccent', () {
    test('every accent maps to a non-empty BCP-47 locale', () {
      for (final accent in CaddieVoiceAccent.values) {
        expect(accent.languageCode, isNotEmpty);
        expect(accent.languageCode, matches(r'^[a-z]{2}-[A-Z]{2}$'));
      }
    });

    test('canonical accent → locale mappings', () {
      expect(CaddieVoiceAccent.american.languageCode, 'en-US');
      expect(CaddieVoiceAccent.british.languageCode, 'en-GB');
      expect(CaddieVoiceAccent.scottish.languageCode, 'en-GB');
      expect(CaddieVoiceAccent.irish.languageCode, 'en-IE');
      expect(CaddieVoiceAccent.australian.languageCode, 'en-AU');
    });

    test('every accent has a display name', () {
      for (final accent in CaddieVoiceAccent.values) {
        expect(accent.displayName, isNotEmpty);
      }
    });
  });

  group('CaddieVoiceGender', () {
    test('male pitch < neutral < female pitch', () {
      // The pitch values are lifted from the Android native:
      // 0.85 male, 1.15 female. Neutral (1.0) sits between.
      expect(CaddieVoiceGender.male.pitch, lessThan(1.0));
      expect(CaddieVoiceGender.female.pitch, greaterThan(1.0));
    });
  });

  group('CaddieVoicePersona — KAN-278 AC #1 (10 combos)', () {
    test('allPersonas has exactly 10 combinations (2 genders × 5 accents)',
        () {
      expect(CaddieVoicePersona.allPersonas, hasLength(10));
    });

    test('every combination is represented exactly once', () {
      final seen = <String>{};
      for (final p in CaddieVoicePersona.allPersonas) {
        final key = '${p.gender.name}-${p.accent.name}';
        expect(seen.add(key), isTrue,
            reason: 'duplicate combination: $key');
      }
      // Sanity: 2 × 5 = 10
      expect(seen, hasLength(10));
    });

    test('contains every (gender, accent) cartesian product', () {
      for (final gender in CaddieVoiceGender.values) {
        for (final accent in CaddieVoiceAccent.values) {
          final expected = CaddieVoicePersona(gender: gender, accent: accent);
          expect(
            CaddieVoicePersona.allPersonas.contains(expected),
            isTrue,
            reason: 'missing $gender / $accent',
          );
        }
      }
    });

    test('default persona is female + American', () {
      expect(
        CaddieVoicePersona.defaultPersona,
        const CaddieVoicePersona(
          gender: CaddieVoiceGender.female,
          accent: CaddieVoiceAccent.american,
        ),
      );
    });

    test('persona equality is value-based', () {
      const a = CaddieVoicePersona(
        gender: CaddieVoiceGender.male,
        accent: CaddieVoiceAccent.scottish,
      );
      const b = CaddieVoicePersona(
        gender: CaddieVoiceGender.male,
        accent: CaddieVoiceAccent.scottish,
      );
      const c = CaddieVoicePersona(
        gender: CaddieVoiceGender.female,
        accent: CaddieVoiceAccent.scottish,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
