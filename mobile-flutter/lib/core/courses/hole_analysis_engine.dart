// HoleAnalysisEngine — Flutter port of the iOS HoleAnalysisEngine.
// Produces a deterministic, structured analysis of a single hole
// (geometry, hazards, weather context) that the LLM caddie prompt
// can consume without any model calls.

import 'dart:math' as math;

import '../geo/geo.dart';
import '../../models/normalized_course.dart';
import '../weather/weather_data.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class HoleAnalysis {
  final int holeNumber;
  final int? par;
  final int? totalDistanceYards;
  final Map<String, int>? yardagesByTee;
  final DoglegInfo? dogleg;
  final int? fairwayWidthAtLandingYards;
  final int? greenDepthYards;
  final int? greenWidthYards;
  final List<HoleHazardInfo> hazards;
  final HoleWeatherContext? weather;
  final String deterministicSummary;

  const HoleAnalysis({
    required this.holeNumber,
    required this.par,
    required this.totalDistanceYards,
    required this.yardagesByTee,
    required this.dogleg,
    required this.fairwayWidthAtLandingYards,
    required this.greenDepthYards,
    required this.greenWidthYards,
    required this.hazards,
    required this.weather,
    required this.deterministicSummary,
  });
}

class DoglegInfo {
  final String direction; // "left" or "right"
  final int distanceFromTeeYards;
  final double bendAngleDegrees;

  const DoglegInfo({
    required this.direction,
    required this.distanceFromTeeYards,
    required this.bendAngleDegrees,
  });
}

enum HazardSide { left, right, greenside, frontOfGreen, crossing }

class HoleHazardInfo {
  final String type; // "Water" or "Bunker"
  final HazardSide side;
  final int? distanceFromTeeYards;
  final String description;

  const HoleHazardInfo({
    required this.type,
    required this.side,
    required this.distanceFromTeeYards,
    required this.description,
  });
}

class HoleWeatherContext {
  final int temperatureF;
  final int windSpeedMph;
  final String windCompassDirection;
  final String windRelativeToHole; // "into", "helping", "cross left-to-right", "cross right-to-left"
  final String conditionDescription;
  final String summaryText;

  const HoleWeatherContext({
    required this.temperatureF,
    required this.windSpeedMph,
    required this.windCompassDirection,
    required this.windRelativeToHole,
    required this.conditionDescription,
    required this.summaryText,
  });
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

class HoleAnalysisEngine {
  HoleAnalysisEngine._();

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  static HoleAnalysis analyze({
    required NormalizedHole hole,
    String? selectedTee,
    WeatherData? weather,
  }) {
    final dogleg =
        hole.lineOfPlay != null ? detectDogleg(hole.lineOfPlay!) : null;
    final fairwayWidth = estimateFairwayWidth(hole);
    final greenDims = measureGreen(hole);
    final hazards = classifyHazards(hole);
    final weatherCtx =
        weather != null ? buildWeatherContext(weather, hole) : null;

    final totalYards = selectedTee != null
        ? hole.yardages[selectedTee]
        : (hole.yardages.isNotEmpty ? hole.yardages.values.first : null);

    final analysis = HoleAnalysis(
      holeNumber: hole.number,
      par: hole.par,
      totalDistanceYards: totalYards,
      yardagesByTee: hole.yardages.isNotEmpty ? hole.yardages : null,
      dogleg: dogleg,
      fairwayWidthAtLandingYards: fairwayWidth,
      greenDepthYards: greenDims?.depth,
      greenWidthYards: greenDims?.width,
      hazards: hazards,
      weather: weatherCtx,
      deterministicSummary: '', // placeholder, replaced below
    );

    final summary = buildDeterministicSummary(analysis);
    return HoleAnalysis(
      holeNumber: analysis.holeNumber,
      par: analysis.par,
      totalDistanceYards: analysis.totalDistanceYards,
      yardagesByTee: analysis.yardagesByTee,
      dogleg: analysis.dogleg,
      fairwayWidthAtLandingYards: analysis.fairwayWidthAtLandingYards,
      greenDepthYards: analysis.greenDepthYards,
      greenWidthYards: analysis.greenWidthYards,
      hazards: analysis.hazards,
      weather: analysis.weather,
      deterministicSummary: summary,
    );
  }

  /// Walk segments of the line of play, detect bearing changes ≥ 15°.
  static DoglegInfo? detectDogleg(LineString lineOfPlay) {
    final pts = lineOfPlay.points;
    if (pts.length < 3) return null;

    double cumulativeDistance = 0;
    double prevBearing = bearingDegrees(pts[0], pts[1]);

    for (int i = 1; i < pts.length - 1; i++) {
      cumulativeDistance += haversineMeters(pts[i - 1], pts[i]);
      final nextBearing = bearingDegrees(pts[i], pts[i + 1]);

      var change = nextBearing - prevBearing;
      // Normalize to [-180, 180].
      while (change > 180) {
        change -= 360;
      }
      while (change < -180) {
        change += 360;
      }

      if (change.abs() >= 15) {
        return DoglegInfo(
          direction: change > 0 ? 'right' : 'left',
          distanceFromTeeYards: metersToYards(cumulativeDistance).round(),
          bendAngleDegrees: change.abs(),
        );
      }
      prevBearing = nextBearing;
    }
    return null;
  }

  /// Estimate fairway width at the landing zone by projecting
  /// perpendicular lines from the line-of-play centerline.
  static int? estimateFairwayWidth(NormalizedHole hole) {
    final line = hole.lineOfPlay;
    if (line == null || line.points.length < 2) return null;

    final double landingFraction;
    switch (hole.par) {
      case 3:
        landingFraction = 0.70;
        break;
      case 5:
        landingFraction = 0.40;
        break;
      default:
        landingFraction = 0.60;
    }

    final center = _pointAtFraction(line, landingFraction);
    if (center == null) return null;
    final bearing = _bearingAtFraction(line, landingFraction);

    final leftBearing = (bearing - 90 + 360) % 360;
    final rightBearing = (bearing + 90) % 360;

    final leftPt = _projectPoint(center, leftBearing, 50);
    final rightPt = _projectPoint(center, rightBearing, 50);

    final widthYards = metersToYards(haversineMeters(leftPt, rightPt)).round();
    return widthYards.clamp(0, 60);
  }

  /// Measure the green's depth (along approach) and width (perpendicular).
  static ({int depth, int width})? measureGreen(NormalizedHole hole) {
    final greenPoly = hole.green;
    if (greenPoly == null || greenPoly.outerRing.isEmpty) return null;

    // Approach bearing from the last segment of line of play.
    double approachBearing = 0;
    final line = hole.lineOfPlay;
    if (line != null && line.points.length >= 2) {
      final pts = line.points;
      approachBearing =
          bearingDegrees(pts[pts.length - 2], pts[pts.length - 1]);
    }

    final approachRad = approachBearing * math.pi / 180;
    final perpRad = approachRad + math.pi / 2;

    // Project each green point onto the depth and width axes.
    double minDepth = double.infinity;
    double maxDepth = -double.infinity;
    double minWidth = double.infinity;
    double maxWidth = -double.infinity;

    final greenCenter = greenPoly.centroid;
    if (greenCenter == null) return null;

    for (final pt in greenPoly.outerRing) {
      final dLat = pt.lat - greenCenter.lat;
      final dLon = pt.lon - greenCenter.lon;

      // Project onto approach axis (depth).
      final depthProj = dLat * math.cos(approachRad) + dLon * math.sin(approachRad);
      // Project onto perpendicular axis (width).
      final widthProj = dLat * math.cos(perpRad) + dLon * math.sin(perpRad);

      if (depthProj < minDepth) minDepth = depthProj;
      if (depthProj > maxDepth) maxDepth = depthProj;
      if (widthProj < minWidth) minWidth = widthProj;
      if (widthProj > maxWidth) maxWidth = widthProj;
    }

    // Convert degree-space deltas to meters: 1° latitude ≈ 111139 m.
    const metersPerDegree = 111139.0;
    final depthMeters = (maxDepth - minDepth) * metersPerDegree;
    final widthMeters = (maxWidth - minWidth) * metersPerDegree;

    final depthYards = math.max(1, metersToYards(depthMeters).round());
    final widthYards = math.max(1, metersToYards(widthMeters).round());

    return (depth: depthYards, width: widthYards);
  }

  /// Classify all bunker and water hazards relative to the hole.
  static List<HoleHazardInfo> classifyHazards(NormalizedHole hole) {
    final results = <HoleHazardInfo>[];
    final line = hole.lineOfPlay;
    final greenCenter = hole.green?.centroid;
    final totalDist = line != null ? _totalDistance(line) : 0.0;

    void classify(Polygon poly, String type) {
      final centroid = poly.centroid;
      if (centroid == null) return;

      HazardSide side;
      int? distFromTee;

      // Check if greenside: centroid within 30 yards (27.432 m) of green center.
      if (greenCenter != null &&
          haversineMeters(centroid, greenCenter) < 27.432) {
        side = HazardSide.greenside;
      } else if (line != null && totalDist > 0) {
        final along = _distanceAlongLine(line, centroid);
        final fraction = along / totalDist;
        distFromTee = metersToYards(along).round();

        if (fraction > 0.90) {
          side = HazardSide.frontOfGreen;
        } else {
          // Use cross product of line direction vs hazard center to
          // determine left or right.
          final bearing = _bearingAtFraction(line, fraction.clamp(0.0, 1.0));
          final bearingRad = bearing * math.pi / 180;

          final refPt = _pointAtFraction(line, fraction.clamp(0.0, 1.0));
          if (refPt == null) {
            side = HazardSide.crossing;
          } else {
            final dx = centroid.lon - refPt.lon;
            final dy = centroid.lat - refPt.lat;
            // Cross product: direction × (hazard - ref).
            // direction vector: (sin(bearing), cos(bearing)) in (lon, lat) space.
            final cross =
                math.sin(bearingRad) * dy - math.cos(bearingRad) * dx;
            side = cross > 0 ? HazardSide.left : HazardSide.right;
          }
        }
      } else {
        side = HazardSide.crossing;
      }

      if (distFromTee == null && line != null && totalDist > 0) {
        final along = _distanceAlongLine(line, centroid);
        distFromTee = metersToYards(along).round();
      }

      final desc = _hazardDescription(type, side, distFromTee);
      results.add(HoleHazardInfo(
        type: type,
        side: side,
        distanceFromTeeYards: distFromTee,
        description: desc,
      ));
    }

    for (final b in hole.bunkers) {
      classify(b, 'Bunker');
    }
    for (final w in hole.water) {
      classify(w, 'Water');
    }

    return results;
  }

  /// Build weather context for the hole.
  static HoleWeatherContext? buildWeatherContext(
      WeatherData weather, NormalizedHole hole) {
    final holeBearing = hole.teeToGreenBearing();
    final relative = weather.relativeWindDirection(holeBearing);

    final String relativeStr;
    switch (relative) {
      case RelativeWindDirection.into:
        relativeStr = 'into';
        break;
      case RelativeWindDirection.helping:
        relativeStr = 'helping';
        break;
      case RelativeWindDirection.crossLeftToRight:
        relativeStr = 'cross left-to-right';
        break;
      case RelativeWindDirection.crossRightToLeft:
        relativeStr = 'cross right-to-left';
        break;
    }

    final cardinal = _degreesToCardinal(weather.windDirectionDegrees);
    final condition = _weatherCodeDescription(weather.weatherCode);
    final tempF = weather.temperatureF.round();
    final windMph = weather.windSpeedMph.round();

    final summary =
        '$tempF°F, $condition, $windMph mph $cardinal wind ($relativeStr on this hole)';

    return HoleWeatherContext(
      temperatureF: tempF,
      windSpeedMph: windMph,
      windCompassDirection: cardinal,
      windRelativeToHole: relativeStr,
      conditionDescription: condition,
      summaryText: summary,
    );
  }

  /// Build a natural-language deterministic summary.
  static String buildDeterministicSummary(HoleAnalysis analysis) {
    final buf = StringBuffer();

    // Opening: par + yardage.
    if (analysis.par != null) {
      buf.write('Par ${analysis.par}');
      if (analysis.totalDistanceYards != null) {
        buf.write(', ${analysis.totalDistanceYards} yards');
      }
      buf.write('. ');
    }

    // Dogleg.
    if (analysis.dogleg != null) {
      final d = analysis.dogleg!;
      buf.write(
          'Dogleg ${d.direction} at ${d.distanceFromTeeYards} yards '
          '(${d.bendAngleDegrees.round()}° bend). ');
    }

    // Fairway width.
    if (analysis.fairwayWidthAtLandingYards != null) {
      final w = analysis.fairwayWidthAtLandingYards!;
      final String widthLabel;
      if (w < 25) {
        widthLabel = 'narrow';
      } else if (w > 40) {
        widthLabel = 'generous';
      } else {
        widthLabel = 'average';
      }
      buf.write('Fairway is $widthLabel ($w yards at the landing zone). ');
    }

    // Green dimensions.
    if (analysis.greenDepthYards != null && analysis.greenWidthYards != null) {
      buf.write(
          'Green is ${analysis.greenDepthYards} yards deep and '
          '${analysis.greenWidthYards} yards wide. ');
    }

    // Weather + wind.
    if (analysis.weather != null) {
      final w = analysis.weather!;
      buf.write('${w.summaryText}. ');
      if (w.windSpeedMph >= 10) {
        if (w.windRelativeToHole == 'into') {
          buf.write('Club up for the headwind. ');
        } else if (w.windRelativeToHole == 'helping') {
          buf.write('Wind is helping — consider clubbing down. ');
        } else {
          buf.write('Expect crosswind to move the ball. ');
        }
      }
    }

    // Hazards.
    if (analysis.hazards.isNotEmpty) {
      buf.write('Hazards: ');
      buf.write(analysis.hazards.map((h) => h.description).join('; '));
      buf.write('. ');
    }

    // Tee shot suggestion.
    if (analysis.par != null && analysis.par! >= 4) {
      if (analysis.dogleg != null) {
        final opposite =
            analysis.dogleg!.direction == 'left' ? 'right' : 'left';
        buf.write(
            'Tee shot: favor the $opposite side to open up the angle. ');
      } else if (analysis.fairwayWidthAtLandingYards != null &&
          analysis.fairwayWidthAtLandingYards! < 25) {
        buf.write(
            'Tee shot: accuracy is key on this tight fairway. ');
      } else {
        buf.write('Tee shot: aim for the center of the fairway. ');
      }
    }

    return buf.toString().trim();
  }

  // -----------------------------------------------------------------------
  // Private geometry helpers
  // -----------------------------------------------------------------------

  /// Total distance of a LineString in meters.
  static double _totalDistance(LineString line) {
    double total = 0;
    for (int i = 0; i < line.points.length - 1; i++) {
      total += haversineMeters(line.points[i], line.points[i + 1]);
    }
    return total;
  }

  /// Interpolate a point at a given fraction (0.0–1.0) of total line distance.
  static LngLat? _pointAtFraction(LineString line, double fraction) {
    if (line.points.isEmpty) return null;
    if (line.points.length == 1) return line.points.first;

    final total = _totalDistance(line);
    if (total == 0) return line.points.first;

    final target = fraction.clamp(0.0, 1.0) * total;
    double accumulated = 0;

    for (int i = 0; i < line.points.length - 1; i++) {
      final segLen = haversineMeters(line.points[i], line.points[i + 1]);
      if (accumulated + segLen >= target) {
        final segFrac = segLen > 0 ? (target - accumulated) / segLen : 0.0;
        return LngLat(
          line.points[i].lon +
              (line.points[i + 1].lon - line.points[i].lon) * segFrac,
          line.points[i].lat +
              (line.points[i + 1].lat - line.points[i].lat) * segFrac,
        );
      }
      accumulated += segLen;
    }
    return line.points.last;
  }

  /// Bearing at a given fraction along the line.
  static double _bearingAtFraction(LineString line, double fraction) {
    if (line.points.length < 2) return 0;

    final total = _totalDistance(line);
    if (total == 0) return bearingDegrees(line.points.first, line.points.last);

    final target = fraction.clamp(0.0, 1.0) * total;
    double accumulated = 0;

    for (int i = 0; i < line.points.length - 1; i++) {
      final segLen = haversineMeters(line.points[i], line.points[i + 1]);
      if (accumulated + segLen >= target || i == line.points.length - 2) {
        return bearingDegrees(line.points[i], line.points[i + 1]);
      }
      accumulated += segLen;
    }
    return bearingDegrees(
        line.points[line.points.length - 2], line.points.last);
  }

  /// Project a point onto the line and return the distance from the start.
  static double _distanceAlongLine(LineString line, LngLat point) {
    if (line.points.length < 2) return 0;

    double bestAlong = 0;
    double bestDist = double.infinity;
    double accumulated = 0;

    for (int i = 0; i < line.points.length - 1; i++) {
      final a = line.points[i];
      final b = line.points[i + 1];
      final segLen = haversineMeters(a, b);

      if (segLen == 0) continue;

      // Project point onto segment [a, b].
      final dLon = b.lon - a.lon;
      final dLat = b.lat - a.lat;
      final pLon = point.lon - a.lon;
      final pLat = point.lat - a.lat;
      var t = (pLon * dLon + pLat * dLat) / (dLon * dLon + dLat * dLat);
      t = t.clamp(0.0, 1.0);

      final proj = LngLat(a.lon + t * dLon, a.lat + t * dLat);
      final dist = haversineMeters(point, proj);

      if (dist < bestDist) {
        bestDist = dist;
        bestAlong = accumulated + t * segLen;
      }
      accumulated += segLen;
    }
    return bestAlong;
  }

  /// Forward geodesic projection: given an origin, bearing (degrees), and
  /// distance (meters), return the destination point.
  static LngLat _projectPoint(
      LngLat origin, double bearingDeg, double distanceMeters) {
    const R = 6371000.0;
    final lat1 = origin.lat * math.pi / 180;
    final lon1 = origin.lon * math.pi / 180;
    final brng = bearingDeg * math.pi / 180;
    final d = distanceMeters / R;

    final lat2 = math.asin(
        math.sin(lat1) * math.cos(d) + math.cos(lat1) * math.sin(d) * math.cos(brng));
    final lon2 = lon1 +
        math.atan2(math.sin(brng) * math.sin(d) * math.cos(lat1),
            math.cos(d) - math.sin(lat1) * math.sin(lat2));

    return LngLat(lon2 * 180 / math.pi, lat2 * 180 / math.pi);
  }

  // -----------------------------------------------------------------------
  // Private utility helpers
  // -----------------------------------------------------------------------

  static String _degreesToCardinal(double degrees) {
    const cardinals = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((degrees + 22.5) % 360 / 45).floor();
    return cardinals[index];
  }

  static String _weatherCodeDescription(int code) {
    if (code == 0) return 'Clear';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 48) return 'Foggy';
    if (code <= 57) return 'Drizzle';
    if (code <= 67) return 'Rain';
    if (code <= 77) return 'Snow';
    if (code <= 99) return 'Thunderstorm';
    return 'Unknown';
  }

  static String _hazardDescription(String type, HazardSide side, int? dist) {
    final sideStr = switch (side) {
      HazardSide.left => 'left',
      HazardSide.right => 'right',
      HazardSide.greenside => 'greenside',
      HazardSide.frontOfGreen => 'front of green',
      HazardSide.crossing => 'crossing',
    };

    if (dist != null) {
      return '$type $sideStr at $dist yards';
    }
    return '$type $sideStr';
  }
}
