//
//  ShotRecommendation.swift
//  CaddieAI
//

import Foundation

struct ShotRecommendation: Codable, Sendable, Identifiable {
    var id = UUID()
    var club: String
    var effectiveDistanceYards: Int
    var target: String
    var preferredMiss: String
    var riskLevel: RiskLevel
    var confidence: ConfidenceLevel
    var rationale: [String]
    var conservativeOption: String?
    var swingThought: String
    var executionPlan: ExecutionPlan?

    enum CodingKeys: String, CodingKey {
        case club
        case effectiveDistanceYards
        case target
        case preferredMiss
        case riskLevel
        case confidence
        case rationale
        case conservativeOption
        case swingThought
        case executionPlan
    }

    static var mock: ShotRecommendation {
        ShotRecommendation(
            club: "7 Iron",
            effectiveDistanceYards: 161,
            target: "Center of green, favoring the left side",
            preferredMiss: "Short and left, away from the bunker right",
            riskLevel: .medium,
            confidence: .high,
            rationale: [
                "161 effective yards fits your 7 iron carry",
                "Light wind into adds 5 yards to the playing distance",
                "Fairway lie gives clean contact"
            ],
            conservativeOption: "8 iron to front edge, two-putt from there.",
            swingThought: "Smooth tempo, full shoulder turn, trust the club.",
            executionPlan: .mock
        )
    }
}
