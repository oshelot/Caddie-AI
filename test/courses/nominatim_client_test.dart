// Unit tests for NominatimClient. Uses the same FakeHttpTransport
// pattern as the rest of the courses suite (see _fake_transport.dart).

import 'package:caddieai/core/courses/course_search_results.dart';
import 'package:caddieai/core/courses/nominatim_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '_fake_transport.dart';

void main() {
  late FakeHttpTransport transport;
  late NominatimClient client;

  setUp(() {
    transport = FakeHttpTransport();
    client = NominatimClient(transport: transport);
  });

  group('request shape', () {
    test('sets the User-Agent header per Nominatim TOS', () async {
      transport.enqueueJson('[]');
      await client.searchCourses('sharp park');
      expect(transport.requests, hasLength(1));
      final req = transport.requests.single;
      expect(req.method, 'GET');
      expect(req.headers['User-Agent'], contains('CaddieAI'));
    });

    test('prefixes the query with "golf course" so OSM filters', () async {
      transport.enqueueJson('[]');
      await client.searchCourses('Sharp Park');
      final req = transport.requests.single;
      expect(req.url.queryParameters['q'], 'golf course Sharp Park');
      expect(req.url.queryParameters['format'], 'json');
      expect(req.url.queryParameters['addressdetails'], '1');
    });

    test('returns empty list for empty input without hitting the wire',
        () async {
      final result = await client.searchCourses('   ');
      expect(result, isEmpty);
      expect(transport.requests, isEmpty);
    });
  });

  group('parsing', () {
    test('parses a typical golf course response', () async {
      transport.enqueueJson('''
        [
          {
            "place_id": 1,
            "osm_type": "way",
            "osm_id": 12345,
            "lat": "37.6244",
            "lon": "-122.4885",
            "display_name": "Sharp Park Golf Course, Pacifica, CA, USA",
            "class": "leisure",
            "type": "golf_course",
            "address": {
              "city": "Pacifica",
              "state": "California"
            }
          }
        ]
      ''');

      final result = await client.searchCourses('sharp park');
      expect(result, hasLength(1));
      expect(result.first.name, 'Sharp Park Golf Course');
      expect(result.first.latitude, closeTo(37.6244, 0.0001));
      expect(result.first.longitude, closeTo(-122.4885, 0.0001));
      expect(result.first.city, 'Pacifica');
      expect(result.first.source, CourseSearchSource.nominatim);
      expect(result.first.cacheKey, 'nominatim:way12345');
    });

    test('strips trailing digits from quirky Nominatim names', () async {
      transport.enqueueJson('''
        [{
          "place_id": 1, "osm_type": "way", "osm_id": 1,
          "lat": "37", "lon": "-122",
          "display_name": "Sharp Park Golf Course50, Pacifica, CA",
          "type": "golf_course",
          "address": {"city": "Pacifica"}
        }]
      ''');
      final result = await client.searchCourses('sharp park');
      expect(result.first.name, 'Sharp Park Golf Course');
    });

    test('skips entries that are not golf courses', () async {
      transport.enqueueJson('''
        [
          {"place_id":1,"osm_type":"node","osm_id":1,"lat":"37","lon":"-122",
           "display_name":"Pacifica Pizza, Pacifica, CA","type":"restaurant"},
          {"place_id":2,"osm_type":"way","osm_id":2,"lat":"37","lon":"-122",
           "display_name":"Sharp Park Golf Course, Pacifica","type":"golf_course"}
        ]
      ''');
      final result = await client.searchCourses('park');
      expect(result, hasLength(1));
      expect(result.first.name, 'Sharp Park Golf Course');
    });

    test('keeps entries whose display_name contains "golf club" even if '
        'the type is wrong', () async {
      transport.enqueueJson('''
        [{
          "place_id": 1, "osm_type": "way", "osm_id": 1,
          "lat":"37","lon":"-122",
          "display_name": "Wellshire Golf Club, Denver, CO",
          "type": "park"
        }]
      ''');
      final result = await client.searchCourses('wellshire');
      expect(result, hasLength(1));
      expect(result.first.name, 'Wellshire Golf Club');
    });

    test('returns empty list on HTTP error', () async {
      transport.enqueueError(503);
      final result = await client.searchCourses('anything');
      expect(result, isEmpty);
    });

    test('returns empty list on malformed JSON', () async {
      transport.enqueueJson('not json');
      final result = await client.searchCourses('anything');
      expect(result, isEmpty);
    });
  });
}
