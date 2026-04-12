// Tests the pure-function 3-source merge: dedup + manifest overlay.
// Mirrors the iOS test contract embedded in
// CourseViewModel.swift:90-129. The merger has no I/O, so these are
// just direct list assertions.

import 'package:caddieai/core/courses/course_search_merger.dart';
import 'package:caddieai/core/courses/course_search_results.dart';
import 'package:flutter_test/flutter_test.dart';

CourseSearchEntry _entry({
  required String name,
  String city = '',
  String state = '',
  required CourseSearchSource source,
  String? cacheKey,
}) {
  return CourseSearchEntry(
    cacheKey: cacheKey ?? '${source.name}:${name.toLowerCase()}',
    name: name,
    city: city,
    state: state,
    latitude: 37.0,
    longitude: -122.0,
    source: source,
  );
}

void main() {
  const merger = CourseSearchMerger();

  group('dedup', () {
    test('Nominatim results come first, in input order', () {
      final result = merger.merge(
        nominatim: [
          _entry(name: 'Sharp Park Golf Course', source: CourseSearchSource.nominatim),
          _entry(name: 'Lincoln Park', source: CourseSearchSource.nominatim),
        ],
        googlePlaces: const [],
        manifestEntries: const [],
      );
      expect(result.map((e) => e.name).toList(),
          ['Sharp Park Golf Course', 'Lincoln Park']);
    });

    test('Places result with exact-name match (case-insensitive) is dropped',
        () {
      final result = merger.merge(
        nominatim: [
          _entry(name: 'Sharp Park Golf Course', source: CourseSearchSource.nominatim),
        ],
        googlePlaces: [
          _entry(name: 'sharp park golf course', source: CourseSearchSource.googlePlaces),
        ],
        manifestEntries: const [],
      );
      expect(result, hasLength(1));
      expect(result.first.source, CourseSearchSource.nominatim);
    });

    test('Places result that fuzzy-contains a Nominatim name is dropped', () {
      // iOS rule: drop if either name substring-contains the other.
      final result = merger.merge(
        nominatim: [
          _entry(name: 'Sharp Park', source: CourseSearchSource.nominatim),
        ],
        googlePlaces: [
          _entry(name: 'Sharp Park Golf Course', source: CourseSearchSource.googlePlaces),
        ],
        manifestEntries: const [],
      );
      expect(result, hasLength(1));
      expect(result.first.source, CourseSearchSource.nominatim);
    });

    test('Places result that does NOT overlap is appended after Nominatim',
        () {
      final result = merger.merge(
        nominatim: [
          _entry(name: 'Sharp Park', source: CourseSearchSource.nominatim),
        ],
        googlePlaces: [
          _entry(name: 'Wellshire Golf Course', source: CourseSearchSource.googlePlaces),
        ],
        manifestEntries: const [],
      );
      expect(result.map((e) => e.name).toList(),
          ['Sharp Park', 'Wellshire Golf Course']);
      expect(result.last.source, CourseSearchSource.googlePlaces);
    });
  });

  group('manifest overlay', () {
    test('overlays Google-Places-corrected city onto a Nominatim result', () {
      // Real-world example: Nominatim says Sharp Park is in San
      // Francisco, but the manifest (corrected via Google Places at
      // PUT time) says Pacifica.
      final result = merger.merge(
        nominatim: [
          _entry(
            name: 'Sharp Park Golf Course',
            city: 'San Francisco',
            state: 'CA',
            source: CourseSearchSource.nominatim,
          ),
        ],
        googlePlaces: const [],
        manifestEntries: [
          _entry(
            name: 'Sharp Park Golf Course',
            city: 'Pacifica',
            state: 'CA',
            source: CourseSearchSource.manifest,
          ),
        ],
      );
      expect(result.first.city, 'Pacifica');
      expect(result.first.state, 'CA');
      // The source is preserved — only city/state is overwritten.
      expect(result.first.source, CourseSearchSource.nominatim);
    });

    test('overlay matches by case-insensitive substring (manifest contains row)',
        () {
      final result = merger.merge(
        nominatim: [
          _entry(name: 'Sharp Park', city: 'Wrong', source: CourseSearchSource.nominatim),
        ],
        googlePlaces: const [],
        manifestEntries: [
          _entry(
            name: 'Sharp Park Golf Course',
            city: 'Pacifica',
            source: CourseSearchSource.manifest,
          ),
        ],
      );
      expect(result.first.city, 'Pacifica');
    });

    test('overlay matches by case-insensitive substring (row contains manifest)',
        () {
      final result = merger.merge(
        nominatim: [
          _entry(
            name: 'Sharp Park Golf Course',
            city: 'Wrong',
            source: CourseSearchSource.nominatim,
          ),
        ],
        googlePlaces: const [],
        manifestEntries: [
          _entry(name: 'Sharp Park', city: 'Pacifica', source: CourseSearchSource.manifest),
        ],
      );
      expect(result.first.city, 'Pacifica');
    });

    test('empty manifest city does NOT clobber a non-empty Nominatim city',
        () {
      final result = merger.merge(
        nominatim: [
          _entry(name: 'Foo', city: 'KeepMe', source: CourseSearchSource.nominatim),
        ],
        googlePlaces: const [],
        manifestEntries: [
          _entry(name: 'Foo', city: '', source: CourseSearchSource.manifest),
        ],
      );
      expect(result.first.city, 'KeepMe');
    });

    test('rows with no manifest match are passed through unchanged', () {
      final original = _entry(
        name: 'No Match',
        city: 'KeepMe',
        state: 'CA',
        source: CourseSearchSource.nominatim,
      );
      final result = merger.merge(
        nominatim: [original],
        googlePlaces: const [],
        manifestEntries: [
          _entry(name: 'Different', city: 'Other', source: CourseSearchSource.manifest),
        ],
      );
      expect(result.first.city, 'KeepMe');
      expect(result.first.state, 'CA');
    });
  });

  test('three-source happy path: dedup + overlay together', () {
    // This is the realistic end-to-end shape: Nominatim returns a
    // wrong-city row, Places returns a duplicate that gets dropped,
    // and the manifest overlays the correct city.
    final result = merger.merge(
      nominatim: [
        _entry(
          name: 'Sharp Park Golf Course',
          city: 'San Francisco',
          source: CourseSearchSource.nominatim,
        ),
      ],
      googlePlaces: [
        _entry(
          name: 'Sharp Park Golf Course',
          city: 'Pacifica',
          source: CourseSearchSource.googlePlaces,
        ),
      ],
      manifestEntries: [
        _entry(
          name: 'Sharp Park Golf Course',
          city: 'Pacifica',
          source: CourseSearchSource.manifest,
        ),
      ],
    );
    expect(result, hasLength(1));
    expect(result.first.source, CourseSearchSource.nominatim);
    expect(result.first.city, 'Pacifica');
  });
}
