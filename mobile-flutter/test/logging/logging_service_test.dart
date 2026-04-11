// LoggingService tests for KAN-273 (S3). Covers every behavior the
// AC pinned: 10-event flush threshold, 5-second flush timer,
// 200-entry ring buffer with drop-oldest, telemetryEnabled gate,
// re-queue on send failure, and the canonical event-name constants.
//
// Tests use a `FakeLogSender` so we never touch `dart:io HttpClient`
// — we want to assert against what the sender SAW, not what some
// real HTTP transport did.

import 'package:caddieai/core/logging/log_event.dart';
import 'package:caddieai/core/logging/log_sender.dart';
import 'package:caddieai/core/logging/logging_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLogSender implements LogSender {
  final List<List<LogEntry>> batches = [];
  bool nextResponseSucceeds = true;

  @override
  Future<bool> send({
    required List<LogEntry> entries,
    required String deviceId,
    required String sessionId,
  }) async {
    batches.add(List.of(entries));
    return nextResponseSucceeds;
  }

  int get totalEntries =>
      batches.fold(0, (sum, batch) => sum + batch.length);
}

void main() {
  late FakeLogSender sender;
  late LoggingService service;

  setUp(() {
    sender = FakeLogSender();
    service = LoggingService(
      sender: sender,
      deviceId: 'device-test',
      sessionId: 'session-test',
      enabled: true,
      flushInterval: const Duration(seconds: 5),
      flushThreshold: 10,
      maxBufferSize: 200,
    );
  });

  tearDown(() => service.dispose());

  group('threshold flush', () {
    test('flushes immediately on the 10th event', () async {
      for (var i = 0; i < 9; i++) {
        service.info(LogCategory.general, 'event $i');
      }
      // Below threshold — nothing sent yet.
      expect(sender.batches, isEmpty);

      service.info(LogCategory.general, 'event 9');
      // Let the microtask scheduled by _flushNow drain.
      await Future<void>.delayed(Duration.zero);

      expect(sender.batches, hasLength(1));
      expect(sender.batches.first, hasLength(10));
      expect(service.bufferLengthForTest, 0);
    });

    test('a single event does not trigger a flush', () async {
      service.info(LogCategory.general, 'lonely');
      await Future<void>.delayed(Duration.zero);
      expect(sender.batches, isEmpty);
      expect(service.bufferLengthForTest, 1);
    });
  });

  group('periodic flush', () {
    test('flushes after the configured interval', () async {
      // Use a tight 50 ms interval so the test runs fast without
      // pulling in fake_async. The behavior under test is the
      // periodic-timer codepath, not the exact 5-second spec —
      // a tiny interval exercises the same code.
      final fastService = LoggingService(
        sender: sender,
        deviceId: 'd',
        sessionId: 's',
        enabled: true,
        flushInterval: const Duration(milliseconds: 50),
        flushThreshold: 999, // never auto-flushes by count
        maxBufferSize: 200,
      );
      addTearDown(fastService.dispose);

      fastService.info(LogCategory.general, 'first');
      expect(sender.batches, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(sender.batches, hasLength(1));
      expect(sender.batches.first, hasLength(1));
    });
  });

  group('ring buffer overflow', () {
    test('drops oldest when the buffer hits maxBufferSize', () async {
      // Use a tiny cap so the test runs fast and is obviously
      // exercising the overflow path.
      final smallService = LoggingService(
        sender: sender,
        deviceId: 'd',
        sessionId: 's',
        enabled: true,
        flushInterval: const Duration(hours: 1),
        flushThreshold: 999, // never auto-flushes
        maxBufferSize: 5,
      );
      addTearDown(smallService.dispose);

      for (var i = 0; i < 8; i++) {
        smallService.info(LogCategory.general, 'msg $i');
      }
      expect(smallService.bufferLengthForTest, 5);

      // Manually flush and inspect what survived.
      await smallService.flush();
      expect(sender.batches, hasLength(1));
      final messages = sender.batches.first.map((e) => e.message).toList();
      // Oldest 3 dropped — kept msgs 3..7.
      expect(messages, ['msg 3', 'msg 4', 'msg 5', 'msg 6', 'msg 7']);
    });
  });

  group('re-queue on send failure', () {
    test('failed batch goes back at the head of the buffer', () async {
      sender.nextResponseSucceeds = false;

      service.info(LogCategory.llm, 'first');
      service.info(LogCategory.llm, 'second');

      await service.flush();

      // The send failed, so both entries should be back in the
      // buffer, ready to retry.
      expect(service.bufferLengthForTest, 2);
      expect(sender.batches, hasLength(1));

      // Next flush succeeds and ships them.
      sender.nextResponseSucceeds = true;
      await service.flush();
      expect(sender.batches, hasLength(2));
      expect(sender.batches.last, hasLength(2));
      expect(service.bufferLengthForTest, 0);
    });

    test('re-queue obeys maxBufferSize', () async {
      final tinyService = LoggingService(
        sender: sender,
        deviceId: 'd',
        sessionId: 's',
        enabled: true,
        flushInterval: const Duration(hours: 1),
        flushThreshold: 999,
        maxBufferSize: 3,
      );
      addTearDown(tinyService.dispose);

      sender.nextResponseSucceeds = false;
      tinyService.info(LogCategory.general, 'a');
      tinyService.info(LogCategory.general, 'b');
      tinyService.info(LogCategory.general, 'c');
      await tinyService.flush();

      // Buffer is full of the re-queued entries.
      expect(tinyService.bufferLengthForTest, 3);

      // New entries come in — drop-oldest kicks in.
      tinyService.info(LogCategory.general, 'd');
      tinyService.info(LogCategory.general, 'e');
      expect(tinyService.bufferLengthForTest, 3);

      sender.nextResponseSucceeds = true;
      await tinyService.flush();
      final messages =
          sender.batches.last.map((e) => e.message).toList();
      // 'a' was dropped to make room for 'd'; 'b' was dropped to
      // make room for 'e'.
      expect(messages, ['c', 'd', 'e']);
    });
  });

  group('telemetryEnabled gate', () {
    test('disabled service drops every log call', () async {
      service.setEnabled(false);
      service.info(LogCategory.general, 'should be dropped');
      service.error(LogCategory.llm, 'also dropped');
      await service.flush();
      expect(sender.batches, isEmpty);
      expect(service.bufferLengthForTest, 0);
    });

    test('disabling clears the existing buffer and stops the timer',
        () async {
      service.info(LogCategory.general, 'first');
      expect(service.bufferLengthForTest, 1);
      expect(service.hasFlushTimerForTest, isTrue);

      service.setEnabled(false);
      expect(service.bufferLengthForTest, 0);
      expect(service.hasFlushTimerForTest, isFalse);
    });

    test('re-enabling does not replay dropped events', () async {
      service.setEnabled(false);
      service.info(LogCategory.general, 'lost');
      service.setEnabled(true);
      await service.flush();
      expect(sender.batches, isEmpty);
    });
  });

  group('canonical event names', () {
    test('match the strings the production CloudWatch filters expect', () {
      // These are the exact strings that have CloudWatch metric
      // filters in production. If anyone renames them, the
      // dashboards stop receiving data — fail the build instead.
      expect(LoggingService.events.layerRender, 'layer_render');
      expect(LoggingService.events.llmLatency, 'llm_latency');
      expect(LoggingService.events.sttLatency, 'stt_latency');
      expect(LoggingService.events.ttsLatency, 'tts_latency');
    });
  });

  group('LogEntry.toJson wire format', () {
    test('omits the metadata key when no metadata is set', () {
      const entry = LogEntry(
        level: LogLevel.info,
        category: LogCategory.map,
        message: 'layer_render',
        timestampMs: 1000,
      );
      final json = entry.toJson();
      expect(json['level'], 'info');
      expect(json['category'], 'map');
      expect(json['message'], 'layer_render');
      expect(json['timestampMs'], 1000);
      expect(json.containsKey('metadata'), isFalse);
    });

    test('emits metadata as a flat string-string map', () {
      const entry = LogEntry(
        level: LogLevel.error,
        category: LogCategory.llm,
        message: 'llm_latency',
        timestampMs: 1000,
        metadata: {
          'provider': 'openAI',
          'model': 'gpt-4o',
          'latencyMs': '1234',
        },
      );
      final json = entry.toJson();
      final metadata = json['metadata'] as Map<String, String>;
      expect(metadata['provider'], 'openAI');
      expect(metadata['latencyMs'], '1234');
    });
  });
}
