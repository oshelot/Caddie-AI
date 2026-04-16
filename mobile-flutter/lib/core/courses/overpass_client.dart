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

  /// Ordered list of Overpass mirrors to cycle through on failure.
  /// Each mirror has its own rate limiter and server pool, so when
  /// one is rate-limited (typically returning 429 or 504), the others
  /// are likely still healthy. Order is rough reliability rank; the
  /// next request to this client starts from a randomized offset so
  /// load is spread across mirrors over time.
  static const _mirrors = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.osm.jp/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  static const _bboxBuffer = 0.002;
  static const _maxAttemptsPerMirror = 2;
  static const _timeout = Duration(seconds: 45);

  /// Randomized starting offset so consecutive client instances don't
  /// all hammer the same mirror first.
  static int _mirrorOffset =
      DateTime.now().millisecondsSinceEpoch % _mirrors.length;

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
        '  way["leisure"="golf_course"]($s,$w,$n,$e);\n'
        '  relation["leisure"="golf_course"]($s,$w,$n,$e);\n'
        ');\n'
        'out geom;';

    final body = 'data=${Uri.encodeComponent(query)}';

    // Try each mirror in order, starting from a rotating offset.
    // Fast-fail on 429/504 and move to the next mirror immediately.
    Object? lastError;
    final startOffset = _mirrorOffset;
    _mirrorOffset = (_mirrorOffset + 1) % _mirrors.length;

    for (var i = 0; i < _mirrors.length; i++) {
      final endpoint = _mirrors[(startOffset + i) % _mirrors.length];
      try {
        // ignore: avoid_print
        print('OVERPASS: trying $endpoint');
        return await _fetchWithRetry(endpoint, body);
      } catch (e) {
        // ignore: avoid_print
        print('OVERPASS: $endpoint failed: $e');
        lastError = e;
        // Fall through to next mirror.
      }
    }
    throw lastError ??
        Exception('All ${_mirrors.length} Overpass mirrors failed');
  }

  Future<OverpassResponse> _fetchWithRetry(
    String endpoint,
    String body,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttemptsPerMirror; attempt++) {
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

        // 429/504 → fast-fail this mirror so the caller can try another.
        // Only retry on 504 once within the same mirror (might be a
        // transient queue spike).
        if (response.statusCode == 429) {
          throw Exception('Overpass returned 429 (rate-limited)');
        }
        if (response.statusCode == 504) {
          if (attempt < _maxAttemptsPerMirror) {
            lastError = Exception(
                'Overpass returned 504 on attempt $attempt');
            await Future<void>.delayed(const Duration(seconds: 1));
            continue;
          }
          throw Exception('Overpass returned 504');
        }

        if (!response.isSuccess) {
          throw Exception(
              'Overpass error ${response.statusCode}: ${response.body}');
        }

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return OverpassResponse.fromJson(json);
      } catch (e) {
        lastError = e;
        if (attempt < _maxAttemptsPerMirror) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
      }
    }
    throw lastError ?? Exception('Overpass request failed');
  }
}
