// Voice persona settings — KAN-278 (S8) caddie voice configuration.
// Independent of the speech I/O implementations so the Profile
// screen (KAN-S13) and the caddie screen (KAN-S11) can read these
// without depending on `flutter_tts` directly.
//
// **Spec note (5 vs 4 accents):** the KAN-S8 story spec lists 5
// accents — American / British / Scottish / Irish / Australian.
// The native iOS app actually ships only 4 — American / British /
// Australian / Indian (with Scottish/Irish missing and Indian
// added). The Android native ships the spec's 5. The Flutter port
// follows the **spec / Android shape** (5 accents) so the caddie
// screen UI matches the documented options. iOS-side will need
// updating post-cutover to add Scottish/Irish — that's tracked
// alongside the other "Android-or-iOS to be aligned post-cutover"
// items in ADR 0008.

/// Caddie voice gender. Maps to the TTS pitch multiplier
/// (lower = male-leaning, higher = female-leaning) on Android,
/// and to the platform's voice-gender filter on iOS.
enum CaddieVoiceGender {
  male,
  female;

  /// Pitch multiplier applied to the TTS engine. Lifted from the
  /// Android `TextToSpeechService.kt` constants (0.85 male / 1.15
  /// female). iOS doesn't take a multiplier — it filters voices
  /// by `gender` directly.
  double get pitch {
    switch (this) {
      case CaddieVoiceGender.male:
        return 0.85;
      case CaddieVoiceGender.female:
        return 1.15;
    }
  }
}

/// Caddie voice accent. The 5-value set from the KAN-S8 story
/// spec. Each maps to a BCP-47 language tag the underlying
/// platform engines understand.
enum CaddieVoiceAccent {
  american,
  british,
  scottish,
  irish,
  australian;

  /// BCP-47 locale string for the underlying platform TTS engine.
  /// `flutter_tts` accepts these directly via `setLanguage`.
  ///
  /// Scottish maps to `en-GB` because no major TTS engine ships
  /// a distinct Scottish English voice — the closest available
  /// is the British set with the highest-pitch alternative voice.
  /// Same trade-off as Android `TextToSpeechService.kt`.
  String get languageCode {
    switch (this) {
      case CaddieVoiceAccent.american:
        return 'en-US';
      case CaddieVoiceAccent.british:
        return 'en-GB';
      case CaddieVoiceAccent.scottish:
        return 'en-GB';
      case CaddieVoiceAccent.irish:
        return 'en-IE';
      case CaddieVoiceAccent.australian:
        return 'en-AU';
    }
  }

  /// Display label for the Profile screen voice picker.
  String get displayName {
    switch (this) {
      case CaddieVoiceAccent.american:
        return 'American';
      case CaddieVoiceAccent.british:
        return 'British';
      case CaddieVoiceAccent.scottish:
        return 'Scottish';
      case CaddieVoiceAccent.irish:
        return 'Irish';
      case CaddieVoiceAccent.australian:
        return 'Australian';
    }
  }
}

/// One full voice persona — gender + accent. Combined into a
/// single value type so the caddie screen can pass one object
/// to `TtsService.speak`.
class CaddieVoicePersona {
  const CaddieVoicePersona({
    required this.gender,
    required this.accent,
  });

  final CaddieVoiceGender gender;
  final CaddieVoiceAccent accent;

  /// Default persona — female + American. Matches the iOS native
  /// `PlayerProfile.default` shape.
  static const CaddieVoicePersona defaultPersona = CaddieVoicePersona(
    gender: CaddieVoiceGender.female,
    accent: CaddieVoiceAccent.american,
  );

  /// All 10 combinations the AC requires (2 genders × 5 accents).
  /// Used by the Profile screen voice preview row and by the
  /// `TtsService` test that asserts every combination renders.
  static const List<CaddieVoicePersona> allPersonas = [
    CaddieVoicePersona(gender: CaddieVoiceGender.male, accent: CaddieVoiceAccent.american),
    CaddieVoicePersona(gender: CaddieVoiceGender.female, accent: CaddieVoiceAccent.american),
    CaddieVoicePersona(gender: CaddieVoiceGender.male, accent: CaddieVoiceAccent.british),
    CaddieVoicePersona(gender: CaddieVoiceGender.female, accent: CaddieVoiceAccent.british),
    CaddieVoicePersona(gender: CaddieVoiceGender.male, accent: CaddieVoiceAccent.scottish),
    CaddieVoicePersona(gender: CaddieVoiceGender.female, accent: CaddieVoiceAccent.scottish),
    CaddieVoicePersona(gender: CaddieVoiceGender.male, accent: CaddieVoiceAccent.irish),
    CaddieVoicePersona(gender: CaddieVoiceGender.female, accent: CaddieVoiceAccent.irish),
    CaddieVoicePersona(gender: CaddieVoiceGender.male, accent: CaddieVoiceAccent.australian),
    CaddieVoicePersona(gender: CaddieVoiceGender.female, accent: CaddieVoiceAccent.australian),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CaddieVoicePersona &&
          gender == other.gender &&
          accent == other.accent);

  @override
  int get hashCode => Object.hash(gender, accent);
}
