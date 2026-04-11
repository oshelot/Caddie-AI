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
