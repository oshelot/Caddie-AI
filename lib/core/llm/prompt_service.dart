// PromptService — downloads and caches the centralized prompts.json
// from S3 (KAN-62/KAN-83). The iOS app calls fetchIfNeeded() at
// startup (CaddieAIApp.swift:145); we do the same in main.dart.
//
// Bucket: s3://caddieai-config/config/prompts.json
// Served via: direct S3 public read or a CloudFront/presigned URL.
// For now we hit the S3 object URL directly (public-read ACL).
//
// The prompts.json contains:
//   caddieSystemPrompt — structured JSON-response prompt for shot advice
//   holeAnalysisSystemPrompt — tee shot recommendation prompt
//   followUpAugmentation — appended for follow-up turns
//   personaFragments — map of persona name → augmentation text
//   golfKeywords — list of golf terms for input validation
//   offTopicResponse — canned response for non-golf questions
//   featureFlags — map of feature name → bool

import 'dart:convert';

import '../courses/http_transport.dart';

class PromptService {
  PromptService._();

  static final PromptService shared = PromptService._();

  static const String _defaultUrl =
      'https://caddieai-config.s3.us-east-2.amazonaws.com/config/prompts.json';

  // Cached prompt data
  String _caddieSystemPrompt = '';
  String _holeAnalysisSystemPrompt = '';
  String _followUpAugmentation = '';
  Map<String, String> _personaFragments = {};
  List<String> _golfKeywords = [];
  String _offTopicResponse =
      "I'm your golf caddie — I can help with club selection, "
      'shot strategy, and course management. What\'s your shot situation?';
  Map<String, bool> _featureFlags = {};

  bool _loaded = false;

  /// True once prompts have been fetched (or fallback applied).
  bool get isLoaded => _loaded;

  /// The main caddie system prompt — expects JSON response with
  /// club, target, executionPlan, etc.
  String get caddieSystemPrompt => _caddieSystemPrompt;

  /// System prompt for hole analysis tee shot recommendations.
  String get holeAnalysisSystemPrompt => _holeAnalysisSystemPrompt;

  /// Appended to the system prompt for follow-up conversation turns.
  String get followUpAugmentation => _followUpAugmentation;

  /// Canned response for non-golf questions.
  String get offTopicResponse => _offTopicResponse;

  /// Check if a feature flag is enabled.
  bool isFeatureEnabled(String flag) => _featureFlags[flag] ?? false;

  /// Returns the caddie system prompt with persona augmentation
  /// appended if the persona has a fragment.
  String caddieSystemPromptWithPersona(String? persona) {
    if (persona == null || !_personaFragments.containsKey(persona)) {
      return _caddieSystemPrompt;
    }
    return '$_caddieSystemPrompt\n\n${_personaFragments[persona]}';
  }

  /// Returns the hole analysis prompt with persona augmentation.
  String holeAnalysisSystemPromptWithPersona(String? persona) {
    if (persona == null || !_personaFragments.containsKey(persona)) {
      return _holeAnalysisSystemPrompt;
    }
    return '$_holeAnalysisSystemPrompt\n\n${_personaFragments[persona]}';
  }

  /// Checks if the input text is golf-related using the keyword list.
  bool isGolfRelated(String input) {
    if (_golfKeywords.isEmpty) return true; // no keywords = allow all
    final lower = input.toLowerCase();
    return _golfKeywords.any((kw) => lower.contains(kw));
  }

  /// Fetch prompts from S3. Call once at app startup.
  /// Non-fatal: if the fetch fails, falls back to hardcoded defaults.
  Future<void> fetchIfNeeded({
    HttpTransport? transport,
    String url = _defaultUrl,
  }) async {
    if (_loaded) return;
    final t = transport ?? DartIoHttpTransport();
    try {
      final response = await t.send(HttpRequestLike(
        method: 'GET',
        url: Uri.parse(url),
        timeout: const Duration(seconds: 10),
      ));
      if (!response.isSuccess) {
        _applyDefaults();
        return;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _caddieSystemPrompt = json['caddieSystemPrompt'] as String? ?? '';
      _holeAnalysisSystemPrompt =
          json['holeAnalysisSystemPrompt'] as String? ?? '';
      _followUpAugmentation =
          json['followUpAugmentation'] as String? ?? '';
      _offTopicResponse = json['offTopicResponse'] as String? ??
          _offTopicResponse;

      // Persona fragments
      final personas = json['personaFragments'];
      if (personas is Map) {
        _personaFragments = personas.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
      }

      // Golf keywords
      final keywords = json['golfKeywords'];
      if (keywords is List) {
        _golfKeywords = keywords.map((e) => e.toString().toLowerCase()).toList();
      }

      // Feature flags
      final flags = json['featureFlags'];
      if (flags is Map) {
        _featureFlags = flags.map(
          (k, v) => MapEntry(k.toString(), v == true),
        );
      }

      _loaded = true;
      // ignore: avoid_print
      print('PROMPTS: loaded from S3 — '
          '${_caddieSystemPrompt.length} chars system, '
          '${_personaFragments.length} personas, '
          '${_golfKeywords.length} keywords');
    } catch (e) {
      // ignore: avoid_print
      print('PROMPTS: S3 fetch failed ($e), using defaults');
      _applyDefaults();
    }
  }

  void _applyDefaults() {
    _caddieSystemPrompt = _defaultCaddiePrompt;
    _holeAnalysisSystemPrompt = _defaultHoleAnalysisPrompt;
    _loaded = true;
  }

  static const String _defaultCaddiePrompt =
      'You are an expert golf caddie AI assistant with 20+ years of '
      'PGA Tour experience. Analyze the shot situation and give a '
      'confident, clear recommendation. Respond with valid JSON matching: '
      '{"club":"string","target":"string","rationale":["string"],'
      '"swingThought":"string"}';

  static const String _defaultHoleAnalysisPrompt =
      'You are an expert golf caddie with 20+ years of PGA Tour '
      'experience. Standing on the tee box with your player, give a '
      'focused tee shot recommendation. Be specific and actionable. '
      'Keep it to 2-3 short sentences. Do NOT use markdown.';
}
