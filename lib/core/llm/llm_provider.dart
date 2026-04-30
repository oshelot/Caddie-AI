// Provider abstraction for the LLM router. Every backend that
// can answer a `LlmRequest` (the Lambda proxy, direct OpenAI,
// direct Claude, direct Gemini) implements this interface, so
// the router can treat them uniformly.
//
// **Why an interface, not a concrete class:** the unit tests
// inject `FakeLlmProvider` (in
// `test/llm/_fake_llm_provider.dart`) instead of standing up
// a real HTTP server. The router never knows the difference.

import 'llm_messages.dart';

abstract class LlmProvider {
  /// Provider identifier — `openAi` / `claude` / `gemini`. The
  /// proxy provider returns `openAi` since it ultimately speaks
  /// the OpenAI wire format.
  LlmProviderId get id;

  /// True if the provider is fully configured (endpoint + auth)
  /// and reachable in principle. The router uses this to short-
  /// circuit before attempting a call that's guaranteed to 401.
  bool get isAvailable;

  /// Non-streaming chat completion. Throws `LlmException` on any
  /// failure; the router decides whether to fall back based on
  /// the exception's `recoverable` flag.
  Future<LlmResponse> chatCompletion(LlmRequest request);

  /// Streaming chat completion. Returns a `Stream<String>` of
  /// content deltas (NOT accumulated text). Caller folds them
  /// to render token-by-token, or calls `accumulateSseStream`
  /// to get the final text in one shot.
  Stream<String> chatCompletionStream(LlmRequest request);
}
