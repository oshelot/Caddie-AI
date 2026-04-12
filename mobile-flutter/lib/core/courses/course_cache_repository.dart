// CourseCacheRepository — disk-backed persistence for fetched
// `NormalizedCourse` payloads, with TTL semantics.
//
// Per **ADR 0004**, the structured store is Hive. The native apps
// use one file per course on disk plus an index file; we collapse
// that into a single Hive box keyed by server cache key. Each
// stored value is a small JSON envelope:
//
// ```
// { "cachedAtMs": <int>, "course": <NormalizedCourse JSON> }
// ```
//
// **TTL policy.** Both natives cache courses indefinitely (no
// automatic expiration; only manual invalidation). The KAN-275 AC
// says "TTL matching native", which is "infinite by default" — but
// we expose a configurable `ttl` on the repository so KAN-S5
// consumers can choose to treat older entries as stale and force
// a re-fetch. Default TTL is `null` (= never stale), matching
// native behavior. Pass an explicit `Duration` to opt in to
// staleness checks for a particular call site.
//
// **In-memory hot cache:** the iOS native keeps an 8-entry LRU and
// the Android native keeps a 10-entry LinkedHashMap. We use a
// 16-entry `LinkedHashMap` for parity-plus-headroom. The cache
// keys are the server cache keys (string).

import 'dart:collection';
import 'dart:convert';

import '../../models/normalized_course.dart';
import '../storage/app_storage.dart';
import 'course_search_results.dart';

/// One entry as stored in the Hive box. Public so tests can
/// inspect the envelope shape directly.
class CachedCourseEnvelope {
  const CachedCourseEnvelope({
    required this.cachedAtMs,
    required this.course,
  });

  final int cachedAtMs;
  final NormalizedCourse course;

  Map<String, dynamic> toJson() => {
        'cachedAtMs': cachedAtMs,
        'course': _serializeCourse(course),
      };

  factory CachedCourseEnvelope.fromJson(Map<String, dynamic> json) {
    return CachedCourseEnvelope(
      cachedAtMs: (json['cachedAtMs'] as num).toInt(),
      course: NormalizedCourse.fromJson(
        (json['course'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  /// Round-trips just enough of `NormalizedCourse` to satisfy
  /// `NormalizedCourse.fromJson`'s required fields. The lifted
  /// model only carries the fields used by rendering, so this
  /// envelope is intentionally lean — id, name, city, state,
  /// centroid, and per-hole headers (number/par/yardages/etc.)
  /// without geometry.
  ///
  /// **Why no geometry:** the map screen always re-fetches the
  /// full course from `CourseCacheClient.fetchCourse` when it
  /// opens (the geometry is heavy and the network round-trip is
  /// fast on the cache hit path). The disk cache is a metadata
  /// store today, not a render-time backup. If a follow-up story
  /// needs geometry caching for offline mode, extend the
  /// envelope to round-trip the polygons.
  static Map<String, dynamic> _serializeCourse(NormalizedCourse course) {
    return {
      'id': course.id,
      'name': course.name,
      'city': course.city,
      'state': course.state,
      'centroid': {
        'latitude': course.centroid.lat,
        'longitude': course.centroid.lon,
      },
      'teeNames': course.teeNames,
      'teeYardageTotals': course.teeYardageTotals,
      'holes': course.holes
          .map((h) => {
                'number': h.number,
                'par': h.par,
                'strokeIndex': h.strokeIndex,
                'yardages': h.yardages,
                'teeAreas': const [],
                'lineOfPlay': null,
                'green': null,
                'pin': null,
                'bunkers': const [],
                'water': const [],
              })
          .toList(),
    };
  }
}

class CourseCacheRepository {
  CourseCacheRepository({
    DateTime Function()? clock,
    int memoryCacheSize = 16,
    Duration? defaultTtl,
  })  : _clock = clock ?? DateTime.now,
        _memoryCacheSize = memoryCacheSize,
        _defaultTtl = defaultTtl;

  final DateTime Function() _clock;
  final int _memoryCacheSize;
  final Duration? _defaultTtl;

  // LinkedHashMap with insertion order = LRU (we re-insert on
  // every read to bump entries to the head). 16 hot entries
  // covers the working set for a typical session.
  final LinkedHashMap<String, CachedCourseEnvelope> _hot =
      LinkedHashMap<String, CachedCourseEnvelope>();

  /// Returns a cached course if one exists AND it's within the
  /// configured TTL. Pass an explicit `ttl` to override the
  /// repository default for a particular call. Returns null on
  /// miss or stale.
  CachedCourseEnvelope? load(String cacheKey, {Duration? ttl}) {
    // Hot cache first.
    final hot = _hot.remove(cacheKey);
    if (hot != null) {
      _hot[cacheKey] = hot; // bump to MRU
      if (_isFresh(hot, ttl ?? _defaultTtl)) return hot;
    }

    final raw = AppStorage.courseCacheBox.get(cacheKey);
    if (raw == null) return null;

    final envelope = CachedCourseEnvelope.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    _bumpHot(cacheKey, envelope);
    if (!_isFresh(envelope, ttl ?? _defaultTtl)) return null;
    return envelope;
  }

  /// Persists a course in both the hot cache and the disk box.
  Future<void> save(String cacheKey, NormalizedCourse course) async {
    final envelope = CachedCourseEnvelope(
      cachedAtMs: _clock().millisecondsSinceEpoch,
      course: course,
    );
    _bumpHot(cacheKey, envelope);
    await AppStorage.courseCacheBox.put(
      cacheKey,
      jsonEncode(envelope.toJson()),
    );
  }

  /// Removes a single course from both layers. Used by the
  /// (currently future) "refresh course" UI affordance.
  Future<void> evict(String cacheKey) async {
    _hot.remove(cacheKey);
    await AppStorage.courseCacheBox.delete(cacheKey);
  }

  /// Wipes every cached course. Used by tests and a future
  /// "Clear app cache" settings entry.
  Future<void> clear() async {
    _hot.clear();
    await AppStorage.courseCacheBox.clear();
  }

  /// Number of distinct courses currently cached on disk.
  int get cachedCount => AppStorage.courseCacheBox.length;

  // ── favorites + saved listing (Story C, KAN-296 follow-up) ──────
  //
  // Mirrors `android/.../data/course/CourseCacheService.kt:102-170`
  // and the iOS `CourseCacheService.favoriteCourses` API. The
  // favorites store is a Hive box used as a set: keys are server
  // cache keys, values are the sentinel string `'1'`. The Saved tab
  // and the Favorites quick-access section both consume this.

  /// True when the user has starred [cacheKey].
  bool isFavorite(String cacheKey) =>
      AppStorage.courseFavoritesBox.containsKey(cacheKey);

  /// All starred cache keys, in insertion order. Used by the page
  /// wrapper to overlay the favorite flag on merged search results
  /// and to filter the Saved tab into Favorites + Other.
  Iterable<String> get favoriteCacheKeys =>
      AppStorage.courseFavoritesBox.keys.cast<String>();

  /// Toggles the favorite flag for [cacheKey]. Returns the new
  /// state (true = now favorited, false = now un-favorited).
  Future<bool> toggleFavorite(String cacheKey) async {
    final box = AppStorage.courseFavoritesBox;
    if (box.containsKey(cacheKey)) {
      await box.delete(cacheKey);
      return false;
    }
    await box.put(cacheKey, '1');
    return true;
  }

  /// Lists every course currently in the disk cache, materialized
  /// as `CourseSearchEntry` rows so the screen renders them through
  /// the same code path as live search results. Each row carries
  /// the real `isFavorite` flag (read from the favorites box) and
  /// the persisted `cachedAtMs` so the screen can show
  /// "Saved 2d ago"-style captions. Sorted by name.
  ///
  /// Source on every row is `CourseSearchSource.manifest`, which
  /// signals to the page wrapper that the cacheKey IS a real
  /// server cache key — opening the row goes through the regular
  /// fetch path and hits the local cache before any network call.
  List<CourseSearchEntry> listSaved() {
    final box = AppStorage.courseCacheBox;
    final out = <CourseSearchEntry>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final envelope = CachedCourseEnvelope.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        final course = envelope.course;
        out.add(CourseSearchEntry(
          cacheKey: key as String,
          name: course.name,
          city: course.city ?? '',
          state: course.state ?? '',
          latitude: course.centroid.lat,
          longitude: course.centroid.lon,
          source: CourseSearchSource.manifest,
          isFavorite: isFavorite(key),
          cachedAtMs: envelope.cachedAtMs,
        ));
      } catch (_) {
        // Corrupt envelope — skip silently. The repository's
        // existing tests cover the round-trip; a parse failure here
        // means a hand-edited box, which we don't want to crash on.
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  // ── internals ────────────────────────────────────────────────────

  void _bumpHot(String key, CachedCourseEnvelope envelope) {
    _hot.remove(key);
    _hot[key] = envelope;
    while (_hot.length > _memoryCacheSize) {
      _hot.remove(_hot.keys.first);
    }
  }

  bool _isFresh(CachedCourseEnvelope envelope, Duration? ttl) {
    if (ttl == null) return true; // infinite — matches native
    final ageMs = _clock().millisecondsSinceEpoch - envelope.cachedAtMs;
    return ageMs <= ttl.inMilliseconds;
  }
}
