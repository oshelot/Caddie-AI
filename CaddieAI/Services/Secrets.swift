//
//  Secrets.swift
//  CaddieAI
//
//  Reads API tokens from the gitignored Secrets.plist bundle resource.
//

import Foundation

enum Secrets {
    private static let secrets: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict
    }()

    /// Mapbox public access token from Secrets.plist
    static var mapboxAccessToken: String? {
        secrets?["MBXAccessToken"] as? String
    }

    /// Telemetry ingestion endpoint URL
    static var telemetryEndpoint: String? {
        secrets?["TelemetryEndpoint"] as? String
    }

    /// Telemetry API key (x-api-key header)
    static var telemetryApiKey: String? {
        secrets?["TelemetryApiKey"] as? String
    }
}
