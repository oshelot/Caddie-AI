// Integration check for KAN-403: parse a real schema-1.1 file pulled
// from production v1.0/. If this passes, every other 1.1 file should too.

import 'dart:convert';
import 'dart:io';

import 'package:caddieai/models/normalized_course.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema 1.1 — 5 by 80 Golf and Country Club (real file) parses', () {
    final file = File('test/fixtures/schema_1_1_5_by_80.json');
    if (!file.existsSync()) {
      markTestSkipped('fixture not present — run scripts/fetch_schema_1_1_fixture.sh');
      return;
    }
    final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final course = NormalizedCourse.fromJson(j);

    expect(course.name, isNotEmpty);
    expect(course.holes, isNotEmpty);

    // Every hole should have a parseable green (synthesized octagon) and
    // at least one parseable tee area.
    for (final h in course.holes) {
      expect(h.green, isNotNull, reason: 'green null on hole ${h.number}');
      expect(h.green!.outerRing.length, greaterThanOrEqualTo(3),
          reason: 'green ring too small on hole ${h.number}');
      expect(h.teeAreas, isNotEmpty,
          reason: 'no tee areas on hole ${h.number}');
    }
  });
}
