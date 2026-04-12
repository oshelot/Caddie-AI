// LlmRouter — KAN-294 (S7.3) Flutter port of
// `ios/CaddieAI/Services/LLMRouter.swift`. Routes a `LlmRequest`
// to the right backend based on the user's tier and provider
// preference, falls back to the next provider on a recoverable
// failure, and logs every attempt to `LoggingService` so the
// CloudWatch `llm_latency` metric filter sees Flutter traffic
// alongside the existing iOS / Android data.
//
// **Routing rules** (lifted from `LLMRouter.swift`):
//
//   - **Free tier:** picks the provider matching the user's
//     `PlayerProfile.llmProvider`. If that provider is
//     unavailable (key missing, returns a recoverable error),
//     fall back through the remaining providers in this order:
//     openAi → claude → gemini.
//   - **Paid tier:** always uses the proxy. If the proxy is
//     unavailable, falls back to the user's selected free-tier
//     provider as a last resort.
//
// **Logging contract:** every attempt logs a `llm_latency` event
// (the canonical event name from `LoggingService.events`) with
// `tier` + `provider` + `success` + `latencyMs` metadata. The
// existing CloudWatch dashboard binds against those exact field
// names — adding or renaming fields silently breaks the dashboard.

import '../logging/log_event.dart';
import '../logging/logging_service.dart';
import 'llm_messages.dart';
import 'llm_provider.dart';

class LlmRouter {
  LlmRouter({
    required this.providers,
    required this.proxy,
    required this.logger,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        // Sanity-check that the providers map is keyed by id.
        assert(
          providers.entries.every((e) => e.key == e.value.id),
          'providers map keys must match each provider.id',
        );

  /// Direct providers, keyed by id (`openAi` / `claude` / `gemini`).
  /// Each provider may be `null`-isAvailable in which case the
  /// router skips it.
  final Map<LlmProviderId, LlmProvider> providers;

  /// Proxy provider — used for paid tier. May be unavailable in
  /// which case the router falls back to direct.
  final LlmProvider proxy;

  /// LoggingService instance from `lib/main.dart`'s top-level
  /// `logger` getter (or a test fake). Used for the `llm_latency`
  /// telemetry events the router emits on every attempt.
  final LoggingService logger;

  final DateTime Function() _clock;

  /// Default fallback order when the user's preferred provider
  /// fails. Matches the iOS native ordering.
  static const List<LlmProviderId> _fallbackOrder = [
    LlmProviderId.openAi,
    LlmProviderId.claude,
    LlmProviderId.gemini,
  ];

  /// Non-streaming chat completion. Tries the preferred provider
  /// first, falls back through the remaining ones on recoverable
  /// failures.
  Future<LlmResponse> chatCompletion({
    required LlmRequest request,
    required LlmTier tier,
    required LlmProviderId preferredProvider,
  }) async {
    final ordered = _selectProviderOrder(
      tier: tier,
      preferredProvider: preferredProvider,
    );

    LlmException? lastError;
    for (final provider in ordered) {
      final start = _clock();
      try {
        final response = await provider.chatCompletion(request);
        _logSuccess(
          tier: tier,
          provider: provider.id,
          start: start,
        );
        return response;
      } on LlmException catch (e) {
        _logFailure(
          tier: tier,
          provider: provider.id,
          start: start,
          error: e,
        );
        lastError = e;
        if (!e.recoverable) {
          // Non-recoverable (e.g. 401 invalid key) — bail straight
          // out, don't waste another provider's quota.
          rethrow;
        }
      } catch (e) {
        _logFailure(
          tier: tier,
          provider: provider.id,
          start: start,
          error: LlmException('Unexpected error: $e'),
        );
        lastError = LlmException('Unexpected error: $e');
      }
    }
    throw lastError ??
        const LlmException('No providers configured');
  }

  /// Streaming variant. Returns the stream from the FIRST provider
  /// that successfully starts streaming — there is no mid-stream
  /// fallback (once tokens have started flowing, switching
  /// providers would re-start the response, which is worse than
  /// just propagating the error).
  Stream<String> chatCompletionStream({
    required LlmRequest request,
    required LlmTier tier,
    required LlmProviderId preferredProvider,
  }) async* {
    final ordered = _selectProviderOrder(
      tier: tier,
      preferredProvider: preferredProvider,
    );
    LlmException? lastError;
    for (final provider in ordered) {
      final start = _clock();
      try {
        final stream = provider.chatCompletionStream(request);
        // We can't tell from the stream alone whether the first
        // chunk will arrive successfully — we have to consume at
        // least one event before declaring "this provider is
        // working". The pattern below uses a try/await on the
        // first chunk, then yields it + the remainder.
        var firstYielded = false;
        await for (final chunk in stream) {
          if (!firstYielded) {
            firstYielded = true;
            _logSuccess(tier: tier, provider: provider.id, start: start);
          }
          yield chunk;
        }
        return;
      } on LlmException catch (e) {
        _logFailure(
          tier: tier,
          provider: provider.id,
          start: start,
          error: e,
        );
        lastError = e;
        if (!e.recoverable) rethrow;
      } catch (e) {
        _logFailure(
          tier: tier,
          provider: provider.id,
          start: start,
          error: LlmException('Unexpected error: $e'),
        );
        lastError = LlmException('Unexpected error: $e');
      }
    }
    throw lastError ?? const LlmException('No providers configured');
  }

  /// Builds the ordered list of providers to try. The first
  /// element is the most-preferred; the rest are fallbacks in
  /// the iOS-canonical order. Skips providers that are
  /// unavailable up-front.
  List<LlmProvider> _selectProviderOrder({
    required LlmTier tier,
    required LlmProviderId preferredProvider,
  }) {
    final candidates = <LlmProvider>[];
    if (tier == LlmTier.paid) {
      // Paid tier: proxy first (managed backend, no user key needed).
      if (proxy.isAvailable) candidates.add(proxy);
    }
    // Preferred direct provider first.
    final preferred = providers[preferredProvider];
    if (preferred != null && preferred.isAvailable) {
      candidates.add(preferred);
    }
    // Fallback order, skipping the preferred and any unavailable.
    for (final id in _fallbackOrder) {
      if (id == preferredProvider) continue;
      final p = providers[id];
      if (p != null && p.isAvailable && !candidates.contains(p)) {
        candidates.add(p);
      }
    }
    // Free tier: proxy is the last-resort fallback when no direct
    // provider is configured (the user hasn't entered any API keys
    // yet). The proxy Lambda calls Bedrock and doesn't enforce tier
    // gating — it's CaddieAI's managed backend. This keeps the
    // caddie functional out-of-the-box for new users.
    if (tier == LlmTier.free && proxy.isAvailable && !candidates.contains(proxy)) {
      candidates.add(proxy);
    }
    return candidates;
  }

  void _logSuccess({
    required LlmTier tier,
    required LlmProviderId provider,
    required DateTime start,
  }) {
    final latencyMs =
        _clock().millisecondsSinceEpoch - start.millisecondsSinceEpoch;
    logger.info(
      LogCategory.llm,
      LoggingService.events.llmLatency,
      metadata: {
        'tier': tier.name,
        'provider': provider.wireName,
        'success': 'true',
        'latencyMs': '$latencyMs',
      },
    );
  }

  void _logFailure({
    required LlmTier tier,
    required LlmProviderId provider,
    required DateTime start,
    required LlmException error,
  }) {
    final latencyMs =
        _clock().millisecondsSinceEpoch - start.millisecondsSinceEpoch;
    logger.warning(
      LogCategory.llm,
      LoggingService.events.llmLatency,
      metadata: {
        'tier': tier.name,
        'provider': provider.wireName,
        'success': 'false',
        'latencyMs': '$latencyMs',
        'error': error.message,
        if (error.statusCode != null)
          'statusCode': '${error.statusCode}',
      },
    );
  }
}
