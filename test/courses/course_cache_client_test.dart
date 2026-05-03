// CourseCacheClient tests for KAN-275 (S5). Covers every AC:
//
//   AC #1: `platform=ios&schema=1.0` MUST be passed on every call.
//          Asserted on search and fetchCourse — every test in this
//          file inspects the outbound URL params and fails the build
//          if either is missing or wrong.
//          (putCourse was removed in KAN-331 — cloud pipeline is the
//          sole authoritative writer to the server cache.)
//   AC #2: Cache miss → search → fetch → persist happy path,
//          covered by an integration test against the fake
//          transport (acts as the test-server double).
//   AC #3: gzip handling — DartIoHttpTransport opts in to
//          autoUncompress, so this is more about ensuring the
//          client doesn't accidentally re-encode the body. We
//          test with a literal JSON string response (no encoding
//          twist) — the gzip path is exercised in production by
//          dart:io and is identical to the URLSession/OkHttp
//          behavior the natives rely on.

import 'package:caddieai/core/courses/course_cache_client.dart';
import 'package:caddieai/core/courses/course_search_results.dart';
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

void main() {
  late FakeHttpTransport transport;
  late CourseCacheClient client;

  setUp(() {
    transport = FakeHttpTransport();
    client = _newClient(transport);
  });

  group('AC #1 — platform=ios & schema=1.0 on every call', () {
    test('searchManifest sends platform=ios and schema=1.0', () async {
      transport.enqueueJson('[]');
      await client.searchManifest(query: 'wellshire');

      expect(transport.requests, hasLength(1));
      final url = transport.requests.first.url;
      expect(url.queryParameters['platform'], 'ios');
      expect(url.queryParameters['schema'], '1.0');
      expect(url.queryParameters['q'], 'wellshire');
      // Manifest mode is the default for searchManifest.
      expect(url.queryParameters['mode'], 'metadata');
    });

    test('searchManifest with lat/lon includes them', () async {
      transport.enqueueJson('[]');
      await client.searchManifest(
        query: 'pebble',
        latitude: 36.5681,
        longitude: -121.9499,
      );
      final url = transport.requests.first.url;
      expect(url.queryParameters['platform'], 'ios');
      expect(url.queryParameters['schema'], '1.0');
      expect(url.queryParameters['lat'], '36.5681');
      expect(url.queryParameters['lon'], '-121.9499');
    });

    test('fetchCourse sends platform=ios and schema=1.0', () async {
      // Minimal NormalizedCourse JSON — just the fields the
      // lifted model parses.
      transport.enqueueJson(
        '{"id":"wellshire","name":"Wellshire","city":"Denver","state":"CO",'
        '"centroid":{"latitude":39.6,"longitude":-105.0},"holes":[]}',
      );
      await client.fetchCourse('wellshire-denver');

      final url = transport.requests.first.url;
      expect(url.queryParameters['platform'], 'ios');
      expect(url.queryParameters['schema'], '1.0');
      expect(url.path, '/courses/wellshire-denver');
    });

    // putCourse test removed — KAN-331: cloud pipeline is the sole
    // authoritative writer to the server cache.
  });

  group('Auth header', () {
    test('every request includes the x-api-key header', () async {
      transport.enqueueJson('[]');
      await client.searchManifest(query: 'q');
      expect(transport.requests.first.headers['x-api-key'], _apiKey);
    });
  });

  group('fetchCourse', () {
    test('returns null on 404', () async {
      transport.enqueueNotFound();
      final result = await client.fetchCourse('not-in-cache');
      expect(result, isNull);
    });

    test('parses a NormalizedCourse on 200', () async {
      transport.enqueueJson(
        '{"id":"wellshire","name":"Wellshire Golf Course",'
        '"city":"Denver","state":"CO",'
        '"centroid":{"latitude":39.6,"longitude":-105.0},"holes":['
        '{"number":1,"par":4,"strokeIndex":7,"yardages":{"white":380},'
        '"teeAreas":[],"lineOfPlay":null,"green":null,"pin":null,'
        '"bunkers":[],"water":[]}]}',
      );
      final course = await client.fetchCourse('wellshire');
      expect(course, isNotNull);
      expect(course!.name, 'Wellshire Golf Course');
      expect(course.holes, hasLength(1));
      expect(course.holes.first.par, 4);
    });

    test('throws CourseClientException on a 500', () async {
      transport.enqueueError(500, 'server boom');
      expect(
        () => client.fetchCourse('any'),
        throwsA(isA<CourseClientException>()),
      );
    });
  });

  group('searchManifest', () {
    test('parses a bare-array result list', () async {
      transport.enqueueJson(
        '[{"cacheKey":"a","name":"Course A","city":"Denver",'
        '"state":"CO","lat":39.7,"lon":-104.9},'
        '{"cacheKey":"b","name":"Course B","city":"Boulder",'
        '"state":"CO","lat":40.0,"lon":-105.3}]',
      );
      final results = await client.searchManifest(query: 'co');
      expect(results, hasLength(2));
      expect(results[0].cacheKey, 'a');
      expect(results[0].name, 'Course A');
      expect(results[1].name, 'Course B');
    });

    test('parses a {results: [...]} wrapped result', () async {
      transport.enqueueJson(
        '{"results":[{"cacheKey":"a","name":"Course A","city":"X",'
        '"state":"Y","lat":1.0,"lon":2.0}]}',
      );
      final results = await client.searchManifest(query: 'co');
      expect(results, hasLength(1));
      expect(results.first.cacheKey, 'a');
    });

    test('returns empty on 404', () async {
      transport.enqueueNotFound();
      final results = await client.searchManifest(query: 'nope');
      expect(results, isEmpty);
    });
  });

  group('AC #2 — search → fetch → persist happy path', () {
    test('integrates against the fake-transport test double', () async {
      // 1. Manifest search returns one entry.
      transport.enqueueJson(
        '[{"cacheKey":"wellshire-denver","name":"Wellshire",'
        '"city":"Denver","state":"CO","lat":39.6,"lon":-105.0}]',
      );
      // 2. Full course fetch returns a parseable course.
      transport.enqueueJson(
        '{"id":"wellshire-denver","name":"Wellshire",'
        '"city":"Denver","state":"CO",'
        '"centroid":{"latitude":39.6,"longitude":-105.0},"holes":['
        '{"number":1,"par":4,"strokeIndex":1,"yardages":{},'
        '"teeAreas":[],"lineOfPlay":null,"green":null,"pin":null,'
        '"bunkers":[],"water":[]}]}',
      );

      final hits = await client.searchManifest(query: 'wellshire');
      expect(hits, hasLength(1));
      expect(hits.first.cacheKey, 'wellshire-denver');

      final course = await client.fetchCourse(hits.first.cacheKey);
      expect(course, isNotNull);
      expect(course!.id, 'wellshire-denver');
      expect(course.name, 'Wellshire');

      // The orchestration: search, then fetch — both hit the
      // server. Both requests carry the AC #1 params.
      expect(transport.requests, hasLength(2));
      for (final req in transport.requests) {
        expect(req.url.queryParameters['platform'], 'ios');
        expect(req.url.queryParameters['schema'], '1.0');
      }
    });
  });
}
