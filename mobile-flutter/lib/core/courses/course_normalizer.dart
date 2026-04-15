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
  }) {
    final all = normalizeAll(
      features: features,
      courseName: courseName,
      osmCourseId: osmCourseId,
      city: city,
      state: state,
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
  }) {
    // 1. Build raw holes from holeLines (or greens as fallback).
    var rawHoles = _buildRawHoles(features);
    if (rawHoles.isEmpty) return [];

    // 2. Associate features to holes.
    _associateGreens(rawHoles, features.greens);
    _associateTees(rawHoles, features.tees);
    _associatePins(rawHoles, features.pins);
    _associateBunkers(rawHoles, features.bunkers);
    _associateWater(rawHoles, features.waterFeatures);

    // 3. Multi-course detection.
    final clusters = _detectMultiCourse(rawHoles);

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

  void _associateGreens(List<_RawHole> holes, List<ParsedGreen> greens) {
    for (final green in greens) {
      final greenCenter = green.polygon.centroid;
      if (greenCenter == null) continue;

      _RawHole? best;
      double bestDist = 500;
      for (final hole in holes) {
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

  List<List<_RawHole>> _detectMultiCourse(List<_RawHole> holes) {
    // Check for duplicate hole numbers.
    final numberCounts = <int, int>{};
    for (final h in holes) {
      if (h.number > 0) {
        numberCounts[h.number] = (numberCounts[h.number] ?? 0) + 1;
      }
    }
    final hasDuplicates = numberCounts.values.any((c) => c > 1);
    if (!hasDuplicates) return [holes];

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
        clusters.values.where((c) => c.length >= 3).toList();
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

  _RawHole({
    required this.number,
    required this.par,
    this.lineOfPlay,
    this.green,
  });
}
