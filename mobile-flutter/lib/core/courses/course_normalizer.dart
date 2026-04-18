// CourseNormalizer — assembles parsed OSM features into NormalizedCourse
// models. Port of ios/CaddieAI/Services/CourseNormalizer.swift.
//
// Handles spatial association (greens → holes, bunkers → corridors, etc.),
// confidence scoring, and multi-course detection via Union-Find clustering.

import 'dart:math' as math;

import '../../core/geo/geo.dart';
import '../../models/normalized_course.dart';
import 'osm_parser.dart';

class CourseNormalizer {
  /// Returns the single best (largest) course from the parsed features.
  NormalizedCourse normalize({
    required ParsedFeatures features,
    required String courseName,
    required String osmCourseId,
    String? city,
    String? state,
    LngLat? facilityPoint,
  }) {
    final all = normalizeAll(
      features: features,
      courseName: courseName,
      osmCourseId: osmCourseId,
      city: city,
      state: state,
      facilityPoint: facilityPoint,
    );
    if (all.isEmpty) {
      return NormalizedCourse(
        id: osmCourseId,
        name: courseName,
        city: city,
        state: state,
        centroid: const LngLat(0, 0),
        holes: const [],
      );
    }
    // Return the course with the most holes.
    all.sort((a, b) => b.holes.length.compareTo(a.holes.length));
    return all.first;
  }

  /// Returns multiple courses if multi-course facility is detected.
  List<NormalizedCourse> normalizeAll({
    required ParsedFeatures features,
    required String courseName,
    required String osmCourseId,
    String? city,
    String? state,
    /// If provided alongside a non-empty
    /// [ParsedFeatures.golfCourseBoundaries], filter holes to those
    /// inside polygons that share this facility name, or (fallback)
    /// the single polygon containing this point. Removes holes from
    /// neighboring facilities (disc golf, adjacent courses) that
    /// share the `golf=hole` tag.
    LngLat? facilityPoint,
    /// Minimum holes per cluster. Default 3 drops small fragments.
    /// Set to 1 for the RAG backend path to keep every hole.
    int minClusterSize = 3,
  }) {
    // 1. Build raw holes from holeLines (or greens as fallback).
    var rawHoles = _buildRawHoles(features);
    if (rawHoles.isEmpty) return [];

    // 1b. Filter by facility boundary. Many facilities (e.g.,
    // Kennedy) have MULTIPLE `leisure=golf_course` polygons —
    // one per sub-course ("Kennedy 9-Hole Regulation Course",
    // "Kennedy 18-Hole Course", "Kennedy 9-Hole Par-3 Course").
    // Match polygons by name prefix against the searched facility,
    // and include holes/features inside ANY matching polygon.
    // Fall back to "polygon containing facilityPoint" if no name match.
    //
    // IMPORTANT: the filter must also apply to tees, greens, bunkers,
    // pins, and water — otherwise the association step will attach
    // features from neighboring facilities (disc golf, adjacent
    // courses) to our holes by proximity, and the map will zoom out
    // to fit all those stray points.
    var greens = features.greens;
    var tees = features.tees;
    var pins = features.pins;
    var bunkers = features.bunkers;
    var waterFeatures = features.waterFeatures;

    if (facilityPoint != null && features.golfCourseBoundaries.isNotEmpty) {
      final targetPolygons = _selectFacilityPolygons(
        features.golfCourseBoundaries,
        courseName,
        facilityPoint,
      );
      if (targetPolygons.isNotEmpty) {
        bool inBoundary(LngLat? p) {
          if (p == null) return true; // no centroid? keep
          for (final poly in targetPolygons) {
            if (poly.contains(p)) return true;
          }
          return false;
        }

        final beforeHoles = rawHoles.length;
        rawHoles = rawHoles.where((h) {
          final lop = h.lineOfPlay;
          if (lop == null || lop.points.isEmpty) return true;
          return inBoundary(lop.points[lop.points.length ~/ 2]);
        }).toList();

        final beforeGreens = greens.length;
        greens = greens.where((g) => inBoundary(g.polygon.centroid)).toList();

        final beforeTees = tees.length;
        tees = tees.where((t) => inBoundary(t.polygon.centroid)).toList();

        final beforePins = pins.length;
        pins = pins.where((p) => inBoundary(p.point)).toList();

        final beforeBunkers = bunkers.length;
        bunkers = bunkers.where((b) => inBoundary(b.polygon.centroid)).toList();

        final beforeWater = waterFeatures.length;
        waterFeatures =
            waterFeatures.where((w) => inBoundary(w.polygon.centroid)).toList();

        // ignore: avoid_print
        print('NORMALIZER: boundary filter kept '
            'holes=$beforeHoles→${rawHoles.length}, '
            'greens=$beforeGreens→${greens.length}, '
            'tees=$beforeTees→${tees.length}, '
            'pins=$beforePins→${pins.length}, '
            'bunkers=$beforeBunkers→${bunkers.length}, '
            'water=$beforeWater→${waterFeatures.length}');
      }
    }

    // 2. Associate features to holes.
    _associateGreens(rawHoles, greens);
    _associateTees(rawHoles, tees);
    _associatePins(rawHoles, pins);
    _associateBunkers(rawHoles, bunkers);
    _associateWater(rawHoles, waterFeatures);

    // 3. Multi-course detection.
    final clusters = _detectMultiCourse(rawHoles, minClusterSize);

    final courses = <NormalizedCourse>[];
    for (var i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      cluster.sort((a, b) => a.number.compareTo(b.number));

      // Assign sequential numbers if needed.
      _assignSequentialNumbers(cluster);

      final normalizedHoles = cluster.map(_toNormalizedHole).toList();
      final allPoints = <LngLat>[];
      for (final h in normalizedHoles) {
        allPoints.addAll(h.allGeometryPoints());
      }

      final centroid = _computeCentroid(allPoints);
      final name = clusters.length > 1
          ? '$courseName (${_subCourseName(i)})'
          : courseName;
      final id =
          clusters.length > 1 ? '${osmCourseId}_$i' : osmCourseId;

      courses.add(NormalizedCourse(
        id: id,
        name: name,
        city: city,
        state: state,
        centroid: centroid,
        holes: normalizedHoles,
      ));
    }

    return courses;
  }

  /// Picks the set of `leisure=golf_course` polygons that represent
  /// the searched facility. Uses name-based matching first (handles
  /// facilities with multiple sub-course polygons like Kennedy).
  /// Falls back to the single polygon containing [facilityPoint].
  List<Polygon> _selectFacilityPolygons(
    List<ParsedGolfCourseBoundary> boundaries,
    String courseName,
    LngLat facilityPoint,
  ) {
    final facilityTokens = _nameTokens(courseName);
    if (facilityTokens.isNotEmpty) {
      // Collect polygons whose name shares at least one
      // non-generic token with the searched facility name.
      final matches = <Polygon>[];
      for (final b in boundaries) {
        final bName = b.name;
        if (bName == null) continue;
        final bTokens = _nameTokens(bName);
        for (final t in bTokens) {
          if (facilityTokens.contains(t)) {
            matches.add(b.polygon);
            break;
          }
        }
      }
      if (matches.isNotEmpty) return matches;
    }
    // Fallback: polygon containing the facility point.
    for (final b in boundaries) {
      if (b.polygon.contains(facilityPoint)) return [b.polygon];
    }
    return const [];
  }

  /// Tokens for name matching. Lowercases and strips common golf
  /// suffix words so "Kennedy Golf Course" matches "Kennedy 18-Hole
  /// Course" on the "kennedy" token.
  static const _nameStopWords = {
    'golf', 'course', 'club', 'country', 'the', 'and', '&', 'at',
    'of', 'a', 'an', 'regulation', 'hole', 'holes', '18-hole',
    '9-hole', 'par', 'par-3', 'links',
  };

  Set<String> _nameTokens(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp('[\'"\\-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !_nameStopWords.contains(t))
        .toSet();
  }

  /// Returns true if [course] has duplicate hole numbers (i.e., it
  /// is a multi-course facility stored as a single course).
  bool hasMultipleCourses(NormalizedCourse course) {
    final seen = <int>{};
    for (final h in course.holes) {
      if (h.number > 0 && !seen.add(h.number)) return true;
    }
    return false;
  }

  /// Splits a multi-course facility into separate courses using
  /// Golf Course API par sequences to assign each hole to the
  /// correct course. This works even when the courses are spatially
  /// interleaved (e.g., Terra Lago North/South share the same
  /// property and holes from both courses neighbor each other).
  ///
  /// For each duplicate hole number, the hole whose par matches
  /// apiCourse[0] goes to course 0, and the hole matching
  /// apiCourse[1] goes to course 1, etc. Holes with unique
  /// numbers or no par match go to the first course.
  ///
  /// Returns a single-element list if no duplicates exist.
  List<NormalizedCourse> splitByParSequence(
    NormalizedCourse course,
    List<List<int>> apiParSequences,
  ) {
    if (apiParSequences.length < 2) return [course];
    if (!hasMultipleCourses(course)) return [course];

    final courseCount = apiParSequences.length;
    final buckets = List.generate(courseCount, (_) => <NormalizedHole>[]);

    // Group holes by number.
    final byNumber = <int, List<NormalizedHole>>{};
    for (final h in course.holes) {
      byNumber.putIfAbsent(h.number, () => []).add(h);
    }

    for (final entry in byNumber.entries) {
      final holeNum = entry.key;
      final candidates = entry.value;

      if (candidates.length == 1) {
        // Unique hole number — assign to whichever API course's par
        // matches, defaulting to course 0.
        final h = candidates.first;
        var assigned = false;
        for (var ci = 0; ci < courseCount; ci++) {
          if (holeNum - 1 < apiParSequences[ci].length &&
              apiParSequences[ci][holeNum - 1] == h.par) {
            buckets[ci].add(h);
            assigned = true;
            break;
          }
        }
        if (!assigned) buckets[0].add(h);
      } else {
        // Duplicate hole numbers — match each candidate to the API
        // course whose par at this hole number agrees.
        final usedCourses = <int>{};
        final unmatched = <NormalizedHole>[];

        for (final h in candidates) {
          var matched = false;
          for (var ci = 0; ci < courseCount; ci++) {
            if (usedCourses.contains(ci)) continue;
            if (holeNum - 1 < apiParSequences[ci].length &&
                apiParSequences[ci][holeNum - 1] == h.par) {
              buckets[ci].add(h);
              usedCourses.add(ci);
              matched = true;
              break;
            }
          }
          if (!matched) unmatched.add(h);
        }

        // Assign remaining unmatched holes to unused courses.
        for (final h in unmatched) {
          for (var ci = 0; ci < courseCount; ci++) {
            if (!usedCourses.contains(ci)) {
              buckets[ci].add(h);
              usedCourses.add(ci);
              break;
            }
          }
        }
      }
    }

    final results = <NormalizedCourse>[];
    for (var i = 0; i < courseCount; i++) {
      final holes = buckets[i];
      if (holes.isEmpty) continue;
      holes.sort((a, b) => a.number.compareTo(b.number));

      final allPoints = <LngLat>[];
      for (final h in holes) {
        allPoints.addAll(h.allGeometryPoints());
      }
      final centroid = _computeCentroid(allPoints);

      results.add(NormalizedCourse(
        id: '${course.id}_$i',
        name: '${course.name} (${_subCourseName(i)})',
        city: course.city,
        state: course.state,
        centroid: centroid,
        holes: holes,
      ));
    }

    return results.isEmpty ? [course] : results;
  }

  // -------------------------------------------------------------------------
  // Hole building
  // -------------------------------------------------------------------------

  List<_RawHole> _buildRawHoles(ParsedFeatures features) {
    if (features.holeLines.isNotEmpty) {
      return features.holeLines.map((hl) {
        return _RawHole(
          number: hl.number ?? 0,
          par: hl.par ?? 4,
          lineOfPlay: hl.lineString,
          refPrefix: hl.refPrefix,
          isPar3Course: hl.isPar3Course,
        );
      }).toList();
    }
    // Fallback: build from greens.
    if (features.greens.isNotEmpty) {
      return features.greens.map((g) {
        return _RawHole(
          number: g.holeNumber ?? 0,
          par: 4,
          green: g.polygon,
        );
      }).toList();
    }
    return [];
  }

  // -------------------------------------------------------------------------
  // Spatial association
  // -------------------------------------------------------------------------

  /// True when [feature]'s ref prefix is compatible with [hole]'s.
  /// A feature can be attached to a hole if:
  ///   - Both have the same non-empty prefix (e.g., both "west"), OR
  ///   - The hole has no prefix (numeric refs) and the feature has
  ///     no prefix either. A feature with a non-empty prefix is NOT
  ///     attached to a numeric-ref hole (prevents West tees ending
  ///     up on Lind/Creek holes).
  bool _prefixCompatible(String holePrefix, String featurePrefix) {
    if (holePrefix == featurePrefix) return true;
    // Allow fallback: if feature has no prefix and hole has one, still
    // match. (Some OSM tees are just numeric refs even within a named
    // sub-course.) But NOT the other way around — a prefixed feature
    // must belong to a prefixed hole of the same family.
    if (featurePrefix.isEmpty && holePrefix.isNotEmpty) return true;
    return false;
  }

  void _associateGreens(List<_RawHole> holes, List<ParsedGreen> greens) {
    for (final green in greens) {
      final greenCenter = green.polygon.centroid;
      if (greenCenter == null) continue;

      _RawHole? best;
      double bestDist = 500;
      for (final hole in holes) {
        if (!_prefixCompatible(hole.refPrefix, green.refPrefix)) continue;
        // Match by hole number first.
        if (green.holeNumber != null &&
            green.holeNumber == hole.number &&
            hole.number > 0) {
          best = hole;
          break;
        }
        // Match by proximity to line-of-play end.
        final endPt = hole.lineOfPlay?.endPoint;
        if (endPt != null) {
          final d = haversineMeters(endPt, greenCenter);
          if (d < bestDist) {
            bestDist = d;
            best = hole;
          }
        }
      }
      if (best != null && best.green == null) {
        best.green = green.polygon;
      }
    }
  }

  void _associateTees(List<_RawHole> holes, List<ParsedTee> tees) {
    for (final tee in tees) {
      final teeCenter = tee.polygon.centroid;
      if (teeCenter == null) continue;

      _RawHole? best;
      double bestDist = 300;
      for (final hole in holes) {
        if (!_prefixCompatible(hole.refPrefix, tee.refPrefix)) continue;
        if (tee.holeNumber != null &&
            tee.holeNumber == hole.number &&
            hole.number > 0) {
          best = hole;
          break;
        }
        final startPt = hole.lineOfPlay?.startPoint;
        if (startPt != null) {
          final d = haversineMeters(startPt, teeCenter);
          if (d < bestDist) {
            bestDist = d;
            best = hole;
          }
        }
      }
      if (best != null) {
        best.tees.add(tee.polygon);
      }
    }
  }

  void _associatePins(List<_RawHole> holes, List<ParsedPin> pins) {
    for (final pin in pins) {
      _RawHole? best;
      double bestDist = 100;
      for (final hole in holes) {
        if (!_prefixCompatible(hole.refPrefix, pin.refPrefix)) continue;
        if (pin.holeNumber != null &&
            pin.holeNumber == hole.number &&
            hole.number > 0) {
          best = hole;
          break;
        }
        final greenCenter = hole.green?.centroid;
        if (greenCenter != null) {
          final d = haversineMeters(greenCenter, pin.point);
          if (d < bestDist) {
            bestDist = d;
            best = hole;
          }
        }
      }
      if (best != null && best.pin == null) {
        best.pin = pin.point;
      }
    }
  }

  void _associateBunkers(List<_RawHole> holes, List<ParsedBunker> bunkers) {
    for (final bunker in bunkers) {
      final bunkerCenter = bunker.polygon.centroid;
      if (bunkerCenter == null) continue;

      _RawHole? best;
      double bestDist = 100;
      for (final hole in holes) {
        final d = _minDistanceToCorridor(bunkerCenter, hole);
        if (d < bestDist) {
          bestDist = d;
          best = hole;
        }
      }
      if (best != null) {
        best.bunkers.add(bunker.polygon);
      }
    }
  }

  void _associateWater(List<_RawHole> holes, List<ParsedWater> waters) {
    for (final water in waters) {
      final waterCenter = water.polygon.centroid;
      if (waterCenter == null) continue;

      for (final hole in holes) {
        final d = _minDistanceToCorridor(waterCenter, hole);
        if (d < 150) {
          hole.water.add(water.polygon);
        }
      }
    }
  }

  /// Minimum distance from a point to the hole's corridor (lineOfPlay
  /// points + green centroid).
  double _minDistanceToCorridor(LngLat point, _RawHole hole) {
    double minDist = double.infinity;
    final lop = hole.lineOfPlay;
    if (lop != null) {
      for (final p in lop.points) {
        final d = haversineMeters(point, p);
        if (d < minDist) minDist = d;
      }
    }
    final gc = hole.green?.centroid;
    if (gc != null) {
      final d = haversineMeters(point, gc);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  // -------------------------------------------------------------------------
  // Multi-course detection (Union-Find clustering)
  // -------------------------------------------------------------------------

  List<List<_RawHole>> _detectMultiCourse(List<_RawHole> holes, [int minSize = 3]) {
    // First, exclude par-3 course holes — they're a separate
    // facility feature that should never be mixed with regulation
    // course clusters (e.g., Kennedy's 9-hole par-3 course).
    final regulationHoles = holes.where((h) => !h.isPar3Course).toList();
    if (regulationHoles.isEmpty) return [holes];

    // Check for duplicate hole numbers among regulation holes.
    final numberCounts = <int, int>{};
    for (final h in regulationHoles) {
      if (h.number > 0) {
        numberCounts[h.number] = (numberCounts[h.number] ?? 0) + 1;
      }
    }
    final hasDuplicates = numberCounts.values.any((c) => c > 1);
    if (!hasDuplicates) return [regulationHoles];

    // STEP 1: Pre-group by ref prefix. Holes with non-empty prefixes
    // (e.g., "west9-1", "west9-2") are known-same-course and must
    // not be mixed with other prefixes or numeric-only refs. This
    // prevents spatial clustering from chaining unrelated courses
    // together when their bounding boxes overlap.
    final prefixGroups = <String, List<_RawHole>>{};
    for (final h in regulationHoles) {
      prefixGroups.putIfAbsent(h.refPrefix, () => []).add(h);
    }

    // If ref prefixes cleanly separate the courses (multiple
    // non-empty prefixes, or a non-empty prefix alongside numerics),
    // use those groups directly. Each group is treated as its own
    // course — no further spatial clustering within a group.
    final nonEmptyPrefixes = prefixGroups.keys.where((k) => k.isNotEmpty).length;
    if (nonEmptyPrefixes >= 1) {
      final result = <List<_RawHole>>[];
      for (final group in prefixGroups.values) {
        if (group.length < minSize) continue;
        final isNumericGroup = group.first.refPrefix.isEmpty;
        final hasLate = group.any((h) => h.number > 9);
        final hasEarly = group.any((h) => h.number >= 1 && h.number <= 9);

        if (isNumericGroup && hasLate && hasEarly) {
          // Numeric refs spanning 1-18 alongside another prefix
          // group = "combined scorecard 18" at a multi-9 facility
          // (e.g., Kennedy Lind+Creek → 1-18). Dedupe by hole
          // number (multiple OSM ways with the same ref are
          // typical data-quality duplicates — green + fairway +
          // line all tagged with ref=2), keeping the entry with
          // the longest line-of-play (most complete geometry),
          // then split at 9 into front/back.
          final deduped = _dedupeByHoleNumber(group);
          final front = deduped.where((h) => h.number <= 9).toList();
          final back = deduped.where((h) => h.number > 9).toList();
          // Renumber back nine to 1-9 so downstream matching works
          // per-9.
          for (final h in back) {
            h.number -= 9;
          }
          if (front.length >= minSize) result.add(front);
          if (back.length >= minSize) result.add(back);
        } else if (isNumericGroup && _hasDuplicateNumbers(group)) {
          // Terra Lago style: duplicates within 1-9 means two full
          // courses share numbering → spatial clustering separates
          // them.
          final subClusters = _spatialCluster(group);
          for (final sc in subClusters) {
            if (sc.length >= minSize) result.add(sc);
          }
        } else {
          result.add(group);
        }
      }
      if (result.length >= 2) return result;
    }

    // STEP 2 (fallback): Pure numeric refs with duplicates —
    // Terra Lago style. Use spatial clustering.
    return _spatialCluster(regulationHoles);
  }

  bool _hasDuplicateNumbers(List<_RawHole> holes) {
    final seen = <int>{};
    for (final h in holes) {
      if (h.number > 0 && !seen.add(h.number)) return true;
    }
    return false;
  }

  /// For each distinct hole number, keeps the single entry with the
  /// longest line-of-play (most complete geometry). OSM commonly
  /// has duplicate ways tagged with the same `ref` — e.g., a
  /// fairway way + a line-of-play way both tagged ref="2" — which
  /// are really the same physical hole and shouldn't be treated
  /// as separate courses.
  List<_RawHole> _dedupeByHoleNumber(List<_RawHole> holes) {
    final bestByNumber = <int, _RawHole>{};
    for (final h in holes) {
      final existing = bestByNumber[h.number];
      if (existing == null) {
        bestByNumber[h.number] = h;
        continue;
      }
      final existingPts = existing.lineOfPlay?.points.length ?? 0;
      final candidatePts = h.lineOfPlay?.points.length ?? 0;
      if (candidatePts > existingPts) bestByNumber[h.number] = h;
    }
    return bestByNumber.values.toList();
  }

  List<List<_RawHole>> _spatialCluster(List<_RawHole> holes) {
    // Union-Find clustering with 400m threshold.
    final parent = List<int>.generate(holes.length, (i) => i);

    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (var i = 0; i < holes.length; i++) {
      for (var j = i + 1; j < holes.length; j++) {
        final ci = _holeCentroid(holes[i]);
        final cj = _holeCentroid(holes[j]);
        if (ci != null && cj != null) {
          if (haversineMeters(ci, cj) < 400) {
            union(i, j);
          }
        }
      }
    }

    final clusters = <int, List<_RawHole>>{};
    for (var i = 0; i < holes.length; i++) {
      final root = find(i);
      clusters.putIfAbsent(root, () => []).add(holes[i]);
    }

    // Filter clusters with >= 3 holes.
    final result =
        clusters.values.where((c) => c.length >= minSize).toList();
    return result.isEmpty ? [holes] : result;
  }

  LngLat? _holeCentroid(_RawHole hole) {
    final lop = hole.lineOfPlay;
    if (lop != null && lop.points.isNotEmpty) {
      return lop.points[lop.points.length ~/ 2];
    }
    return hole.green?.centroid;
  }

  // -------------------------------------------------------------------------
  // Finalization
  // -------------------------------------------------------------------------

  void _assignSequentialNumbers(List<_RawHole> holes) {
    // If any holes lack numbers, assign sequentially.
    final hasGaps = holes.any((h) => h.number <= 0);
    if (hasGaps) {
      for (var i = 0; i < holes.length; i++) {
        if (holes[i].number <= 0) {
          holes[i].number = i + 1;
        }
      }
    }
  }

  NormalizedHole _toNormalizedHole(_RawHole raw) {
    return NormalizedHole(
      number: raw.number,
      par: raw.par,
      strokeIndex: null,
      yardages: const {},
      teeAreas: raw.tees,
      lineOfPlay: raw.lineOfPlay,
      green: raw.green,
      pin: raw.pin,
      bunkers: raw.bunkers,
      water: raw.water,
    );
  }

  LngLat _computeCentroid(List<LngLat> points) {
    if (points.isEmpty) return const LngLat(0, 0);
    double sumLon = 0, sumLat = 0;
    for (final p in points) {
      sumLon += p.lon;
      sumLat += p.lat;
    }
    return LngLat(sumLon / points.length, sumLat / points.length);
  }

  String _subCourseName(int index) {
    const names = [
      'North',
      'South',
      'East',
      'West',
      'Links',
      'Pines',
      'Lakes',
      'Hills'
    ];
    return index < names.length ? names[index] : 'Course ${index + 1}';
  }
}

// ---------------------------------------------------------------------------
// Internal mutable hole during assembly
// ---------------------------------------------------------------------------

class _RawHole {
  int number;
  int par;
  LineString? lineOfPlay;
  Polygon? green;
  LngLat? pin;
  List<Polygon> tees = [];
  List<Polygon> bunkers = [];
  List<Polygon> water = [];
  /// From ParsedHoleLine.refPrefix. Non-empty prefix = "this hole
  /// belongs to a named sub-course" (e.g., "west" for Kennedy West).
  String refPrefix = '';
  bool isPar3Course = false;

  _RawHole({
    required this.number,
    required this.par,
    this.lineOfPlay,
    this.green,
    this.refPrefix = '',
    this.isPar3Course = false,
  });
}
