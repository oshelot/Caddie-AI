//
//  WeatherData.swift
//  CaddieAI
//
//  Real-time weather conditions from Open-Meteo.
//

import Foundation

struct WeatherData: Codable, Sendable {
    var temperatureF: Double
    var windSpeedMph: Double
    var windDirectionDegrees: Double  // meteorological: 0=N, 90=E, 180=S, 270=W
    var weatherCode: Int              // WMO weather code
    var fetchedAt: Date

    // MARK: - Wind Strength Mapping

    /// Maps continuous wind speed (mph) to the app's discrete WindStrength enum
    var windStrength: WindStrength {
        switch windSpeedMph {
        case ..<5:   return .none
        case 5..<12: return .light
        case 12..<20: return .moderate
        default:      return .strong
        }
    }

    // MARK: - Wind Relative to Hole Bearing

    /// Given a hole bearing (degrees, 0-360, tee-to-green), compute the
    /// relative wind direction as seen by the golfer playing the hole.
    ///
    /// Wind meteorological convention: wind direction is where wind COMES FROM.
    /// So wind at 0° means wind blowing FROM the north (toward south).
    ///
    /// If the hole plays north (bearing ~0°) and wind comes from north (0°),
    /// the golfer faces a headwind (into).
    func relativeWindDirection(holeBearingDegrees: Double) -> WindDirection {
        var diff = windDirectionDegrees - holeBearingDegrees
        // Normalize to -180...180
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }

        let absDiff = abs(diff)

        if absDiff <= 30 {
            return .into
        } else if absDiff >= 150 {
            return .helping
        } else if diff > 0 {
            // Wind source is clockwise from hole bearing
            return .crossRightToLeft
        } else {
            return .crossLeftToRight
        }
    }

    // MARK: - Display Helpers

    var windDescription: String {
        let cardinal = Self.cardinalDirection(from: windDirectionDegrees)
        return "\(Int(windSpeedMph)) mph from \(cardinal)"
    }

    var temperatureDescription: String {
        "\(Int(temperatureF))°F"
    }

    /// Short weather condition from WMO code
    var conditionDescription: String {
        switch weatherCode {
        case 0:          return "Clear"
        case 1, 2, 3:    return "Partly Cloudy"
        case 45, 48:     return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 61, 63, 65: return "Rain"
        case 71, 73, 75: return "Snow"
        case 80, 81, 82: return "Showers"
        case 95, 96, 99: return "Thunderstorm"
        default:         return "Overcast"
        }
    }

    /// SF Symbol name for the weather condition
    var conditionSymbol: String {
        switch weatherCode {
        case 0:          return "sun.max.fill"
        case 1, 2, 3:    return "cloud.sun.fill"
        case 45, 48:     return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 71, 73, 75: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default:         return "cloud.fill"
        }
    }

    /// Whether weather data is still fresh (< 15 minutes old)
    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 900
    }

    // MARK: - Cardinal Direction

    static func cardinalDirection(from degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25).truncatingRemainder(dividingBy: 360) / 22.5)
        return directions[index % 16]
    }
}
