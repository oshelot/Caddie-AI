// OsmParser — converts raw OverpassResponse elements into typed golf
// feature DTOs. Port of ios/CaddieAI/Services/OSMParser.swift.
//
// Pure static class with no side effects. The output ParsedFeatures
// struct feeds into CourseNormalizer which builds NormalizedCourse.

import '../../core/geo/geo.dart';
import 'overpass_client.dart';

// ---------------------------------------------------------------------------
// Parsed feature DTOs
// ---------------------------------------------------------------------------

class ParsedHoleLine {
  final int osmId;
  final int? number;
  final int? par;
  final LineString lineString;
  const ParsedHoleLine({
    required this.osmId,
    this.number,
    this.par,
    required this.lineString,
  });
}

class ParsedGreen {
  final int osmId;
  final int? holeNumber;
  final Polygon polygon;
  const ParsedGreen({
    required this.osmId,
    this.holeNumber,
    required this.polygon,
  });
}

class ParsedTee {
  final int osmId;
  final int? holeNumber;
  final Polygon polygon;
  const ParsedTee({
    required this.osmId,
    this.holeNumber,
    required this.polygon,
  });
}

class ParsedPin {
  final int osmId;
  final int? holeNumber;
  final LngLat point;
  const ParsedPin({
    required this.osmId,
    this.holeNumber,
    required this.point,
  });
}

class ParsedBunker {
  final int osmId;
  final Polygon polygon;
  const ParsedBunker({required this.osmId, required this.polygon});
}

class ParsedWater {
  final int osmId;
  final Polygon polygon;
  const ParsedWater({required this.osmId, required this.polygon});
}

class ParsedFeatures {
  final List<ParsedHoleLine> holeLines;
  final List<ParsedGreen> greens;
  final List<ParsedTee> tees;
  final List<ParsedPin> pins;
  final List<ParsedBunker> bunkers;
  final List<ParsedWater> waterFeatures;

  const ParsedFeatures({
    required this.holeLines,
    required this.greens,
    required this.tees,
    required this.pins,
    required this.bunkers,
    required this.waterFeatures,
  });
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class OsmParser {
  OsmParser._();

  /// Parses an OverpassResponse into categorized golf feature DTOs.
  static ParsedFeatures parse(OverpassResponse response) {
    final holeLines = <ParsedHoleLine>[];
    final greens = <ParsedGreen>[];
    final tees = <ParsedTee>[];
    final pins = <ParsedPin>[];
    final bunkers = <ParsedBunker>[];
    final waterFeatures = <ParsedWater>[];

    for (final el in response.elements) {
      final tags = el.tags;
      if (tags == null) continue;

      final golf = tags['golf'];
      final natural = tags['natural'];

      if (golf == 'hole' && el.type == 'way') {
        final ls = _extractLineString(el);
        if (ls != null) {
          holeLines.add(ParsedHoleLine(
            osmId: el.id,
            number: _parseHoleNumber(tags),
            par: _parsePar(tags),
            lineString: ls,
          ));
        }
      } else if (golf == 'green' && el.type == 'way') {
        final poly = _extractPolygon(el);
        if (poly != null) {
          greens.add(ParsedGreen(
            osmId: el.id,
            holeNumber: _parseHoleNumber(tags),
            polygon: poly,
          ));
        }
      } else if (golf == 'tee' && el.type == 'way') {
        final poly = _extractPolygon(el);
        if (poly != null) {
          tees.add(ParsedTee(
            osmId: el.id,
            holeNumber: _parseHoleNumber(tags),
            polygon: poly,
          ));
        }
      } else if (golf == 'pin' && el.type == 'node') {
        final pt = _extractPoint(el);
        if (pt != null) {
          pins.add(ParsedPin(
            osmId: el.id,
            holeNumber: _parseHoleNumber(tags),
            point: pt,
          ));
        }
      } else if (golf == 'bunker' && el.type == 'way') {
        final poly = _extractPolygon(el);
        if (poly != null) {
          bunkers.add(ParsedBunker(osmId: el.id, polygon: poly));
        }
      } else if (natural == 'water') {
        if (el.type == 'way') {
          final poly = _extractPolygon(el);
          if (poly != null) {
            waterFeatures.add(ParsedWater(osmId: el.id, polygon: poly));
          }
        } else if (el.type == 'relation') {
          // For relations, extract outer members.
          final members = el.members;
          if (members != null) {
            for (final member in members) {
              if (member.role == 'outer' && member.geometry != null) {
                final poly = _polygonFromNodes(member.geometry!);
                if (poly != null) {
                  waterFeatures
                      .add(ParsedWater(osmId: el.id, polygon: poly));
                }
              }
            }
          }
        }
      }
    }

    return ParsedFeatures(
      holeLines: holeLines,
      greens: greens,
      tees: tees,
      pins: pins,
      bunkers: bunkers,
      waterFeatures: waterFeatures,
    );
  }

  // -------------------------------------------------------------------------
  // Geometry extraction
  // -------------------------------------------------------------------------

  static LineString? _extractLineString(OverpassElement el) {
    final geom = el.geometry;
    if (geom == null || geom.length < 2) return null;
    return LineString(
      geom.map((n) => LngLat(n.lon, n.lat)).toList(growable: false),
    );
  }

  static Polygon? _extractPolygon(OverpassElement el) {
    final geom = el.geometry;
    if (geom == null) return null;
    return _polygonFromNodes(geom);
  }

  static Polygon? _polygonFromNodes(List<OverpassGeomNode> nodes) {
    if (nodes.length < 3) return null;
    final points =
        nodes.map((n) => LngLat(n.lon, n.lat)).toList(growable: false);
    // Close ring if not already closed.
    final ring = List<LngLat>.from(points);
    if (ring.first.lon != ring.last.lon || ring.first.lat != ring.last.lat) {
      ring.add(ring.first);
    }
    return Polygon(ring);
  }

  static LngLat? _extractPoint(OverpassElement el) {
    if (el.lat != null && el.lon != null) {
      return LngLat(el.lon!, el.lat!);
    }
    // Fallback: centroid of geometry nodes.
    final geom = el.geometry;
    if (geom == null || geom.isEmpty) return null;
    double sumLon = 0, sumLat = 0;
    for (final n in geom) {
      sumLon += n.lon;
      sumLat += n.lat;
    }
    return LngLat(sumLon / geom.length, sumLat / geom.length);
  }

  // -------------------------------------------------------------------------
  // Tag parsing
  // -------------------------------------------------------------------------

  /// Try ref, then hole, then extract digits from name. Validate 1-18.
  static int? _parseHoleNumber(Map<String, String> tags) {
    final candidates = [tags['ref'], tags['hole'], tags['name']];
    for (final raw in candidates) {
      if (raw == null) continue;
      final digits = RegExp(r'\d+').firstMatch(raw);
      if (digits != null) {
        final n = int.tryParse(digits.group(0)!);
        if (n != null && n >= 1 && n <= 18) return n;
      }
    }
    return null;
  }

  static int? _parsePar(Map<String, String> tags) {
    final raw = tags['par'];
    if (raw == null) return null;
    return int.tryParse(raw);
  }
}
