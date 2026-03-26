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

    // Phase 3: Player preferences
    var bunkerConfidence: SelfConfidence
    var wedgeConfidence: SelfConfidence
    var preferredChipStyle: ChipStyle
    var swingTendency: SwingTendency

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
        bunkerConfidence = try container.decodeIfPresent(SelfConfidence.self, forKey: .bunkerConfidence) ?? .average
        wedgeConfidence = try container.decodeIfPresent(SelfConfidence.self, forKey: .wedgeConfidence) ?? .average
        preferredChipStyle = try container.decodeIfPresent(ChipStyle.self, forKey: .preferredChipStyle) ?? .noPreference
        swingTendency = try container.decodeIfPresent(SwingTendency.self, forKey: .swingTendency) ?? .neutral
    }

    init(handicap: Double, stockShape: StockShape, missTendency: MissTendency, clubDistances: [ClubDistance], defaultAggressiveness: Aggressiveness, apiKey: String, golfCourseApiKey: String = "", bunkerConfidence: SelfConfidence = .average, wedgeConfidence: SelfConfidence = .average, preferredChipStyle: ChipStyle = .noPreference, swingTendency: SwingTendency = .neutral) {
        self.handicap = handicap
        self.stockShape = stockShape
        self.missTendency = missTendency
        self.clubDistances = clubDistances
        self.defaultAggressiveness = defaultAggressiveness
        self.apiKey = apiKey
        self.golfCourseApiKey = golfCourseApiKey
        self.bunkerConfidence = bunkerConfidence
        self.wedgeConfidence = wedgeConfidence
        self.preferredChipStyle = preferredChipStyle
        self.swingTendency = swingTendency
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
            swingTendency: .neutral
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
