//
//  CourseGeoJSONBuilder.swift
//  CaddieAI
//
//  Converts NormalizedCourse into Mapbox-compatible GeoJSON FeatureCollections.
//  Each feature type (green, tee, bunker, water, hole line, label, boundary)
//  gets a "type" property for layer filtering.
//

import Foundation
import CoreLocation
import MapboxMaps

enum CourseGeoJSONBuilder {

    // MARK: - Build all features for a course

    static func buildFeatureCollection(from course: NormalizedCourse) -> FeatureCollection {
        var features: [Feature] = []

        // Course boundary
        if let boundary = course.courseBoundary {
            features.append(buildPolygonFeature(boundary, type: "boundary"))
        }

        for hole in course.holes {
            // Hole line of play
            if let line = hole.lineOfPlay {
                features.append(buildLineFeature(line, type: "holeLine", holeNumber: hole.number))
            }

            // Green
            if let green = hole.green {
                features.append(buildPolygonFeature(green, type: "green", holeNumber: hole.number))
            }

            // Tee areas
            for tee in hole.teeAreas {
                features.append(buildPolygonFeature(tee, type: "tee", holeNumber: hole.number))
            }

            // Bunkers
            for bunker in hole.bunkers {
                features.append(buildPolygonFeature(bunker, type: "bunker", holeNumber: hole.number))
            }

            // Water
            for water in hole.water {
                features.append(buildPolygonFeature(water, type: "water", holeNumber: hole.number))
            }

            // Hole label (placed at green centroid or line midpoint)
            if let labelPoint = holeLabelPoint(for: hole) {
                features.append(buildPointFeature(labelPoint, type: "holeLabel", holeNumber: hole.number))
            }

            // Pin
            if let pin = hole.pin {
                features.append(buildPointFeature(pin, type: "pin", holeNumber: hole.number))
            }
        }

        return FeatureCollection(features: features)
    }

    // MARK: - Feature Builders

    private static func buildPolygonFeature(
        _ polygon: GeoJSONPolygon,
        type: String,
        holeNumber: Int? = nil
    ) -> Feature {
        let coords = polygon.coordinates.map { ring in
            ring.map { coord in
                LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
            }
        }
        var feature = Feature(geometry: .polygon(Polygon(coords)))
        var props: JSONObject = ["type": .string(type)]
        if let num = holeNumber {
            props["holeNumber"] = .number(Double(num))
        }
        feature.properties = props
        return feature
    }

    private static func buildLineFeature(
        _ line: GeoJSONLineString,
        type: String,
        holeNumber: Int? = nil
    ) -> Feature {
        let coords = line.coordinates.map { coord in
            LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
        }
        var feature = Feature(geometry: .lineString(LineString(coords)))
        var props: JSONObject = ["type": .string(type)]
        if let num = holeNumber {
            props["holeNumber"] = .number(Double(num))
        }
        feature.properties = props
        return feature
    }

    private static func buildPointFeature(
        _ point: GeoJSONPoint,
        type: String,
        holeNumber: Int? = nil
    ) -> Feature {
        let coord = LocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        var feature = Feature(geometry: .point(Point(coord)))
        var props: JSONObject = ["type": .string(type)]
        if let num = holeNumber {
            props["holeNumber"] = .number(Double(num))
            props["label"] = .string("\(num)")
        }
        feature.properties = props
        return feature
    }

    // MARK: - Helpers

    private static func holeLabelPoint(for hole: NormalizedHole) -> GeoJSONPoint? {
        // Prefer green centroid, fallback to line midpoint
        if let green = hole.green {
            return green.centroid
        }
        if let line = hole.lineOfPlay {
            let points = line.points
            guard !points.isEmpty else { return nil }
            let mid = points[points.count / 2]
            return mid
        }
        return nil
    }
}
