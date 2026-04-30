// WeatherService — KAN-276 (S6) Flutter port of the iOS
// `WeatherService.swift` and Android `WeatherService.kt`.
//
// **Endpoint:** `GET https://api.open-meteo.com/v1/forecast`
// with the same query params both natives use:
//
//   latitude=<lat>
//   longitude=<lon>
//   current=temperature_2m,wind_speed_10m,wind_direction_10m,weather_code
//   temperature_unit=fahrenheit
//   wind_speed_unit=mph
//
// No auth headers, no API key.
//
// **Caching (KAN-276 AC):** stale-while-revalidate. The first
// `fetchWeather(lat, lon)` returns the freshly-fetched reading.
// Subsequent calls within the TTL window (5 minutes per the AC,
// matching native's 15 minutes is the existing iOS/Android
// constant — we use the AC's tighter 5-minute window) return the
// cached reading **immediately** AND, if the cache is past the
// background-refresh threshold, kick off a background refresh
// that updates the cache without blocking the caller.
//
// The 5-minute "stale" threshold and the 15-minute "hard expiry"
// (after which a cache hit is treated as a miss) live in the
// constructor as configurable durations so tests can compress
// the time scales.
//
// **Location tolerance:** the natives match cached entries
// against incoming requests within ~1 km (lat/lon diff < 0.01).
// Same here.

import 'dart:async';
import 'dart:convert';

import '../courses/http_transport.dart';
import '../logging/log_event.dart';
import '../../main.dart' show logger;
import 'weather_data.dart';

class WeatherService {
  WeatherService({
    required this.transport,
    DateTime Function()? clock,
    Duration freshTtl = const Duration(minutes: 5),
    Duration hardTtl = const Duration(minutes: 15),
    String baseUrl = 'https://api.open-meteo.com/v1/forecast',
  })  : _clock = clock ?? DateTime.now,
        _freshTtl = freshTtl,
        _hardTtl = hardTtl,
        _baseUrl = baseUrl;

  final HttpTransport transport;
  final DateTime Function() _clock;
  final Duration _freshTtl;
  final Duration _hardTtl;
  final String _baseUrl;

  /// Sentinel match radius — both natives use a ~1 km lat/lon
  /// box (0.01 degrees ≈ 1.1 km at the equator, less near the
  /// poles). Two requests within this radius hit the same cache
  /// entry.
  static const double _locationTolerance = 0.01;

  WeatherData? _cached;
  Future<WeatherData?>? _inflightRefresh;

  /// Fetches the weather for the given lat/lon. Behavior:
  ///
  ///   - **No cache:** awaits the network call, returns the
  ///     fresh reading.
  ///   - **Cache fresh** (within `freshTtl`): returns the cached
  ///     reading immediately, no network call.
  ///   - **Cache stale-but-not-expired** (between `freshTtl` and
  ///     `hardTtl`): returns the cached reading immediately AND
  ///     fires off a background refresh. Subsequent calls during
  ///     the in-flight refresh return the same cached reading.
  ///   - **Cache hard-expired** (past `hardTtl`): treats as no
  ///     cache; awaits a fresh fetch.
  ///   - **Different location** (more than `_locationTolerance`
  ///     away from the cached entry): treats as no cache; awaits
  ///     a fresh fetch.
  Future<WeatherData?> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    final cached = _cached;
    if (cached != null && _matchesLocation(cached, latitude, longitude)) {
      final ageMs =
          _clock().millisecondsSinceEpoch - cached.fetchedAtMs;
      if (ageMs <= _freshTtl.inMilliseconds) {
        // Hot — no work to do.
        return cached;
      }
      if (ageMs <= _hardTtl.inMilliseconds) {
        // Stale-while-revalidate. Trigger a background refresh
        // (de-duped via _inflightRefresh) and return the stale
        // reading immediately.
        _inflightRefresh ??= _refreshInBackground(latitude, longitude);
        return cached;
      }
      // Hard-expired — fall through to a blocking fetch.
    }
    return _fetchAndCache(latitude, longitude);
  }

  /// Forces a fresh fetch, ignoring the cache. Used by manual
  /// "refresh weather" UI affordances and by the tests.
  Future<WeatherData?> refresh({
    required double latitude,
    required double longitude,
  }) =>
      _fetchAndCache(latitude, longitude);

  void clearCache() {
    _cached = null;
    _inflightRefresh = null;
  }

  // ── internals ────────────────────────────────────────────────────

  bool _matchesLocation(
    WeatherData cached,
    double latitude,
    double longitude,
  ) {
    return (cached.latitude - latitude).abs() < _locationTolerance &&
        (cached.longitude - longitude).abs() < _locationTolerance;
  }

  Future<WeatherData?> _refreshInBackground(double lat, double lon) async {
    try {
      return await _fetchAndCache(lat, lon);
    } finally {
      _inflightRefresh = null;
    }
  }

  Future<WeatherData?> _fetchAndCache(double lat, double lon) async {
    final url = Uri.parse(_baseUrl).replace(queryParameters: {
      'latitude': lat.toString(),
      'longitude': lon.toString(),
      'current':
          'temperature_2m,wind_speed_10m,wind_direction_10m,weather_code',
      'temperature_unit': 'fahrenheit',
      'wind_speed_unit': 'mph',
    });
    try {
      final sw = Stopwatch()..start();
      final response = await transport.send(HttpRequestLike(
        method: 'GET',
        url: url,
        timeout: const Duration(seconds: 10),
      ));
      sw.stop();
      if (!response.isSuccess) return _cached;
      logger.info(LogCategory.network, 'weather_fetch', metadata: {
        'latency': '${sw.elapsedMilliseconds}',
        'latitude': '$lat',
        'longitude': '$lon',
      });
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = (json['current'] as Map?)?.cast<String, dynamic>();
      if (current == null) return _cached;
      final reading = WeatherData(
        temperatureF: (current['temperature_2m'] as num).toDouble(),
        windSpeedMph: (current['wind_speed_10m'] as num).toDouble(),
        windDirectionDegrees:
            (current['wind_direction_10m'] as num).toDouble(),
        weatherCode: (current['weather_code'] as num).toInt(),
        fetchedAtMs: _clock().millisecondsSinceEpoch,
        latitude: lat,
        longitude: lon,
      );
      _cached = reading;
      return reading;
    } catch (_) {
      // Best-effort: weather is non-critical to app function.
      // Return whatever's in the cache (possibly null).
      return _cached;
    }
  }
}
