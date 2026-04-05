//
//  PlayerProfile.swift
//  CaddieAI
//

import Foundation
import SwiftUI

// MARK: - Club Distance

struct ClubDistance: Codable, Identifiable, Sendable {
    var id: Club { club }
    var club: Club
    var carryYards: Int
}

// MARK: - Player Profile

struct PlayerProfile: Codable, Sendable {
    var handicap: Double
    var stockShape: StockShape
    var missTendency: MissTendency
    var clubDistances: [ClubDistance]
    var defaultAggressiveness: Aggressiveness
    var apiKey: String
    var golfCourseApiKey: String
    var mapboxAccessToken: String

    // LLM provider selection
    var llmProvider: LLMProvider
    var llmModel: LLMModel
    var claudeApiKey: String
    var geminiApiKey: String

    // Telemetry
    var telemetryEnabled: Bool

    // Caddie voice & persona
    var caddieVoiceGender: CaddieVoiceGender
    var caddieVoiceAccent: CaddieVoiceAccent
    var caddiePersona: CaddiePersona

    // Phase 3: Player preferences
    var bunkerConfidence: SelfConfidence
    var wedgeConfidence: SelfConfidence
    var preferredChipStyle: ChipStyle
    var swingTendency: SwingTendency

    // Contact info ("Stay in Touch")
    var contactName: String
    var contactEmail: String
    var contactPhone: String

    // Per-category stock shapes
    var woodsStockShape: StockShape
    var ironsStockShape: StockShape
    var hybridsStockShape: StockShape

    // Swing onboarding
    var hasCompletedSwingOnboarding: Bool
    var hasConfiguredBag: Bool

    // Beta features
    var betaImageAnalysis: Bool

    // Tee box preference
    var preferredTeeBox: TeeBoxPreference

    // Scoring
    var scoringEnabled: Bool

    // Onboarding contact prompt tracking
    var contactPromptSkipCount: Int
    var contactPromptLastShown: Date?

    // Custom decoder for backward compatibility with saved profiles missing new fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handicap = try container.decode(Double.self, forKey: .handicap)
        stockShape = try container.decode(StockShape.self, forKey: .stockShape)
        missTendency = try container.decode(MissTendency.self, forKey: .missTendency)
        clubDistances = try container.decode([ClubDistance].self, forKey: .clubDistances)
        defaultAggressiveness = try container.decode(Aggressiveness.self, forKey: .defaultAggressiveness)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        golfCourseApiKey = try container.decodeIfPresent(String.self, forKey: .golfCourseApiKey) ?? ""
        mapboxAccessToken = try container.decodeIfPresent(String.self, forKey: .mapboxAccessToken) ?? ""
        llmProvider = try container.decodeIfPresent(LLMProvider.self, forKey: .llmProvider) ?? .openAI
        llmModel = try container.decodeIfPresent(LLMModel.self, forKey: .llmModel) ?? .gpt4o
        claudeApiKey = try container.decodeIfPresent(String.self, forKey: .claudeApiKey) ?? ""
        geminiApiKey = try container.decodeIfPresent(String.self, forKey: .geminiApiKey) ?? ""
        telemetryEnabled = try container.decodeIfPresent(Bool.self, forKey: .telemetryEnabled) ?? true
        caddieVoiceGender = try container.decodeIfPresent(CaddieVoiceGender.self, forKey: .caddieVoiceGender) ?? .female
        caddieVoiceAccent = try container.decodeIfPresent(CaddieVoiceAccent.self, forKey: .caddieVoiceAccent) ?? .american
        // Gracefully handle removed persona values (e.g. "britishCommentator")
        if let rawPersona = try container.decodeIfPresent(String.self, forKey: .caddiePersona),
           let persona = CaddiePersona(rawValue: rawPersona) {
            caddiePersona = persona
        } else {
            caddiePersona = .professional
        }
        bunkerConfidence = try container.decodeIfPresent(SelfConfidence.self, forKey: .bunkerConfidence) ?? .average
        wedgeConfidence = try container.decodeIfPresent(SelfConfidence.self, forKey: .wedgeConfidence) ?? .average
        preferredChipStyle = try container.decodeIfPresent(ChipStyle.self, forKey: .preferredChipStyle) ?? .noPreference
        swingTendency = try container.decodeIfPresent(SwingTendency.self, forKey: .swingTendency) ?? .neutral
        contactName = try container.decodeIfPresent(String.self, forKey: .contactName) ?? ""
        contactEmail = try container.decodeIfPresent(String.self, forKey: .contactEmail) ?? ""
        contactPhone = try container.decodeIfPresent(String.self, forKey: .contactPhone) ?? ""
        woodsStockShape = try container.decodeIfPresent(StockShape.self, forKey: .woodsStockShape) ?? stockShape
        ironsStockShape = try container.decodeIfPresent(StockShape.self, forKey: .ironsStockShape) ?? stockShape
        hybridsStockShape = try container.decodeIfPresent(StockShape.self, forKey: .hybridsStockShape) ?? stockShape
        hasCompletedSwingOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedSwingOnboarding) ?? true
        hasConfiguredBag = try container.decodeIfPresent(Bool.self, forKey: .hasConfiguredBag) ?? true
        betaImageAnalysis = try container.decodeIfPresent(Bool.self, forKey: .betaImageAnalysis) ?? false
        preferredTeeBox = try container.decodeIfPresent(TeeBoxPreference.self, forKey: .preferredTeeBox) ?? .white
        scoringEnabled = try container.decodeIfPresent(Bool.self, forKey: .scoringEnabled) ?? false
        contactPromptSkipCount = try container.decodeIfPresent(Int.self, forKey: .contactPromptSkipCount) ?? 0
        contactPromptLastShown = try container.decodeIfPresent(Date.self, forKey: .contactPromptLastShown)
    }

    init(handicap: Double, stockShape: StockShape, missTendency: MissTendency, clubDistances: [ClubDistance], defaultAggressiveness: Aggressiveness, apiKey: String, golfCourseApiKey: String = "", mapboxAccessToken: String = "", llmProvider: LLMProvider = .openAI, llmModel: LLMModel = .gpt4o, claudeApiKey: String = "", geminiApiKey: String = "", telemetryEnabled: Bool = true, caddieVoiceGender: CaddieVoiceGender = .female, caddieVoiceAccent: CaddieVoiceAccent = .american, caddiePersona: CaddiePersona = .professional, bunkerConfidence: SelfConfidence = .average, wedgeConfidence: SelfConfidence = .average, preferredChipStyle: ChipStyle = .noPreference, swingTendency: SwingTendency = .neutral, woodsStockShape: StockShape = .straight, ironsStockShape: StockShape = .straight, hybridsStockShape: StockShape = .straight, hasCompletedSwingOnboarding: Bool = false, hasConfiguredBag: Bool = false, contactName: String = "", contactEmail: String = "", contactPhone: String = "", betaImageAnalysis: Bool = false, preferredTeeBox: TeeBoxPreference = .white, scoringEnabled: Bool = false, contactPromptSkipCount: Int = 0, contactPromptLastShown: Date? = nil) {
        self.handicap = handicap
        self.stockShape = stockShape
        self.missTendency = missTendency
        self.clubDistances = clubDistances
        self.defaultAggressiveness = defaultAggressiveness
        self.apiKey = apiKey
        self.golfCourseApiKey = golfCourseApiKey
        self.mapboxAccessToken = mapboxAccessToken
        self.llmProvider = llmProvider
        self.llmModel = llmModel
        self.claudeApiKey = claudeApiKey
        self.geminiApiKey = geminiApiKey
        self.telemetryEnabled = telemetryEnabled
        self.caddieVoiceGender = caddieVoiceGender
        self.caddieVoiceAccent = caddieVoiceAccent
        self.caddiePersona = caddiePersona
        self.bunkerConfidence = bunkerConfidence
        self.wedgeConfidence = wedgeConfidence
        self.preferredChipStyle = preferredChipStyle
        self.swingTendency = swingTendency
        self.woodsStockShape = woodsStockShape
        self.ironsStockShape = ironsStockShape
        self.hybridsStockShape = hybridsStockShape
        self.hasCompletedSwingOnboarding = hasCompletedSwingOnboarding
        self.hasConfiguredBag = hasConfiguredBag
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.betaImageAnalysis = betaImageAnalysis
        self.preferredTeeBox = preferredTeeBox
        self.scoringEnabled = scoringEnabled
        self.contactPromptSkipCount = contactPromptSkipCount
        self.contactPromptLastShown = contactPromptLastShown
    }

    /// Returns the API key for the currently selected LLM provider.
    var activeLLMApiKey: String {
        switch llmProvider {
        case .openAI: return apiKey
        case .claude: return claudeApiKey
        case .gemini: return geminiApiKey
        }
    }

    /// Returns the stock shape for the given club's category.
    func stockShapeForClub(_ club: Club) -> StockShape {
        switch club.category {
        case .woods: return woodsStockShape
        case .hybrids: return hybridsStockShape
        case .irons: return ironsStockShape
        }
    }

    static var `default`: PlayerProfile {
        PlayerProfile(
            handicap: 15.0,
            stockShape: .fade,
            missTendency: .right,
            clubDistances: Club.defaultBag.map {
                ClubDistance(club: $0, carryYards: $0.defaultCarryYards)
            },
            defaultAggressiveness: .normal,
            apiKey: "",
            bunkerConfidence: .average,
            wedgeConfidence: .average,
            preferredChipStyle: .noPreference,
            swingTendency: .neutral,
            hasCompletedSwingOnboarding: false,
            hasConfiguredBag: false
        )
    }
}

// MARK: - Profile Store

@Observable
final class ProfileStore {
    var profile: PlayerProfile {
        didSet { save() }
    }

    private static let storageKey = "playerProfile"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(PlayerProfile.self, from: data) {
            // If saved profile has an empty API key, fill in the default
            if decoded.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                var updated = decoded
                updated.apiKey = PlayerProfile.default.apiKey
                self.profile = updated
            } else {
                self.profile = decoded
            }
        } else {
            self.profile = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
