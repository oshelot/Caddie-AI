//
//  CourseCacheAPIClient.swift
//  CaddieAI
//
//  Client for the server-side course geometry cache (S3-backed via
//  API Gateway + Lambda). Checks the shared cache before falling back
//  to the full Overpass/OSM ingestion pipeline, and uploads newly
//  ingested courses so future loads are instant.
//
//  Auth: "x-api-key: <api_key>" header
//

import Foundation

enum CourseCacheAPIClient {

    // MARK: - Search cached courses (fuzzy)

    /// Fuzzy-search the server cache by course name + optional coordinates.
    /// Returns `nil` on 404 (no match) — callers should fall through to Overpass.
    static func searchCourse(query: String, latitude: Double?, longitude: Double?,
                             schemaVersion: String = "1.0") async throws -> NormalizedCourse? {
        guard let endpoint = Secrets.courseCacheEndpoint, !endpoint.isEmpty,
              let apiKey = Secrets.courseCacheApiKey, !apiKey.isEmpty
        else { throw CourseCacheError.notConfigured }

        var components = URLComponents(string: "\(endpoint)/courses/search")
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "schema", value: schemaVersion),
        ]
        if let lat = latitude, let lon = longitude {
            queryItems.append(URLQueryItem(name: "lat", value: String(format: "%.4f", lat)))
            queryItems.append(URLQueryItem(name: "lon", value: String(format: "%.4f", lon)))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw CourseCacheError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CourseCacheError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return nil  // No match — not an error
        }

        guard httpResponse.statusCode == 200 else {
            throw CourseCacheError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NormalizedCourse.self, from: data)
    }

    // MARK: - Search manifest metadata (lightweight)

    /// Lightweight search that returns just manifest metadata (name, city, state)
    /// for matching courses — no full course data. Used to correct Nominatim
    /// city/state in search results before displaying.
    static func searchManifestMetadata(query: String) async throws -> [CourseManifestEntry] {
        guard let endpoint = Secrets.courseCacheEndpoint, !endpoint.isEmpty,
              let apiKey = Secrets.courseCacheApiKey, !apiKey.isEmpty
        else { throw CourseCacheError.notConfigured }

        var components = URLComponents(string: "\(endpoint)/courses/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "mode", value: "metadata"),
        ]

        guard let url = components?.url else {
            throw CourseCacheError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CourseCacheError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return []
        }

        guard httpResponse.statusCode == 200 else {
            throw CourseCacheError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode([CourseManifestEntry].self, from: data)
    }

    // MARK: - GET cached course (exact key)

    /// Fetch a cached course from the server using an exact key.
    /// Returns `nil` on 404 (cache miss) — callers should fall through to Overpass.
    static func getCourse(serverCacheKey: String, schemaVersion: String = "1.0") async throws -> NormalizedCourse? {
        guard let endpoint = Secrets.courseCacheEndpoint, !endpoint.isEmpty,
              let apiKey = Secrets.courseCacheApiKey, !apiKey.isEmpty
        else { throw CourseCacheError.notConfigured }

        let encodedKey = serverCacheKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? serverCacheKey
        guard let url = URL(string: "\(endpoint)/courses/\(encodedKey)?schema=\(schemaVersion)") else {
            throw CourseCacheError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CourseCacheError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return nil  // Cache miss — not an error
        }

        guard httpResponse.statusCode == 200 else {
            throw CourseCacheError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NormalizedCourse.self, from: data)
    }

    // MARK: - PUT course to cache

    /// Upload a course to the server cache using its name-only key.
    /// Errors are non-fatal — callers should catch and log rather than surfacing to the user.
    static func putCourse(_ course: NormalizedCourse) async throws {
        guard let endpoint = Secrets.courseCacheEndpoint, !endpoint.isEmpty,
              let apiKey = Secrets.courseCacheApiKey, !apiKey.isEmpty
        else { throw CourseCacheError.notConfigured }

        let cacheKey = course.serverCacheKey
        let encodedKey = cacheKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cacheKey
        guard let url = URL(string: "\(endpoint)/courses/\(encodedKey)?schema=\(course.schemaVersion)") else {
            throw CourseCacheError.invalidResponse
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(course)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CourseCacheError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CourseCacheError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Errors

/// Lightweight manifest entry returned by the metadata search endpoint.
struct CourseManifestEntry: Decodable {
    let name: String
    let city: String?
    let state: String?
    let lat: Double?
    let lon: Double?
    let courseId: String?
}

enum CourseCacheError: LocalizedError {
    case notConfigured
    case httpError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Course cache endpoint not configured"
        case .httpError(let code): return "Course cache error (HTTP \(code))"
        case .invalidResponse: return "Invalid response from course cache"
        }
    }
}
