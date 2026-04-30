// WeatherData + RelativeWindDirection — KAN-276 (S6) Flutter port
// of the iOS `WeatherData.swift` and Android `WeatherData.kt`.
//
// **Provider:** the natives use Open-Meteo
// (`https://api.open-meteo.com/v1/forecast`) — free, no API key,
// no auth headers, no signed JWTs. Picked because it works
// identically across platforms with zero plumbing. WeatherKit
// (Apple) was rejected for the migration because it requires a
// signed JWT and would force a platform channel just for iOS.
//
// **Units (request):** the natives ask the API for fahrenheit +
// mph. We do the same so the response shape matches what's
// already on the dashboard side.
//
// **Wind direction convention:** Open-Meteo uses the
// **meteorological** convention — `wind_direction_10m` is the
// direction the wind is blowing **FROM**, in compass degrees,
// 0 = north, 90 = east, 180 = south, 270 = west. This matters
// for the projection math below: a hole that points north
// (`bearing = 0°`) hit by a "wind from 0°" reading is a
// **headwind**, not a tailwind.

class WeatherData {
  const WeatherData({
    required this.temperatureF,
    required this.windSpeedMph,
    required this.windDirectionDegrees,
    required this.weatherCode,
    required this.fetchedAtMs,
    required this.latitude,
    required this.longitude,
  });

  /// Temperature in degrees Fahrenheit.
  final double temperatureF;

  /// Wind speed at 10 m above ground, in mph.
  final double windSpeedMph;

  /// Compass direction the wind is blowing FROM, 0..360, with
  /// 0 = north and increasing clockwise. Meteorological convention
  /// (NOT "where the wind is going").
  final double windDirectionDegrees;

  /// WMO weather code (0 = clear, 1-3 = partly cloudy, 45-48 =
  /// fog, 51-67 = drizzle/rain, 71-77 = snow, 95-99 = thunder).
  /// Stored raw — feature code maps to icons / labels.
  final int weatherCode;

  /// Epoch milliseconds when this reading was fetched. Used by
  /// the cache layer for staleness checks.
  final int fetchedAtMs;

  /// Latitude this reading was fetched for. Used by the cache to
  /// match incoming requests against the cached entry's location
  /// (within the ~1 km tolerance the natives use).
  final double latitude;

  /// Longitude this reading was fetched for.
  final double longitude;

  /// Projects this wind reading onto a hole's tee-to-green bearing
  /// and returns the player-relative wind direction. Direct port
  /// of `WeatherData.relativeWindDirection(holeBearingDegrees:)`
  /// from iOS — the same banding (`±30°` headwind, `±150°+`
  /// tailwind, otherwise cross). Android has two implementations
  /// (an 8-band variant in `AutoDetectService` and a 4-band
  /// variant in `HoleAnalysisViewModel`); we port the iOS 4-band
  /// variant because it's the one the existing UI badges already
  /// use.
  ///
  /// `holeBearingDegrees` is the tee-to-green compass bearing,
  /// 0 = north, increasing clockwise.
  RelativeWindDirection relativeWindDirection(double holeBearingDegrees) {
    var diff = windDirectionDegrees - holeBearingDegrees;
    // Normalize to [-180, 180].
    while (diff > 180) {
      diff -= 360;
    }
    while (diff < -180) {
      diff += 360;
    }

    final absDiff = diff.abs();
    if (absDiff <= 30) return RelativeWindDirection.into;
    if (absDiff >= 150) return RelativeWindDirection.helping;
    // diff > 0 means the wind source is clockwise from the hole
    // bearing, which (since the wind is blowing FROM that source)
    // pushes the ball counter-clockwise — i.e. right-to-left.
    return diff > 0
        ? RelativeWindDirection.crossRightToLeft
        : RelativeWindDirection.crossLeftToRight;
  }

  Map<String, dynamic> toJson() => {
        'temperatureF': temperatureF,
        'windSpeedMph': windSpeedMph,
        'windDirectionDegrees': windDirectionDegrees,
        'weatherCode': weatherCode,
        'fetchedAtMs': fetchedAtMs,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      temperatureF: (json['temperatureF'] as num).toDouble(),
      windSpeedMph: (json['windSpeedMph'] as num).toDouble(),
      windDirectionDegrees: (json['windDirectionDegrees'] as num).toDouble(),
      weatherCode: (json['weatherCode'] as num).toInt(),
      fetchedAtMs: (json['fetchedAtMs'] as num).toInt(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

/// 4-band wind direction relative to the hole's tee-to-green
/// bearing. Matches the iOS `WindDirection` enum casings — the
/// shot-recommendation engines (KAN-S7) and the caddie screen
/// badges (KAN-S11) consume this enum directly.
enum RelativeWindDirection {
  /// Wind blowing into the player (head-on). The hole bearing
  /// and the wind direction differ by ≤ 30°.
  into,

  /// Wind blowing with the player (tail wind). Bearing and
  /// direction differ by ≥ 150° (i.e. the wind is coming from
  /// roughly behind the player).
  helping,

  /// Cross wind from the right side of the hole, pushing the
  /// ball left.
  crossRightToLeft,

  /// Cross wind from the left side of the hole, pushing the
  /// ball right.
  crossLeftToRight,
}
