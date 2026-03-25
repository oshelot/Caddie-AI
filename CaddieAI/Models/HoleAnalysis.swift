//
//  HoleAnalysis.swift
//  CaddieAI
//
//  Result model for hole geometry analysis and strategic advice.
//

import Foundation

// MARK: - Hole Analysis Result

struct HoleAnalysis: Codable, Sendable {
    var holeNumber: Int
    var par: Int?
    var totalDistanceYards: Int?
    var yardagesByTee: [String: Int]?
    var dogleg: DoglegInfo?
    var fairwayWidthAtLandingYards: Int?
    var greenDepthYards: Int?
    var greenWidthYards: Int?
    var hazards: [HoleHazardInfo]
    var strategicAdvice: String?
    var deterministicSummary: String
}

// MARK: - Dogleg Info

struct DoglegInfo: Codable, Sendable {
    var direction: DoglegDirection
    var distanceFromTeeYards: Int
    var bendAngleDegrees: Double
}

enum DoglegDirection: String, Codable, Sendable {
    case left, right

    var displayName: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        }
    }
}

// MARK: - Hazard Info

struct HoleHazardInfo: Codable, Sendable {
    var type: HazardType
    var side: HazardSide
    var distanceFromTeeYards: Int?
    var description: String
}

enum HazardType: String, Codable, Sendable {
    case water, bunker

    var displayName: String {
        switch self {
        case .water: return "Water"
        case .bunker: return "Bunker"
        }
    }
}

enum HazardSide: String, Codable, Sendable {
    case left, right, crossing, greenside, frontOfGreen

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .crossing: return "Crossing"
        case .greenside: return "Greenside"
        case .frontOfGreen: return "Front of green"
        }
    }
}
