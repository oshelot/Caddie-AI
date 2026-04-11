// HoleAnalysisEngine — KAN-293 (S7.2) Flutter port of
// `ios/CaddieAI/Services/HoleAnalysisEngine.swift`. Per **ADR 0008**,
// iOS is the authoritative source.
//
// **Scope:** the AC requires dogleg detection, green depth/width,
// and hazard side classification (left / right / greenside /
// frontOfGreen). The verbose `_buildSummary` builder from iOS
// (~85 lines of string concatenation) is implemented in a leaner
// form here — it produces the same structured fields, but the
// strategic-summary text is built by joining the same per-section
// strings the iOS native uses. Future stories can extend the
// summary builder if KAN-S11 (caddie screen) needs richer text.
//
// **Geometry helpers** (`_pointAtDistance`, `_bearingAtDistance`,
// `_distanceAlongLine`, `_projectPoint`) live as private static
// methods at the bottom of this file because they're only used
// by this engine. The `geo.dart` shared module has the basics
// (`haversineMeters`, `bearingDegrees`); these are the additional
// LineString-walking helpers.

import 'dart:math' as math;

import '../../models/normalized_course.dart';
import '../geo/geo.dart';
import 'hole_analysis.dart';

abstract final class HoleAnalysisEngine {
  HoleAnalysisEngine._();

  static const double _metersToYards = 1.09361;

  /// Primary entry point. Mirrors iOS `HoleAnalysisEngine.analyze(
  /// hole:course:profile:weatherContext:selectedTee:)`. Returns a
  /// `HoleAnalysis` with all fields populated where possible
  /// (nullable fields stay null when the underlying geometry is
  /// missing — e.g. par 3 holes with no line-of-play don't get a
  /// dogleg analysis).
  static HoleAnalysis analyze({
    required NormalizedHole hole,
    String? selectedTee,
  }) {
    final teeYards = selectedTee != null ? hole.yardages[selectedTee] : null;
    final lineDist = hole.lineOfPlay == null
        ? 0.0
        : _totalDistance(hole.lineOfPlay!.points);
    final totalYards = teeYards ??
        (lineDist > 0 ? (lineDist * _metersToYards).round() : null);

    final dogleg = _detectDogleg(hole.lineOfPlay);
    final fairwayWidth = _estimateFairwayWidth(hole);
    final greenDims = _measureGreen(hole);
    final hazards = _classifyHazards(hole);

    final summary = _buildSummary(
      hole: hole,
      totalDistYards: totalYards,
      dogleg: dogleg,
      fairwayWidthYards: fairwayWidth,
      greenDims: greenDims,
      hazards: hazards,
      selectedTee: selectedTee,
    );

    return HoleAnalysis(
      holeNumber: hole.number,
      par: hole.par,
      totalDistanceYards: totalYards,
      dogleg: dogleg,
      fairwayWidthAtLandingYards: fairwayWidth,
      greenDepthYards: greenDims?.depth,
      greenWidthYards: greenDims?.width,
      hazards: hazards,
      deterministicSummary: summary,
    );
  }

  // ── Dogleg detection (iOS lines 101-144) ────────────────────────

  static DoglegInfo? _detectDogleg(LineString? line) {
    if (line == null) return null;
    final pts = line.points;
    if (pts.length < 3) return null;

    final segments = <_Segment>[];
    for (var i = 1; i < pts.length; i++) {
      final bearing = bearingDegrees(pts[i - 1], pts[i]);
      final length = haversineMeters(pts[i - 1], pts[i]);
      segments.add(_Segment(bearing, length));
    }

    var maxChange = 0.0;
    var maxChangeIndex = 0;
    for (var i = 1; i < segments.length; i++) {
      var change = segments[i].bearing - segments[i - 1].bearing;
      if (change > 180) change -= 360;
      if (change < -180) change += 360;
      if (change.abs() > maxChange.abs()) {
        maxChange = change;
        maxChangeIndex = i;
      }
    }

    if (maxChange.abs() < 15) return null;

    var distToBend = 0.0;
    for (var i = 0; i < maxChangeIndex; i++) {
      distToBend += segments[i].length;
    }

    return DoglegInfo(
      direction: maxChange > 0 ? DoglegDirection.right : DoglegDirection.left,
      distanceFromTeeYards: (distToBend * _metersToYards).round(),
      bendAngleDegrees: maxChange.abs(),
    );
  }

  // ── Fairway width (iOS lines 149-184) ───────────────────────────

  static int? _estimateFairwayWidth(NormalizedHole hole) {
    final line = hole.lineOfPlay;
    if (line == null) return null;
    final totalDist = _totalDistance(line.points);
    if (totalDist <= 0) return null;

    final double landingFraction;
    switch (hole.par) {
      case 3:
        landingFraction = 0.70;
      case 5:
        landingFraction = 0.40;
      default:
        landingFraction = 0.60;
    }
    final landingDist = totalDist * landingFraction;

    final landingPoint = _pointAtDistance(line.points, landingDist);
    final bearing = _bearingAtDistance(line.points, landingDist);
    if (landingPoint == null || bearing == null) return null;

    final perpBearing = bearing + 90;
    const sampleDist = 50.0;
    final left = _projectPoint(landingPoint, perpBearing, sampleDist);
    final right =
        _projectPoint(landingPoint, perpBearing + 180, sampleDist);

    final widthMeters = haversineMeters(left, right);
    final widthYards = (widthMeters * _metersToYards).round();
    return widthYards > 60 ? 60 : widthYards;
  }

  // ── Green dimension projection (iOS lines 217-269) ──────────────

  static GreenDimensions? _measureGreen(NormalizedHole hole) {
    final green = hole.green;
    if (green == null) return null;
    final ring = green.outerRing;
    if (ring.length < 3) return null;

    double approachBearing = 0;
    final line = hole.lineOfPlay;
    if (line != null && line.points.length >= 2 && line.endPoint != null) {
      final secondLast = line.points[line.points.length - 2];
      approachBearing = bearingDegrees(secondLast, line.endPoint!);
    }
    final perpBearing = approachBearing + 90;
    final centroid = green.centroid;
    if (centroid == null) return null;

    var minDepth = double.infinity;
    var maxDepth = -double.infinity;
    var minWidth = double.infinity;
    var maxWidth = -double.infinity;

    final approachRad = approachBearing * math.pi / 180;
    final perpRad = perpBearing * math.pi / 180;
    final cosCenterLat = math.cos(centroid.lat * math.pi / 180);

    for (final p in ring) {
      final dx = (p.lon - centroid.lon) * cosCenterLat;
      final dy = p.lat - centroid.lat;
      final depthProj = dx * math.sin(approachRad) + dy * math.cos(approachRad);
      final widthProj = dx * math.sin(perpRad) + dy * math.cos(perpRad);
      if (depthProj < minDepth) minDepth = depthProj;
      if (depthProj > maxDepth) maxDepth = depthProj;
      if (widthProj < minWidth) minWidth = widthProj;
      if (widthProj > maxWidth) maxWidth = widthProj;
    }

    final depthDeg = maxDepth - minDepth;
    final widthDeg = maxWidth - minWidth;
    final depthMeters = depthDeg * 111139;
    final widthMeters = widthDeg * 111139;
    final depthYards = math.max(1, (depthMeters * _metersToYards).round());
    final widthYards = math.max(1, (widthMeters * _metersToYards).round());

    return GreenDimensions(depth: depthYards, width: widthYards);
  }

  // ── Hazard classification (iOS lines 273-367) ───────────────────

  static List<HoleHazardInfo> _classifyHazards(NormalizedHole hole) {
    final line = hole.lineOfPlay;
    if (line == null) return const [];
    final totalDist = _totalDistance(line.points);
    if (totalDist <= 0 || line.points.length < 2) return const [];

    final greenCenter = hole.green?.centroid;
    const greensideThresholdMeters = 27.432; // 30 yards in meters

    final hazards = <HoleHazardInfo>[];

    void process(List<Polygon> polygons, HazardType type) {
      for (final poly in polygons) {
        final centroid = poly.centroid;
        if (centroid == null) continue;
        hazards.add(_classifySingle(
          centroid: centroid,
          type: type,
          line: line,
          totalDist: totalDist,
          greenCenter: greenCenter,
          greensideThresholdMeters: greensideThresholdMeters,
        ));
      }
    }

    process(hole.bunkers, HazardType.bunker);
    process(hole.water, HazardType.water);

    hazards.sort((a, b) {
      final aDist = a.distanceFromTeeYards ?? 0;
      final bDist = b.distanceFromTeeYards ?? 0;
      return aDist.compareTo(bDist);
    });
    return hazards;
  }

  static HoleHazardInfo _classifySingle({
    required LngLat centroid,
    required HazardType type,
    required LineString line,
    required double totalDist,
    required LngLat? greenCenter,
    required double greensideThresholdMeters,
  }) {
    final distAlong = _distanceAlongLine(line.points, centroid);
    final distYards = (distAlong * _metersToYards).round();

    HazardSide side;
    if (greenCenter != null &&
        haversineMeters(centroid, greenCenter) < greensideThresholdMeters) {
      side = HazardSide.greenside;
    } else if (distAlong > totalDist * 0.90) {
      side = HazardSide.frontOfGreen;
    } else {
      final linePoint = _pointAtDistance(line.points, distAlong);
      final bearing = _bearingAtDistance(line.points, distAlong);
      if (linePoint == null || bearing == null) {
        side = HazardSide.left;
      } else {
        const lookAhead = 10.0;
        final directionPoint = _projectPoint(linePoint, bearing, lookAhead);
        final cross = _crossProductSign(linePoint, directionPoint, centroid);
        side = cross > 0 ? HazardSide.left : HazardSide.right;
      }
    }

    final description = _describeHazard(type, side, distYards);
    return HoleHazardInfo(
      type: type,
      side: side,
      distanceFromTeeYards: distYards,
      description: description,
    );
  }

  static String _describeHazard(HazardType type, HazardSide side, int distYards) {
    final typeName = type == HazardType.bunker ? 'Bunker' : 'Water';
    switch (side) {
      case HazardSide.greenside:
        return '$typeName greenside';
      case HazardSide.frontOfGreen:
        return '$typeName in front of green';
      case HazardSide.crossing:
        return '$typeName crossing fairway at $distYards yards';
      case HazardSide.left:
        return '$typeName left at $distYards yards';
      case HazardSide.right:
        return '$typeName right at $distYards yards';
    }
  }

  // ── Summary builder (lean port — iOS lines 388-486) ─────────────

  static String _buildSummary({
    required NormalizedHole hole,
    required int? totalDistYards,
    required DoglegInfo? dogleg,
    required int? fairwayWidthYards,
    required GreenDimensions? greenDims,
    required List<HoleHazardInfo> hazards,
    String? selectedTee,
  }) {
    final parts = <String>[];

    var opening = 'Hole ${hole.number}';
    opening += ' is a par ${hole.par}';
    if (selectedTee != null && hole.yardages[selectedTee] != null) {
      opening +=
          ' playing ${hole.yardages[selectedTee]} yards from the $selectedTee tees';
    } else if (totalDistYards != null) {
      opening += ' playing approximately $totalDistYards yards';
    }
    opening += '.';
    parts.add(opening);

    if (dogleg != null) {
      final dirName =
          dogleg.direction == DoglegDirection.left ? 'left' : 'right';
      parts.add(
        'The fairway doglegs $dirName at about ${dogleg.distanceFromTeeYards} yards from the tee.',
      );
    }

    if (fairwayWidthYards != null) {
      final desc = fairwayWidthYards < 25
          ? 'narrow'
          : fairwayWidthYards < 35
              ? 'average width'
              : 'generous';
      if (dogleg != null) {
        parts.add(
          'The fairway is approximately $fairwayWidthYards yards wide at the ${dogleg.distanceFromTeeYards}-yard mark — $desc.',
        );
      } else {
        parts.add(
          'The fairway is approximately $fairwayWidthYards yards wide at the landing zone — $desc.',
        );
      }
    }

    if (greenDims != null) {
      parts.add(
        'The green is ${greenDims.depth} yards deep and ${greenDims.width} yards wide.',
      );
    }

    if (hazards.isNotEmpty) {
      final descs = hazards.map((h) => h.description.toLowerCase()).toList();
      if (descs.length == 1) {
        parts.add('Watch for ${descs.first}.');
      } else {
        final joined = descs.sublist(0, descs.length - 1).join(', ');
        parts.add('Hazards include $joined, and ${descs.last}.');
      }
    }

    return parts.join(' ');
  }

  // ── LineString geometry helpers ─────────────────────────────────
  //
  // These mirror the iOS `GeoJSONLineString` extension methods. They
  // live as private functions here because the lifted Dart `LineString`
  // (in `lib/core/geo/geo.dart`) intentionally stays minimal —
  // adding domain-specific helpers there would bloat a module that's
  // supposed to be just primitives.

  static double _totalDistance(List<LngLat> pts) {
    if (pts.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      total += haversineMeters(pts[i - 1], pts[i]);
    }
    return total;
  }

  /// Returns the LngLat at the given distance along the polyline,
  /// linearly interpolating within the segment that contains it.
  /// Null if the distance is outside the line.
  static LngLat? _pointAtDistance(List<LngLat> pts, double distMeters) {
    if (pts.length < 2 || distMeters < 0) return null;
    var traveled = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final segLen = haversineMeters(pts[i - 1], pts[i]);
      if (traveled + segLen >= distMeters) {
        final frac = segLen == 0 ? 0.0 : (distMeters - traveled) / segLen;
        return LngLat(
          pts[i - 1].lon + (pts[i].lon - pts[i - 1].lon) * frac,
          pts[i - 1].lat + (pts[i].lat - pts[i - 1].lat) * frac,
        );
      }
      traveled += segLen;
    }
    return pts.last;
  }

  /// Returns the bearing of the segment that contains the given
  /// distance along the polyline. Null if the line is empty.
  static double? _bearingAtDistance(List<LngLat> pts, double distMeters) {
    if (pts.length < 2) return null;
    var traveled = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final segLen = haversineMeters(pts[i - 1], pts[i]);
      if (traveled + segLen >= distMeters) {
        return bearingDegrees(pts[i - 1], pts[i]);
      }
      traveled += segLen;
    }
    return bearingDegrees(pts[pts.length - 2], pts.last);
  }

  /// Distance along the polyline from the start to the closest
  /// point on the line to the supplied target. Used to position
  /// hazards relative to the tee.
  static double _distanceAlongLine(List<LngLat> pts, LngLat target) {
    if (pts.length < 2) return 0;
    var bestDist = double.infinity;
    var bestAlong = 0.0;
    var traveled = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final segLen = haversineMeters(pts[i - 1], pts[i]);
      // Project target onto this segment, clamped to [0, 1].
      final ax = pts[i - 1].lon;
      final ay = pts[i - 1].lat;
      final bx = pts[i].lon;
      final by = pts[i].lat;
      final tx = target.lon;
      final ty = target.lat;
      final dx = bx - ax;
      final dy = by - ay;
      final lenSq = dx * dx + dy * dy;
      double t;
      if (lenSq == 0) {
        t = 0;
      } else {
        t = ((tx - ax) * dx + (ty - ay) * dy) / lenSq;
        if (t < 0) t = 0;
        if (t > 1) t = 1;
      }
      final projLon = ax + dx * t;
      final projLat = ay + dy * t;
      final distToTarget =
          haversineMeters(LngLat(projLon, projLat), target);
      if (distToTarget < bestDist) {
        bestDist = distToTarget;
        bestAlong = traveled + segLen * t;
      }
      traveled += segLen;
    }
    return bestAlong;
  }

  /// Projects a point along a bearing for a given distance, using
  /// the spherical-law-of-cosines variant. Mirrors iOS `projectPoint`.
  static LngLat _projectPoint(
    LngLat origin,
    double bearing,
    double distanceMeters,
  ) {
    const r = 6371000.0;
    final bearingRad = bearing * math.pi / 180;
    final lat1 = origin.lat * math.pi / 180;
    final lon1 = origin.lon * math.pi / 180;
    final d = distanceMeters / r;

    final lat2 = math.asin(math.sin(lat1) * math.cos(d) +
        math.cos(lat1) * math.sin(d) * math.cos(bearingRad));
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearingRad) * math.sin(d) * math.cos(lat1),
          math.cos(d) - math.sin(lat1) * math.sin(lat2),
        );

    return LngLat(lon2 * 180 / math.pi, lat2 * 180 / math.pi);
  }

  /// 2D cross-product sign for left/right side detection. Returns
  /// > 0 for points on the left of the origin→target line, < 0 for
  /// the right. Operates in lon/lat space directly which is fine
  /// for the small distances hazards live at.
  static double _crossProductSign(
    LngLat origin,
    LngLat target,
    LngLat point,
  ) {
    final ax = target.lon - origin.lon;
    final ay = target.lat - origin.lat;
    final bx = point.lon - origin.lon;
    final by = point.lat - origin.lat;
    return ax * by - ay * bx;
  }
}

class _Segment {
  const _Segment(this.bearing, this.length);
  final double bearing;
  final double length;
}
