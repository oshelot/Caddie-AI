// FlutterTtsService — production `TtsService` impl that delegates
// to the `flutter_tts` plugin. Wraps both the iOS and Android
// platform engines (AVSpeechSynthesizer / android.speech.tts.TextToSpeech)
// behind one Dart API.
//
// **Why a separate file from `tts_service.dart`:** the abstract
// interface stays free of platform-plugin imports, so unit tests
// can stub it without dragging `flutter_tts` into the test runner.
// Anything that touches `FlutterTts` lives only in this file.

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../logging/logging_service.dart';
import 'tts_service.dart';
import 'voice_settings.dart';

class FlutterTtsService implements TtsService {
  FlutterTtsService({
    required LoggingService logger,
    FlutterTts? tts,
    DateTime Function()? clock,
  })  : _tts = tts ?? FlutterTts(),
        _latency = TtsLatencyTracker(logger: logger, clock: clock);

  final FlutterTts _tts;
  final TtsLatencyTracker _latency;

  bool _initialized = false;
  bool _isSpeaking = false;
  final StreamController<bool> _speakingController =
      StreamController<bool>.broadcast();

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Stream<bool> get isSpeakingStream => _speakingController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Wire the start / completion / error callbacks. flutter_tts
    // exposes these as setter-style hooks; the plugin invokes
    // them on the main isolate.
    _tts.setStartHandler(() {
      _latency.markSpeakStarted();
      _setSpeaking(true);
    });
    _tts.setCompletionHandler(() => _setSpeaking(false));
    _tts.setCancelHandler(() => _setSpeaking(false));
    _tts.setErrorHandler((dynamic _) => _setSpeaking(false));

    // Speech rate: lifted from the Android native (0.95). iOS
    // native uses 0.5 — but iOS's flutter_tts speech-rate scale
    // is normalized to [0, 1] across both platforms by the
    // plugin, so 0.5 here means "platform default rate" which
    // matches both natives' intent ("slightly slower for
    // clarity").
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  @override
  Future<void> speak(
    String text, {
    required CaddieVoicePersona persona,
  }) async {
    if (!_initialized) await initialize();

    // Cancel any in-progress utterance — matches the iOS
    // `stopSpeaking(at: .immediate)` and Android `QUEUE_FLUSH`.
    await _tts.stop();

    // Apply the persona BEFORE the speak call. flutter_tts
    // requires language + pitch to be set on the engine itself,
    // not on a per-utterance basis.
    await _tts.setLanguage(persona.accent.languageCode);
    await _tts.setPitch(persona.gender.pitch);

    _latency.markSpeakRequested(text, persona);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _setSpeaking(false);
  }

  @override
  Future<void> dispose() async {
    await _tts.stop();
    await _speakingController.close();
  }

  void _setSpeaking(bool value) {
    if (_isSpeaking == value) return;
    _isSpeaking = value;
    _speakingController.add(value);
  }
}
