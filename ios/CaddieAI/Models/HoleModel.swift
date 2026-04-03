//
//  HoleModel.swift
//  CaddieAI
//
//  Normalized hole representation with confidence scoring.
//

import Foundation

// MARK: - Normalized Hole

struct NormalizedHole: Codable, Sendable, Identifiable {
    var id: String           // "hole_1", "hole_2", etc.
    var number: Int
    var par: Int?
    var strokeIndex: Int?
    /// Yardages keyed by tee name (e.g., "Blue": 425, "White": 410)
    var yardages: [String: Int]?
    var confidence: Double   // 0.0...1.0
    var lineOfPlay: GeoJSONLineString?
    var teeAreas: [GeoJSONPolygon]
    var green: GeoJSONPolygon?
    var pin: GeoJSONPoint?
    var bunkers: [GeoJSONPolygon]
    var water: [GeoJSONPolygon]
    var confidenceBreakdown: HoleConfidenceBreakdown?

    /// Raw OSM IDs for debugging/traceability
    var rawRefs: HoleRawRefs?
}

// MARK: - Confidence Breakdown

struct HoleConfidenceBreakdown: Codable, Sendable {
    var holePath: Double          // weight: 0.35
    var green: Double             // weight: 0.30
    var tee: Double               // weight: 0.15
    var holeNumber: Double        // weight: 0.10
    var hazards: Double           // weight: 0.05
    var geometryConsistency: Double // weight: 0.05

    var weighted: Double {
        holePath * 0.35 +
        green * 0.30 +
        tee * 0.15 +
        holeNumber * 0.10 +
        hazards * 0.05 +
        geometryConsistency * 0.05
    }
}

// MARK: - Raw References

struct HoleRawRefs: Codable, Sendable {
    var holeWayId: Int64?
    var greenWayId: Int64?
    var teeIds: [Int64]
}
