//
//  WeatherService.swift
//  CaddieAI
//
//  Fetches real-time weather from Open-Meteo (free, no API key).
//  Uses course centroid coordinates. Caches for 15 minutes.
//

import Foundation

enum WeatherService {

    private static var cachedWeather: WeatherData?
    private static var cachedCoordinate: (lat: Double, lon: Double)?

    // MARK: - Fetch Weather

    /// Fetches current weather for a coordinate. Returns cached data if fresh
    /// and for the same location (within ~1km).
    static func fetchWeather(
        latitude: Double,
        longitude: Double
    ) async throws -> WeatherData {
        // Return cache if fresh and same location
        if let cached = cachedWeather,
           cached.isFresh,
           let coord = cachedCoordinate,
           abs(coord.lat - latitude) < 0.01,
           abs(coord.lon - longitude) < 0.01 {
            return cached
        }

        let urlString = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(latitude)"
            + "&longitude=\(longitude)"
            + "&current=temperature_2m,wind_speed_10m,wind_direction_10m,weather_code"
            + "&temperature_unit=fahrenheit"
            + "&wind_speed_unit=mph"

        guard let url = URL(string: urlString) else {
            throw WeatherError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let fetchStart = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeatherError.fetchFailed
        }

        let weather = try parseResponse(data)
        let fetchMs = Int((CFAbsoluteTimeGetCurrent() - fetchStart) * 1000)

        // Update cache
        cachedWeather = weather
        cachedCoordinate = (latitude, longitude)

        TelemetryService.shared.recordWeatherCall()
        LoggingService.shared.info(.weather, "weather_fetch", metadata: [
            "latencyMs": "\(fetchMs)",
            "source": "open_meteo",
        ])

        return weather
    }

    // MARK: - Parse Open-Meteo Response

    private static func parseResponse(_ data: Data) throws -> WeatherData {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double,
              let windSpeed = current["wind_speed_10m"] as? Double,
              let windDir = current["wind_direction_10m"] as? Double,
              let code = current["weather_code"] as? Int
        else {
            throw WeatherError.parseFailed
        }

        return WeatherData(
            temperatureF: temp,
            windSpeedMph: windSpeed,
            windDirectionDegrees: windDir,
            weatherCode: code,
            fetchedAt: Date()
        )
    }
}

// MARK: - Errors

enum WeatherError: LocalizedError {
    case invalidURL
    case fetchFailed
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid weather API URL"
        case .fetchFailed: return "Could not fetch weather data"
        case .parseFailed: return "Could not parse weather response"
        }
    }
}
