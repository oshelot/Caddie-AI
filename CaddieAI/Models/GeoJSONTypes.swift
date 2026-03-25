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

// MARK: - Distance & Bearing Helpers

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

    /// Initial bearing in degrees (0-360) from this point to another
    func bearing(to other: GeoJSONPoint) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - LineString Geometry Helpers

extension GeoJSONLineString {
    /// Total path length in meters
    func totalDistance() -> Double {
        let pts = points
        guard pts.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count {
            total += pts[i - 1].distance(to: pts[i])
        }
        return total
    }

    /// Interpolated point at a given distance (meters) along the line
    func pointAtDistance(_ meters: Double) -> GeoJSONPoint? {
        let pts = points
        guard pts.count >= 2 else { return nil }

        var remaining = meters
        for i in 1..<pts.count {
            let segmentLength = pts[i - 1].distance(to: pts[i])
            if remaining <= segmentLength {
                let fraction = segmentLength > 0 ? remaining / segmentLength : 0
                let lat = pts[i - 1].latitude + fraction * (pts[i].latitude - pts[i - 1].latitude)
                let lon = pts[i - 1].longitude + fraction * (pts[i].longitude - pts[i - 1].longitude)
                return GeoJSONPoint(latitude: lat, longitude: lon)
            }
            remaining -= segmentLength
        }
        return pts.last
    }

    /// Bearing of the line at a given distance along it
    func bearingAtDistance(_ meters: Double) -> Double? {
        let pts = points
        guard pts.count >= 2 else { return nil }

        var remaining = meters
        for i in 1..<pts.count {
            let segmentLength = pts[i - 1].distance(to: pts[i])
            if remaining <= segmentLength {
                return pts[i - 1].bearing(to: pts[i])
            }
            remaining -= segmentLength
        }
        // Return bearing of last segment
        guard pts.count >= 2 else { return nil }
        return pts[pts.count - 2].bearing(to: pts[pts.count - 1])
    }

    /// Distance along the line from start to the nearest point to a given external point
    func distanceAlongLine(toNearestPointFrom point: GeoJSONPoint) -> Double {
        let pts = points
        guard pts.count >= 2 else { return 0 }

        var bestDist = Double.greatestFiniteMagnitude
        var bestAlong = 0.0
        var cumulativeDist = 0.0

        for i in 1..<pts.count {
            let segLen = pts[i - 1].distance(to: pts[i])
            let distToStart = point.distance(to: pts[i - 1])
            let distToEnd = point.distance(to: pts[i])

            // Project point onto segment
            if segLen > 0 {
                let dx = pts[i].longitude - pts[i - 1].longitude
                let dy = pts[i].latitude - pts[i - 1].latitude
                let px = point.longitude - pts[i - 1].longitude
                let py = point.latitude - pts[i - 1].latitude
                let t = max(0, min(1, (px * dx + py * dy) / (dx * dx + dy * dy)))
                let projLat = pts[i - 1].latitude + t * dy
                let projLon = pts[i - 1].longitude + t * dx
                let projPoint = GeoJSONPoint(latitude: projLat, longitude: projLon)
                let dist = point.distance(to: projPoint)
                if dist < bestDist {
                    bestDist = dist
                    bestAlong = cumulativeDist + t * segLen
                }
            }

            // Also check segment endpoints
            if distToStart < bestDist {
                bestDist = distToStart
                bestAlong = cumulativeDist
            }
            if distToEnd < bestDist {
                bestDist = distToEnd
                bestAlong = cumulativeDist + segLen
            }

            cumulativeDist += segLen
        }
        return bestAlong
    }
}

// MARK: - Cross Product Helper

/// Returns positive if point is to the left of the line from origin to target, negative if right
func crossProductSign(origin: GeoJSONPoint, target: GeoJSONPoint, point: GeoJSONPoint) -> Double {
    let dx1 = target.longitude - origin.longitude
    let dy1 = target.latitude - origin.latitude
    let dx2 = point.longitude - origin.longitude
    let dy2 = point.latitude - origin.latitude
    return dx1 * dy2 - dy1 * dx2
}
