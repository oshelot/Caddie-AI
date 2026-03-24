//
//  GeoJSONTypes.swift
//  CaddieAI
//
//  Lightweight GeoJSON geometry types for course data.
//

import Foundation

// MARK: - Point

struct GeoJSONPoint: Codable, Sendable, Equatable {
    var latitude: Double
    var longitude: Double

    var coordinates: [Double] { [longitude, latitude] }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - LineString

struct GeoJSONLineString: Codable, Sendable {
    var coordinates: [[Double]]  // [[lon, lat], ...]

    var points: [GeoJSONPoint] {
        coordinates.compactMap { coord in
            guard coord.count >= 2 else { return nil }
            return GeoJSONPoint(latitude: coord[1], longitude: coord[0])
        }
    }

    var startPoint: GeoJSONPoint? { points.first }
    var endPoint: GeoJSONPoint? { points.last }
}

// MARK: - Polygon

struct GeoJSONPolygon: Codable, Sendable {
    var coordinates: [[[Double]]]  // [[[lon, lat], ...]] outer ring + optional holes

    var outerRing: [GeoJSONPoint] {
        (coordinates.first ?? []).compactMap { coord in
            guard coord.count >= 2 else { return nil }
            return GeoJSONPoint(latitude: coord[1], longitude: coord[0])
        }
    }

    var centroid: GeoJSONPoint {
        let ring = outerRing
        guard !ring.isEmpty else {
            return GeoJSONPoint(latitude: 0, longitude: 0)
        }
        let avgLat = ring.map(\.latitude).reduce(0, +) / Double(ring.count)
        let avgLon = ring.map(\.longitude).reduce(0, +) / Double(ring.count)
        return GeoJSONPoint(latitude: avgLat, longitude: avgLon)
    }
}

// MARK: - Distance Helpers

extension GeoJSONPoint {
    /// Haversine distance in meters between two points
    func distance(to other: GeoJSONPoint) -> Double {
        let R = 6371000.0 // Earth radius in meters
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }
}
