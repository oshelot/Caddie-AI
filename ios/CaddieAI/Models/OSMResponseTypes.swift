//
//  OSMResponseTypes.swift
//  CaddieAI
//
//  Raw Overpass API response DTOs. Transient — not persisted.
//

import Foundation

// MARK: - Overpass Response

struct OverpassResponse: Codable, Sendable {
    let elements: [OverpassElement]
}

// MARK: - Element

struct OverpassElement: Codable, Sendable {
    let type: String        // "node", "way", "relation"
    let id: Int64
    let lat: Double?        // only for nodes
    let lon: Double?        // only for nodes
    let tags: [String: String]?
    let nodes: [Int64]?     // for ways (when not using out:geom)
    let members: [OverpassMember]?
    let geometry: [OverpassGeomNode]?  // when using out:geom
}

// MARK: - Relation Member

struct OverpassMember: Codable, Sendable {
    let type: String
    let ref: Int64
    let role: String?
    let geometry: [OverpassGeomNode]?
}

// MARK: - Geometry Node (inline coordinates from out:geom)

struct OverpassGeomNode: Codable, Sendable {
    let lat: Double
    let lon: Double
}
