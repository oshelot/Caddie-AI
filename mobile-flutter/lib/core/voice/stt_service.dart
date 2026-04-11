// SttService — KAN-278 (S8) speech-to-text abstraction.
//
// Mirrors the iOS `SpeechRecognitionService.swift` and Android
// `SpeechRecognitionService.kt` API surface but in a Dart-idiomatic
// stream-of-events shape. The caddie screen (KAN-S11) consumes
// this stream to render token-by-token transcription as the user
// speaks.
//
// **Why a sealed-class-style state stream:** the underlying
// `speech_to_text` plugin emits separate callbacks for partial
// vs final results, plus error / lifecycle events. The caddie
// screen wants ONE stream it can `await for`, so we union the
// platform callbacks into `SttEvent` subtypes. Tests inject a
// `FakeSttService` that emits whatever sequence the test needs.
//
// **Latency tracking:** `SttEvent.finalTranscript` carries
// `latencyMs` (ms from `startListening` to the final-result
// callback). The production impl logs that to
// `LoggingService.events.sttLatency` automatically; tests can
// inspect the value directly without going through the logger.

import 'dart:async';

import 'voice_settings.dart';

/// One event from the STT pipeline. Subtypes match the iOS /
/// Android RecognitionState shape:
///
///   - `listening` — engine is ready, no transcript yet
///   - `partial` — partial result delta as the user speaks
///   - `finalTranscript` — the user paused; this is the locked-in
///     transcription
///   - `error` — recognizer-side failure (network, no match, etc.)
sealed class SttEvent {
  const SttEvent();
}

class SttListeningEvent extends SttEvent {
  const SttListeningEvent();
}

class SttPartialEvent extends SttEvent {
  const SttPartialEvent(this.text);
  final String text;
}

class SttFinalTranscriptEvent extends SttEvent {
  const SttFinalTranscriptEvent({
    required this.text,
    required this.latencyMs,
    this.alternatives = const [],
  });

  final String text;

  /// Time from `startListening()` to this final-result callback.
  /// Logged via `LoggingService.events.sttLatency` by the
  /// production impl.
  final int latencyMs;

  /// Alternative transcriptions the engine considered. Empty
  /// when the engine returns only the top result.
  final List<String> alternatives;
}

class SttErrorEvent extends SttEvent {
  const SttErrorEvent({required this.code, required this.message});
  final String code;
  final String message;
}

abstract class SttService {
  /// True if a speech recognizer is available on this device.
  /// On Android this checks the system service; on iOS this
  /// checks the SFSpeechRecognizer authorization status.
  Future<bool> get isAvailable;

  /// Requests microphone + speech-recognition permission. Returns
  /// true if permission is granted (or was already granted).
  /// Triggers the system permission dialog on first call.
  Future<bool> requestPermission();

  /// Starts a recognition session and returns a stream of events
  /// for the duration of that session. The stream completes when
  /// the engine emits a final transcript or an error.
  ///
  /// Pass `accent` to bias the recognizer language. Defaults to
  /// `american` so a fresh install picks up English without the
  /// caller having to wire `PlayerProfile.caddieVoiceAccent`.
  Stream<SttEvent> startListening({
    CaddieVoiceAccent accent = CaddieVoiceAccent.american,
  });

  /// Stops the current recognition session early. The stream
  /// returned by `startListening` will receive a final transcript
  /// event with whatever was captured up to that point.
  Future<void> stop();

  /// True between `startListening` and the stream completing.
  bool get isListening;
}
