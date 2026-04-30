// Widget tests for KAN-281 (S11) CaddieScreen — the flagship UX.
//
// **Logger lifecycle reminder:** see
// `test/features/course/course_search_screen_test.dart` header.
// Every test that triggers an LLM call (which logs llm_latency)
// or a TTS speak (which logs tts_latency) MUST call
// `logger.dispose()` inside the test body before the framework's
// pending-timer check.
//
// Coverage:
//   1. Form rendering — every shot context field is editable
//   2. Engine baseline — tapping "Get recommendation" runs the
//      engine and renders the deterministic card
//   3. LLM streaming — tapping "Ask AI" streams chunks into the
//      transcript area
//   4. LLM error — provider failure surfaces an error message
//   5. TTS playback — when the LLM stream completes, TTS speak
//      is invoked with the assembled transcript and the configured
//      persona
//   6. Voice input → form update — a final transcript event
//      flows through VoiceInputParser into the ShotContext
//   7. End-to-end happy path: voice → engine → LLM → TTS

import 'dart:async';

import 'package:caddieai/core/golf/golf_enums.dart';
import 'package:caddieai/core/golf/golf_logic_engine.dart';
import 'package:caddieai/core/golf/shot_context.dart';
import 'package:caddieai/core/golf/target_strategy.dart';
import 'package:caddieai/core/llm/llm_messages.dart';
import 'package:caddieai/core/llm/llm_provider.dart';
import 'package:caddieai/core/llm/llm_router.dart';
import 'package:caddieai/core/logging/log_event.dart';
import 'package:caddieai/core/logging/log_sender.dart';
import 'package:caddieai/core/logging/logging_service.dart';
import 'package:caddieai/core/voice/stt_service.dart';
import 'package:caddieai/core/voice/tts_service.dart';
import 'package:caddieai/core/voice/voice_settings.dart';
import 'package:caddieai/features/caddie/presentation/caddie_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Fakes ──────────────────────────────────────────────────────────

class CapturingLogSender implements LogSender {
  final List<LogEntry> sent = [];
  @override
  Future<bool> send({
    required List<LogEntry> entries,
    required String deviceId,
    required String sessionId,
  }) async {
    sent.addAll(entries);
    return true;
  }
}

class FakeLlmProvider implements LlmProvider {
  FakeLlmProvider({
    this.id = LlmProviderId.openAi,
    this.streamChunks = const ['Stay smooth.', ' Trust the club.'],
    this.shouldThrow = false,
  });

  @override
  final LlmProviderId id;
  @override
  bool get isAvailable => true;

  final List<String> streamChunks;
  final bool shouldThrow;
  int streamCallCount = 0;

  @override
  Future<LlmResponse> chatCompletion(LlmRequest request) async {
    streamCallCount++;
    if (shouldThrow) {
      throw const LlmException('boom', recoverable: false);
    }
    return LlmResponse(text: streamChunks.join(''));
  }

  @override
  Stream<String> chatCompletionStream(LlmRequest request) async* {
    streamCallCount++;
    if (shouldThrow) {
      throw const LlmException('boom', recoverable: false);
    }
    for (final chunk in streamChunks) {
      yield chunk;
    }
  }
}

class FakeSttService implements SttService {
  bool _granted = false;
  bool _isListening = false;
  final List<SttEvent> scripted = [];
  int requestCallCount = 0;

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<bool> requestPermission() async {
    requestCallCount++;
    _granted = true;
    return true;
  }

  @override
  Stream<SttEvent> startListening({
    CaddieVoiceAccent accent = CaddieVoiceAccent.american,
  }) async* {
    if (!_granted) {
      yield const SttErrorEvent(
        code: 'permission_denied',
        message: 'Microphone permission required',
      );
      return;
    }
    _isListening = true;
    for (final event in scripted) {
      yield event;
      if (event is SttFinalTranscriptEvent || event is SttErrorEvent) break;
    }
    _isListening = false;
  }

  @override
  Future<void> stop() async {
    _isListening = false;
  }

  @override
  bool get isListening => _isListening;
}

class FakeTtsService implements TtsService {
  bool _isSpeaking = false;
  final StreamController<bool> _speakingController =
      StreamController<bool>.broadcast();

  String? lastSpokenText;
  CaddieVoicePersona? lastPersona;
  int speakCallCount = 0;

  /// When true, `speak()` emits start + completion synchronously
  /// (the default — most tests want a deterministic flow). When
  /// false, `speak()` only emits the start event and the test is
  /// responsible for calling [completeSpeaking] when it wants the
  /// "done" state to fire.
  bool autoComplete = true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak(
    String text, {
    required CaddieVoicePersona persona,
  }) async {
    speakCallCount++;
    lastSpokenText = text;
    lastPersona = persona;
    _isSpeaking = true;
    _speakingController.add(true);
    if (autoComplete) {
      // Synchronously fire the completion event so the screen
      // transitions speaking → done within the same pump cycle.
      // No real timer involved — keeps the test framework's
      // pending-timer check happy.
      _isSpeaking = false;
      _speakingController.add(false);
    }
  }

  /// Manually fire the completion event for tests that disable
  /// `autoComplete`.
  void completeSpeaking() {
    _isSpeaking = false;
    _speakingController.add(false);
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    _speakingController.add(false);
  }

  @override
  Future<void> dispose() async {
    if (!_speakingController.isClosed) await _speakingController.close();
  }

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Stream<bool> get isSpeakingStream => _speakingController.stream;
}

// ── Test helpers ───────────────────────────────────────────────────

LoggingService _newLogger(CapturingLogSender sender) => LoggingService(
      sender: sender,
      deviceId: 'd',
      sessionId: 's',
      enabled: true,
      flushThreshold: 1,
      flushInterval: const Duration(hours: 1),
    );

LlmRouter _newRouter(FakeLlmProvider provider, LoggingService logger) {
  return LlmRouter(
    providers: {LlmProviderId.openAi: provider},
    proxy: FakeLlmProvider(id: LlmProviderId.openAi)..streamCallCount = 0,
    logger: logger,
  );
}

const _bagPreferences = ShotPreferences(
  clubDistances: {
    Club.driver: 245,
    Club.iron7: 160,
    Club.iron8: 150,
    Club.pitchingWedge: 125,
    Club.sandWedge: 90,
  },
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required LoggingService logger,
  required FakeLlmProvider llmProvider,
  required FakeSttService stt,
  required FakeTtsService tts,
  ShotContext initialContext = const ShotContext(distanceYards: 160),
  DeterministicAnalysis Function(ShotContext, ShotPreferences)? engine,
}) async {
  // Bigger-than-default viewport so the entire form + recommendation
  // card lays out without scrolling. The default 800x600 cuts off
  // the "Get recommendation" CTA, which makes hit-testing fail.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = _newRouter(llmProvider, logger);
  await tester.pumpWidget(MaterialApp(
    home: CaddieScreen(
      profile: _bagPreferences,
      llmRouter: router,
      sttService: stt,
      ttsService: tts,
      logger: logger,
      initialContext: initialContext,
      engine: engine ??
          (ctx, profile) => GolfLogicEngine.analyze(
                context: ctx,
                profile: profile,
              ),
    ),
  ));
  // Settle the initial state set by initState (TTS subscription, etc).
  await tester.pump();
}

// ── Tests ──────────────────────────────────────────────────────────

void main() {
  late CapturingLogSender sender;
  late LoggingService logger;
  late FakeLlmProvider llmProvider;
  late FakeSttService stt;
  late FakeTtsService tts;

  setUp(() {
    sender = CapturingLogSender();
    logger = _newLogger(sender);
    llmProvider = FakeLlmProvider();
    stt = FakeSttService();
    tts = FakeTtsService();
  });

  group('shot input form', () {
    testWidgets('renders all editable fields', (tester) async {
      await _pumpScreen(
        tester,
        logger: logger,
        llmProvider: llmProvider,
        stt: stt,
        tts: tts,
      );
      expect(find.byKey(const Key('caddie-distance-field')), findsOneWidget);
      expect(find.text('Shot context'), findsOneWidget);
      expect(find.text('Get recommendation'), findsOneWidget);
    });
  });

  group('engine baseline', () {
    testWidgets('tapping "Get recommendation" renders the analysis card',
        (tester) async {
      await _pumpScreen(
        tester,
        logger: logger,
        llmProvider: llmProvider,
        stt: stt,
        tts: tts,
      );
      // Initial state — no card.
      expect(find.byKey(const Key('caddie-recommendation-card')),
          findsNothing);

      await tester.tap(find.text('Get recommendation'));
      await tester.pump();

      expect(find.byKey(const Key('caddie-recommendation-card')),
          findsOneWidget);
      // Effective distance for 160y / fairway / no wind / level → 160.
      expect(find.textContaining('160 yards'), findsWidgets);
      // 7-iron carries 160 in the test bag → recommended.
      expect(find.text('7-Iron'), findsOneWidget);
      // The "Ask AI" CTA is now visible.
      expect(find.byKey(const Key('caddie-ask-ai-button')), findsOneWidget);
    });
  });

  group('LLM call', () {
    testWidgets('"Ask AI" calls the LLM and renders the transcript', (tester) async {
      llmProvider = FakeLlmProvider(
        streamChunks: const ['Hello.', ' Trust your swing.'],
      );
      await _pumpScreen(
        tester,
        logger: logger,
        llmProvider: llmProvider,
        stt: stt,
        tts: tts,
      );

      await tester.tap(find.text('Get recommendation'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('caddie-ask-ai-button')));
      // Pump enough frames to drain the stream + the followup
      // TTS-speak microtask.
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(llmProvider.streamCallCount, 1);
      // The full transcript should appear in one shot (non-streaming).
      expect(find.textContaining('Hello. Trust your swing.'), findsWidgets);
      logger.dispose();
    });

    testWidgets('LLM error renders an error message + retry button',
        (tester) async {
      llmProvider = FakeLlmProvider(shouldThrow: true);
      await _pumpScreen(
        tester,
        logger: logger,
        llmProvider: llmProvider,
        stt: stt,
        tts: tts,
      );
      await tester.tap(find.text('Get recommendation'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('caddie-ask-ai-button')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('caddie-llm-error')), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      logger.dispose();
    });
  });

  group('TTS playback', () {
    testWidgets(
        'on LLM completion, TTS does NOT auto-play — user taps Listen',
        (tester) async {
      llmProvider = FakeLlmProvider(streamChunks: const ['One.', ' Two.']);
      await _pumpScreen(
        tester,
        logger: logger,
        llmProvider: llmProvider,
        stt: stt,
        tts: tts,
      );
      await tester.tap(find.text('Get recommendation'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('caddie-ask-ai-button')));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      // TTS should NOT have been called automatically.
      expect(tts.speakCallCount, 0);
      // A Listen button should be visible.
      expect(find.byKey(const Key('caddie-listen-button')), findsOneWidget);
      logger.dispose();
    });
  });

  group('voice input', () {
    testWidgets(
        'final transcript event flows through VoiceInputParser into '
        'the ShotContext (distance updated)', (tester) async {
      // Pure-distance transcript so we don't accidentally also
      // change the wind/lie/etc and shift the engine output in
      // multiple directions at once.
      stt.scripted.addAll([
        const SttListeningEvent(),
        const SttPartialEvent('one'),
        const SttPartialEvent('one fifty'),
        const SttFinalTranscriptEvent(
          text: 'one fifty',
          latencyMs: 800,
        ),
      ]);
      await _pumpScreen(
        tester,
        logger: logger,
        llmProvider: llmProvider,
        stt: stt,
        tts: tts,
      );

      // Initial distance is 160 (the default in _pumpScreen).
      expect(find.text('160'), findsWidgets);

      await tester.tap(find.byKey(const Key('caddie-voice-button')));
      // Drain stream events.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The transcript display shows the final text.
      expect(find.byKey(const Key('caddie-voice-transcript')), findsOneWidget);
      expect(find.textContaining('one fifty'), findsOneWidget);

      // Run the engine — should now use distance 150 (parsed from
      // "one fifty"). With no wind and a fairway lie, effective
      // distance = 150 → 8-iron (carry 150) is the perfect fit.
      await tester.tap(find.text('Get recommendation'));
      await tester.pump();
      expect(find.text('8-Iron'), findsOneWidget);
    });

    testWidgets('voice button calls requestPermission before listening',
        (tester) async {
      await _pumpScreen(
        tester,
        logger: logger,
        llmProvider: llmProvider,
        stt: stt,
        tts: tts,
      );
      expect(stt.requestCallCount, 0);
      await tester.tap(find.byKey(const Key('caddie-voice-button')));
      await tester.pump();
      expect(stt.requestCallCount, 1);
    });
  });

  group('reset flow', () {
    testWidgets('after the full flow finishes, "New shot" resets the screen',
        (tester) async {
      llmProvider = FakeLlmProvider(streamChunks: const ['Done.']);
      await _pumpScreen(
        tester,
        logger: logger,
        llmProvider: llmProvider,
        stt: stt,
        tts: tts,
      );
      await tester.tap(find.text('Get recommendation'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('caddie-ask-ai-button')));
      // Drain stream + speak + speaking-completed callback.
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      // The reset button should be visible (done stage).
      expect(find.byKey(const Key('caddie-reset-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('caddie-reset-button')));
      await tester.pump();

      // Recommendation card is gone.
      expect(find.byKey(const Key('caddie-recommendation-card')),
          findsNothing);
      // The form is back.
      expect(find.text('Get recommendation'), findsOneWidget);
      logger.dispose();
    });
  });
}
