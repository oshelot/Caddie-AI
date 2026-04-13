// CaddiePage — KAN-281 (S11) route-level wiring for the caddie
// flagship screen. Loads the player profile from
// `ProfileRepository`, builds the production `LlmRouter`,
// `SttService`, `TtsService`, and hands them to `CaddieScreen`.
//
// **Why a separate file from `caddie_screen.dart`:** the leaf
// widget is platform-plugin-free → unit-testable. The page
// constructs `flutter_tts` / `speech_to_text` / `dart:io HttpClient`
// instances which all need real platform channels.

import '../../../core/build_mode.dart';
import 'package:flutter/material.dart';

import '../../../core/courses/http_transport.dart';
import '../../../core/golf/golf_enums.dart' as golf;
import '../../../core/golf/shot_context.dart';
import '../../../core/llm/direct_openai_provider.dart';
import '../../../core/llm/llm_messages.dart';
import '../../../core/logging/log_event.dart';
import '../../../core/llm/llm_proxy_provider.dart';
import '../../../core/llm/llm_router.dart';
import '../../../core/storage/profile_repository.dart';
import '../../../core/storage/secure_keys_storage.dart';
import '../../../core/voice/flutter_tts_service.dart';
import '../../../core/voice/speech_to_text_service.dart';
import '../../../core/voice/voice_settings.dart';
import '../../../main.dart' show logger;
import '../../../models/player_profile.dart';
import 'caddie_screen.dart';

class CaddiePage extends StatefulWidget {
  const CaddiePage({super.key});

  @override
  State<CaddiePage> createState() => _CaddiePageState();
}

class _CaddiePageState extends State<CaddiePage> {
  final _profileRepo = ProfileRepository();
  final _secureKeys = SecureKeysStorage();

  late final SpeechToTextService _stt =
      SpeechToTextService(logger: logger);
  late final FlutterTtsService _tts = FlutterTtsService(logger: logger);

  LlmRouter? _router;
  bool _loadingKeys = true;

  @override
  void initState() {
    super.initState();
    _loadKeysAndBuildRouter();
  }

  Future<void> _loadKeysAndBuildRouter() async {
    // Read user-supplied API keys from secure storage so direct
    // providers can be constructed for free-tier users.
    String openAiKey = '';
    try {
      openAiKey = await _secureKeys.read(SecureKey.openAi) ?? '';
    } catch (_) {
      // SecureKeysStorage unavailable in unit-test runtime.
    }

    final transport = DartIoHttpTransport();

    // Proxy provider — used for paid tier (Lambda → Bedrock).
    const proxyEndpoint =
        String.fromEnvironment('LLM_PROXY_ENDPOINT', defaultValue: '');
    const proxyApiKey =
        String.fromEnvironment('LLM_PROXY_API_KEY', defaultValue: '');
    final proxy = LlmProxyProvider(
      endpoint: proxyEndpoint,
      apiKey: proxyApiKey,
      transport: transport,
    );

    // Direct providers — used for free tier with user-supplied keys.
    final openAi = DirectOpenAiProvider(
      userApiKey: openAiKey,
      transport: transport,
    );

    // Diagnostic log so CloudWatch shows exactly what the router
    // was built with — helps debug "no providers" errors.
    logger.info(
      LogCategory.llm,
      'caddie_router_init',
      metadata: {
        'proxyAvailable': '${proxy.isAvailable}',
        'proxyEndpoint': proxyEndpoint.isEmpty ? 'MISSING' : 'set',
        'openAiKeyAvailable': '${openAi.isAvailable}',
        'isDevMode': '$isDevMode',
      },
    );

    if (!mounted) return;
    setState(() {
      _router = LlmRouter(
        providers: {
          LlmProviderId.openAi: openAi,
          // TODO: DirectClaudeProvider and DirectGeminiProvider for
          // free-tier users who choose those providers. For now,
          // only OpenAI direct is wired; Claude/Gemini keys are
          // stored in SecureKeysStorage but not consumed here yet.
        },
        proxy: proxy,
        logger: logger,
      );
      _loadingKeys = false;
    });
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingKeys || _router == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Defensive: in unit tests Hive isn't initialized, so the
    // profile load throws. Catch and use a default. Production
    // always has the boxes open by the time the route builds.
    PlayerProfile profile;
    try {
      profile = _profileRepo.loadOrDefault();
    } catch (_) {
      profile = const PlayerProfile();
    }
    final preferences = _toShotPreferences(profile);
    final persona = CaddieVoicePersona(
      gender: _parseGender(profile.caddieVoiceGender),
      accent: _parseAccent(profile.caddieVoiceAccent),
    );
    // Debug builds default to paid tier so the proxy/Bedrock path
    // works out-of-the-box without requiring an API key. Release
    // builds respect the profile's userTier field.
    final tier = isDevMode
        ? LlmTier.paid
        : (profile.userTier.toLowerCase() == 'pro'
            ? LlmTier.paid
            : LlmTier.free);
    final preferredProvider =
        LlmProviderId.fromWireName(profile.llmProvider) ??
            LlmProviderId.openAi;

    return CaddieScreen(
      profile: preferences,
      llmRouter: _router!,
      sttService: _stt,
      ttsService: _tts,
      logger: logger,
      preferredProvider: preferredProvider,
      tier: tier,
      persona: persona,
    );
  }

  /// Bridges the persistence-layer `PlayerProfile` (untyped string
  /// fields) to the engine-layer `ShotPreferences` (typed enums).
  /// Mirrors the same conversion the LLM-router page wrappers will
  /// need; we keep it here in the caddie page until a shared
  /// helper has multiple consumers.
  ShotPreferences _toShotPreferences(PlayerProfile profile) {
    return ShotPreferences(
      handicap: profile.handicap,
      preferredChipStyle: _parseChipStyle(profile.chipStyle),
      bunkerConfidence: _parseConfidence(profile.bunkerConfidence),
      wedgeConfidence: _parseConfidence(profile.wedgeConfidence),
      swingTendency: _parseSwingTendency(profile.swingTendency),
      stockShape: _parseStockShape(profile.stockShape),
      woodsStockShape: _parseStockShape(profile.woodsStockShape),
      ironsStockShape: _parseStockShape(profile.ironsStockShape),
      hybridsStockShape: _parseStockShape(profile.hybridsStockShape),
      missTendency: _parseMissTendency(profile.missTendency),
      defaultAggressiveness: _parseAggressiveness(profile.aggressiveness),
      ironType: _parseIronType(profile.ironType),
      // ClubDistances translation: the persistence layer stores
      // string keys; the engine wants `Map<Club, int>`. We
      // best-effort the parse and drop unrecognized clubs. A real
      // bag editor (KAN-S13) will normalize this on save.
      clubDistances: _parseClubDistances(profile.clubDistances),
    );
  }

  golf.ChipStyle _parseChipStyle(String s) {
    final normalized = s.toLowerCase().replaceAll('_', '');
    if (normalized.contains('bump')) return golf.ChipStyle.bumpAndRun;
    if (normalized.contains('lofted')) return golf.ChipStyle.lofted;
    return golf.ChipStyle.noPreference;
  }

  golf.SelfConfidence _parseConfidence(String s) {
    switch (s.toLowerCase()) {
      case 'low':
        return golf.SelfConfidence.low;
      case 'high':
        return golf.SelfConfidence.high;
      default:
        return golf.SelfConfidence.average;
    }
  }

  golf.SwingTendency _parseSwingTendency(String s) {
    switch (s.toLowerCase()) {
      case 'steep':
        return golf.SwingTendency.steep;
      case 'shallow':
        return golf.SwingTendency.shallow;
      default:
        return golf.SwingTendency.neutral;
    }
  }

  golf.StockShape _parseStockShape(String s) {
    switch (s.toLowerCase()) {
      case 'fade':
        return golf.StockShape.fade;
      case 'draw':
        return golf.StockShape.draw;
      default:
        return golf.StockShape.straight;
    }
  }

  golf.MissTendency _parseMissTendency(String s) {
    switch (s.toLowerCase()) {
      case 'left':
        return golf.MissTendency.left;
      case 'right':
        return golf.MissTendency.right;
      case 'thin':
        return golf.MissTendency.thin;
      case 'fat':
        return golf.MissTendency.fat;
      default:
        return golf.MissTendency.straight;
    }
  }

  golf.Aggressiveness _parseAggressiveness(String s) {
    switch (s.toLowerCase()) {
      case 'conservative':
        return golf.Aggressiveness.conservative;
      case 'aggressive':
        return golf.Aggressiveness.aggressive;
      default:
        return golf.Aggressiveness.normal;
    }
  }

  golf.IronType? _parseIronType(String? s) {
    if (s == null) return null;
    if (s.toLowerCase().contains('super')) {
      return golf.IronType.superGameImprovement;
    }
    if (s.toLowerCase().contains('game')) {
      return golf.IronType.gameImprovement;
    }
    return null;
  }

  CaddieVoiceGender _parseGender(String s) {
    return s.toLowerCase() == 'male'
        ? CaddieVoiceGender.male
        : CaddieVoiceGender.female;
  }

  CaddieVoiceAccent _parseAccent(String s) {
    switch (s.toLowerCase()) {
      case 'british':
        return CaddieVoiceAccent.british;
      case 'scottish':
        return CaddieVoiceAccent.scottish;
      case 'irish':
        return CaddieVoiceAccent.irish;
      case 'australian':
        return CaddieVoiceAccent.australian;
      default:
        return CaddieVoiceAccent.american;
    }
  }

  Map<golf.Club, int> _parseClubDistances(Map<String, int> raw) {
    final out = <golf.Club, int>{};
    for (final entry in raw.entries) {
      final club = _parseClub(entry.key);
      if (club != null) out[club] = entry.value;
    }
    return out;
  }

  golf.Club? _parseClub(String s) {
    final normalized = s.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    // Direct enum name match.
    for (final club in golf.Club.values) {
      if (club.name.toLowerCase() == normalized) return club;
    }
    // Match via displayName (handles "3-Wood" → "3-Wood", "5-Iron" → "5-Iron").
    final displayNorm = s.trim().toLowerCase();
    for (final club in golf.Club.values) {
      if (club.displayName.toLowerCase() == displayNorm) return club;
    }
    // Friendly aliases.
    if (normalized.contains('driver')) return golf.Club.driver;
    if (normalized.contains('pitchingwedge') ||
        normalized == 'pw') {
      return golf.Club.pitchingWedge;
    }
    if (normalized.contains('sandwedge') || normalized == 'sw') {
      return golf.Club.sandWedge;
    }
    if (normalized.contains('lobwedge') || normalized == 'lw') {
      return golf.Club.lobWedge;
    }
    return null;
  }
}
