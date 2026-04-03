//
//  CourseSearchResult.swift
//  CaddieAI
//
//  Search result for the course selection UI.
//

import Foundation

enum CourseSearchSource: String, Codable, Sendable {
    case osm          // Found in OpenStreetMap (Nominatim) — full geometry likely available
    case appleMapKit  // Found via Apple Maps only — geometry may be limited or absent
}

struct CourseSearchResult: Codable, Sendable, Identifiable {
    var id: String            // OSM element ID or synthetic ID
    var name: String
    var city: String?
    var state: String?
    var centroid: GeoJSONPoint
    var boundingBox: CourseBoundingBox?
    var isCached: Bool
    var source: CourseSearchSource = .osm
}
