// FakeHttpTransport — in-memory test double for the
// `HttpTransport` interface from
// `lib/core/courses/http_transport.dart`. Records every outbound
// request so tests can assert on URL, query params, headers, and
// body without touching `dart:io HttpClient`.
//
// **Why this is the only way to test the AC.** KAN-275 AC #1
// requires that `platform=ios&schema=1.0` appears on every
// outbound request. The only way to assert that is to inspect
// the `Uri` the client built BEFORE it hits the wire. Mocking
// `HttpClient` is possible but noisy; a one-method abstraction
// is two dozen lines and far easier to reason about.

import 'package:caddieai/core/courses/http_transport.dart';

class FakeHttpTransport extends HttpTransport {
  /// Every request the client made, in call order. Tests assert
  /// against `[0]`, `[1]`, etc.
  final List<HttpRequestLike> requests = [];

  /// Scripted responses, returned in order. If the test runs out
  /// of scripted responses, returns a default 404 (so an
  /// unexpected extra call is loud).
  final List<HttpResponseLike> responses = [];

  void enqueueJson(String body, {int statusCode = 200}) {
    responses.add(HttpResponseLike(
      statusCode: statusCode,
      body: body,
      headers: const {'content-type': 'application/json'},
    ));
  }

  void enqueueNotFound() {
    responses.add(const HttpResponseLike(
      statusCode: 404,
      body: '',
      headers: {},
    ));
  }

  void enqueueError(int statusCode, [String body = '']) {
    responses.add(HttpResponseLike(
      statusCode: statusCode,
      body: body,
      headers: const {},
    ));
  }

  @override
  Future<HttpResponseLike> send(HttpRequestLike request) async {
    requests.add(request);
    if (responses.isEmpty) {
      return const HttpResponseLike(
        statusCode: 404,
        body: 'no scripted response',
        headers: {},
      );
    }
    return responses.removeAt(0);
  }

  void reset() {
    requests.clear();
    responses.clear();
  }
}
