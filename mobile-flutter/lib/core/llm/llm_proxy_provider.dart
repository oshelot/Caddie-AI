// LlmProxyProvider — KAN-294 (S7.3) port of the iOS
// `LLMProxyService.swift`. Sends chat-completion requests through
// the existing CaddieAI Lambda proxy, which:
//
//   - injects the server-side OpenAI API key (so paid-tier users
//     don't need their own key)
//   - forces `gpt-4o-mini` as the model regardless of what the
//     caller specified
//   - speaks the OpenAI Chat Completions wire format on the
//     request side AND on the response side, with optional
//     SSE streaming when the request body has `"stream": true`
//
// **Auth:** `x-api-key` header, sourced from a `--dart-define`
// at build time (`LLM_PROXY_API_KEY`). The endpoint URL also comes
// from a `--dart-define` (`LLM_PROXY_ENDPOINT`). If either is
// missing, `isAvailable` returns false and the router skips the
// proxy provider.

import 'dart:async';
import 'dart:convert';

import '../courses/http_transport.dart';
import 'llm_messages.dart';
import 'llm_provider.dart';
import 'sse_parser.dart';

class LlmProxyProvider implements LlmProvider {
  LlmProxyProvider({
    required this.endpoint,
    required this.apiKey,
    required this.transport,
    Duration timeout = const Duration(seconds: 60),
  }) : _timeout = timeout;

  final String endpoint;
  final String apiKey;
  final HttpTransport transport;
  final Duration _timeout;

  @override
  LlmProviderId get id => LlmProviderId.openAi;

  @override
  bool get isAvailable => endpoint.isNotEmpty && apiKey.isNotEmpty;

  @override
  Future<LlmResponse> chatCompletion(LlmRequest request) async {
    if (!isAvailable) {
      throw const LlmException(
        'LLM proxy not configured',
        recoverable: false,
      );
    }
    final body = jsonEncode(request.toOpenAiJson());
    final response = await transport.send(HttpRequestLike(
      method: 'POST',
      url: Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
      },
      body: body,
      timeout: _timeout,
    ));
    if (!response.isSuccess) {
      throw LlmException(
        'Proxy returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        recoverable: response.statusCode >= 500,
      );
    }
    return _parseOpenAiResponse(response.body);
  }

  @override
  Stream<String> chatCompletionStream(LlmRequest request) async* {
    if (!isAvailable) {
      throw const LlmException(
        'LLM proxy not configured',
        recoverable: false,
      );
    }
    // The current `HttpTransport` interface returns the full body
    // as a string, not a chunked stream. For the streaming path
    // we re-use the same transport but parse the response as one
    // SSE blob — the parser handles multi-event payloads. A
    // future story can extend `HttpTransport` to expose a true
    // chunked stream, which would let us render tokens as they
    // arrive instead of after the whole response. For now, the
    // streaming method returns deltas in one batch — but the
    // public API is still `Stream<String>` so the caddie screen
    // doesn't need to change when the underlying transport adds
    // real chunking.
    final body = jsonEncode(request.toOpenAiJson(stream: true));
    final response = await transport.send(HttpRequestLike(
      method: 'POST',
      url: Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'Accept': 'text/event-stream',
      },
      body: body,
      timeout: _timeout,
    ));
    if (!response.isSuccess) {
      throw LlmException(
        'Proxy returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        recoverable: response.statusCode >= 500,
      );
    }
    // Wrap the response body in a single-element stream and let
    // the SSE parser do its thing.
    yield* parseOpenAiSseStream(Stream.value(response.body));
  }

  /// Parses the standard OpenAI Chat Completions response shape
  /// (also what the proxy returns). Pulls out the assistant
  /// message content and optional usage block.
  static LlmResponse _parseOpenAiResponse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw const LlmException(
          'Proxy response missing choices',
          recoverable: false,
        );
      }
      final first = choices[0] as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      if (message == null) {
        throw const LlmException(
          'Proxy response missing message',
          recoverable: false,
        );
      }
      final content = message['content'] as String? ?? '';
      final usageJson = json['usage'] as Map<String, dynamic>?;
      return LlmResponse(
        text: content,
        usage:
            usageJson != null ? LlmTokenUsage.fromOpenAiJson(usageJson) : null,
      );
    } catch (e) {
      if (e is LlmException) rethrow;
      throw LlmException('Malformed proxy response: $e');
    }
  }
}
