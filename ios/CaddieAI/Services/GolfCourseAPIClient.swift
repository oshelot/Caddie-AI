//
//  GolfCourseAPIClient.swift
//  CaddieAI
//
//  Client for golfcourseapi.com — fetches scorecard data (par, yardages,
//  slope/rating, stroke index) to enrich OSM-sourced course models.
//
//  Auth: "Authorization: Key <api_key>"
//  Docs: https://api.golfcourseapi.com/docs/api/openapi.yml
//

import Foundation

enum GolfCourseAPIClient {

    private static let baseURL = "https://api.golfcourseapi.com/v1"

    // MARK: - Search by name

    static func searchCourses(name: String, apiKey: String) async throws -> [GolfCourseAPICourse] {
        guard !apiKey.isEmpty else { return [] }

        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [URLQueryItem(name: "search_query", value: name)]

        var request = URLRequest(url: components.url!)
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GolfCourseAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw GolfCourseAPIError.httpError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(GolfCourseAPISearchResponse.self, from: data)
        return decoded.courses
    }

    // MARK: - Get course detail by ID

    static func getCourse(id: Int, apiKey: String) async throws -> GolfCourseAPICourse? {
        guard !apiKey.isEmpty else { return nil }

        let urlString = "\(baseURL)/courses/\(id)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GolfCourseAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 { return nil }
            throw GolfCourseAPIError.httpError(httpResponse.statusCode)
        }

        let wrapper = try JSONDecoder().decode(GolfCourseAPICourseWrapper.self, from: data)
        return wrapper.course
    }
}

// MARK: - Response Types

struct GolfCourseAPICourseWrapper: Codable {
    var course: GolfCourseAPICourse
}

struct GolfCourseAPISearchResponse: Codable {
    var courses: [GolfCourseAPICourse]
}

struct GolfCourseAPICourse: Codable {
    var id: Int
    var clubName: String?
    var courseName: String?
    var location: GolfCourseAPILocation?
    var tees: GolfCourseAPITees?

    enum CodingKeys: String, CodingKey {
        case id
        case clubName = "club_name"
        case courseName = "course_name"
        case location, tees
    }

    var displayName: String {
        courseName ?? clubName ?? "Unknown"
    }
}

struct GolfCourseAPILocation: Codable {
    var address: String?
    var city: String?
    var state: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?
}

struct GolfCourseAPITees: Codable {
    var male: [GolfCourseAPITeeBox]?
    var female: [GolfCourseAPITeeBox]?

    /// All tee boxes combined
    var allTees: [GolfCourseAPITeeBox] {
        (male ?? []) + (female ?? [])
    }
}

struct GolfCourseAPITeeBox: Codable {
    var teeName: String?
    var courseRating: Double?
    var slopeRating: Int?
    var bogeyRating: Double?
    var totalYards: Int?
    var totalMeters: Int?
    var numberOfHoles: Int?
    var parTotal: Int?
    var frontCourseRating: Double?
    var frontSlopeRating: Int?
    var backCourseRating: Double?
    var backSlopeRating: Int?
    var holes: [GolfCourseAPIHole]?

    enum CodingKeys: String, CodingKey {
        case teeName = "tee_name"
        case courseRating = "course_rating"
        case slopeRating = "slope_rating"
        case bogeyRating = "bogey_rating"
        case totalYards = "total_yards"
        case totalMeters = "total_meters"
        case numberOfHoles = "number_of_holes"
        case parTotal = "par_total"
        case frontCourseRating = "front_course_rating"
        case frontSlopeRating = "front_slope_rating"
        case backCourseRating = "back_course_rating"
        case backSlopeRating = "back_slope_rating"
        case holes
    }
}

struct GolfCourseAPIHole: Codable {
    var par: Int?
    var yardage: Int?
    var handicap: Int?
}

// MARK: - Errors

enum GolfCourseAPIError: LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Golf Course API"
        case .httpError(let code): return "Golf Course API error (HTTP \(code))"
        }
    }
}

// MARK: - Scorecard Extraction

extension GolfCourseAPICourse {

    /// Extract structured scorecard data from all tee boxes.
    /// Deduplicates tees that share the same name (case-insensitive),
    /// merging male/female entries under a single canonical name.
    func extractScorecardData() -> ScorecardData {
        guard let tees = tees else { return ScorecardData() }

        let allTees = tees.allTees
        guard !allTees.isEmpty else { return ScorecardData() }

        var pars: [Int: Int] = [:]
        var strokeIndexes: [Int: Int] = [:]
        var teeYardages: [String: [Int: Int]] = [:]
        var teeBoxInfos: [TeeBoxInfo] = []

        // Track canonical tee names (case-insensitive) to merge male/female duplicates
        var canonicalNames: [String: String] = [:]  // lowercased -> first-seen casing

        for teeBox in allTees {
            let teeName = teeBox.teeName ?? "Unknown"
            let key = teeName.lowercased()

            // Resolve to canonical (first-seen) casing
            let canonical: String
            if let existing = canonicalNames[key] {
                canonical = existing
            } else {
                canonicalNames[key] = teeName
                canonical = teeName
            }

            // Only add tee box info for the first occurrence of this canonical name
            if !teeBoxInfos.contains(where: { $0.name == canonical }) {
                teeBoxInfos.append(TeeBoxInfo(
                    name: canonical,
                    slopeRating: teeBox.slopeRating.map(Double.init),
                    courseRating: teeBox.courseRating,
                    totalYards: teeBox.totalYards,
                    parTotal: teeBox.parTotal
                ))
            }

            // Per-hole data (merged under canonical name)
            guard let holes = teeBox.holes else { continue }
            for (index, hole) in holes.enumerated() {
                let holeNum = index + 1

                if let par = hole.par {
                    pars[holeNum] = par
                }
                if let handicap = hole.handicap {
                    strokeIndexes[holeNum] = handicap
                }
                if let yardage = hole.yardage {
                    teeYardages[canonical, default: [:]][holeNum] = yardage
                }
            }
        }

        return ScorecardData(
            pars: pars,
            strokeIndexes: strokeIndexes,
            teeYardages: teeYardages,
            teeBoxInfos: teeBoxInfos
        )
    }
}

struct TeeBoxInfo {
    var name: String
    var slopeRating: Double?
    var courseRating: Double?
    var totalYards: Int?
    var parTotal: Int?
}

struct ScorecardData {
    var pars: [Int: Int] = [:]
    var strokeIndexes: [Int: Int] = [:]
    /// Tee name -> (hole number -> yardage)
    var teeYardages: [String: [Int: Int]] = [:]
    var teeBoxInfos: [TeeBoxInfo] = []

    var isEmpty: Bool { pars.isEmpty && teeYardages.isEmpty }

    var totalPar: Int? {
        // Prefer tee box parTotal, fallback to summing hole pars
        if let firstTotal = teeBoxInfos.first?.parTotal {
            return firstTotal
        }
        guard !pars.isEmpty else { return nil }
        return pars.values.reduce(0, +)
    }
}
