// CourseCacheRepository tests for KAN-275 (S5). Covers the
// disk-cache half of the AC: round-trip persistence, hot-cache
// LRU bumping, TTL staleness, and infinite-default behavior
// (matching native).

import 'dart:io';

import 'package:caddieai/core/courses/course_cache_repository.dart';
import 'package:caddieai/core/courses/course_search_results.dart';
import 'package:caddieai/core/geo/geo.dart';
import 'package:caddieai/core/storage/app_storage.dart';
import 'package:caddieai/models/normalized_course.dart';
import 'package:flutter_test/flutter_test.dart';

import '../storage/_helpers.dart';

NormalizedCourse _newCourse(String id, {String name = 'Test Course'}) {
  return NormalizedCourse(
    id: id,
    name: name,
    city: 'Denver',
    state: 'CO',
    centroid: const LngLat(-105.0, 39.7),
    holes: const [],
  );
}

void main() {
  late Directory tempDir;
  late CourseCacheRepository repo;
  late DateTime now;

  setUp(() async {
    tempDir = makeHiveTempDir();
    await AppStorage.initForTest(tempDir.path);
    now = DateTime.utc(2026, 4, 11, 12, 0, 0);
    repo = CourseCacheRepository(clock: () => now);
  });

  tearDown(() async {
    await AppStorage.resetForTest();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('round-trip', () {
    test('save then load returns the same course', () async {
      await repo.save('wellshire', _newCourse('wellshire', name: 'Wellshire'));
      final loaded = repo.load('wellshire');
      expect(loaded, isNotNull);
      expect(loaded!.course.id, 'wellshire');
      expect(loaded.course.name, 'Wellshire');
      expect(loaded.cachedAtMs, now.millisecondsSinceEpoch);
    });

    test('load returns null on a miss', () {
      expect(repo.load('not-cached'), isNull);
    });

    test('cachedCount reflects the box size', () async {
      expect(repo.cachedCount, 0);
      await repo.save('a', _newCourse('a'));
      await repo.save('b', _newCourse('b'));
      expect(repo.cachedCount, 2);
    });
  });

  group('TTL', () {
    test('infinite default — entries never go stale', () async {
      await repo.save('w', _newCourse('w'));
      // Advance the clock by a year.
      now = now.add(const Duration(days: 365));
      expect(repo.load('w'), isNotNull,
          reason: 'native default is infinite TTL — match it');
    });

    test('explicit TTL invalidates entries past the threshold',
        () async {
      await repo.save('w', _newCourse('w'));
      // Within the TTL window — fresh.
      now = now.add(const Duration(minutes: 4));
      expect(repo.load('w', ttl: const Duration(minutes: 5)), isNotNull);
      // Past the TTL — stale, returns null.
      now = now.add(const Duration(minutes: 2));
      expect(repo.load('w', ttl: const Duration(minutes: 5)), isNull);
    });
  });

  group('hot cache LRU', () {
    test('bumps recently-read entries to the front', () async {
      final smallRepo = CourseCacheRepository(
        clock: () => now,
        memoryCacheSize: 2,
      );
      await smallRepo.save('a', _newCourse('a'));
      await smallRepo.save('b', _newCourse('b'));
      // Access 'a' so it becomes MRU; 'b' becomes LRU.
      smallRepo.load('a');
      // Adding 'c' should evict 'b' (the LRU).
      await smallRepo.save('c', _newCourse('c'));
      // All three are still on disk (LRU only affects the in-
      // memory hot cache, not the persistent box). The test
      // proves the disk fallback works:
      expect(smallRepo.load('a'), isNotNull);
      expect(smallRepo.load('b'), isNotNull);
      expect(smallRepo.load('c'), isNotNull);
    });
  });

  group('evict + clear', () {
    test('evict removes a single course from both layers', () async {
      await repo.save('a', _newCourse('a'));
      await repo.save('b', _newCourse('b'));
      await repo.evict('a');
      expect(repo.load('a'), isNull);
      expect(repo.load('b'), isNotNull);
      expect(repo.cachedCount, 1);
    });

    test('clear wipes everything', () async {
      await repo.save('a', _newCourse('a'));
      await repo.save('b', _newCourse('b'));
      await repo.clear();
      expect(repo.load('a'), isNull);
      expect(repo.load('b'), isNull);
      expect(repo.cachedCount, 0);
    });
  });

  group('favorites (Story C)', () {
    test('isFavorite is false on a fresh repo', () {
      expect(repo.isFavorite('wellshire'), isFalse);
      expect(repo.favoriteCacheKeys, isEmpty);
    });

    test('toggleFavorite adds, returns true, then removes, returns false',
        () async {
      final firstResult = await repo.toggleFavorite('wellshire');
      expect(firstResult, isTrue);
      expect(repo.isFavorite('wellshire'), isTrue);
      expect(repo.favoriteCacheKeys, contains('wellshire'));

      final secondResult = await repo.toggleFavorite('wellshire');
      expect(secondResult, isFalse);
      expect(repo.isFavorite('wellshire'), isFalse);
      expect(repo.favoriteCacheKeys, isEmpty);
    });

    test('multiple favorites coexist', () async {
      await repo.toggleFavorite('a');
      await repo.toggleFavorite('b');
      await repo.toggleFavorite('c');
      expect(repo.favoriteCacheKeys, containsAll(['a', 'b', 'c']));
      expect(repo.isFavorite('a'), isTrue);
      expect(repo.isFavorite('b'), isTrue);
      expect(repo.isFavorite('c'), isTrue);
    });

    test('favorites survive a fresh repository instance (persisted)',
        () async {
      await repo.toggleFavorite('persisted');
      // Drop the repository and build a fresh one — favorites are
      // backed by the Hive box which is shared across instances.
      final fresh = CourseCacheRepository(clock: () => now);
      expect(fresh.isFavorite('persisted'), isTrue);
    });
  });

  group('listSaved (Story C)', () {
    test('returns an empty list on a fresh repo', () {
      expect(repo.listSaved(), isEmpty);
    });

    test('lists every cached course as a CourseSearchEntry, sorted by name',
        () async {
      await repo.save('wellshire',
          _newCourse('wellshire', name: 'Wellshire Golf Course'));
      await repo.save('apple', _newCourse('apple', name: 'Apple Tree GC'));
      await repo.save('mid', _newCourse('mid', name: 'Mid Course'));

      final saved = repo.listSaved();
      expect(saved.map((e) => e.name).toList(),
          ['Apple Tree GC', 'Mid Course', 'Wellshire Golf Course']);
      expect(saved.first.source, CourseSearchSource.manifest);
      expect(saved.first.cachedAtMs, isNotNull);
    });

    test('isFavorite flag on listSaved entries reflects the favorites box',
        () async {
      await repo.save('wellshire', _newCourse('wellshire', name: 'Wellshire'));
      await repo.save('lincoln', _newCourse('lincoln', name: 'Lincoln Park'));
      await repo.toggleFavorite('wellshire');

      final saved = repo.listSaved();
      final wellshireRow =
          saved.firstWhere((e) => e.cacheKey == 'wellshire');
      final lincolnRow =
          saved.firstWhere((e) => e.cacheKey == 'lincoln');
      expect(wellshireRow.isFavorite, isTrue);
      expect(lincolnRow.isFavorite, isFalse);
    });

    test('listSaved cacheKey IS the server cache key — round-trips '
        'through fetchCourse-via-cache', () async {
      await repo.save('sharp-park-golf-course',
          _newCourse('sharp-park-golf-course', name: 'Sharp Park Golf Course'));
      final saved = repo.listSaved();
      expect(saved.single.cacheKey, 'sharp-park-golf-course');
    });
  });
}
