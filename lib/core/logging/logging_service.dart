// LoggingService — KAN-273 (S3) Flutter port of the iOS
// `LoggingService` and Android `DiagnosticLogger`. Batches structured
// log entries and ships them to the CloudWatch-backed endpoint
// (`prod/logs`) used by the existing native apps.
//
// **Behavior contract** (from KAN-273 ACs):
//
// 1. **Batched flush**: every 10 events OR every 5 seconds,
//    whichever comes first. The numbers are in `_flushThreshold`
//    and `_flushInterval` below — they intentionally diverge from
//    the native (50 / 30s) because the AC pinned them tighter for
//    the Flutter port. The receiver Lambda has no per-batch
//    rate limit, so the smaller batches are fine.
// 2. **Offline queue**: up to 200 entries buffered in memory; when
//    the buffer overflows, drop the oldest. This matches the
//    Android `DiagnosticLogger` ring buffer (`RING_BUFFER_MAX = 200`).
//    On a flush failure, the failed batch is re-queued at the head
//    of the buffer (newest = first to retry).
// 3. **Telemetry opt-out**: `setEnabled(false)` short-circuits
//    every `log()` call. Wired by the Profile screen (KAN-S13)
//    when `PlayerProfile.telemetryEnabled` flips. Until that screen
//    lands, the gate is on by default in release builds; in debug
//    builds, the service is disabled by default to keep dev noise
//    out of the production CloudWatch stream.
// 4. **Event name parity**: feature code uses `info('event_name', …)`
//    where the event name is part of the log message string. The
//    canonical names that have CloudWatch metric filters built
//    against them — `layer_render`, `llm_latency`, `stt_latency`,
//    `tts_latency` — are exposed as constants in
//    `LoggingService.events` so feature code references them
//    instead of typing string literals.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'log_event.dart';
import 'log_sender.dart';

class LoggingService {
  /// Production constructor. Wired in `main.dart` from the
  /// `--dart-define`d endpoint and API key. The `enabled` default
  /// follows the build mode: enabled in release, disabled in debug
  /// (so local dev runs don't pollute the CloudWatch dashboards).
  /// The Profile screen (KAN-S13) flips this to match
  /// `PlayerProfile.telemetryEnabled` once the user opens the app.
  LoggingService({
    required LogSender sender,
    required this.deviceId,
    required this.sessionId,
    bool? enabled,
    DateTime Function()? clock,
    Duration flushInterval = const Duration(seconds: 5),
    int flushThreshold = 10,
    int maxBufferSize = 200,
  })  : _sender = sender,
        _enabled = enabled ?? !kDebugMode,
        _clock = clock ?? DateTime.now,
        _flushInterval = flushInterval,
        _flushThreshold = flushThreshold,
        _maxBufferSize = maxBufferSize;

  final LogSender _sender;
  final String deviceId;
  final String sessionId;

  bool _enabled;
  final DateTime Function() _clock;
  final Duration _flushInterval;
  final int _flushThreshold;
  final int _maxBufferSize;

  // The in-memory ring buffer. `Queue` gives us O(1) addLast +
  // removeFirst, which is what the drop-oldest-on-overflow path
  // needs. Wrapped in a synchronous critical section because
  // `log()` may be called from any isolate-zone callback.
  final Queue<LogEntry> _buffer = Queue<LogEntry>();

  Timer? _flushTimer;

  /// Canonical event name constants. These are the strings that
  /// have CloudWatch metric filters and dashboards built against
  /// them in production today. Feature code MUST use these
  /// constants rather than retyping the strings — a typo silently
  /// breaks the dashboards.
  static const events = _CanonicalEvents();

  bool get isEnabled => _enabled;

  @visibleForTesting
  int get bufferLengthForTest => _buffer.length;

  @visibleForTesting
  bool get hasFlushTimerForTest => _flushTimer?.isActive ?? false;

  /// Toggle the entire logging pipeline on or off. When disabled,
  /// the buffer is cleared and the periodic flush timer is stopped.
  /// Re-enabling does NOT replay anything that was dropped.
  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      _buffer.clear();
      _flushTimer?.cancel();
      _flushTimer = null;
    }
  }

  // ── Public log API ───────────────────────────────────────────────

  void info(
    LogCategory category,
    String message, {
    Map<String, String> metadata = const {},
  }) =>
      _enqueue(LogLevel.info, category, message, metadata);

  void warning(
    LogCategory category,
    String message, {
    Map<String, String> metadata = const {},
  }) =>
      _enqueue(LogLevel.warning, category, message, metadata);

  void error(
    LogCategory category,
    String message, {
    Map<String, String> metadata = const {},
  }) =>
      _enqueue(LogLevel.error, category, message, metadata);

  void _enqueue(
    LogLevel level,
    LogCategory category,
    String message,
    Map<String, String> metadata,
  ) {
    if (!_enabled) return;

    final entry = LogEntry(
      level: level,
      category: category,
      message: message,
      timestampMs: _clock().millisecondsSinceEpoch,
      metadata: metadata,
    );

    if (_buffer.length >= _maxBufferSize) {
      // Drop oldest. Logging is best-effort — losing the head of
      // the queue is preferable to dropping fresh entries that may
      // contain the actual signal.
      _buffer.removeFirst();
    }
    _buffer.addLast(entry);

    // Lazy-start the periodic flush timer on the first event so
    // the service has zero overhead when nothing is being logged.
    _flushTimer ??= Timer.periodic(_flushInterval, (_) => _flushNow());

    if (_buffer.length >= _flushThreshold) {
      // Don't await — `_enqueue` is fire-and-forget for callers.
      _flushNow();
    }
  }

  // ── Flush ─────────────────────────────────────────────────────────

  /// Public flush for app-lifecycle hooks (background, terminate).
  /// Returns true on a successful round-trip OR an empty buffer.
  Future<bool> flush() => _flushNow();

  Future<bool> _flushNow() async {
    if (_buffer.isEmpty) return true;

    final batch = List<LogEntry>.unmodifiable(_buffer);
    _buffer.clear();

    bool ok;
    try {
      ok = await _sender.send(
        entries: batch,
        deviceId: deviceId,
        sessionId: sessionId,
      );
    } catch (_) {
      ok = false;
    }

    if (!ok) {
      // Recoverable failure. Re-queue at the head, then trim if
      // we'd overflow (the buffer may have grown during the in-
      // flight send). Drop-oldest applies during the trim — the
      // re-queued entries are at the head, so the oldest queued
      // entries (the ones that timed out) are the first to go.
      for (final entry in batch.reversed) {
        _buffer.addFirst(entry);
      }
      while (_buffer.length > _maxBufferSize) {
        _buffer.removeFirst();
      }
    }
    return ok;
  }

  /// Cancels the periodic flush timer. Tests should call this in
  /// `tearDown` to avoid leaking timers across cases.
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}

class _CanonicalEvents {
  const _CanonicalEvents();

  /// Course-map layer render latency event. Emitted by the map
  /// screen (KAN-S10) once per style-load. Metadata: `latencyMs`,
  /// `holeCount`. Has a CloudWatch metric filter `MapLayerRenderMs`.
  String get layerRender => 'layer_render';

  /// Emitted by the map screen (KAN-S10) when `verifyLayersPresent`
  /// reports a layer missing immediately after `tryAddLayer`. Means
  /// `addLayer` returned ok but the layer never made it into the
  /// rendered style — see SPIKE_REPORT §4 Bug 2/3 and ADR / CONVENTIONS
  /// C-2. Metadata: `layerId`. Critical signal for the iOS-side
  /// upstream regressions tracked at mapbox/mapbox-maps-flutter#1121
  /// and #1122.
  String get layerAddFailure => 'layer_add_failure';

  /// Emitted by the map screen (KAN-S10) when a layer that PASSED the
  /// initial post-add audit is later found missing on the first hole-
  /// tap interaction (the Bug 2/3 mutated symptom on
  /// mapbox_maps_flutter 2.21.1 — the audit reports the layer present,
  /// then it disappears from the rendered style milliseconds later).
  /// Metadata: `layerId`. Distinct from `layer_add_failure` so the
  /// CloudWatch dashboard can graph the two failure modes separately.
  String get layerDropPostAudit => 'layer_drop_post_audit';

  /// LLM round-trip latency. Emitted by the LLM router (KAN-S7)
  /// for every completed request. Metadata: `provider`, `model`,
  /// `tier`, `latencyMs`, `tokensIn`, `tokensOut`. CloudWatch
  /// filter: `LlmLatencyMs`.
  String get llmLatency => 'llm_latency';

  /// Speech-to-text completion from start of utterance to final
  /// transcript. Emitted by the STT service (KAN-S8). Metadata:
  /// `latency`, `wordCount`. Filter: `SttLatencyMs`.
  String get sttComplete => 'stt_complete';

  /// Legacy alias — kept so any feature code referencing the old
  /// name still compiles. Prefer `sttComplete`.
  String get sttLatency => 'stt_complete';

  /// Text-to-speech start event from request to first audio frame.
  /// Emitted by the TTS service (KAN-S8). Metadata: `latency`,
  /// `textLength`, `voiceGender`, `voiceAccent`. Filter: `TtsLatencyMs`.
  String get ttsStart => 'tts_start';

  /// Legacy alias — kept so any feature code referencing the old
  /// name still compiles. Prefer `ttsStart`.
  String get ttsLatency => 'tts_start';

  /// Course search latency from typing-stop (debounce fire) to
  /// the search-result list rendering. Emitted by the course
  /// search screen (KAN-S9). Metadata: `latencyMs`, `query`,
  /// `resultCount`, `hasLocation`. CloudWatch filter:
  /// `CourseSearchLatencyMs`. Used to verify the AC's "results
  /// within 1 s of typing stop" target.
  String get searchLatency => 'log_search_latency';
}
