// HttpTransport — minimal abstraction over `dart:io HttpClient` that
// the course/Golf-API/weather clients use to make HTTP requests.
//
// Why a custom abstraction instead of `package:http`:
//   1. We already use `dart:io HttpClient` in `HttpLogSender` (KAN-273)
//      — keeping the entire stack on one HTTP library reduces the
//      dependency surface.
//   2. The transport interface lets unit tests inject a fake without
//      mocking platform plugins. The fake can pre-canned responses,
//      replay gzip-encoded payloads, and assert on the exact query
//      params each client sends — which the KAN-275 AC requires
//      ("`platform=ios&schema=1.0` MUST be passed on every call").
//   3. `dart:io HttpClient` already handles transparent gzip decoding
//      via `request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip')`.
//      The KAN-252 spike report flagged a "gzip surprise" but the
//      receiving end was the iOS native — Dart's HttpClient handles
//      gzip identically to URLSession and OkHttp, so the symptom
//      doesn't apply to the Flutter port.
//
// **Test pattern:** every test injects a `FakeHttpTransport` (in
// `test/courses/_fake_transport.dart`) that records every request
// and returns scripted responses. Production code uses
// `DartIoHttpTransport` (the impl in this file).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One outbound HTTP response. The body is decoded as UTF-8 string
/// — every endpoint we talk to returns JSON.
class HttpResponseLike {
  const HttpResponseLike({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  bool get isNotFound => statusCode == 404;
}

/// Minimal HTTP request shape. The clients build one of these and
/// hand it to `HttpTransport.send`.
class HttpRequestLike {
  const HttpRequestLike({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
    this.timeout = const Duration(seconds: 15),
  });

  final String method; // 'GET', 'POST', 'PUT'
  final Uri url;
  final Map<String, String> headers;
  final String? body;
  final Duration timeout;
}

abstract class HttpTransport {
  Future<HttpResponseLike> send(HttpRequestLike request);

  /// Streaming variant — returns the raw response body as a
  /// `Stream<String>` of UTF-8 chunks instead of buffering into
  /// a single string. Used by the LLM proxy for token-by-token
  /// SSE streaming. Also returns the status code so the caller
  /// can bail on non-2xx before consuming the stream.
  Future<({int statusCode, Stream<String> body})> sendStreaming(
      HttpRequestLike request) async {
    // Default implementation falls back to buffered send.
    final response = await send(request);
    return (
      statusCode: response.statusCode,
      body: Stream.value(response.body),
    );
  }
}

/// Production HTTP transport. Wraps `dart:io HttpClient` with
/// gzip decoding enabled and a configurable timeout. Re-uses the
/// underlying client across calls so connection pooling kicks in
/// for the chatty cache endpoints.
class DartIoHttpTransport implements HttpTransport {
  DartIoHttpTransport({HttpClient? client})
      : _client = client ?? (HttpClient()..autoUncompress = true);

  final HttpClient _client;

  @override
  Future<HttpResponseLike> send(HttpRequestLike request) async {
    final HttpClientRequest req;
    switch (request.method) {
      case 'GET':
        req = await _client.getUrl(request.url).timeout(request.timeout);
      case 'POST':
        req = await _client.postUrl(request.url).timeout(request.timeout);
      case 'PUT':
        req = await _client.putUrl(request.url).timeout(request.timeout);
      default:
        throw ArgumentError('Unsupported method: ${request.method}');
    }
    request.headers.forEach(req.headers.set);
    // Always advertise gzip — the AcceptEncoding header tells the
    // server it can compress responses. dart:io's HttpClient with
    // `autoUncompress = true` (the default) decodes the response
    // transparently before we read the body.
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
    if (request.body != null) {
      req.add(utf8.encode(request.body!));
    }
    final response = await req.close().timeout(request.timeout);
    final body = await response.transform(utf8.decoder).join();
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    return HttpResponseLike(
      statusCode: response.statusCode,
      body: body,
      headers: headers,
    );
  }

  /// True streaming — returns the response body as a Stream<String>
  /// of raw UTF-8 chunks. Each chunk may contain zero, one, or
  /// multiple SSE event lines. The SSE parser handles reassembly.
  @override
  Future<({int statusCode, Stream<String> body})> sendStreaming(
      HttpRequestLike request) async {
    final req = await _client.postUrl(request.url).timeout(request.timeout);
    request.headers.forEach(req.headers.set);
    if (request.body != null) {
      req.add(utf8.encode(request.body!));
    }
    final response = await req.close().timeout(request.timeout);
    return (
      statusCode: response.statusCode,
      body: response.transform(utf8.decoder),
    );
  }
}
