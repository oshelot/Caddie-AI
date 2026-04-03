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
    var weather: HoleWeatherContext?
    var strategicAdvice: String?
    var deterministicSummary: String
}

// MARK: - Weather Context (hole-specific)

struct HoleWeatherContext: Codable, Sendable {
    var temperatureF: Int
    var windSpeedMph: Int
    var windCompassDirection: String
    var windRelativeToHole: WindDirection
    var windStrength: WindStrength
    var conditionDescription: String
    var holeBearingDegrees: Double

    var summaryText: String {
        if windStrength == .none {
            return "\(temperatureF)\u{00B0}F, \(conditionDescription), calm wind"
        }
        return "\(temperatureF)\u{00B0}F, \(conditionDescription), \(windSpeedMph) mph \(windCompassDirection) wind (\(windRelativeToHole.displayName.lowercased()) on this hole)"
    }
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
