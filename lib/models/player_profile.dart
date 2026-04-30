// PlayerProfile — the unified Flutter representation of the player's
// settings, preferences, and golf attributes. Replaces both:
//
//   - iOS:     `ios/CaddieAI/Models/PlayerProfile.swift`
//              (persisted via UserDefaults key `playerProfile`)
//   - Android: `android/app/src/main/java/com/caddieai/android/data/model/PlayerProfile.kt`
//              (persisted via DataStore Preferences key `player_profile_v1`)
//
// **Fields are the union of both native models.** Where iOS and
// Android disagreed on a field name (e.g. `contactName` vs `name`,
// `defaultAggressiveness` vs `aggressiveness`), the Flutter side
// picks one canonical name and the migration importer in
// `lib/core/storage/native_migration_importer.dart` does the
// translation. The canonical names below were picked to read well in
// Dart, not to match either native shape — there's no requirement
// that the Flutter JSON match either native blob byte-for-byte
// (the migration is one-way at first launch).
//
// **API keys are NOT in this model.** Per ADR 0004 and the KAN-272
// AC, LLM provider keys (`openAiApiKey`, `claudeApiKey`,
// `geminiApiKey`), the Golf Course API key, and the Mapbox token live
// in `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPrefs
// on Android). They are **never** serialized into the Hive box that
// holds this model. The KAN-272 secure-keys-isolation test
// (`test/storage/secure_keys_isolation_test.dart`) asserts this by
// reading the raw Hive box contents and grepping for an API key
// shape; that test should fail if anyone ever adds an API-key field
// here.
//
// Why hand-written and not freezed: ADR 0004 explicitly allows
// hand-written toJson/fromJson, and dropping the codegen step keeps
// the iteration loop on the storage layer cheap. If a future story
// genuinely needs freezed (union types, value-equality codegen), the
// migration is mechanical — keep the field list, swap the boilerplate
// for `@freezed` annotations.

import 'package:flutter/foundation.dart';

@immutable
class PlayerProfile {
  // ── Identity ─────────────────────────────────────────────────────
  // iOS used `contactName/contactEmail/contactPhone`; Android used
  // `name/email/phone`. Flutter picks the shorter Android-style name.
  final String name;
  final String email;
  final String phone;

  // ── Golf attributes ──────────────────────────────────────────────
  final double handicap;

  /// Club name (string key, e.g. "driver", "7-iron") → carry yards.
  /// Club enum porting is deferred — we just store the string keys
  /// the native apps used. A future story can introduce a typed Club
  /// enum and a migration that re-keys this map.
  final Map<String, int> clubDistances;

  /// The set of clubs currently in the bag (Android-only field).
  /// Empty on iOS-migrated profiles — UI should treat empty as
  /// "use clubDistances.keys" rather than "no clubs".
  final List<String> bagClubs;

  final String stockShape;
  final String woodsStockShape;
  final String ironsStockShape;
  final String hybridsStockShape;
  final String missTendency;
  final String aggressiveness;
  final String bunkerConfidence;
  final String wedgeConfidence;
  final String chipStyle;
  final String swingTendency;

  // ── LLM provider selection ───────────────────────────────────────
  // API keys are NOT here — they're in SecureKeysStorage. This field
  // only records *which* provider the user picked.
  final String llmProvider;
  final String llmModel;

  /// Free / Pro tier — Android-only field. Defaults to "free" for
  /// iOS-migrated profiles.
  final String userTier;

  // Recommendation toggles (Android-only).
  final bool includeClubAlternatives;
  final bool includeWindAdjustment;
  final bool includeSlopeAdjustment;

  // ── Voice / persona ──────────────────────────────────────────────
  final String caddieVoiceGender;
  final String caddieVoiceAccent;
  final String caddiePersona;

  // ── Preferences ──────────────────────────────────────────────────
  /// Android-only. Defaults to false (yards) for iOS-migrated profiles.
  final bool usesMetric;

  /// Android-only. Defaults to true for iOS-migrated profiles.
  final bool voiceEnabled;

  // ── Onboarding state ─────────────────────────────────────────────
  /// iOS field. True if the player completed the swing onboarding
  /// flow. Android's `setupNoticeSeen` migrates into this field.
  final bool hasCompletedSwingOnboarding;

  /// iOS field. True once the player has confirmed their bag.
  /// Android-migrated profiles default to true (Android assumes a
  /// default bag and never gates on this flag).
  final bool hasConfiguredBag;

  /// Number of times the contact prompt has been skipped.
  final int contactPromptSkipCount;

  /// Last contact-prompt timestamp in epoch milliseconds. Null = never.
  final int? contactPromptLastShownMs;

  /// Android-only. True if the player explicitly opted in to receive
  /// contact from the team. Defaults to false on iOS-migrated profiles.
  final bool contactOptedIn;

  // ── Feature flags ────────────────────────────────────────────────
  final bool betaImageAnalysisEnabled;
  final bool telemetryEnabled;
  final bool scoringEnabled;

  // ── Tee box / iron type ──────────────────────────────────────────
  final String preferredTeeBox;
  final String? ironType;

  // ── Metadata ─────────────────────────────────────────────────────
  /// Epoch milliseconds. Set when the profile is first imported or
  /// created. Android tracked this natively; iOS-migrated profiles
  /// get the import timestamp.
  final int createdAtMs;

  /// Epoch milliseconds. Updated by the repository on every save.
  final int updatedAtMs;

  const PlayerProfile({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.handicap = 18.0,
    this.clubDistances = const {
      'Driver': 200,
      '3-Wood': 180,
      '5-Wood': 170,
      '4-Hybrid': 160,
      '5-Iron': 150,
      '6-Iron': 140,
      '7-Iron': 130,
      '8-Iron': 120,
      '9-Iron': 110,
      'Pitching Wedge': 100,
      'Gap Wedge': 90,
      'Sand Wedge': 80,
      'Lob Wedge': 60,
    },
    this.bagClubs = const [
      'Driver', '3-Wood', '5-Wood', '4-Hybrid',
      '5-Iron', '6-Iron', '7-Iron', '8-Iron', '9-Iron',
      'Pitching Wedge', 'Gap Wedge', 'Sand Wedge', 'Lob Wedge',
    ],
    this.stockShape = 'straight',
    this.woodsStockShape = 'straight',
    this.ironsStockShape = 'straight',
    this.hybridsStockShape = 'straight',
    this.missTendency = 'none',
    this.aggressiveness = 'normal',
    this.bunkerConfidence = 'average',
    this.wedgeConfidence = 'average',
    this.chipStyle = 'noPreference',
    this.swingTendency = 'neutral',
    this.llmProvider = 'openAI',
    this.llmModel = 'gpt-4o',
    this.userTier = 'free',
    this.includeClubAlternatives = true,
    this.includeWindAdjustment = true,
    this.includeSlopeAdjustment = true,
    this.caddieVoiceGender = 'female',
    this.caddieVoiceAccent = 'american',
    this.caddiePersona = 'professional',
    this.usesMetric = false,
    this.voiceEnabled = true,
    this.hasCompletedSwingOnboarding = false,
    this.hasConfiguredBag = false,
    this.contactPromptSkipCount = 0,
    this.contactPromptLastShownMs,
    this.contactOptedIn = false,
    this.betaImageAnalysisEnabled = false,
    this.telemetryEnabled = true,
    this.scoringEnabled = false,
    this.preferredTeeBox = 'white',
    this.ironType,
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
  });

  PlayerProfile copyWith({
    String? name,
    String? email,
    String? phone,
    double? handicap,
    Map<String, int>? clubDistances,
    List<String>? bagClubs,
    String? stockShape,
    String? woodsStockShape,
    String? ironsStockShape,
    String? hybridsStockShape,
    String? missTendency,
    String? aggressiveness,
    String? bunkerConfidence,
    String? wedgeConfidence,
    String? chipStyle,
    String? swingTendency,
    String? llmProvider,
    String? llmModel,
    String? userTier,
    bool? includeClubAlternatives,
    bool? includeWindAdjustment,
    bool? includeSlopeAdjustment,
    String? caddieVoiceGender,
    String? caddieVoiceAccent,
    String? caddiePersona,
    bool? usesMetric,
    bool? voiceEnabled,
    bool? hasCompletedSwingOnboarding,
    bool? hasConfiguredBag,
    int? contactPromptSkipCount,
    int? contactPromptLastShownMs,
    bool? contactOptedIn,
    bool? betaImageAnalysisEnabled,
    bool? telemetryEnabled,
    bool? scoringEnabled,
    String? preferredTeeBox,
    String? ironType,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return PlayerProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      handicap: handicap ?? this.handicap,
      clubDistances: clubDistances ?? this.clubDistances,
      bagClubs: bagClubs ?? this.bagClubs,
      stockShape: stockShape ?? this.stockShape,
      woodsStockShape: woodsStockShape ?? this.woodsStockShape,
      ironsStockShape: ironsStockShape ?? this.ironsStockShape,
      hybridsStockShape: hybridsStockShape ?? this.hybridsStockShape,
      missTendency: missTendency ?? this.missTendency,
      aggressiveness: aggressiveness ?? this.aggressiveness,
      bunkerConfidence: bunkerConfidence ?? this.bunkerConfidence,
      wedgeConfidence: wedgeConfidence ?? this.wedgeConfidence,
      chipStyle: chipStyle ?? this.chipStyle,
      swingTendency: swingTendency ?? this.swingTendency,
      llmProvider: llmProvider ?? this.llmProvider,
      llmModel: llmModel ?? this.llmModel,
      userTier: userTier ?? this.userTier,
      includeClubAlternatives:
          includeClubAlternatives ?? this.includeClubAlternatives,
      includeWindAdjustment:
          includeWindAdjustment ?? this.includeWindAdjustment,
      includeSlopeAdjustment:
          includeSlopeAdjustment ?? this.includeSlopeAdjustment,
      caddieVoiceGender: caddieVoiceGender ?? this.caddieVoiceGender,
      caddieVoiceAccent: caddieVoiceAccent ?? this.caddieVoiceAccent,
      caddiePersona: caddiePersona ?? this.caddiePersona,
      usesMetric: usesMetric ?? this.usesMetric,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      hasCompletedSwingOnboarding:
          hasCompletedSwingOnboarding ?? this.hasCompletedSwingOnboarding,
      hasConfiguredBag: hasConfiguredBag ?? this.hasConfiguredBag,
      contactPromptSkipCount:
          contactPromptSkipCount ?? this.contactPromptSkipCount,
      contactPromptLastShownMs:
          contactPromptLastShownMs ?? this.contactPromptLastShownMs,
      contactOptedIn: contactOptedIn ?? this.contactOptedIn,
      betaImageAnalysisEnabled:
          betaImageAnalysisEnabled ?? this.betaImageAnalysisEnabled,
      telemetryEnabled: telemetryEnabled ?? this.telemetryEnabled,
      scoringEnabled: scoringEnabled ?? this.scoringEnabled,
      preferredTeeBox: preferredTeeBox ?? this.preferredTeeBox,
      ironType: ironType ?? this.ironType,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'phone': phone,
        'handicap': handicap,
        'clubDistances': clubDistances,
        'bagClubs': bagClubs,
        'stockShape': stockShape,
        'woodsStockShape': woodsStockShape,
        'ironsStockShape': ironsStockShape,
        'hybridsStockShape': hybridsStockShape,
        'missTendency': missTendency,
        'aggressiveness': aggressiveness,
        'bunkerConfidence': bunkerConfidence,
        'wedgeConfidence': wedgeConfidence,
        'chipStyle': chipStyle,
        'swingTendency': swingTendency,
        'llmProvider': llmProvider,
        'llmModel': llmModel,
        'userTier': userTier,
        'includeClubAlternatives': includeClubAlternatives,
        'includeWindAdjustment': includeWindAdjustment,
        'includeSlopeAdjustment': includeSlopeAdjustment,
        'caddieVoiceGender': caddieVoiceGender,
        'caddieVoiceAccent': caddieVoiceAccent,
        'caddiePersona': caddiePersona,
        'usesMetric': usesMetric,
        'voiceEnabled': voiceEnabled,
        'hasCompletedSwingOnboarding': hasCompletedSwingOnboarding,
        'hasConfiguredBag': hasConfiguredBag,
        'contactPromptSkipCount': contactPromptSkipCount,
        'contactPromptLastShownMs': contactPromptLastShownMs,
        'contactOptedIn': contactOptedIn,
        'betaImageAnalysisEnabled': betaImageAnalysisEnabled,
        'telemetryEnabled': telemetryEnabled,
        'scoringEnabled': scoringEnabled,
        'preferredTeeBox': preferredTeeBox,
        'ironType': ironType,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
      };

  /// Decoder is intentionally lenient — every field has a default,
  /// so a partial JSON (e.g. an older blob missing newer fields)
  /// loads cleanly with defaults filling the gaps. This mirrors the
  /// `decodeIfPresent` pattern in the iOS Codable initializer.
  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    return PlayerProfile(
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      handicap: (json['handicap'] as num?)?.toDouble() ?? 18.0,
      clubDistances: _decodeIntMap(json['clubDistances']),
      bagClubs: _decodeStringList(json['bagClubs']),
      stockShape: json['stockShape'] as String? ?? 'straight',
      woodsStockShape: json['woodsStockShape'] as String? ?? 'straight',
      ironsStockShape: json['ironsStockShape'] as String? ?? 'straight',
      hybridsStockShape: json['hybridsStockShape'] as String? ?? 'straight',
      missTendency: json['missTendency'] as String? ?? 'none',
      aggressiveness: json['aggressiveness'] as String? ?? 'normal',
      bunkerConfidence: json['bunkerConfidence'] as String? ?? 'average',
      wedgeConfidence: json['wedgeConfidence'] as String? ?? 'average',
      chipStyle: json['chipStyle'] as String? ?? 'noPreference',
      swingTendency: json['swingTendency'] as String? ?? 'neutral',
      llmProvider: json['llmProvider'] as String? ?? 'openAI',
      llmModel: json['llmModel'] as String? ?? 'gpt-4o',
      userTier: json['userTier'] as String? ?? 'free',
      includeClubAlternatives:
          json['includeClubAlternatives'] as bool? ?? true,
      includeWindAdjustment: json['includeWindAdjustment'] as bool? ?? true,
      includeSlopeAdjustment: json['includeSlopeAdjustment'] as bool? ?? true,
      caddieVoiceGender: json['caddieVoiceGender'] as String? ?? 'female',
      caddieVoiceAccent: json['caddieVoiceAccent'] as String? ?? 'american',
      caddiePersona: json['caddiePersona'] as String? ?? 'professional',
      usesMetric: json['usesMetric'] as bool? ?? false,
      voiceEnabled: json['voiceEnabled'] as bool? ?? true,
      hasCompletedSwingOnboarding:
          json['hasCompletedSwingOnboarding'] as bool? ?? false,
      hasConfiguredBag: json['hasConfiguredBag'] as bool? ?? false,
      contactPromptSkipCount: (json['contactPromptSkipCount'] as num?)?.toInt() ?? 0,
      contactPromptLastShownMs:
          (json['contactPromptLastShownMs'] as num?)?.toInt(),
      contactOptedIn: json['contactOptedIn'] as bool? ?? false,
      betaImageAnalysisEnabled:
          json['betaImageAnalysisEnabled'] as bool? ?? false,
      telemetryEnabled: json['telemetryEnabled'] as bool? ?? true,
      scoringEnabled: json['scoringEnabled'] as bool? ?? false,
      preferredTeeBox: json['preferredTeeBox'] as String? ?? 'white',
      ironType: json['ironType'] as String?,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, int> _decodeIntMap(dynamic raw) {
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }

  static List<String> _decodeStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList(growable: false);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PlayerProfile) return false;
    return name == other.name &&
        email == other.email &&
        phone == other.phone &&
        handicap == other.handicap &&
        _mapEquals(clubDistances, other.clubDistances) &&
        _listEquals(bagClubs, other.bagClubs) &&
        stockShape == other.stockShape &&
        woodsStockShape == other.woodsStockShape &&
        ironsStockShape == other.ironsStockShape &&
        hybridsStockShape == other.hybridsStockShape &&
        missTendency == other.missTendency &&
        aggressiveness == other.aggressiveness &&
        bunkerConfidence == other.bunkerConfidence &&
        wedgeConfidence == other.wedgeConfidence &&
        chipStyle == other.chipStyle &&
        swingTendency == other.swingTendency &&
        llmProvider == other.llmProvider &&
        llmModel == other.llmModel &&
        userTier == other.userTier &&
        includeClubAlternatives == other.includeClubAlternatives &&
        includeWindAdjustment == other.includeWindAdjustment &&
        includeSlopeAdjustment == other.includeSlopeAdjustment &&
        caddieVoiceGender == other.caddieVoiceGender &&
        caddieVoiceAccent == other.caddieVoiceAccent &&
        caddiePersona == other.caddiePersona &&
        usesMetric == other.usesMetric &&
        voiceEnabled == other.voiceEnabled &&
        hasCompletedSwingOnboarding == other.hasCompletedSwingOnboarding &&
        hasConfiguredBag == other.hasConfiguredBag &&
        contactPromptSkipCount == other.contactPromptSkipCount &&
        contactPromptLastShownMs == other.contactPromptLastShownMs &&
        contactOptedIn == other.contactOptedIn &&
        betaImageAnalysisEnabled == other.betaImageAnalysisEnabled &&
        telemetryEnabled == other.telemetryEnabled &&
        scoringEnabled == other.scoringEnabled &&
        preferredTeeBox == other.preferredTeeBox &&
        ironType == other.ironType &&
        createdAtMs == other.createdAtMs &&
        updatedAtMs == other.updatedAtMs;
  }

  @override
  int get hashCode => Object.hashAll([
        name,
        email,
        phone,
        handicap,
        Object.hashAllUnordered(clubDistances.entries.map((e) => '${e.key}=${e.value}')),
        Object.hashAll(bagClubs),
        stockShape,
        woodsStockShape,
        ironsStockShape,
        hybridsStockShape,
        missTendency,
        aggressiveness,
        bunkerConfidence,
        wedgeConfidence,
        chipStyle,
        swingTendency,
        llmProvider,
        llmModel,
        userTier,
        includeClubAlternatives,
        includeWindAdjustment,
        includeSlopeAdjustment,
        caddieVoiceGender,
        caddieVoiceAccent,
        caddiePersona,
        usesMetric,
        voiceEnabled,
        hasCompletedSwingOnboarding,
        hasConfiguredBag,
        contactPromptSkipCount,
        contactPromptLastShownMs,
        contactOptedIn,
        betaImageAnalysisEnabled,
        telemetryEnabled,
        scoringEnabled,
        preferredTeeBox,
        ironType,
        createdAtMs,
        updatedAtMs,
      ]);
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
