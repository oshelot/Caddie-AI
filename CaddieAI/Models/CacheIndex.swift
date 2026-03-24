//
//  CacheIndex.swift
//  CaddieAI
//
//  Index of cached normalized course models.
//

import Foundation

// MARK: - Cache Index

struct CourseCacheIndex: Codable, Sendable {
    var schemaVersion: String = NormalizedCourse.currentSchemaVersion
    var entries: [CourseCacheEntry]
}

// MARK: - Cache Entry

struct CourseCacheEntry: Codable, Sendable, Identifiable {
    var id: String               // matches NormalizedCourse.id
    var name: String
    var city: String?
    var state: String?
    var centroid: GeoJSONPoint
    var cachedAt: Date
    var schemaVersion: String
    var fileName: String         // "course_<hash>.json"
    var overallConfidence: Double
}
