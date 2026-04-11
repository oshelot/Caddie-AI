// VoiceInputParser — KAN-295 (S7.4) Flutter port of
// `ios/CaddieAI/Services/VoiceInputParser.swift`. Per **ADR 0008**,
// this is a heuristic / best-effort layer (NOT byte-identical):
// the goal is to extract whatever structured shot context can be
// pulled out of a voice transcript, leaving fields the parser
// can't recognize at their previous values, and passing the raw
// transcript through to the LLM as `voiceNotes` so the model
// gets the full context regardless.
//
// Both natives marked this engine as `TODO(migration)` tech debt
// in their original surveys — the heuristics drift between iOS
// and Android. The Flutter port follows iOS as the more
// comprehensive of the two (richer word-list distance parsing,
// more shot-type keywords) and adds the Android regex fallback
// for unrecognized numeric distances.
//
// **Why a class instead of an `abstract final class`:** the
// public API is one static `parse(transcript)` plus one
// `apply(result, into context)`. Static methods are fine here —
// there's no state, no clock, no DI.

import '../golf/golf_enums.dart';
import '../golf/shot_context.dart';

/// Result of running `VoiceInputParser.parse` against a transcript.
/// Every field is optional — null means "the parser could not
/// confidently extract this field from the transcript". Callers
/// pass the result to `VoiceInputParser.apply` to fold the
/// non-null fields into a `ShotContext`.
class VoiceParseResult {
  const VoiceParseResult({
    this.distance,
    this.shotType,
    this.lieType,
    this.windStrength,
    this.windDirection,
    this.slope,
    this.aggressiveness,
    this.hazardNotes,
    required this.rawText,
  });

  final int? distance;
  final ShotType? shotType;
  final LieType? lieType;
  final WindStrength? windStrength;
  final WindDirection? windDirection;
  final Slope? slope;
  final Aggressiveness? aggressiveness;
  final String? hazardNotes;

  /// Full original transcript. Passed straight through so the LLM
  /// caddie screen (KAN-S11) can hand it to the prompt as
  /// additional context.
  final String rawText;

  /// True if the parser extracted at least one structured field.
  /// Used by the caddie screen to decide whether to highlight the
  /// updated context fields after a voice input event.
  bool get hasAnyExtraction =>
      distance != null ||
      shotType != null ||
      lieType != null ||
      windStrength != null ||
      windDirection != null ||
      slope != null ||
      aggressiveness != null ||
      (hazardNotes != null && hazardNotes!.isNotEmpty);
}

/// One ShotContext + voice notes pair, returned from
/// `VoiceInputParser.apply`. Immutable so callers can compare
/// against the previous state to render diff highlights.
class VoiceApplyResult {
  const VoiceApplyResult({required this.context, required this.voiceNotes});
  final ShotContext context;
  final String voiceNotes;
}

abstract final class VoiceInputParser {
  VoiceInputParser._();

  /// Parses a voice transcript into a `VoiceParseResult`. The
  /// transcript is lowercased internally for matching; the raw
  /// (mixed-case) transcript is preserved on the result.
  static VoiceParseResult parse(String text) {
    final lower = text.toLowerCase();
    return VoiceParseResult(
      distance: _parseDistance(lower),
      shotType: _parseShotType(lower),
      lieType: _parseLieType(lower),
      windStrength: _parseWindStrength(lower),
      windDirection: _parseWindDirection(lower),
      slope: _parseSlope(lower),
      aggressiveness: _parseAggressiveness(lower),
      hazardNotes: _parseHazards(lower),
      rawText: text,
    );
  }

  /// Folds the parsed fields into a ShotContext, leaving fields
  /// the parser couldn't extract at their previous values
  /// (non-destructive update). Returns the new context + the raw
  /// voice notes the caller should attach for the LLM.
  ///
  /// **Hazard notes are appended, not replaced.** If the existing
  /// context already has hazard notes (e.g. from a previous voice
  /// input or the manual form), the new hazards are concatenated
  /// with `". "`.
  static VoiceApplyResult apply({
    required VoiceParseResult result,
    required ShotContext into,
    String existingVoiceNotes = '',
  }) {
    var ctx = into;
    if (result.distance != null) {
      ctx = ctx.copyWith(distanceYards: result.distance);
    }
    if (result.shotType != null) {
      ctx = ctx.copyWith(shotType: result.shotType);
    }
    if (result.lieType != null) {
      ctx = ctx.copyWith(lieType: result.lieType);
    }
    if (result.windStrength != null) {
      ctx = ctx.copyWith(windStrength: result.windStrength);
    }
    if (result.windDirection != null) {
      ctx = ctx.copyWith(windDirection: result.windDirection);
    }
    if (result.slope != null) {
      ctx = ctx.copyWith(slope: result.slope);
    }
    if (result.aggressiveness != null) {
      ctx = ctx.copyWith(aggressiveness: result.aggressiveness);
    }
    final newHazards = result.hazardNotes;
    if (newHazards != null && newHazards.isNotEmpty) {
      final combined = ctx.hazardNotes.isEmpty
          ? newHazards
          : '${ctx.hazardNotes}. $newHazards';
      ctx = ctx.copyWith(hazardNotes: combined);
    }
    final notes =
        result.rawText.isNotEmpty ? result.rawText : existingVoiceNotes;
    return VoiceApplyResult(context: ctx, voiceNotes: notes);
  }

  // ── Distance (iOS lines 78-110) ─────────────────────────────────

  /// Word-form distance lookup table — covers the common golf
  /// distances (100-250 yards in 10-yard increments). Lifted
  /// directly from `VoiceInputParser.swift` lines 80-87.
  static const Map<String, int> _distanceWords = {
    'two hundred': 200,
    'two fifty': 250,
    'two forty': 240,
    'two thirty': 230,
    'two twenty': 220,
    'two ten': 210,
    'one hundred': 100,
    'one fifty': 150,
    'one forty': 140,
    'one thirty': 130,
    'one twenty': 120,
    'one ten': 110,
    'one sixty': 160,
    'one seventy': 170,
    'one eighty': 180,
    'one ninety': 190,
  };

  static int? _parseDistance(String text) {
    // Word forms first (more specific).
    for (final entry in _distanceWords.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    // Yardage suffix patterns (Android-style regex fallback).
    final yardMatch =
        RegExp(r'(\d{2,3})\s*(?:yards?|yds?|out)').firstMatch(text);
    if (yardMatch != null) {
      return int.tryParse(yardMatch.group(1)!);
    }
    // Standalone 2-3 digit number in the 30-300 range. The bounds
    // protect against picking up things like jersey numbers, ages,
    // or "I shot 80 last week".
    final numberMatch = RegExp(r'\b(\d{2,3})\b').firstMatch(text);
    if (numberMatch != null) {
      final value = int.tryParse(numberMatch.group(1)!);
      if (value != null && value >= 30 && value <= 300) return value;
    }
    return null;
  }

  // ── Shot type (iOS lines 115-138) ───────────────────────────────

  static ShotType? _parseShotType(String text) {
    if (text.contains('tee') ||
        text.contains('tee shot') ||
        text.contains('tee box') ||
        text.contains('teeing')) {
      return ShotType.tee;
    }
    if (text.contains('chip') || text.contains('chipping')) {
      return ShotType.chip;
    }
    if (text.contains('pitch') || text.contains('pitching')) {
      return ShotType.pitch;
    }
    if (text.contains('bunker') ||
        text.contains('sand') ||
        text.contains('trap')) {
      return ShotType.bunker;
    }
    if (text.contains('punch') ||
        text.contains('recovery') ||
        text.contains('under the tree') ||
        text.contains('under trees')) {
      return ShotType.punchRecovery;
    }
    if (text.contains('layup') ||
        text.contains('lay up') ||
        text.contains('laying up')) {
      return ShotType.layup;
    }
    if (text.contains('approach')) {
      return ShotType.approach;
    }
    return null;
  }

  // ── Lie type (iOS lines 142-176) ────────────────────────────────

  static LieType? _parseLieType(String text) {
    if (text.contains('deep rough') ||
        text.contains('thick rough') ||
        text.contains('heavy rough')) {
      return LieType.deepRough;
    }
    if (text.contains('first cut') || text.contains('light rough')) {
      return LieType.firstCut;
    }
    if (text.contains('greenside bunker') ||
        text.contains('green side bunker')) {
      return LieType.greensideBunker;
    }
    if (text.contains('fairway bunker')) {
      return LieType.fairwayBunker;
    }
    if (text.contains('bunker') ||
        text.contains('sand') ||
        text.contains('trap')) {
      return LieType.greensideBunker;
    }
    if (text.contains('rough')) {
      return LieType.rough;
    }
    if (text.contains('hardpan') ||
        text.contains('hard pan') ||
        text.contains('bare') ||
        text.contains('dirt')) {
      return LieType.hardpan;
    }
    if (text.contains('pine straw') || text.contains('pine needles')) {
      return LieType.pineStraw;
    }
    if (text.contains('tree') ||
        text.contains('obstructed') ||
        text.contains('blocked')) {
      return LieType.treesObstructed;
    }
    if (text.contains('fairway')) {
      return LieType.fairway;
    }
    return null;
  }

  // ── Wind (iOS lines 180-214) ────────────────────────────────────

  static WindStrength? _parseWindStrength(String text) {
    if (text.contains('no wind') ||
        text.contains('calm') ||
        text.contains('still')) {
      return WindStrength.none;
    }
    if (text.contains('strong wind') ||
        text.contains('heavy wind') ||
        text.contains('really windy') ||
        text.contains('very windy')) {
      return WindStrength.strong;
    }
    if (text.contains('moderate wind') ||
        text.contains('medium wind') ||
        text.contains('some wind') ||
        text.contains('windy')) {
      return WindStrength.moderate;
    }
    if (text.contains('light wind') ||
        text.contains('slight wind') ||
        text.contains('little wind') ||
        text.contains('breeze')) {
      return WindStrength.light;
    }
    if (text.contains('wind') ||
        text.contains('into the wind') ||
        text.contains('downwind')) {
      return WindStrength.moderate;
    }
    return null;
  }

  static WindDirection? _parseWindDirection(String text) {
    if (text.contains('into') ||
        text.contains('in my face') ||
        text.contains('headwind') ||
        text.contains('into the wind')) {
      return WindDirection.into;
    }
    if (text.contains('helping') ||
        text.contains('downwind') ||
        text.contains('behind me') ||
        text.contains('with the wind') ||
        text.contains('at my back')) {
      return WindDirection.helping;
    }
    if (text.contains('left to right') || text.contains('left-to-right')) {
      return WindDirection.crossLeftToRight;
    }
    if (text.contains('right to left') || text.contains('right-to-left')) {
      return WindDirection.crossRightToLeft;
    }
    return null;
  }

  // ── Slope (iOS lines 218-235) ───────────────────────────────────

  static Slope? _parseSlope(String text) {
    if (text.contains('ball above') ||
        text.contains('above my feet') ||
        text.contains('above feet')) {
      return Slope.ballAboveFeet;
    }
    if (text.contains('ball below') ||
        text.contains('below my feet') ||
        text.contains('below feet')) {
      return Slope.ballBelowFeet;
    }
    if (text.contains('uphill') ||
        text.contains('up hill') ||
        text.contains('going up')) {
      return Slope.uphill;
    }
    if (text.contains('downhill') ||
        text.contains('down hill') ||
        text.contains('going down')) {
      return Slope.downhill;
    }
    if (text.contains('flat') || text.contains('level')) {
      return Slope.level;
    }
    return null;
  }

  // ── Aggressiveness (iOS lines 239-247) ──────────────────────────

  static Aggressiveness? _parseAggressiveness(String text) {
    if (text.contains('aggressive') ||
        text.contains('go for it') ||
        text.contains('attack') ||
        text.contains('fire at')) {
      return Aggressiveness.aggressive;
    }
    if (text.contains('conservative') ||
        text.contains('safe') ||
        text.contains('play it safe') ||
        text.contains('bail out')) {
      return Aggressiveness.conservative;
    }
    return null;
  }

  // ── Hazards (iOS lines 251-291) ─────────────────────────────────

  static String? _parseHazards(String text) {
    final hazards = <String>[];

    if (text.contains('water') ||
        text.contains('lake') ||
        text.contains('pond') ||
        text.contains('creek')) {
      final side = _extractSide(text, ['water', 'lake', 'pond', 'creek']);
      hazards.add('Water$side');
    }
    if (text.contains('ob') ||
        text.contains('out of bounds') ||
        text.contains('o.b.')) {
      final side = _extractSide(text, ['ob', 'out of bounds', 'o.b.']);
      hazards.add('OB$side');
    }
    if (text.contains('bunker') ||
        text.contains('sand') ||
        text.contains('trap')) {
      // Only emit as a hazard note if the player isn't IN the bunker
      // (in which case it's a lie, not a hazard).
      if (!text.contains('in the bunker') &&
          !text.contains('from the bunker') &&
          !text.contains('in the sand')) {
        final side = _extractSide(text, ['bunker', 'sand', 'trap']);
        hazards.add('Bunker$side');
      }
    }
    if (text.contains('drop off') ||
        text.contains('drop-off') ||
        text.contains('falls off')) {
      hazards.add('Drop-off');
    }
    if (hazards.isEmpty) return null;
    return hazards.join(', ');
  }

  static String _extractSide(String text, List<String> keywords) {
    for (final keyword in keywords) {
      final index = text.indexOf(keyword);
      if (index < 0) continue;
      final tail = text.substring(index + keyword.length);
      final window = tail.length > 30 ? tail.substring(0, 30) : tail;
      if (window.contains('right')) return ' right';
      if (window.contains('left')) return ' left';
      if (window.contains('front') || window.contains('short')) return ' front';
      if (window.contains('behind') ||
          window.contains('long') ||
          window.contains('back')) {
        return ' behind';
      }
    }
    return '';
  }
}
