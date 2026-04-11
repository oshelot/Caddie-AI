// Smoke tests for the Dart port of CourseGeoJSONBuilder. Uses the real
// Sharp Park fixture, so a regression in the server schema also gets
// caught here.
import 'dart:convert';
import 'dart:io';

import 'package:caddieai_flutter_spike/course_geojson_builder.dart';
import 'package:caddieai_flutter_spike/models/course.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late NormalizedCourse course;

  setUpAll(() {
    final raw = File('assets/fixtures/sharp_park.json').readAsStringSync();
    course = NormalizedCourse.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  });

  test('fixture parses into 18 holes', () {
    expect(course.holes, hasLength(18));
    expect(course.name, contains('Sharp Park'));
  });

  test('buildFeatureCollection emits only known feature types', () {
    final fc = CourseGeoJsonBuilder.buildFeatureCollection(course);
    final features = fc['features'] as List;
    expect(features, isNotEmpty);

    const allowed = {
      CourseFeatureType.boundary,
      CourseFeatureType.holeLine,
      CourseFeatureType.green,
      CourseFeatureType.tee,
      CourseFeatureType.bunker,
      CourseFeatureType.water,
      CourseFeatureType.holeLabel,
      CourseFeatureType.pin,
    };
    for (final f in features) {
      final type = (f as Map)['properties']['type'] as String;
      expect(allowed, contains(type));
    }
  });

  test('every hole produces a hole-line and a hole-label feature', () {
    final fc = CourseGeoJsonBuilder.buildFeatureCollection(course);
    final features = (fc['features'] as List).cast<Map>();
    final lineHoles = features
        .where((f) => f['properties']['type'] == CourseFeatureType.holeLine)
        .map((f) => f['properties']['holeNumber'] as int)
        .toSet();
    final labelHoles = features
        .where((f) => f['properties']['type'] == CourseFeatureType.holeLabel)
        .map((f) => f['properties']['holeNumber'] as int)
        .toSet();
    expect(lineHoles, equals({for (var i = 1; i <= 18; i++) i}));
    expect(labelHoles, equals({for (var i = 1; i <= 18; i++) i}));
  });

  test('label features carry a numeric `label` property', () {
    final fc = CourseGeoJsonBuilder.buildFeatureCollection(course);
    final labels = (fc['features'] as List)
        .cast<Map>()
        .where((f) => f['properties']['type'] == CourseFeatureType.holeLabel);
    for (final f in labels) {
      final label = f['properties']['label'] as String;
      expect(int.tryParse(label), isNotNull);
    }
  });

  test('tee-to-green bearing is in [0, 360) for every hole', () {
    for (final h in course.holes) {
      final b = h.teeToGreenBearing();
      expect(b, greaterThanOrEqualTo(0));
      expect(b, lessThan(360));
    }
  });

  test('haversine distance between hole 1 tee and green is sane', () {
    final h1 = course.holes.first;
    final tee = h1.teeAreas.first.centroid!;
    final green = h1.green!.centroid!;
    final yards = metersToYards(haversineMeters(tee, green));
    // Hole 1 at Sharp Park is ~366 yards from the Blue tees. Give a wide
    // envelope because we're using centroids, not actual tee markers.
    expect(yards, inInclusiveRange(250, 500));
  });
}
