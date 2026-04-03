//
//  OverpassClient.swift
//  CaddieAI
//
//  HTTP client for OpenStreetMap Overpass API.
//  Used only for fetching detailed golf geometry within a known bounding box.
//  Course search/discovery is handled by NominatimClient.
//

import Foundation

enum OverpassClient {

    // Primary endpoint (no rate limits, fast)
    private static let primaryEndpoint = URL(string: "https://overpass.private.coffee/api/interpreter")!
    // Fallback endpoint
    private static let fallbackEndpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    struct OverpassError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Fetch Golf Features Within Course Area

    static func fetchCourseFeatures(
        boundingBox: CourseBoundingBox
    ) async throws -> OverpassResponse {
        let bbox = boundingBox.buffered(by: 0.002) // ~200m buffer
        let bboxStr = "\(bbox.south),\(bbox.west),\(bbox.north),\(bbox.east)"

        let query = """
        [out:json][timeout:45];
        (
          way["golf"="hole"](\(bboxStr));
          way["golf"="green"](\(bboxStr));
          way["golf"="tee"](\(bboxStr));
          node["golf"="pin"](\(bboxStr));
          way["golf"="bunker"](\(bboxStr));
          way["natural"="water"](\(bboxStr));
          relation["natural"="water"](\(bboxStr));
          way["golf"="fairway"](\(bboxStr));
        );
        out geom;
        """

        return try await executeQueryWithFallback(query)
    }

    // MARK: - Query Execution with Fallback

    private static func executeQueryWithFallback(_ query: String) async throws -> OverpassResponse {
        do {
            return try await executeQuery(query, endpoint: primaryEndpoint)
        } catch {
            // Try fallback endpoint
            return try await executeQuery(query, endpoint: fallbackEndpoint)
        }
    }

    private static func executeQuery(
        _ query: String,
        endpoint: URL,
        maxRetries: Int = 2,
        timeoutSeconds: TimeInterval = 45
    ) async throws -> OverpassResponse {
        var lastError: Error?

        for attempt in 0...maxRetries {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(Double(attempt) * 2))
            }

            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                request.httpBody = "data=\(encoded)".data(using: .utf8)
                request.timeoutInterval = timeoutSeconds

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw OverpassError(message: "Invalid response from Overpass.")
                }

                if http.statusCode == 429 || http.statusCode == 504 {
                    lastError = OverpassError(message: "Overpass rate limited or timed out (HTTP \(http.statusCode)).")
                    continue
                }

                guard http.statusCode == 200 else {
                    throw OverpassError(message: "Overpass API error: HTTP \(http.statusCode)")
                }

                return try JSONDecoder().decode(OverpassResponse.self, from: data)

            } catch let error as OverpassError {
                lastError = error
            } catch is DecodingError {
                throw OverpassError(message: "Could not decode Overpass response.")
            } catch {
                lastError = error
            }
        }

        throw lastError ?? OverpassError(message: "Unknown Overpass error after retries.")
    }
}
