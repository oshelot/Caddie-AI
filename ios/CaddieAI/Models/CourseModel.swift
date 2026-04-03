//
//  CourseModel.swift
//  CaddieAI
//
//  Canonical normalized course representation.
//

import Foundation

// MARK: - Normalized Course

struct NormalizedCourse: Codable, Sendable, Identifiable {
    var id: String
    var schemaVersion: String = NormalizedCourse.currentSchemaVersion
    var source: CourseSource
    var name: String
    var city: String?
    var state: String?
    var country: String?
    var centroid: GeoJSONPoint
    var boundingBox: CourseBoundingBox
    var holes: [NormalizedHole]
    var courseBoundary: GeoJSONPolygon?
    var stats: CourseStats

    /// Display label when this is a sub-course within a larger facility
    /// e.g., "Main Course", "Par 3 Course", "Red Nine"
    var subCourseName: String?

    /// Scorecard metadata from Golf Course API
    var totalPar: Int?
    var slopeRating: Double?
    var courseRating: Double?
    var teeNames: [String]?
    /// Total yardage per tee box name from Golf Course API (e.g., ["Blue": 6543, "White": 6021])
    var teeYardageTotals: [String: Int]?

    static let currentSchemaVersion = "1.0"
}

// MARK: - Source Provenance

struct CourseSource: Codable, Sendable {
    var provider: String   // "osm" — pluggable for future commercial sources
    var fetchedAt: Date
    var osmCourseId: String?
    var overpassQueryHash: String?
}

// MARK: - Bounding Box

struct CourseBoundingBox: Codable, Sendable {
    var south: Double
    var west: Double
    var north: Double
    var east: Double

    var asArray: [Double] { [south, west, north, east] }

    /// Expand the bbox by a factor (e.g., 0.002 ≈ ~200m)
    func buffered(by delta: Double) -> CourseBoundingBox {
        CourseBoundingBox(
            south: south - delta,
            west: west - delta,
            north: north + delta,
            east: east + delta
        )
    }
}

// MARK: - Course Stats

struct CourseStats: Codable, Sendable {
    var holesDetected: Int
    var greensDetected: Int
    var teesDetected: Int
    var bunkersDetected: Int
    var waterFeaturesDetected: Int
    var overallConfidence: Double  // 0.0...1.0
}

// MARK: - Course ID Generator

extension NormalizedCourse {
    /// Deterministic ID from normalized name + centroid
    static func generateId(name: String, centroid: GeoJSONPoint) -> String {
        let normalized = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
        let latStr = String(format: "%.4f", centroid.latitude)
        let lonStr = String(format: "%.4f", centroid.longitude)
        return "\(normalized)_\(latStr)_\(lonStr)_osm-v\(currentSchemaVersion)"
    }
}
