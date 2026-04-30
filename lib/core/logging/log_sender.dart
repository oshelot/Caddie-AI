// LogSender — abstraction over the HTTP transport that ships
// `LogEntry` batches to the CloudWatch logging endpoint. Lifted out
// of `LoggingService` so unit tests can inject a fake without
// touching `dart:io`'s `HttpClient`, and so a future story could
// swap in a different transport (e.g. a buffered file writer for
// offline-first replay) without rewriting the service.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'log_event.dart';

/// One side-effect-free request to send a batch of log entries.
/// Returns true on success, false on a recoverable failure (the
/// service will re-queue). Exceptions thrown from `send` are
/// caught upstream and treated as a recoverable failure.
abstract class LogSender {
  Future<bool> send({
    required List<LogEntry> entries,
    required String deviceId,
    required String sessionId,
  });
}

/// Production sender — POSTs JSON to the CloudWatch endpoint.
/// Endpoint and API key are read from `--dart-define`s at build
/// time. If either is missing, [send] returns false (and the
/// service no-ops the entire pipeline — see
/// `LoggingService.isEnabled`).
class HttpLogSender implements LogSender {
  HttpLogSender({
    required this.endpoint,
    required this.apiKey,
    required this.platform,
    required this.appVersion,
    required this.buildNumber,
    required this.osVersion,
    required this.deviceModel,
    HttpClient? httpClient,
    Duration timeout = const Duration(seconds: 15),
  })  : _httpClient = httpClient ?? HttpClient(),
        _timeout = timeout;

  /// Read from `--dart-define=LOGGING_ENDPOINT=https://...`.
  final String endpoint;

  /// Read from `--dart-define=LOGGING_API_KEY=...`. Sent as the
  /// `x-api-key` header (matches the iOS native client).
  final String apiKey;

  final String platform;
  final String appVersion;
  final String buildNumber;
  final String osVersion;
  final String deviceModel;

  final HttpClient _httpClient;
  final Duration _timeout;

  @override
  Future<bool> send({
    required List<LogEntry> entries,
    required String deviceId,
    required String sessionId,
  }) async {
    if (endpoint.isEmpty || apiKey.isEmpty) return false;

    final payload = <String, dynamic>{
      'deviceId': deviceId,
      'platform': platform,
      'sessionId': sessionId,
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'osVersion': osVersion,
      'deviceModel': deviceModel,
      'entries': entries.map((e) => e.toJson()).toList(),
    };

    try {
      final uri = Uri.parse(endpoint);
      final request = await _httpClient.postUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set('x-api-key', apiKey);
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(_timeout);
      // Drain the body so the connection returns to the pool.
      await response.drain<void>();
      // 2xx → success. 5xx → recoverable. 4xx → drop (the entries
      // would never succeed on retry, so don't re-queue).
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      if (response.statusCode >= 500) {
        return false;
      }
      // 4xx — caller should treat as "do not re-queue". We model
      // this as success-from-the-queue's-perspective: the entries
      // are gone for good, no point in retrying. Returning true
      // achieves that without an extra signaling channel.
      return true;
    } catch (_) {
      // Timeout, DNS failure, socket error → recoverable.
      return false;
    }
  }
}
