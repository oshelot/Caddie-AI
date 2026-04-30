// NativeMigrationImporter — translates a native (iOS or Android)
// PlayerProfile / ShotHistory blob into the Flutter storage shape.
// Required by **KAN-272 AC #2**:
//
// > Migration importer produces correct profile for a captured set
// > of native-format fixtures (commit a few sample payloads in
// > `test/fixtures/migration/`)
//
// **Scope of this file:** the *translation* layer is pure Dart and
// fully tested. It takes JSON `Map`s as input and produces Flutter
// model instances + a secret-keys map. It does NOT include the
// platform-channel code that reads `UserDefaults` (iOS) or
// `DataStore` (Android) at first launch — that bridge is a separate
// concern that lands as part of KAN-272's first cutover work
// (rather than at story open time, since the cutover doesn't
// happen until KAN-S16).
//
// The reason for splitting it that way: the platform channel needs
// access to the still-installed native app's data, which only
// exists once we're shipping the Flutter app as a replacement APK
// in the same package id. Until then, the importer is exercised
// only by tests against the fixture payloads in
// `test/fixtures/migration/`. When the cutover happens, S16 will
// add a thin `MigrationBridge` MethodChannel that hands the raw
// JSON blobs to this class.
//
// **Key translation table** (the canonical source-of-truth for
// migration semantics; changes here MUST be reflected in tests):
//
// | iOS native key             | Android native key       | Flutter field                  |
// |---------------------------|--------------------------|--------------------------------|
// | contactName               | name                     | name                           |
// | contactEmail              | email                    | email                          |
// | contactPhone              | phone                    | phone                          |
// | handicap                  | handicap                 | handicap                       |
// | clubDistances [{club,...}]| clubDistances {Club:Int} | clubDistances Map<String,int>  |
// | (none)                    | bagClubs (Set<Club>)     | bagClubs List<String>          |
// | stockShape                | stockShape               | stockShape                     |
// | woods/irons/hybrids…      | woods/irons/hybrids…     | …same                          |
// | missTendency              | missTendency             | missTendency                   |
// | defaultAggressiveness     | aggressiveness           | aggressiveness                 |
// | bunkerConfidence          | bunkerConfidence         | bunkerConfidence               |
// | wedgeConfidence           | wedgeConfidence          | wedgeConfidence                |
// | preferredChipStyle        | chipStyle                | chipStyle                      |
// | swingTendency             | swingTendency            | swingTendency                  |
// | llmProvider               | llmProvider              | llmProvider                    |
// | llmModel                  | llmModel                 | llmModel                       |
// | (none)                    | userTier                 | userTier                       |
// | caddieVoiceGender         | caddieGender             | caddieVoiceGender              |
// | caddieVoiceAccent         | caddieAccent             | caddieVoiceAccent              |
// | caddiePersona             | caddiePersona            | caddiePersona                  |
// | (none)                    | usesMetric               | usesMetric                     |
// | (none)                    | voiceEnabled             | voiceEnabled                   |
// | hasCompletedSwingOnboarding| setupNoticeSeen         | hasCompletedSwingOnboarding    |
// | hasConfiguredBag          | (defaults to true)       | hasConfiguredBag               |
// | contactPromptSkipCount    | contactPromptCount       | contactPromptSkipCount         |
// | contactPromptLastShown    | lastContactPromptMs      | contactPromptLastShownMs       |
// | (none)                    | contactOptedIn           | contactOptedIn                 |
// | betaImageAnalysis         | imageAnalysisBetaEnabled | betaImageAnalysisEnabled       |
// | telemetryEnabled          | telemetryEnabled         | telemetryEnabled               |
// | scoringEnabled            | scoringEnabled           | scoringEnabled                 |
// | preferredTeeBox           | preferredTeeBox          | preferredTeeBox                |
// | ironType                  | ironType                 | ironType                       |
// | (n/a)                     | createdAtMs              | createdAtMs                    |
// | (n/a)                     | updatedAtMs              | updatedAtMs                    |
// | apiKey                    | openAiApiKey             | SecureKey.openAi               |
// | claudeApiKey              | anthropicApiKey          | SecureKey.claude               |
// | geminiApiKey              | googleApiKey             | SecureKey.gemini               |
// | golfCourseApiKey          | (BuildConfig)            | SecureKey.golfCourseApi        |
// | mapboxAccessToken         | (BuildConfig)            | SecureKey.mapbox               |

import '../../models/player_profile.dart';
import '../../models/shot_history_entry.dart';
import 'profile_repository.dart';
import 'secure_keys_storage.dart';
import 'shot_history_repository.dart';

/// Result of running the importer against a native blob. The caller
/// is responsible for actually persisting these — the importer is
/// a pure translator. Splitting parse from persist makes the layer
/// testable without a Hive box open.
class ImportedProfile {
  const ImportedProfile({
    required this.profile,
    required this.secrets,
  });

  /// The translated Flutter PlayerProfile, ready to hand to
  /// `ProfileRepository.save`.
  final PlayerProfile profile;

  /// Map<SecureKey constant, secret value>. Empty values are
  /// included as null so the caller can pass the whole map to
  /// `SecureKeysStorage.writeAll` and have empty fields cleared.
  final Map<String, String?> secrets;
}

class NativeMigrationImporter {
  NativeMigrationImporter({
    required this.profileRepository,
    required this.shotHistoryRepository,
    required this.secureKeysStorage,
  });

  final ProfileRepository profileRepository;
  final ShotHistoryRepository shotHistoryRepository;
  final SecureKeysStorage secureKeysStorage;

  // ─── iOS profile ──────────────────────────────────────────────────

  /// Translates a JSON-decoded iOS `PlayerProfile` blob (the value
  /// originally stored under `UserDefaults.standard.dictionary(
  /// forKey: "playerProfile")`) into a Flutter PlayerProfile +
  /// secrets map.
  ImportedProfile importIosProfile(Map<String, dynamic> json) {
    final profile = PlayerProfile(
      name: json['contactName'] as String? ?? '',
      email: json['contactEmail'] as String? ?? '',
      phone: json['contactPhone'] as String? ?? '',
      handicap: (json['handicap'] as num?)?.toDouble() ?? 18.0,
      clubDistances: _parseIosClubDistances(json['clubDistances']),
      // iOS doesn't track bag membership separately — the keys of
      // clubDistances are the bag. Surface that as bagClubs so
      // Android-style consumers see something coherent.
      bagClubs: _parseIosClubDistances(json['clubDistances']).keys.toList(),
      stockShape: json['stockShape'] as String? ?? 'straight',
      woodsStockShape: json['woodsStockShape'] as String? ?? 'straight',
      ironsStockShape: json['ironsStockShape'] as String? ?? 'straight',
      hybridsStockShape: json['hybridsStockShape'] as String? ?? 'straight',
      missTendency: json['missTendency'] as String? ?? 'none',
      aggressiveness: json['defaultAggressiveness'] as String? ?? 'normal',
      bunkerConfidence: json['bunkerConfidence'] as String? ?? 'average',
      wedgeConfidence: json['wedgeConfidence'] as String? ?? 'average',
      chipStyle: json['preferredChipStyle'] as String? ?? 'noPreference',
      swingTendency: json['swingTendency'] as String? ?? 'neutral',
      llmProvider: json['llmProvider'] as String? ?? 'openAI',
      llmModel: json['llmModel'] as String? ?? 'gpt-4o',
      userTier: 'free', // iOS didn't track this — default to free
      caddieVoiceGender:
          json['caddieVoiceGender'] as String? ?? 'female',
      caddieVoiceAccent:
          json['caddieVoiceAccent'] as String? ?? 'american',
      caddiePersona: json['caddiePersona'] as String? ?? 'professional',
      hasCompletedSwingOnboarding:
          json['hasCompletedSwingOnboarding'] as bool? ?? false,
      hasConfiguredBag: json['hasConfiguredBag'] as bool? ?? false,
      contactPromptSkipCount:
          (json['contactPromptSkipCount'] as num?)?.toInt() ?? 0,
      contactPromptLastShownMs:
          _parseIsoDateMs(json['contactPromptLastShown']),
      betaImageAnalysisEnabled:
          json['betaImageAnalysis'] as bool? ?? false,
      telemetryEnabled: json['telemetryEnabled'] as bool? ?? true,
      scoringEnabled: json['scoringEnabled'] as bool? ?? false,
      preferredTeeBox: json['preferredTeeBox'] as String? ?? 'white',
      ironType: json['ironType'] as String?,
      // iOS didn't track created/updated metadata — the repository
      // will stamp these on first save.
    );

    return ImportedProfile(
      profile: profile,
      secrets: {
        SecureKey.openAi: json['apiKey'] as String?,
        SecureKey.claude: json['claudeApiKey'] as String?,
        SecureKey.gemini: json['geminiApiKey'] as String?,
        SecureKey.golfCourseApi: json['golfCourseApiKey'] as String?,
        SecureKey.mapbox: json['mapboxAccessToken'] as String?,
      },
    );
  }

  // ─── Android profile ──────────────────────────────────────────────

  /// Translates a JSON-decoded Android `PlayerProfile` blob (the
  /// value originally stored in DataStore under `player_profile_v1`)
  /// into a Flutter PlayerProfile + secrets map.
  ImportedProfile importAndroidProfile(Map<String, dynamic> json) {
    final profile = PlayerProfile(
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      handicap: (json['handicap'] as num?)?.toDouble() ?? 18.0,
      clubDistances: _parseAndroidClubDistances(json['clubDistances']),
      bagClubs: _parseAndroidBagClubs(json['bagClubs']),
      stockShape: json['stockShape'] as String? ?? 'STRAIGHT',
      woodsStockShape: json['woodsStockShape'] as String? ?? 'STRAIGHT',
      ironsStockShape: json['ironsStockShape'] as String? ?? 'STRAIGHT',
      hybridsStockShape: json['hybridsStockShape'] as String? ?? 'STRAIGHT',
      missTendency: json['missTendency'] as String? ?? 'NONE',
      aggressiveness: json['aggressiveness'] as String? ?? 'MODERATE',
      bunkerConfidence: json['bunkerConfidence'] as String? ?? 'MEDIUM',
      wedgeConfidence: json['wedgeConfidence'] as String? ?? 'MEDIUM',
      chipStyle: json['chipStyle'] as String? ?? 'BUMP_AND_RUN',
      swingTendency: json['swingTendency'] as String? ?? 'NEUTRAL',
      llmProvider: json['llmProvider'] as String? ?? 'OPENAI',
      llmModel: json['llmModel'] as String? ?? 'gpt-4o',
      userTier: json['userTier'] as String? ?? 'FREE',
      includeClubAlternatives:
          json['includeClubAlternatives'] as bool? ?? true,
      includeWindAdjustment:
          json['includeWindAdjustment'] as bool? ?? true,
      includeSlopeAdjustment:
          json['includeSlopeAdjustment'] as bool? ?? true,
      caddieVoiceGender: json['caddieGender'] as String? ?? 'MALE',
      caddieVoiceAccent: json['caddieAccent'] as String? ?? 'AMERICAN',
      caddiePersona: json['caddiePersona'] as String? ?? 'PROFESSIONAL',
      usesMetric: json['usesMetric'] as bool? ?? false,
      voiceEnabled: json['voiceEnabled'] as bool? ?? true,
      // Android's setupNoticeSeen is the closest analogue to
      // hasCompletedSwingOnboarding — both gate the first-run wizard.
      hasCompletedSwingOnboarding:
          json['setupNoticeSeen'] as bool? ?? false,
      // Android assumes a default bag and never gates on a separate
      // "configured bag" flag — migrate as true so the Profile screen
      // doesn't push the user back through bag setup.
      hasConfiguredBag: true,
      contactPromptSkipCount:
          (json['contactPromptCount'] as num?)?.toInt() ?? 0,
      contactPromptLastShownMs: _zeroToNull(
        (json['lastContactPromptMs'] as num?)?.toInt(),
      ),
      contactOptedIn: json['contactOptedIn'] as bool? ?? false,
      betaImageAnalysisEnabled:
          json['imageAnalysisBetaEnabled'] as bool? ?? false,
      telemetryEnabled: json['telemetryEnabled'] as bool? ?? true,
      scoringEnabled: json['scoringEnabled'] as bool? ?? false,
      preferredTeeBox: json['preferredTeeBox'] as String? ?? 'WHITE',
      ironType: json['ironType'] as String?,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );

    return ImportedProfile(
      profile: profile,
      secrets: {
        SecureKey.openAi: json['openAiApiKey'] as String?,
        SecureKey.claude: json['anthropicApiKey'] as String?,
        SecureKey.gemini: json['googleApiKey'] as String?,
      },
    );
  }

  // ─── Shot history ─────────────────────────────────────────────────

  /// Translates an iOS `[ShotRecord]` JSON blob (the value stored
  /// under `UserDefaults.standard.array(forKey: "shotHistory")`) into
  /// a list of Flutter `ShotHistoryEntry`. The iOS shape uses an
  /// ISO8601 string for `date`; we convert to epoch ms.
  List<ShotHistoryEntry> importIosShotHistory(List<dynamic> records) {
    return records
        .map((raw) => _importIosShotRecord((raw as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  ShotHistoryEntry _importIosShotRecord(Map<String, dynamic> json) {
    final ctxRaw = (json['context'] as Map).cast<String, dynamic>();
    return ShotHistoryEntry(
      id: json['id'] as String,
      timestampMs: _parseIsoDateMs(json['date']) ?? 0,
      // iOS records didn't track courseId/courseName at the entry
      // level — both fields land as null/empty.
      courseId: null,
      courseName: '',
      context: ShotContext(
        distanceYards: (ctxRaw['distanceYards'] as num?)?.toInt() ?? 150,
        shotType: ctxRaw['shotType'] as String? ?? 'approach',
        lieType: ctxRaw['lieType'] as String? ?? 'fairway',
        windStrength: ctxRaw['windStrength'] as String? ?? 'none',
        windDirection: ctxRaw['windDirection'] as String? ?? 'into',
        slope: ctxRaw['slope'] as String? ?? 'level',
        aggressiveness: ctxRaw['aggressiveness'] as String? ?? 'normal',
        hazardNotes: ctxRaw['hazardNotes'] as String? ?? '',
      ),
      recommendedClub: json['recommendedClub'] as String? ?? '',
      actualClubUsed: _emptyToNull(json['actualClubUsed'] as String?),
      effectiveDistance:
          (json['effectiveDistance'] as num?)?.toInt() ?? 0,
      target: json['target'] as String? ?? '',
      outcome: json['outcome'] as String? ?? 'unknown',
      notes: json['notes'] as String? ?? '',
    );
  }

  /// Translates an Android shot history list (DataStore JSON-encoded
  /// `List<ShotHistoryEntry>`) into Flutter ShotHistoryEntry. Android
  /// already uses epoch ms timestamps, so this is a near pass-through.
  List<ShotHistoryEntry> importAndroidShotHistory(List<dynamic> records) {
    return records
        .map((raw) =>
            _importAndroidShotRecord((raw as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  ShotHistoryEntry _importAndroidShotRecord(Map<String, dynamic> json) {
    final ctxRaw = (json['context'] as Map).cast<String, dynamic>();
    return ShotHistoryEntry(
      id: json['id'] as String,
      timestampMs: (json['timestampMs'] as num).toInt(),
      courseId: json['courseId'] as String?,
      courseName: json['courseName'] as String? ?? '',
      context: ShotContext(
        distanceYards: (ctxRaw['distanceYards'] as num?)?.toInt() ?? 150,
        shotType: ctxRaw['shotType'] as String? ?? 'APPROACH',
        lieType: ctxRaw['lieType'] as String? ?? 'FAIRWAY',
        windStrength: ctxRaw['windStrength'] as String? ?? 'NONE',
        windDirection: ctxRaw['windDirection'] as String? ?? 'INTO',
        slope: ctxRaw['slope'] as String? ?? 'LEVEL',
        aggressiveness: ctxRaw['aggressiveness'] as String? ?? 'MODERATE',
        hazardNotes: ctxRaw['hazardNotes'] as String? ?? '',
      ),
      // Android nests `recommendation` (with a `clubName` field)
      // instead of using a flat `recommendedClub` string. Pull the
      // club name out when present.
      recommendedClub: _androidRecommendedClub(json['recommendation']),
      actualClubUsed: json['actualClubUsed'] as String?,
      effectiveDistance: 0, // Android didn't surface this at the entry level
      target: '',
      outcome: json['outcome'] as String? ?? 'UNKNOWN',
      notes: json['notes'] as String? ?? '',
    );
  }

  // ─── Persistence orchestration ────────────────────────────────────

  /// Persists an imported profile + its secrets in one shot. The
  /// caller (the platform-channel bridge that lands in S16) calls
  /// this with the result of `importIosProfile`/`importAndroidProfile`.
  Future<void> persistImportedProfile(ImportedProfile imported) async {
    await profileRepository.save(imported.profile);
    await secureKeysStorage.writeAll(imported.secrets);
  }

  /// Persists a list of imported shot history entries.
  Future<void> persistImportedShotHistory(
    List<ShotHistoryEntry> entries,
  ) =>
      shotHistoryRepository.addAll(entries);

  // ─── Internal parsing helpers ─────────────────────────────────────

  /// iOS clubDistances is `[{ "club": "driver", "carryYards": 250 }, …]`.
  /// We collapse to `{ "driver": 250, … }`.
  Map<String, int> _parseIosClubDistances(dynamic raw) {
    if (raw is! List) return const {};
    final out = <String, int>{};
    for (final entry in raw) {
      if (entry is! Map) continue;
      final club = entry['club'];
      final carry = entry['carryYards'];
      if (club is String && carry is num) {
        out[club] = carry.toInt();
      }
    }
    return out;
  }

  /// Android clubDistances is `{ "DRIVER": 250, "SEVEN_IRON": 150, … }`.
  /// Pass through but coerce values to int.
  Map<String, int> _parseAndroidClubDistances(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((key, value) {
      if (key is String && value is num) {
        out[key] = value.toInt();
      }
    });
    return out;
  }

  /// Android bagClubs is a `Set<Club>` serialized as a JSON array of
  /// enum names like `["DRIVER", "FIVE_IRON", …]`.
  List<String> _parseAndroidBagClubs(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList(growable: false);
  }

  String _androidRecommendedClub(dynamic recommendation) {
    if (recommendation is! Map) return '';
    final club = recommendation['clubName'] ?? recommendation['club'];
    return club is String ? club : '';
  }

  /// Parses an iOS-emitted ISO8601 date string (or epoch seconds — the
  /// Swift `JSONEncoder` default) and returns epoch milliseconds.
  /// Returns null if the input can't be parsed.
  int? _parseIsoDateMs(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      // Swift's default Codable for Date is epoch seconds (Double).
      return (raw.toDouble() * 1000).toInt();
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return null;
  }

  int? _zeroToNull(int? value) =>
      (value == null || value == 0) ? null : value;

  String? _emptyToNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;
}
