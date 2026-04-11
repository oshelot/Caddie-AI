// Tests for KAN-276 (S6) — WeatherService + wind-projection math.
//
// Three groups:
//
//   1. **Wind projection unit tests** (AC: "Unit test covers the
//      wind-projection math (unit circle rotation)") — drives
//      `WeatherData.relativeWindDirection` against the four
//      cardinal cases plus boundary cases at the band edges
//      (±30° headwind boundary, ±150° tailwind boundary).
//   2. **Stale-while-revalidate cache** — drives a service with
//      a fake clock + fake transport, asserting:
//        - first call hits the network
//        - within `freshTtl`, no network call
//        - between fresh and hard TTL, returns cache + triggers
//          a background refresh
//        - past hard TTL, blocks on a fresh fetch
//   3. **Open-Meteo wire format** — verifies the request URL has
//      the exact query params the natives use, and the response
//      parser pulls the right fields out of the JSON shape.

import 'package:caddieai/core/weather/weather_data.dart';
import 'package:caddieai/core/weather/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../courses/_fake_transport.dart';

void main() {
  group('relativeWindDirection — projection math', () {
    /// Helper that builds a WeatherData with only the fields the
    /// projection looks at.
    WeatherData windAt(double degrees) {
      return WeatherData(
        temperatureF: 70,
        windSpeedMph: 10,
        windDirectionDegrees: degrees,
        weatherCode: 0,
        fetchedAtMs: 0,
        latitude: 0,
        longitude: 0,
      );
    }

    test('headwind: hole pointing north, wind from north', () {
      // Hole bearing 0° (north). Wind from 0° → blowing into the
      // player.
      expect(
        windAt(0).relativeWindDirection(0),
        RelativeWindDirection.into,
      );
    });

    test('tailwind: hole pointing north, wind from south', () {
      expect(
        windAt(180).relativeWindDirection(0),
        RelativeWindDirection.helping,
      );
    });

    test('cross right-to-left: hole north, wind from east', () {
      // Wind from 90° (east) → on a north-pointing hole, the wind
      // is coming from the player's right, pushing the ball left.
      expect(
        windAt(90).relativeWindDirection(0),
        RelativeWindDirection.crossRightToLeft,
      );
    });

    test('cross left-to-right: hole north, wind from west', () {
      expect(
        windAt(270).relativeWindDirection(0),
        RelativeWindDirection.crossLeftToRight,
      );
    });

    test('±30° band: 30° from straight is still headwind', () {
      expect(
        windAt(30).relativeWindDirection(0),
        RelativeWindDirection.into,
      );
      expect(
        windAt(330).relativeWindDirection(0),
        RelativeWindDirection.into,
      );
    });

    test('just past ±30°: 31° from straight is cross', () {
      expect(
        windAt(31).relativeWindDirection(0),
        RelativeWindDirection.crossRightToLeft,
      );
      expect(
        windAt(329).relativeWindDirection(0),
        RelativeWindDirection.crossLeftToRight,
      );
    });

    test('±150° band: 150° from straight is still tailwind', () {
      expect(
        windAt(150).relativeWindDirection(0),
        RelativeWindDirection.helping,
      );
      expect(
        windAt(210).relativeWindDirection(0),
        RelativeWindDirection.helping,
      );
    });

    test('hole bearing wraps around: hole pointing east (90°)', () {
      // Wind from 90° → blowing INTO an east-pointing hole.
      expect(
        windAt(90).relativeWindDirection(90),
        RelativeWindDirection.into,
      );
      // Wind from 270° (west) → tailwind for an east-pointing hole.
      expect(
        windAt(270).relativeWindDirection(90),
        RelativeWindDirection.helping,
      );
      // Wind from 0° (north) → cross from the left side of an
      // east-pointing hole, pushing the ball right.
      // diff = 0 - 90 = -90 (after normalization), which is < 0 →
      // crossLeftToRight per the iOS-port semantics.
      expect(
        windAt(0).relativeWindDirection(90),
        RelativeWindDirection.crossLeftToRight,
      );
    });

    test('hole bearing 350°, wind from 10° — handles wrap correctly', () {
      // diff = 10 - 350 = -340 → normalized to +20 → headwind
      expect(
        windAt(10).relativeWindDirection(350),
        RelativeWindDirection.into,
      );
    });
  });

  group('WeatherService — request format', () {
    late FakeHttpTransport transport;
    late WeatherService service;

    setUp(() {
      transport = FakeHttpTransport();
      service = WeatherService(transport: transport);
    });

    test('request includes the exact Open-Meteo query params', () async {
      transport.enqueueJson(
        '{"current":{"temperature_2m":68.2,"wind_speed_10m":8.4,'
        '"wind_direction_10m":210.0,"weather_code":2}}',
      );
      await service.fetchWeather(latitude: 39.6, longitude: -105.0);

      expect(transport.requests, hasLength(1));
      final url = transport.requests.first.url;
      expect(url.host, 'api.open-meteo.com');
      expect(url.path, '/v1/forecast');
      expect(url.queryParameters['latitude'], '39.6');
      expect(url.queryParameters['longitude'], '-105.0');
      expect(url.queryParameters['current'],
          'temperature_2m,wind_speed_10m,wind_direction_10m,weather_code');
      expect(url.queryParameters['temperature_unit'], 'fahrenheit');
      expect(url.queryParameters['wind_speed_unit'], 'mph');
    });

    test('parses temperature, wind, and weather code from the response',
        () async {
      transport.enqueueJson(
        '{"current":{"temperature_2m":72.5,"wind_speed_10m":11.3,'
        '"wind_direction_10m":195.5,"weather_code":3}}',
      );
      final data = await service.fetchWeather(
        latitude: 40.0,
        longitude: -105.0,
      );
      expect(data, isNotNull);
      expect(data!.temperatureF, 72.5);
      expect(data.windSpeedMph, 11.3);
      expect(data.windDirectionDegrees, 195.5);
      expect(data.weatherCode, 3);
      expect(data.latitude, 40.0);
      expect(data.longitude, -105.0);
    });

    test('returns cached value on network failure', () async {
      transport.enqueueJson(
        '{"current":{"temperature_2m":70,"wind_speed_10m":5,'
        '"wind_direction_10m":0,"weather_code":0}}',
      );
      final first =
          await service.fetchWeather(latitude: 40, longitude: -105);
      expect(first, isNotNull);

      // Force a fresh fetch — but enqueue a 500 response.
      transport.enqueueError(500);
      final second =
          await service.refresh(latitude: 40, longitude: -105);
      // Service falls back to the previously-cached reading.
      expect(second, isNotNull);
      expect(second!.temperatureF, 70);
    });
  });

  group('WeatherService — stale-while-revalidate', () {
    late FakeHttpTransport transport;
    late WeatherService service;
    late DateTime now;

    setUp(() {
      transport = FakeHttpTransport();
      now = DateTime.utc(2026, 4, 11, 12, 0, 0);
      service = WeatherService(
        transport: transport,
        clock: () => now,
        freshTtl: const Duration(minutes: 5),
        hardTtl: const Duration(minutes: 15),
      );
    });

    void enqueueReading(double temp) {
      transport.enqueueJson(
        '{"current":{"temperature_2m":$temp,"wind_speed_10m":5,'
        '"wind_direction_10m":0,"weather_code":0}}',
      );
    }

    test('first call hits the network', () async {
      enqueueReading(70);
      await service.fetchWeather(latitude: 40, longitude: -105);
      expect(transport.requests, hasLength(1));
    });

    test('within freshTtl, no second network call', () async {
      enqueueReading(70);
      await service.fetchWeather(latitude: 40, longitude: -105);
      expect(transport.requests, hasLength(1));

      now = now.add(const Duration(minutes: 4));
      final cached =
          await service.fetchWeather(latitude: 40, longitude: -105);
      expect(transport.requests, hasLength(1),
          reason: 'fresh cache hit must not trigger a new request');
      expect(cached!.temperatureF, 70);
    });

    test('past freshTtl but within hardTtl returns cached + bg refresh',
        () async {
      enqueueReading(70);
      await service.fetchWeather(latitude: 40, longitude: -105);

      // Move into the stale-but-not-expired window.
      now = now.add(const Duration(minutes: 7));
      enqueueReading(75); // background refresh result

      final stillCached =
          await service.fetchWeather(latitude: 40, longitude: -105);
      // Returns the OLD reading immediately.
      expect(stillCached!.temperatureF, 70);

      // Background refresh fires asynchronously — let it drain.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(transport.requests, hasLength(2),
          reason: 'background refresh should have hit the network');

      // Subsequent fetch within fresh window of the new reading
      // returns the new value.
      now = now.add(const Duration(seconds: 1));
      final freshened =
          await service.fetchWeather(latitude: 40, longitude: -105);
      expect(freshened!.temperatureF, 75);
    });

    test('past hardTtl forces a blocking fetch', () async {
      enqueueReading(70);
      await service.fetchWeather(latitude: 40, longitude: -105);

      now = now.add(const Duration(minutes: 20));
      enqueueReading(80);

      final fresh =
          await service.fetchWeather(latitude: 40, longitude: -105);
      expect(fresh!.temperatureF, 80);
      expect(transport.requests, hasLength(2));
    });

    test('different location forces a fresh fetch', () async {
      enqueueReading(70);
      await service.fetchWeather(latitude: 40, longitude: -105);

      // Move >1 km away (≥0.01 deg). Should miss the cache.
      enqueueReading(60);
      await service.fetchWeather(latitude: 41, longitude: -105);
      expect(transport.requests, hasLength(2));
    });
  });
}
