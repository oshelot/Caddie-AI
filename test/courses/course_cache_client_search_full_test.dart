// KAN-344 — searchFullCourse must reject server responses whose course
// name doesn't reasonably match the query. Defense in depth alongside
// the lambda's ratio guard.

import 'package:caddieai/core/courses/course_cache_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '_fake_transport.dart';

const _baseUrl = 'https://cache.test.caddieai.app';
const _apiKey = 'fake-cache-api-key';

CourseCacheClient _newClient(FakeHttpTransport transport) =>
    CourseCacheClient(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      transport: transport,
    );

/// Build a minimal NormalizedCourse JSON with the supplied name.
String _coursePayload(String name) => '''
{
  "id": "$name",
  "name": "$name",
  "city": "Denver",
  "state": "CO",
  "centroid": {"latitude": 39.6, "longitude": -104.9},
  "holes": []
}
''';

void main() {
  late FakeHttpTransport transport;
  late CourseCacheClient client;

  setUp(() {
    transport = FakeHttpTransport();
    client = _newClient(transport);
  });

  group('KAN-344 searchFullCourse rejects unrelated server responses', () {
    test('Kennedy query → Valley Country Club response → returns null', () async {
      // Canary: lambda's old fuzzy match would have happily returned
      // Valley Country Club for a Kennedy search. The frontend now
      // catches that as a defense layer.
      transport.enqueueJson(_coursePayload('Valley Country Club'));
      final result = await client.searchFullCourse(
        query: 'Kennedy',
        latitude: 39.7392,
        longitude: -104.9903,
      );
      expect(result, isNull);
    });

    test('Aspen query → Argyle Country Club response → returns null', () async {
      transport.enqueueJson(_coursePayload('Argyle Country Club'));
      final result = await client.searchFullCourse(query: 'Aspen');
      expect(result, isNull);
    });

    test('Sharp Park query → Sharp Park GC response → returns the course',
        () async {
      transport.enqueueJson(_coursePayload('Sharp Park Golf Course'));
      final result = await client.searchFullCourse(query: 'Sharp Park');
      expect(result, isNotNull);
      expect(result!.name, 'Sharp Park Golf Course');
    });

    test('Sharp Pak typo → Sharp Park GC response → returns the course',
        () async {
      transport.enqueueJson(_coursePayload('Sharp Park Golf Course'));
      final result = await client.searchFullCourse(query: 'Sharp Pak');
      expect(result, isNotNull);
    });

    test('exact-name query returns the course', () async {
      transport.enqueueJson(_coursePayload('Wellshire Golf Course'));
      final result = await client.searchFullCourse(query: 'Wellshire Golf Course');
      expect(result, isNotNull);
    });

    test('substring query returns the course', () async {
      transport.enqueueJson(_coursePayload('Wellshire Golf Course'));
      final result = await client.searchFullCourse(query: 'Wellshire');
      expect(result, isNotNull);
    });

    test('404 response still returns null without verification', () async {
      transport.enqueueNotFound();
      final result = await client.searchFullCourse(query: 'Anything');
      expect(result, isNull);
    });
  });
}
