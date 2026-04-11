// SpeechToTextService — production `SttService` impl backed by
// the `speech_to_text` plugin. Wraps SFSpeechRecognizer (iOS) and
// the SpeechRecognizer system service (Android) behind one Dart
// API.
//
// **Why a separate file from `stt_service.dart`:** keeps the
// abstract interface free of platform-plugin imports so unit
// tests can stub it without dragging the plugin into the test
// runner.

import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../logging/log_event.dart';
import '../logging/logging_service.dart';
import 'stt_service.dart';
import 'voice_settings.dart';

class SpeechToTextService implements SttService {
  SpeechToTextService({
    required LoggingService logger,
    stt.SpeechToText? speech,
    DateTime Function()? clock,
  })  : _logger = logger,
        _speech = speech ?? stt.SpeechToText(),
        _clock = clock ?? DateTime.now;

  final LoggingService _logger;
  final stt.SpeechToText _speech;
  final DateTime Function() _clock;

  bool _initialized = false;
  bool _isListening = false;
  StreamController<SttEvent>? _eventController;
  DateTime? _listenStartedAt;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> get isAvailable async {
    if (!_initialized) {
      await _initialize();
    }
    return _speech.isAvailable;
  }

  @override
  Future<bool> requestPermission() async {
    final mic = await Permission.microphone.request();
    if (mic.isPermanentlyDenied || mic.isDenied) return false;

    // On iOS the speech-to-text plugin also wants the speech
    // recognizer authorization, which it requests internally
    // during initialize(). The mic permission is the gating
    // one we surface to the caller.
    if (!_initialized) {
      await _initialize();
    }
    return _speech.isAvailable;
  }

  @override
  Stream<SttEvent> startListening({
    CaddieVoiceAccent accent = CaddieVoiceAccent.american,
  }) {
    // Tear down any previous session before starting a new one.
    _eventController?.close();
    final controller = StreamController<SttEvent>();
    _eventController = controller;

    () async {
      if (!_initialized) await _initialize();
      if (!_speech.isAvailable) {
        controller.add(const SttErrorEvent(
          code: 'unavailable',
          message: 'Speech recognition not available on this device',
        ));
        await controller.close();
        return;
      }

      _isListening = true;
      _listenStartedAt = _clock();
      controller.add(const SttListeningEvent());

      try {
        await _speech.listen(
          localeId: accent.languageCode,
          listenOptions: stt.SpeechListenOptions(
            partialResults: true,
            cancelOnError: true,
            // The plugin's default listen-mode is "dictation"
            // which keeps the recognizer open until the user
            // stops speaking — that's what the caddie screen
            // wants.
          ),
          onResult: (SpeechRecognitionResult result) {
            if (controller.isClosed) return;
            if (result.finalResult) {
              final latencyMs = _listenStartedAt == null
                  ? 0
                  : _clock().millisecondsSinceEpoch -
                      _listenStartedAt!.millisecondsSinceEpoch;
              _logSttLatency(
                latencyMs: latencyMs,
                wordCount: result.recognizedWords.split(' ').length,
              );
              controller.add(SttFinalTranscriptEvent(
                text: result.recognizedWords,
                latencyMs: latencyMs,
                alternatives: result.alternates
                    .skip(1) // first alt = the same as the top result
                    .map((a) => a.recognizedWords)
                    .toList(growable: false),
              ));
              _finishSession(controller);
            } else {
              controller.add(SttPartialEvent(result.recognizedWords));
            }
          },
        );
      } catch (e) {
        controller.add(SttErrorEvent(code: 'exception', message: '$e'));
        _finishSession(controller);
      }
    }();

    return controller.stream;
  }

  @override
  Future<void> stop() async {
    if (!_isListening) return;
    await _speech.stop();
    final controller = _eventController;
    if (controller != null) {
      _finishSession(controller);
    }
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _speech.initialize(
      onStatus: (String status) {
        // The plugin's status callback fires for "listening" /
        // "notListening" / "done". We don't relay these into the
        // event stream — the per-result callback is the source
        // of truth for transcription state.
      },
      onError: (SpeechRecognitionError error) {
        final controller = _eventController;
        if (controller == null || controller.isClosed) return;
        controller.add(SttErrorEvent(
          code: error.errorMsg,
          message: error.permanent
              ? 'Permanent error: ${error.errorMsg}'
              : error.errorMsg,
        ));
        _finishSession(controller);
      },
    );
  }

  void _finishSession(StreamController<SttEvent> controller) {
    _isListening = false;
    _listenStartedAt = null;
    if (!controller.isClosed) {
      controller.close();
    }
  }

  void _logSttLatency({required int latencyMs, required int wordCount}) {
    _logger.info(
      LogCategory.llm,
      LoggingService.events.sttLatency,
      metadata: {
        'latencyMs': '$latencyMs',
        'wordCount': '$wordCount',
      },
    );
  }
}
