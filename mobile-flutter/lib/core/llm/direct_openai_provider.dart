// DirectOpenAiProvider — calls OpenAI's Chat Completions API directly
// using the user's own API key. Used for free-tier users who supply
// their own key in Profile → API Keys.
//
// The wire format is identical to LlmProxyProvider (both speak OpenAI
// Chat Completions). The differences are:
//   - Endpoint: `https://api.openai.com/v1/chat/completions`
//   - Auth: `Authorization: Bearer <user-key>` (not `x-api-key`)
//   - Model: uses whatever the user selected in their profile
//     (the proxy forces gpt-4o-mini regardless)

import 'dart:convert';

import '../courses/http_transport.dart';
import 'llm_messages.dart';
import 'llm_provider.dart';
import 'sse_parser.dart';

class DirectOpenAiProvider implements LlmProvider {
  DirectOpenAiProvider({
    required this.userApiKey,
    required this.transport,
    this.endpoint = 'https://api.openai.com/v1/chat/completions',
    Duration timeout = const Duration(seconds: 60),
  }) : _timeout = timeout;

  final String userApiKey;
  final String endpoint;
  final HttpTransport transport;
  final Duration _timeout;

  @override
  LlmProviderId get id => LlmProviderId.openAi;

  @override
  bool get isAvailable => userApiKey.isNotEmpty;

  @override
  Future<LlmResponse> chatCompletion(LlmRequest request) async {
    if (!isAvailable) {
      throw const LlmException(
        'OpenAI API key not configured. Add your key in Profile → API Keys.',
        recoverable: false,
      );
    }
    final body = jsonEncode(request.toOpenAiJson());
    final response = await transport.send(HttpRequestLike(
      method: 'POST',
      url: Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $userApiKey',
      },
      body: body,
      timeout: _timeout,
    ));
    if (!response.isSuccess) {
      throw LlmException(
        'OpenAI returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        recoverable: response.statusCode >= 500,
      );
    }
    return _parseResponse(response.body);
  }

  @override
  Stream<String> chatCompletionStream(LlmRequest request) async* {
    if (!isAvailable) {
      throw const LlmException(
        'OpenAI API key not configured. Add your key in Profile → API Keys.',
        recoverable: false,
      );
    }
    final body = jsonEncode(request.toOpenAiJson(stream: true));
    final response = await transport.send(HttpRequestLike(
      method: 'POST',
      url: Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $userApiKey',
        'Accept': 'text/event-stream',
      },
      body: body,
      timeout: _timeout,
    ));
    if (!response.isSuccess) {
      throw LlmException(
        'OpenAI returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        recoverable: response.statusCode >= 500,
      );
    }
    yield* parseOpenAiSseStream(Stream.value(response.body));
  }

  static LlmResponse _parseResponse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw const LlmException(
          'OpenAI response missing choices',
          recoverable: false,
        );
      }
      final first = choices[0] as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      if (message == null) {
        throw const LlmException(
          'OpenAI response missing message',
          recoverable: false,
        );
      }
      final content = message['content'] as String? ?? '';
      final usageJson = json['usage'] as Map<String, dynamic>?;
      return LlmResponse(
        text: content,
        usage: usageJson != null
            ? LlmTokenUsage.fromOpenAiJson(usageJson)
            : null,
      );
    } catch (e) {
      if (e is LlmException) rethrow;
      throw LlmException('Malformed OpenAI response: $e');
    }
  }
}
