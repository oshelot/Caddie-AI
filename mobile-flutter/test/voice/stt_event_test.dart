// Tests for KAN-278 (S8) SttService event types and the
// StreamController-based fake the caddie screen tests will use
// to drive scripted recognition flows.

import 'package:caddieai/core/voice/stt_service.dart';
import 'package:caddieai/core/voice/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory fake. Tests construct one, call `enqueueEvents` to
/// script a session, then await the stream returned by
/// `startListening`. Mirrors the production `SpeechToTextService`
/// surface so the caddie screen never knows the difference.
class FakeSttService implements SttService {
  bool available = true;
  bool _granted = false;
  bool _isListening = false;

  /// Events the next `startListening` call will emit, in order.
  final List<SttEvent> scripted = [];
  CaddieVoiceAccent? lastAccent;
  int startCallCount = 0;
  int stopCallCount = 0;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<bool> requestPermission() async {
    _granted = true;
    return true;
  }

  @override
  Stream<SttEvent> startListening({
    CaddieVoiceAccent accent = CaddieVoiceAccent.american,
  }) async* {
    startCallCount++;
    lastAccent = accent;
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
      if (event is SttFinalTranscriptEvent || event is SttErrorEvent) {
        break;
      }
    }
    _isListening = false;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    _isListening = false;
  }

  @override
  bool get isListening => _isListening;
}

void main() {
  group('SttEvent type hierarchy', () {
    test('partial event carries the partial transcript text', () {
      const event = SttPartialEvent('one fifty to the pi');
      expect(event.text, 'one fifty to the pi');
      expect(event, isA<SttEvent>());
    });

    test(
        'final transcript event carries text + latency + alternates',
        () {
      const event = SttFinalTranscriptEvent(
        text: 'one fifty to the pin',
        latencyMs: 1240,
        alternatives: ['one fifty to the pen', '150 to the pin'],
      );
      expect(event.text, 'one fifty to the pin');
      expect(event.latencyMs, 1240);
      expect(event.alternatives, hasLength(2));
    });

    test('error event carries a code and a message', () {
      const event = SttErrorEvent(code: 'no_match', message: 'No speech detected');
      expect(event.code, 'no_match');
      expect(event.message, 'No speech detected');
    });
  });

  group('FakeSttService — fixture pattern for caddie screen tests', () {
    late FakeSttService service;

    setUp(() => service = FakeSttService());

    test('returns an error event when permission has not been granted',
        () async {
      // No requestPermission() call yet → first event is the
      // permission_denied error.
      service.scripted.add(const SttListeningEvent());
      service.scripted.add(const SttFinalTranscriptEvent(
        text: 'never reached',
        latencyMs: 0,
      ));

      final events = await service.startListening().toList();
      expect(events, hasLength(1));
      expect(events.first, isA<SttErrorEvent>());
      expect((events.first as SttErrorEvent).code, 'permission_denied');
    });

    test(
        'after permission is granted, emits the scripted event sequence in '
        'order and stops at the final transcript', () async {
      await service.requestPermission();
      service.scripted.addAll([
        const SttListeningEvent(),
        const SttPartialEvent('one'),
        const SttPartialEvent('one fifty'),
        const SttFinalTranscriptEvent(
          text: 'one fifty to the pin',
          latencyMs: 1500,
        ),
        // Anything after the final event is ignored.
        const SttPartialEvent('should never appear'),
      ]);

      final events = await service.startListening().toList();
      expect(events, hasLength(4));
      expect(events[0], isA<SttListeningEvent>());
      expect(events[1], isA<SttPartialEvent>());
      expect(events[2], isA<SttPartialEvent>());
      expect(events[3], isA<SttFinalTranscriptEvent>());
    });

    test('records the requested accent for assertions', () async {
      await service.requestPermission();
      service.scripted.add(const SttFinalTranscriptEvent(
        text: 'aye laddie',
        latencyMs: 0,
      ));
      await service.startListening(accent: CaddieVoiceAccent.scottish).toList();
      expect(service.lastAccent, CaddieVoiceAccent.scottish);
    });

    test('stop() bumps the stop counter', () async {
      await service.stop();
      await service.stop();
      expect(service.stopCallCount, 2);
    });

    test('isAvailable reflects the test-controlled flag', () async {
      service.available = false;
      expect(await service.isAvailable, isFalse);
      service.available = true;
      expect(await service.isAvailable, isTrue);
    });
  });
}
