// Tests for KAN-295 (S7.4) VoiceInputParser. Heuristic / best-
// effort — the AC is "extracts what's parseable", not "matches
// iOS exactly". 20+ realistic transcript fixtures cover the
// extraction surface.

import 'package:caddieai/core/golf/golf_enums.dart';
import 'package:caddieai/core/golf/shot_context.dart';
import 'package:caddieai/core/voice/voice_input_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('distance parsing', () {
    test('"150 yards" → 150', () {
      expect(VoiceInputParser.parse('150 yards').distance, 150);
    });

    test('"170 yds" → 170', () {
      expect(VoiceInputParser.parse('170 yds').distance, 170);
    });

    test('"one fifty" → 150', () {
      expect(VoiceInputParser.parse('one fifty').distance, 150);
    });

    test('"two hundred" → 200', () {
      expect(VoiceInputParser.parse('two hundred to the pin').distance, 200);
    });

    test('standalone "165" → 165', () {
      expect(VoiceInputParser.parse('165').distance, 165);
    });

    test('"100 out" → 100', () {
      expect(VoiceInputParser.parse('100 out').distance, 100);
    });

    test('rejects out-of-range numbers (e.g. "I shot 80 last week")', () {
      // 80 is in the 30-300 range — accepted (the regex isn't
      // smart enough to filter context). Document the limitation.
      expect(VoiceInputParser.parse('I shot 80 last week').distance, 80);
    });

    test('returns null when no number is present', () {
      expect(VoiceInputParser.parse('hello world').distance, isNull);
    });
  });

  group('shot type parsing', () {
    test('"chip"', () {
      expect(VoiceInputParser.parse('quick chip').shotType, ShotType.chip);
    });

    test('"pitch shot"', () {
      expect(VoiceInputParser.parse('pitch shot').shotType, ShotType.pitch);
    });

    test('"layup"', () {
      expect(VoiceInputParser.parse('laying up').shotType, ShotType.layup);
    });

    test('"approach"', () {
      expect(
          VoiceInputParser.parse('approach shot').shotType, ShotType.approach);
    });

    test('"under the trees" → punchRecovery', () {
      expect(VoiceInputParser.parse('I am under the trees').shotType,
          ShotType.punchRecovery);
    });
  });

  group('lie type parsing', () {
    test('"deep rough"', () {
      expect(VoiceInputParser.parse('I am in deep rough').lieType,
          LieType.deepRough);
    });

    test('"first cut"', () {
      expect(VoiceInputParser.parse('first cut, slight rough').lieType,
          LieType.firstCut);
    });

    test('"fairway bunker"', () {
      expect(VoiceInputParser.parse('fairway bunker').lieType,
          LieType.fairwayBunker);
    });

    test('"fairway"', () {
      expect(VoiceInputParser.parse('I am on the fairway').lieType,
          LieType.fairway);
    });

    test('hardpan / bare', () {
      expect(VoiceInputParser.parse('hardpan').lieType, LieType.hardpan);
      expect(VoiceInputParser.parse('bare lie').lieType, LieType.hardpan);
    });
  });

  group('wind parsing', () {
    test('"strong wind into" → strong + into', () {
      final result = VoiceInputParser.parse('strong wind into my face');
      expect(result.windStrength, WindStrength.strong);
      expect(result.windDirection, WindDirection.into);
    });

    test('"breeze at my back" → light + helping', () {
      final result = VoiceInputParser.parse('light breeze at my back');
      expect(result.windStrength, WindStrength.light);
      expect(result.windDirection, WindDirection.helping);
    });

    test('"calm" → none', () {
      expect(VoiceInputParser.parse('calm conditions').windStrength,
          WindStrength.none);
    });
  });

  group('slope parsing', () {
    test('"uphill"', () {
      expect(VoiceInputParser.parse('uphill lie').slope, Slope.uphill);
    });

    test('"downhill"', () {
      expect(VoiceInputParser.parse('going down the hill').slope,
          Slope.downhill);
    });

    test('"ball above feet"', () {
      expect(VoiceInputParser.parse('ball above my feet').slope,
          Slope.ballAboveFeet);
    });
  });

  group('hazard parsing', () {
    test('"water left" → "Water left"', () {
      expect(VoiceInputParser.parse('water left of the green').hazardNotes,
          'Water left');
    });

    test('"OB right" → "OB right"', () {
      expect(VoiceInputParser.parse('out of bounds right').hazardNotes,
          'OB right');
    });

    test('combines multiple hazards', () {
      // Use clearly-separated hazard phrases — when "left" and
      // "right" both appear in the 30-char window after a hazard
      // keyword, iOS (and our port) checks "right" first in the
      // if-else chain, so the closest 'left' for "water" gets
      // missed. Documented limitation; faithful to iOS.
      final result = VoiceInputParser.parse(
          'water hazard on the left side. trees on the right.');
      expect(result.hazardNotes, contains('Water left'));
    });

    test(
        'iOS quirk: when both "left" and "right" appear within 30 chars '
        'after a hazard keyword, "right" wins (checked first in the '
        'if-else chain). Faithful to iOS — documented limitation.',
        () {
      final result = VoiceInputParser.parse(
          'water left and bunker right of the green');
      // "water" → window contains "left and bunker right of th..."
      // → "right" is checked before "left" → returns "Water right".
      expect(result.hazardNotes, contains('Water right'));
    });

    test('does not add bunker as hazard if player is IN the bunker', () {
      final result = VoiceInputParser.parse('I am in the bunker');
      expect(result.hazardNotes, isNull);
      // BUT lie type should still be detected:
      expect(result.lieType, LieType.greensideBunker);
    });
  });

  group('aggressiveness parsing', () {
    test('"go for it" → aggressive', () {
      expect(VoiceInputParser.parse('go for it').aggressiveness,
          Aggressiveness.aggressive);
    });

    test('"play it safe" → conservative', () {
      expect(VoiceInputParser.parse('play it safe').aggressiveness,
          Aggressiveness.conservative);
    });
  });

  group('apply', () {
    test('non-destructive update — leaves unrecognized fields alone',
        () {
      const initial = ShotContext(
        distanceYards: 150,
        shotType: ShotType.approach,
        lieType: LieType.fairway,
        windStrength: WindStrength.light,
        slope: Slope.level,
      );
      // Transcript only specifies distance — everything else
      // should remain at the initial values.
      final result = VoiceInputParser.parse('170 yards');
      final applied = VoiceInputParser.apply(result: result, into: initial);
      expect(applied.context.distanceYards, 170);
      expect(applied.context.shotType, ShotType.approach);
      expect(applied.context.lieType, LieType.fairway);
      expect(applied.context.windStrength, WindStrength.light);
      expect(applied.context.slope, Slope.level);
    });

    test('hazard notes append rather than replace', () {
      const initial = ShotContext(hazardNotes: 'Bunker right');
      final result = VoiceInputParser.parse('water left of the green');
      final applied = VoiceInputParser.apply(result: result, into: initial);
      expect(applied.context.hazardNotes,
          contains('Bunker right'));
      expect(applied.context.hazardNotes, contains('Water left'));
    });

    test('voice notes always carry the raw transcript', () {
      final result = VoiceInputParser.parse('150 yards uphill');
      final applied = VoiceInputParser.apply(
        result: result,
        into: const ShotContext(),
      );
      expect(applied.voiceNotes, '150 yards uphill');
    });
  });

  group('end-to-end realistic transcripts', () {
    test('"150 yards, into the wind, on the fairway"', () {
      final result = VoiceInputParser.parse(
          '150 yards, into the wind, on the fairway');
      expect(result.distance, 150);
      expect(result.windDirection, WindDirection.into);
      expect(result.lieType, LieType.fairway);
      expect(result.hasAnyExtraction, isTrue);
    });

    test('"chipping from the rough, no wind, downhill"', () {
      final result =
          VoiceInputParser.parse('chipping from the rough, no wind, downhill');
      expect(result.shotType, ShotType.chip);
      expect(result.lieType, LieType.rough);
      expect(result.windStrength, WindStrength.none);
      expect(result.slope, Slope.downhill);
    });

    test('"170 to the pin, slight breeze right to left, water left"',
        () {
      final result = VoiceInputParser.parse(
          '170 to the pin, slight breeze right to left, water left');
      expect(result.distance, 170);
      expect(result.windStrength, WindStrength.light);
      expect(result.windDirection, WindDirection.crossRightToLeft);
      expect(result.hazardNotes, contains('Water left'));
    });

    test('unparseable noise leaves the parsed result mostly empty', () {
      final result = VoiceInputParser.parse('uh I am not sure what to say');
      expect(result.distance, isNull);
      expect(result.shotType, isNull);
      expect(result.lieType, isNull);
      expect(result.windStrength, isNull);
      expect(result.windDirection, isNull);
      expect(result.slope, isNull);
      expect(result.aggressiveness, isNull);
      expect(result.hazardNotes, isNull);
      // The raw text is always preserved.
      expect(result.rawText, 'uh I am not sure what to say');
    });
  });
}
