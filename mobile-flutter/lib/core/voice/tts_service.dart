// TtsService — KAN-278 (S8) text-to-speech abstraction.
//
// **Why an interface, not a direct flutter_tts call:** the caddie
// screen (KAN-S11) needs to test its "speak the recommendation
// after the LLM finishes streaming" flow without standing up a
// real TTS engine. Tests inject `FakeTtsService` (in
// `test/voice/_fake_tts_service.dart`); production code uses
// `FlutterTtsService` which delegates to the `flutter_tts` plugin.
//
// **Latency telemetry:** the iOS native `TextToSpeechService`
// emits a `tts_start` log event with `latencyMs` + `charCount`
// metadata via `LoggingService`. The Flutter port plumbs the
// same event through `LoggingService.events.ttsLatency` so the
// CloudWatch dashboard binds against one canonical name across
// platforms. The interface accepts an injected logger so tests
// can capture the events.

import 'dart:async';

import '../logging/log_event.dart';
import '../logging/logging_service.dart';
import 'voice_settings.dart';

/// Public TTS API. Concrete impls live in
/// `flutter_tts_service.dart` (production) and the test fake.
abstract class TtsService {
  /// Initializes the underlying TTS engine. Must be awaited
  /// before the first `speak()` call. Idempotent — calling
  /// twice is a no-op.
  Future<void> initialize();

  /// Speaks the supplied text using the configured persona. If
  /// the engine is already speaking, the previous utterance is
  /// cancelled (matches iOS `synthesizer.stopSpeaking(at: .immediate)`
  /// + Android `QUEUE_FLUSH`).
  Future<void> speak(String text, {required CaddieVoicePersona persona});

  /// Stops any in-progress speech. Idempotent.
  Future<void> stop();

  /// True while the engine is actively speaking. Backed by a
  /// `Stream<bool>` so the caddie screen can render a "speaking"
  /// indicator that flips on/off automatically.
  bool get isSpeaking;
  Stream<bool> get isSpeakingStream;

  /// Releases the engine. Idempotent. Production code should
  /// call this from the app's lifecycle observer when the
  /// process is going to be killed (matches Android
  /// `tts.shutdown()`).
  Future<void> dispose();
}

/// Latency-logging wrapper that any concrete `TtsService` impl
/// can compose with. Records the time between `speak()` being
/// called and `isSpeakingStream` flipping to `true`, then logs
/// it to `LoggingService.events.ttsLatency` with `voiceGender`
/// + `voiceAccent` + `charCount` metadata. Lifted from the iOS
/// native pattern (TtsDelegate.onStart in
/// `TextToSpeechService.swift`).
///
/// Used by `FlutterTtsService` internally; tests inject a
/// `LoggingService` with a fake sender to verify the contract.
class TtsLatencyTracker {
  TtsLatencyTracker({
    required this.logger,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LoggingService logger;
  final DateTime Function() _clock;

  DateTime? _speakRequestedAt;
  int _pendingCharCount = 0;
  CaddieVoicePersona? _pendingPersona;

  /// Call when `speak()` is invoked, BEFORE the engine starts.
  void markSpeakRequested(String text, CaddieVoicePersona persona) {
    _speakRequestedAt = _clock();
    _pendingCharCount = text.length;
    _pendingPersona = persona;
  }

  /// Call when the engine reports it has actually started
  /// producing audio (the `flutter_tts` `onStart` callback).
  /// Computes the latency and emits the log event.
  void markSpeakStarted() {
    final start = _speakRequestedAt;
    final persona = _pendingPersona;
    if (start == null || persona == null) return;
    final latencyMs =
        _clock().millisecondsSinceEpoch - start.millisecondsSinceEpoch;
    logger.info(
      LogCategory.general,
      'tts_start',
      metadata: {
        'latency': '$latencyMs',
        'textLength': '$_pendingCharCount',
        'voiceGender': persona.gender.name,
        'voiceAccent': persona.accent.name,
      },
    );
    _speakRequestedAt = null;
    _pendingPersona = null;
    _pendingCharCount = 0;
  }
}
