// Tests for KAN-294 (S7.3) LlmRouter — provider routing,
// fallback on recoverable failures, and the `llm_latency` log
// contract that the CloudWatch dashboards depend on.

import 'package:caddieai/core/llm/llm_messages.dart';
import 'package:caddieai/core/llm/llm_provider.dart';
import 'package:caddieai/core/llm/llm_router.dart';
import 'package:caddieai/core/logging/log_event.dart';
import 'package:caddieai/core/logging/log_sender.dart';
import 'package:caddieai/core/logging/logging_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLlmProvider implements LlmProvider {
  FakeLlmProvider({
    required this.id,
    this.isAvailable = true,
    this.exception,
    this.responseText = 'fake response',
    this.streamChunks = const ['fake', ' chunk'],
  });

  @override
  final LlmProviderId id;

  @override
  bool isAvailable;

  /// If non-null, every call throws this exception.
  LlmException? exception;

  String responseText;
  List<String> streamChunks;

  int callCount = 0;

  @override
  Future<LlmResponse> chatCompletion(LlmRequest request) async {
    callCount++;
    if (exception != null) throw exception!;
    return LlmResponse(text: responseText);
  }

  @override
  Stream<String> chatCompletionStream(LlmRequest request) async* {
    callCount++;
    if (exception != null) throw exception!;
    for (final c in streamChunks) {
      yield c;
    }
  }
}

class CapturingLogSender implements LogSender {
  final List<LogEntry> sent = [];
  @override
  Future<bool> send({
    required List<LogEntry> entries,
    required String deviceId,
    required String sessionId,
  }) async {
    sent.addAll(entries);
    return true;
  }
}

LoggingService _newLogger(CapturingLogSender sender) {
  return LoggingService(
    sender: sender,
    deviceId: 'd',
    sessionId: 's',
    enabled: true,
    flushThreshold: 1, // flush on every event so the test can see it
    flushInterval: const Duration(seconds: 5),
  );
}

const _request = LlmRequest(
  messages: [LlmMessage(role: 'user', content: 'hi')],
);

void main() {
  late CapturingLogSender logSender;
  late LoggingService logger;

  setUp(() {
    logSender = CapturingLogSender();
    logger = _newLogger(logSender);
  });

  tearDown(() => logger.dispose());

  group('routing — free tier', () {
    test('uses the preferred provider when available', () async {
      final openAi = FakeLlmProvider(
        id: LlmProviderId.openAi,
        responseText: 'from openai',
      );
      final claude = FakeLlmProvider(id: LlmProviderId.claude);
      final gemini = FakeLlmProvider(id: LlmProviderId.gemini);
      final proxy = FakeLlmProvider(
        id: LlmProviderId.openAi,
        isAvailable: false,
      );

      final router = LlmRouter(
        providers: {
          LlmProviderId.openAi: openAi,
          LlmProviderId.claude: claude,
          LlmProviderId.gemini: gemini,
        },
        proxy: proxy,
        logger: logger,
      );

      final response = await router.chatCompletion(
        request: _request,
        tier: LlmTier.free,
        preferredProvider: LlmProviderId.openAi,
      );
      expect(response.text, 'from openai');
      expect(openAi.callCount, 1);
      expect(claude.callCount, 0);
      expect(gemini.callCount, 0);
    });

    test('falls back to claude when openai returns a recoverable error',
        () async {
      final openAi = FakeLlmProvider(
        id: LlmProviderId.openAi,
        exception: const LlmException(
          'transient',
          statusCode: 503,
          recoverable: true,
        ),
      );
      final claude = FakeLlmProvider(
        id: LlmProviderId.claude,
        responseText: 'from claude',
      );
      final gemini = FakeLlmProvider(id: LlmProviderId.gemini);
      final proxy = FakeLlmProvider(
        id: LlmProviderId.openAi,
        isAvailable: false,
      );

      final router = LlmRouter(
        providers: {
          LlmProviderId.openAi: openAi,
          LlmProviderId.claude: claude,
          LlmProviderId.gemini: gemini,
        },
        proxy: proxy,
        logger: logger,
      );

      final response = await router.chatCompletion(
        request: _request,
        tier: LlmTier.free,
        preferredProvider: LlmProviderId.openAi,
      );
      expect(response.text, 'from claude');
      expect(openAi.callCount, 1);
      expect(claude.callCount, 1);
    });

    test('non-recoverable error bubbles immediately (no fallback)',
        () async {
      final openAi = FakeLlmProvider(
        id: LlmProviderId.openAi,
        exception: const LlmException(
          'invalid api key',
          statusCode: 401,
        ),
      );
      final claude = FakeLlmProvider(id: LlmProviderId.claude);
      final proxy = FakeLlmProvider(
        id: LlmProviderId.openAi,
        isAvailable: false,
      );

      final router = LlmRouter(
        providers: {
          LlmProviderId.openAi: openAi,
          LlmProviderId.claude: claude,
        },
        proxy: proxy,
        logger: logger,
      );

      expect(
        () => router.chatCompletion(
          request: _request,
          tier: LlmTier.free,
          preferredProvider: LlmProviderId.openAi,
        ),
        throwsA(isA<LlmException>()),
      );
      // Wait for the futures to settle, then check that claude
      // was NOT consulted.
      await Future<void>.delayed(Duration.zero);
      expect(claude.callCount, 0);
    });

    test('skips an unavailable preferred provider', () async {
      final openAi = FakeLlmProvider(
        id: LlmProviderId.openAi,
        isAvailable: false,
      );
      final claude = FakeLlmProvider(
        id: LlmProviderId.claude,
        responseText: 'from claude',
      );
      final proxy = FakeLlmProvider(
        id: LlmProviderId.openAi,
        isAvailable: false,
      );

      final router = LlmRouter(
        providers: {
          LlmProviderId.openAi: openAi,
          LlmProviderId.claude: claude,
        },
        proxy: proxy,
        logger: logger,
      );

      final response = await router.chatCompletion(
        request: _request,
        tier: LlmTier.free,
        preferredProvider: LlmProviderId.openAi,
      );
      expect(response.text, 'from claude');
      expect(openAi.callCount, 0);
    });
  });

  group('routing — paid tier', () {
    test('uses the proxy provider', () async {
      final proxy = FakeLlmProvider(
        id: LlmProviderId.openAi,
        responseText: 'from proxy',
      );
      final openAi = FakeLlmProvider(
        id: LlmProviderId.openAi,
        responseText: 'from openai',
      );
      final router = LlmRouter(
        providers: {LlmProviderId.openAi: openAi},
        proxy: proxy,
        logger: logger,
      );
      final response = await router.chatCompletion(
        request: _request,
        tier: LlmTier.paid,
        preferredProvider: LlmProviderId.openAi,
      );
      expect(response.text, 'from proxy');
      expect(proxy.callCount, 1);
      expect(openAi.callCount, 0);
    });

    test('paid tier with unavailable proxy falls back to direct openai',
        () async {
      final proxy = FakeLlmProvider(
        id: LlmProviderId.openAi,
        isAvailable: false,
      );
      final openAi = FakeLlmProvider(
        id: LlmProviderId.openAi,
        responseText: 'from openai',
      );
      final router = LlmRouter(
        providers: {LlmProviderId.openAi: openAi},
        proxy: proxy,
        logger: logger,
      );
      final response = await router.chatCompletion(
        request: _request,
        tier: LlmTier.paid,
        preferredProvider: LlmProviderId.openAi,
      );
      expect(response.text, 'from openai');
      expect(openAi.callCount, 1);
    });
  });

  group('streaming', () {
    test('yields chunks from the first available provider', () async {
      final openAi = FakeLlmProvider(
        id: LlmProviderId.openAi,
        streamChunks: const ['Hello', ' ', 'world'],
      );
      final proxy = FakeLlmProvider(
        id: LlmProviderId.openAi,
        isAvailable: false,
      );
      final router = LlmRouter(
        providers: {LlmProviderId.openAi: openAi},
        proxy: proxy,
        logger: logger,
      );
      final chunks = await router.chatCompletionStream(
        request: _request,
        tier: LlmTier.free,
        preferredProvider: LlmProviderId.openAi,
      ).toList();
      expect(chunks, ['Hello', ' ', 'world']);
    });
  });

  group('telemetry contract', () {
    test('successful call logs llm_latency with success=true metadata',
        () async {
      final openAi = FakeLlmProvider(id: LlmProviderId.openAi);
      final proxy = FakeLlmProvider(
        id: LlmProviderId.openAi,
        isAvailable: false,
      );
      final router = LlmRouter(
        providers: {LlmProviderId.openAi: openAi},
        proxy: proxy,
        logger: logger,
      );
      await router.chatCompletion(
        request: _request,
        tier: LlmTier.free,
        preferredProvider: LlmProviderId.openAi,
      );
      // Wait for the periodic flush to drain (threshold is 1).
      await Future<void>.delayed(Duration.zero);
      expect(logSender.sent, hasLength(1));
      final entry = logSender.sent.first;
      expect(entry.message, 'llm_latency');
      expect(entry.metadata['tier'], 'free');
      expect(entry.metadata['provider'], 'openAI');
      expect(entry.metadata['success'], 'true');
      expect(entry.metadata['latencyMs'], isNotNull);
    });

    test(
        'fallback path logs failure for the first provider and success '
        'for the fallback', () async {
      final openAi = FakeLlmProvider(
        id: LlmProviderId.openAi,
        exception: const LlmException(
          'transient',
          statusCode: 503,
          recoverable: true,
        ),
      );
      final claude = FakeLlmProvider(id: LlmProviderId.claude);
      final proxy = FakeLlmProvider(
        id: LlmProviderId.openAi,
        isAvailable: false,
      );
      final router = LlmRouter(
        providers: {
          LlmProviderId.openAi: openAi,
          LlmProviderId.claude: claude,
        },
        proxy: proxy,
        logger: logger,
      );
      await router.chatCompletion(
        request: _request,
        tier: LlmTier.free,
        preferredProvider: LlmProviderId.openAi,
      );
      await Future<void>.delayed(Duration.zero);
      expect(logSender.sent, hasLength(2));
      // First entry: openai failure
      expect(logSender.sent[0].metadata['provider'], 'openAI');
      expect(logSender.sent[0].metadata['success'], 'false');
      expect(logSender.sent[0].metadata['statusCode'], '503');
      // Second entry: claude success
      expect(logSender.sent[1].metadata['provider'], 'claude');
      expect(logSender.sent[1].metadata['success'], 'true');
    });
  });
}
