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

    // MARK: - GET cached course

    /// Fetch a cached course from the server.
    /// Returns `nil` on 404 (cache miss) — callers should fall through to Overpass.
    static func getCourse(id: String, schemaVersion: String = "1.0") async throws -> NormalizedCourse? {
        guard let endpoint = Secrets.courseCacheEndpoint, !endpoint.isEmpty,
              let apiKey = Secrets.courseCacheApiKey, !apiKey.isEmpty
        else { throw CourseCacheError.notConfigured }

        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: "\(endpoint)/courses/\(encodedId)?schema=\(schemaVersion)") else {
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

    /// Upload a course to the server cache. Errors are non-fatal — callers
    /// should catch and log rather than surfacing to the user.
    static func putCourse(_ course: NormalizedCourse) async throws {
        guard let endpoint = Secrets.courseCacheEndpoint, !endpoint.isEmpty,
              let apiKey = Secrets.courseCacheApiKey, !apiKey.isEmpty
        else { throw CourseCacheError.notConfigured }

        let encodedId = course.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? course.id
        guard let url = URL(string: "\(endpoint)/courses/\(encodedId)?schema=\(course.schemaVersion)") else {
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
