// Overpass API client — fetches raw OSM golf-course features for a
// bounding box. Port of ios/CaddieAI/Services/OverpassClient.swift.
//
// Uses two endpoints (primary + fallback) and retries on 429/504 with
// linear backoff. The response is a typed OverpassResponse that the
// OsmParser consumes downstream.

import 'dart:convert';

import 'http_transport.dart';

// ---------------------------------------------------------------------------
// Response model classes
// ---------------------------------------------------------------------------

class OverpassGeomNode {
  final double lat;
  final double lon;
  const OverpassGeomNode({required this.lat, required this.lon});

  factory OverpassGeomNode.fromJson(Map<String, dynamic> j) =>
      OverpassGeomNode(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );
}

class OverpassMember {
  final String type;
  final int ref;
  final String? role;
  final List<OverpassGeomNode>? geometry;

  const OverpassMember({
    required this.type,
    required this.ref,
    this.role,
    this.geometry,
  });

  factory OverpassMember.fromJson(Map<String, dynamic> j) => OverpassMember(
        type: j['type'] as String,
        ref: (j['ref'] as num).toInt(),
        role: j['role'] as String?,
        geometry: j['geometry'] == null
            ? null
            : (j['geometry'] as List<dynamic>)
                .map((n) =>
                    OverpassGeomNode.fromJson(n as Map<String, dynamic>))
                .toList(growable: false),
      );
}

class OverpassElement {
  final String type;
  final int id;
  final double? lat;
  final double? lon;
  final Map<String, String>? tags;
  final List<OverpassGeomNode>? geometry;
  final List<OverpassMember>? members;

  const OverpassElement({
    required this.type,
    required this.id,
    this.lat,
    this.lon,
    this.tags,
    this.geometry,
    this.members,
  });

  factory OverpassElement.fromJson(Map<String, dynamic> j) => OverpassElement(
        type: j['type'] as String,
        id: (j['id'] as num).toInt(),
        lat: j['lat'] == null ? null : (j['lat'] as num).toDouble(),
        lon: j['lon'] == null ? null : (j['lon'] as num).toDouble(),
        tags: j['tags'] == null
            ? null
            : (j['tags'] as Map<String, dynamic>)
                .map((k, v) => MapEntry(k, v as String)),
        geometry: j['geometry'] == null
            ? null
            : (j['geometry'] as List<dynamic>)
                .map((n) =>
                    OverpassGeomNode.fromJson(n as Map<String, dynamic>))
                .toList(growable: false),
        members: j['members'] == null
            ? null
            : (j['members'] as List<dynamic>)
                .map(
                    (m) => OverpassMember.fromJson(m as Map<String, dynamic>))
                .toList(growable: false),
      );
}

class OverpassResponse {
  final List<OverpassElement> elements;
  const OverpassResponse({required this.elements});

  factory OverpassResponse.fromJson(Map<String, dynamic> j) =>
      OverpassResponse(
        elements: (j['elements'] as List<dynamic>)
            .map((e) => OverpassElement.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

class OverpassClient {
  OverpassClient(this._transport);

  final HttpTransport _transport;

  static const _primaryEndpoint =
      'https://overpass.private.coffee/api/interpreter';
  static const _fallbackEndpoint =
      'https://overpass-api.de/api/interpreter';
  static const _bboxBuffer = 0.002;
  static const _maxAttempts = 2;
  static const _timeout = Duration(seconds: 45);

  /// Fetches all golf-related OSM features within [south, west, north, east],
  /// with a small buffer added to the bounding box.
  Future<OverpassResponse> fetchCourseFeatures(
    double south,
    double west,
    double north,
    double east,
  ) async {
    final s = south - _bboxBuffer;
    final w = west - _bboxBuffer;
    final n = north + _bboxBuffer;
    final e = east + _bboxBuffer;

    final query = '[out:json][timeout:45];\n'
        '(\n'
        '  way["golf"="hole"]($s,$w,$n,$e);\n'
        '  way["golf"="green"]($s,$w,$n,$e);\n'
        '  way["golf"="tee"]($s,$w,$n,$e);\n'
        '  node["golf"="pin"]($s,$w,$n,$e);\n'
        '  way["golf"="bunker"]($s,$w,$n,$e);\n'
        '  way["natural"="water"]($s,$w,$n,$e);\n'
        '  relation["natural"="water"]($s,$w,$n,$e);\n'
        '  way["golf"="fairway"]($s,$w,$n,$e);\n'
        ');\n'
        'out geom;';

    final body = 'data=${Uri.encodeComponent(query)}';

    // Try primary endpoint, fall back on any error.
    try {
      return await _fetchWithRetry(_primaryEndpoint, body);
    } catch (_) {
      return _fetchWithRetry(_fallbackEndpoint, body);
    }
  }

  Future<OverpassResponse> _fetchWithRetry(
    String endpoint,
    String body,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await _transport.send(HttpRequestLike(
          method: 'POST',
          url: Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: body,
          timeout: _timeout,
        ));

        if (response.statusCode == 429 || response.statusCode == 504) {
          lastError = Exception(
              'Overpass returned ${response.statusCode} on attempt $attempt');
          if (attempt < _maxAttempts) {
            await Future<void>.delayed(Duration(seconds: attempt * 2));
            continue;
          }
          throw lastError;
        }

        if (!response.isSuccess) {
          throw Exception(
              'Overpass error ${response.statusCode}: ${response.body}');
        }

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return OverpassResponse.fromJson(json);
      } catch (e) {
        lastError = e;
        if (attempt < _maxAttempts) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
          continue;
        }
      }
    }
    throw lastError ?? Exception('Overpass request failed');
  }
}
