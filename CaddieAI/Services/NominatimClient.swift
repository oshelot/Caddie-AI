//
//  NominatimClient.swift
//  CaddieAI
//
//  Fast golf course search using OpenStreetMap's Nominatim geocoder.
//  Returns results in ~200-500ms vs 5-30s+ for Overpass name searches.
//

import Foundation

enum NominatimClient {

    static let endpoint = URL(string: "https://nominatim.openstreetmap.org/search")!

    struct NominatimError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Search Golf Courses

    static func searchCourses(
        name: String,
        countryCode: String? = nil
    ) async throws -> [CourseSearchResult] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "golf course \(name)"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "extratags", value: "1"),
        ]

        if let cc = countryCode, !cc.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "countrycodes", value: cc))
        }

        guard let url = components.url else {
            throw NominatimError(message: "Invalid search URL.")
        }

        var request = URLRequest(url: url)
        request.setValue("CaddieAI/1.0 (iOS golf caddie app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NominatimError(message: "Nominatim returned HTTP \(code)")
        }

        let decoded = try JSONDecoder().decode([NominatimResult].self, from: data)

        return decoded
            .filter { isGolfCourse($0) }
            .compactMap { result -> CourseSearchResult? in
                guard let lat = Double(result.lat),
                      let lon = Double(result.lon) else { return nil }

                let courseName = extractCourseName(from: result)
                let bbox = parseBoundingBox(result.boundingbox)
                let centroid = GeoJSONPoint(latitude: lat, longitude: lon)

                return CourseSearchResult(
                    id: "\(result.osm_type ?? "node")\(result.osm_id)",
                    name: courseName,
                    city: result.address?["city"]
                        ?? result.address?["town"]
                        ?? result.address?["village"],
                    state: result.address?["state"],
                    centroid: centroid,
                    boundingBox: bbox,
                    isCached: false
                )
            }
    }

    // MARK: - Response Types

    private struct NominatimResult: Decodable {
        let place_id: Int
        let osm_type: String?
        let osm_id: Int64
        let lat: String
        let lon: String
        let display_name: String
        let `class`: String?
        let type: String?
        let importance: Double?
        let boundingbox: [String]?      // [south, north, west, east] as strings
        let address: [String: String]?
        let extratags: [String: String]?
    }

    // MARK: - Helpers

    private static func isGolfCourse(_ result: NominatimResult) -> Bool {
        // Primary: OSM class/type match
        if result.type == "golf_course" { return true }
        if result.`class` == "leisure" && result.type == "golf_course" { return true }

        // Secondary: name contains "golf" (for results tagged differently)
        let name = result.display_name.lowercased()
        if name.contains("golf course") || name.contains("golf club") || name.contains("golf links") {
            return true
        }

        return false
    }

    private static func extractCourseName(from result: NominatimResult) -> String {
        // Use the first component of display_name (before the first comma)
        let full = result.display_name
        if let commaIndex = full.firstIndex(of: ",") {
            return String(full[full.startIndex..<commaIndex]).trimmingCharacters(in: .whitespaces)
        }
        return full
    }

    private static func parseBoundingBox(_ bbox: [String]?) -> CourseBoundingBox? {
        // Nominatim returns [south, north, west, east] as strings
        guard let bbox, bbox.count == 4,
              let south = Double(bbox[0]),
              let north = Double(bbox[1]),
              let west = Double(bbox[2]),
              let east = Double(bbox[3]) else { return nil }

        return CourseBoundingBox(south: south, west: west, north: north, east: east)
    }
}
