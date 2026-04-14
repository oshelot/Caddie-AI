// Tests for KAN-278 (S8) TtsLatencyTracker — the small helper
// every TtsService impl uses to log `tts_latency` events with the
// canonical CloudWatch metadata. Splitting it into its own helper
// means tests can exercise it without standing up a real
// `flutter_tts` engine.

import 'package:caddieai/core/logging/log_event.dart';
import 'package:caddieai/core/logging/log_sender.dart';
import 'package:caddieai/core/logging/logging_service.dart';
import 'package:caddieai/core/voice/tts_service.dart';
import 'package:caddieai/core/voice/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  late CapturingLogSender sender;
  late LoggingService logger;

  setUp(() {
    sender = CapturingLogSender();
    logger = LoggingService(
      sender: sender,
      deviceId: 'd',
      sessionId: 's',
      enabled: true,
      flushThreshold: 1,
    );
  });

  tearDown(() => logger.dispose());

  test('logs tts_latency with the canonical metadata fields', () async {
    // Fake clock — first call returns t0, second returns t0 + 250ms.
    final times = <DateTime>[
      DateTime.utc(2026, 4, 11, 12, 0, 0),
      DateTime.utc(2026, 4, 11, 12, 0, 0, 250),
    ];
    var index = 0;
    final tracker = TtsLatencyTracker(
      logger: logger,
      clock: () => times[index++],
    );

    const persona = CaddieVoicePersona(
      gender: CaddieVoiceGender.female,
      accent: CaddieVoiceAccent.scottish,
    );
    tracker.markSpeakRequested('Driver — full swing.', persona);
    tracker.markSpeakStarted();

    // Drain the periodic flush.
    await Future<void>.delayed(Duration.zero);

    expect(sender.sent, hasLength(1));
    final entry = sender.sent.first;
    expect(entry.message, 'tts_start');
    expect(entry.metadata['latency'], '250');
    expect(entry.metadata['textLength'], '20');
    expect(entry.metadata['voiceGender'], 'female');
    expect(entry.metadata['voiceAccent'], 'scottish');
  });

  test('markSpeakStarted is a no-op without a preceding request', () async {
    final tracker = TtsLatencyTracker(logger: logger);
    tracker.markSpeakStarted(); // no markSpeakRequested first
    await Future<void>.delayed(Duration.zero);
    expect(sender.sent, isEmpty);
  });

  test('clears state after logging so the next request is independent',
      () async {
    final times = <DateTime>[
      DateTime.utc(2026, 4, 11, 12, 0, 0),
      DateTime.utc(2026, 4, 11, 12, 0, 0, 100),
      // Second request
      DateTime.utc(2026, 4, 11, 12, 0, 1),
      DateTime.utc(2026, 4, 11, 12, 0, 1, 50),
    ];
    var index = 0;
    final tracker = TtsLatencyTracker(
      logger: logger,
      clock: () => times[index++],
    );

    tracker.markSpeakRequested('first', CaddieVoicePersona.defaultPersona);
    tracker.markSpeakStarted();
    await Future<void>.delayed(Duration.zero);

    // 19 characters: "second one - longer" — uses an ASCII hyphen
    // so the test isn't sensitive to em-dash byte length quirks.
    tracker.markSpeakRequested(
      'second one - longer',
      CaddieVoicePersona.defaultPersona,
    );
    tracker.markSpeakStarted();
    await Future<void>.delayed(Duration.zero);

    expect(sender.sent, hasLength(2));
    expect(sender.sent[0].metadata['latency'], '100');
    expect(sender.sent[0].metadata['textLength'], '5');
    expect(sender.sent[1].metadata['latency'], '50');
    expect(sender.sent[1].metadata['textLength'], '19');
  });
}
