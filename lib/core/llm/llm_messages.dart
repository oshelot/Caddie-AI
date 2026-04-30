// Value types shared by every LLM client in `lib/core/llm/`
// (KAN-294 / S7.3). Independent of any specific provider — both
// the direct OpenAI/Claude/Gemini clients and the Lambda proxy
// client consume and produce these.
//
// **Wire format compatibility:** the `toOpenAiJson` helpers below
// produce the OpenAI Chat Completions request shape, which is what
// the existing Lambda proxy expects (the proxy is a thin pass-
// through to OpenAI). The Claude and Gemini provider impls have
// to translate from this shape into their own request/response
// formats — those translations live in the per-provider files.

class LlmMessage {
  const LlmMessage({required this.role, required this.content});

  /// `'system'`, `'user'`, or `'assistant'` — matches the OpenAI
  /// Chat Completions schema. Match the iOS native casing exactly
  /// so prompts authored against the existing CaddieAI prompts
  /// keep working without translation.
  final String role;
  final String content;

  Map<String, dynamic> toOpenAiJson() => {
        'role': role,
        'content': content,
      };
}

/// Token usage report. Returned alongside the response by every
/// provider that exposes usage in its API (all of OpenAI, Claude,
/// Gemini do; the proxy passes them through). Used by the Profile
/// screen's API usage display (KAN-S13).
class LlmTokenUsage {
  const LlmTokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  factory LlmTokenUsage.fromOpenAiJson(Map<String, dynamic> json) {
    return LlmTokenUsage(
      promptTokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (json['completion_tokens'] as num?)?.toInt() ?? 0,
      totalTokens: (json['total_tokens'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One LLM request. The provider impl translates this into its
/// native request shape. `responseFormat` is optional and only
/// used by the JSON-mode path (e.g. structured `ShotRecommendation`
/// extraction); `null` means free-text.
class LlmRequest {
  const LlmRequest({
    required this.messages,
    this.model,
    this.maxTokens = 1500,
    this.temperature = 0.7,
    this.responseFormat,
  });

  final List<LlmMessage> messages;

  /// Optional model override. When null, the provider picks its
  /// default (e.g. the proxy forces `gpt-4o-mini`; the direct
  /// OpenAI client uses the value from `PlayerProfile.llmModel`).
  final String? model;

  final int maxTokens;
  final double temperature;

  /// OpenAI-style response format hint, e.g.
  /// `{'type': 'json_object'}` for JSON mode. Pass null for
  /// plain text. Other providers translate this to their own
  /// JSON-mode equivalent.
  final Map<String, dynamic>? responseFormat;

  Map<String, dynamic> toOpenAiJson({bool stream = false}) {
    return {
      'messages': messages.map((m) => m.toOpenAiJson()).toList(),
      if (model != null) 'model': model,
      'max_tokens': maxTokens,
      'temperature': temperature,
      if (responseFormat != null) 'response_format': responseFormat,
      if (stream) 'stream': true,
    };
  }
}

/// Non-streaming response. Free-text content + optional token usage.
class LlmResponse {
  const LlmResponse({required this.text, this.usage});

  final String text;
  final LlmTokenUsage? usage;
}

/// Provider tier — drives routing in `LlmRouter`.
enum LlmTier {
  /// Free tier: routes directly to the user's selected provider
  /// (OpenAI / Claude / Gemini) using their API key from
  /// `SecureKeysStorage`.
  free,

  /// Paid tier: routes through the Lambda proxy. The proxy injects
  /// the server-side OpenAI key and forces `gpt-4o-mini`.
  paid,
}

/// Provider identifier — matches `PlayerProfile.llmProvider` wire
/// values from KAN-272.
enum LlmProviderId {
  openAi,
  claude,
  gemini;

  String get wireName => switch (this) {
        LlmProviderId.openAi => 'openAI',
        LlmProviderId.claude => 'claude',
        LlmProviderId.gemini => 'gemini',
      };

  static LlmProviderId? fromWireName(String name) {
    switch (name) {
      case 'openAI':
        return LlmProviderId.openAi;
      case 'claude':
        return LlmProviderId.claude;
      case 'gemini':
        return LlmProviderId.gemini;
      default:
        return null;
    }
  }
}

/// Thrown by every provider on a failure the router can use to
/// decide whether to fall back. `recoverable = true` triggers a
/// fallback attempt; `recoverable = false` (e.g. a 401 invalid
/// API key) bubbles straight to the caller.
class LlmException implements Exception {
  const LlmException(
    this.message, {
    this.statusCode,
    this.recoverable = false,
  });

  final String message;
  final int? statusCode;
  final bool recoverable;

  @override
  String toString() => statusCode == null
      ? 'LlmException: $message'
      : 'LlmException ($statusCode): $message';
}
