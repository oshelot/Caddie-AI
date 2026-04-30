// Unit tests for PlacesClient — wraps the KAN-296 Lambda routes.
// FakeHttpTransport asserts that the URL, query params, and headers
// match the production Lambda's expected shape.

import 'package:caddieai/core/courses/course_search_results.dart';
import 'package:caddieai/core/courses/places_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '_fake_transport.dart';

void main() {
  const baseUrl = 'https://example.com';
  const apiKey = 'test-key';

  late FakeHttpTransport transport;
  late PlacesClient client;

  setUp(() {
    transport = FakeHttpTransport();
    client = PlacesClient(
      baseUrl: baseUrl,
      apiKey: apiKey,
      transport: transport,
    );
  });

  group('autocomplete', () {
    test('hits /places/autocomplete with the q param + x-api-key', () async {
      transport.enqueueJson('{"suggestions":[]}');
      await client.autocomplete('DEN');
      final req = transport.requests.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/places/autocomplete');
      expect(req.url.queryParameters['q'], 'DEN');
      expect(req.headers['x-api-key'], apiKey);
    });

    test('parses the production response shape', () async {
      transport.enqueueJson('''
        {"suggestions":[
          {"description":"Denver, CO, USA","mainText":"Denver","secondaryText":"CO, USA"},
          {"description":"Denton, TX, USA","mainText":"Denton","secondaryText":"TX, USA"}
        ]}
      ''');
      final result = await client.autocomplete('DEN');
      expect(result, hasLength(2));
      expect(result.first.description, 'Denver, CO, USA');
      expect(result.first.mainText, 'Denver');
      expect(result.first.secondaryText, 'CO, USA');
    });

    test('empty input returns empty list without hitting the wire', () async {
      final result = await client.autocomplete('   ');
      expect(result, isEmpty);
      expect(transport.requests, isEmpty);
    });

    test('unconfigured client returns empty list without hitting the wire',
        () async {
      final unconfigured = PlacesClient(
        baseUrl: '',
        apiKey: '',
        transport: transport,
      );
      final result = await unconfigured.autocomplete('DEN');
      expect(result, isEmpty);
      expect(transport.requests, isEmpty);
      expect(unconfigured.isConfigured, isFalse);
    });

    test('returns empty list on HTTP error', () async {
      transport.enqueueError(500);
      final result = await client.autocomplete('DEN');
      expect(result, isEmpty);
    });
  });

  group('searchCourses', () {
    test('hits /places/search with q + lat/lon when supplied', () async {
      transport.enqueueJson('{"results":[]}');
      await client.searchCourses(
        'sharp park',
        latitude: 37.6244,
        longitude: -122.4885,
      );
      final req = transport.requests.single;
      expect(req.url.path, '/places/search');
      expect(req.url.queryParameters['q'], 'sharp park');
      expect(req.url.queryParameters['lat'], '37.6244');
      expect(req.url.queryParameters['lon'], '-122.4885');
      expect(req.headers['x-api-key'], apiKey);
    });

    test('omits lat/lon when not supplied', () async {
      transport.enqueueJson('{"results":[]}');
      await client.searchCourses('wellshire');
      final req = transport.requests.single;
      expect(req.url.queryParameters.containsKey('lat'), isFalse);
      expect(req.url.queryParameters.containsKey('lon'), isFalse);
    });

    test('parses the production response shape', () async {
      transport.enqueueJson('''
        {"results":[{
          "id":"ChIJabc",
          "name":"Sharp Park Golf Course",
          "city":"Pacifica",
          "state":"CA",
          "lat":37.6248862,
          "lon":-122.4886486,
          "formattedAddress":"1 Sharp Park Rd, Pacifica, CA 94044, USA"
        }]}
      ''');
      final result = await client.searchCourses('sharp park');
      expect(result, hasLength(1));
      expect(result.first.name, 'Sharp Park Golf Course');
      expect(result.first.city, 'Pacifica');
      expect(result.first.state, 'CA');
      expect(result.first.source, CourseSearchSource.googlePlaces);
      expect(result.first.cacheKey, 'gplaces:ChIJabc');
      expect(result.first.formattedAddress, contains('Sharp Park Rd'));
    });

    test('skips results missing lat/lon', () async {
      transport.enqueueJson('''
        {"results":[
          {"id":"a","name":"Has Coords","lat":37.0,"lon":-122.0},
          {"id":"b","name":"No Coords"}
        ]}
      ''');
      final result = await client.searchCourses('q');
      expect(result, hasLength(1));
      expect(result.first.name, 'Has Coords');
    });

    test('returns empty list on HTTP error', () async {
      transport.enqueueError(429);
      final result = await client.searchCourses('q');
      expect(result, isEmpty);
    });
  });
}
