//
//  OSMParser.swift
//  CaddieAI
//
//  Parses raw Overpass API responses into intermediate feature DTOs.
//  Clean seam between raw OSM structure and normalized app models.
//

import Foundation

struct OSMParser {

    // MARK: - Intermediate Feature DTOs

    struct ParsedFeatures: Sendable {
        var courseBoundary: GeoJSONPolygon?
        var courseName: String?
        var holeLines: [ParsedHoleLine]
        var greens: [ParsedGreen]
        var tees: [ParsedTee]
        var pins: [ParsedPin]
        var bunkers: [ParsedBunker]
        var waterFeatures: [ParsedWater]
    }

    struct ParsedHoleLine: Sendable {
        var osmId: Int64
        var number: Int?
        var par: Int?
        var geometry: GeoJSONLineString
    }

    struct ParsedGreen: Sendable {
        var osmId: Int64
        var holeNumber: Int?
        var geometry: GeoJSONPolygon
    }

    struct ParsedTee: Sendable {
        var osmId: Int64
        var holeNumber: Int?
        var geometry: GeoJSONPolygon
    }

    struct ParsedPin: Sendable {
        var osmId: Int64
        var holeNumber: Int?
        var location: GeoJSONPoint
    }

    struct ParsedBunker: Sendable {
        var osmId: Int64
        var geometry: GeoJSONPolygon
    }

    struct ParsedWater: Sendable {
        var osmId: Int64
        var geometry: GeoJSONPolygon
    }

    // MARK: - Parse Raw Response

    static func parse(_ response: OverpassResponse) -> ParsedFeatures {
        var features = ParsedFeatures(
            holeLines: [],
            greens: [],
            tees: [],
            pins: [],
            bunkers: [],
            waterFeatures: []
        )

        for element in response.elements {
            let tags = element.tags ?? [:]

            // Course boundary
            if tags["leisure"] == "golf_course" {
                if let poly = extractPolygon(from: element) {
                    features.courseBoundary = poly
                    features.courseName = tags["name"]
                }
                continue
            }

            // Hole line of play
            if tags["golf"] == "hole" {
                if let line = extractLineString(from: element) {
                    let number = parseHoleNumber(from: tags)
                    let par = Int(tags["par"] ?? "")
                    features.holeLines.append(ParsedHoleLine(
                        osmId: element.id,
                        number: number,
                        par: par,
                        geometry: line
                    ))
                }
                continue
            }

            // Green
            if tags["golf"] == "green" {
                if let poly = extractPolygon(from: element) {
                    features.greens.append(ParsedGreen(
                        osmId: element.id,
                        holeNumber: parseHoleNumber(from: tags),
                        geometry: poly
                    ))
                }
                continue
            }

            // Tee
            if tags["golf"] == "tee" {
                if let poly = extractPolygon(from: element) {
                    features.tees.append(ParsedTee(
                        osmId: element.id,
                        holeNumber: parseHoleNumber(from: tags),
                        geometry: poly
                    ))
                }
                continue
            }

            // Pin
            if tags["golf"] == "pin" {
                if let point = extractPoint(from: element) {
                    features.pins.append(ParsedPin(
                        osmId: element.id,
                        holeNumber: parseHoleNumber(from: tags),
                        location: point
                    ))
                }
                continue
            }

            // Bunker
            if tags["golf"] == "bunker" {
                if let poly = extractPolygon(from: element) {
                    features.bunkers.append(ParsedBunker(
                        osmId: element.id,
                        geometry: poly
                    ))
                }
                continue
            }

            // Water
            if tags["natural"] == "water" || tags["water"] != nil {
                if let poly = extractPolygon(from: element) {
                    features.waterFeatures.append(ParsedWater(
                        osmId: element.id,
                        geometry: poly
                    ))
                }
                // Also handle relation members for multipolygon water
                if element.type == "relation", let members = element.members {
                    for member in members {
                        if let geom = member.geometry, geom.count >= 3 {
                            var coords = geom.map { [$0.lon, $0.lat] }
                            if coords.first != coords.last { coords.append(coords[0]) }
                            let poly = GeoJSONPolygon(coordinates: [coords])
                            features.waterFeatures.append(ParsedWater(
                                osmId: member.ref,
                                geometry: poly
                            ))
                        }
                    }
                }
                continue
            }
        }

        return features
    }

    // MARK: - Geometry Extraction

    private static func extractLineString(from element: OverpassElement) -> GeoJSONLineString? {
        guard let geomNodes = element.geometry, geomNodes.count >= 2 else { return nil }
        let coords = geomNodes.map { [$0.lon, $0.lat] }
        return GeoJSONLineString(coordinates: coords)
    }

    private static func extractPolygon(from element: OverpassElement) -> GeoJSONPolygon? {
        guard let geomNodes = element.geometry, geomNodes.count >= 3 else { return nil }
        var coords = geomNodes.map { [$0.lon, $0.lat] }
        // Ensure ring is closed
        if let first = coords.first, let last = coords.last, first != last {
            coords.append(first)
        }
        return GeoJSONPolygon(coordinates: [coords])
    }

    private static func extractPoint(from element: OverpassElement) -> GeoJSONPoint? {
        if let lat = element.lat, let lon = element.lon {
            return GeoJSONPoint(latitude: lat, longitude: lon)
        }
        // Fallback: centroid of geometry if present
        if let geomNodes = element.geometry, !geomNodes.isEmpty {
            let avgLat = geomNodes.map(\.lat).reduce(0, +) / Double(geomNodes.count)
            let avgLon = geomNodes.map(\.lon).reduce(0, +) / Double(geomNodes.count)
            return GeoJSONPoint(latitude: avgLat, longitude: avgLon)
        }
        return nil
    }

    // MARK: - Tag Helpers

    private static func parseHoleNumber(from tags: [String: String]) -> Int? {
        // Try "ref" first (standard OSM tag for hole number)
        if let ref = tags["ref"], let num = Int(ref) { return num }
        // Try "hole" tag
        if let hole = tags["hole"], let num = Int(hole) { return num }
        // Try extracting from name (e.g., "Hole 5")
        if let name = tags["name"] {
            let digits = name.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let num = Int(digits), (1...18).contains(num) { return num }
        }
        return nil
    }
}
