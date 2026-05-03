// KAN-328: Canonical cache key tests.
//
// Verifies that NormalizedCourse.serverCacheKey() produces the same
// output as make_cache_key() in batch_publish.py. If these two
// diverge, the app and the cloud pipeline will produce different
// S3 keys for the same course.

import 'package:caddieai/models/normalized_course.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('serverCacheKey — canonical format (KAN-328)', () {
    test('simple course with state', () {
      expect(
        NormalizedCourse.serverCacheKey('Wellshire Golf Course', state: 'CO'),
        'wellshire-golf-course-co',
      );
    });

    test('same name, different states', () {
      expect(
        NormalizedCourse.serverCacheKey('Coyote Creek Golf Course',
            state: 'CO'),
        'coyote-creek-golf-course-co',
      );
      expect(
        NormalizedCourse.serverCacheKey('Coyote Creek Golf Course',
            state: 'CA'),
        'coyote-creek-golf-course-ca',
      );
    });

    test('strips apostrophes and quotes', () {
      expect(
        NormalizedCourse.serverCacheKey("O'Malley's Club", state: 'TX'),
        'omalleys-club-tx',
      );
    });

    test('strips special characters', () {
      expect(
        NormalizedCourse.serverCacheKey('Country & Golf Club', state: 'FL'),
        'country-golf-club-fl',
      );
    });

    test('collapses consecutive hyphens', () {
      expect(
        NormalizedCourse.serverCacheKey('Pine - Valley G.C.', state: 'NJ'),
        'pine-valley-gc-nj',
      );
    });

    test('The Ridge at Castle Pines', () {
      expect(
        NormalizedCourse.serverCacheKey('The Ridge at Castle Pines',
            state: 'CO'),
        'the-ridge-at-castle-pines-co',
      );
    });

    test('state is case-insensitive', () {
      expect(
        NormalizedCourse.serverCacheKey('Test Course', state: 'co'),
        NormalizedCourse.serverCacheKey('Test Course', state: 'CO'),
      );
    });

    test('null state returns name-only slug', () {
      expect(
        NormalizedCourse.serverCacheKey('Wellshire Golf Course'),
        'wellshire-golf-course',
      );
    });

    test('empty state returns name-only slug', () {
      expect(
        NormalizedCourse.serverCacheKey('Wellshire Golf Course', state: ''),
        'wellshire-golf-course',
      );
    });

    test('multi-course sub-course name includes facility prefix', () {
      // The app stores sub-courses as "Kennedy Golf Course - West".
      // The slug includes the full name; the /sub-course format is
      // a follow-up (not in this ticket).
      expect(
        NormalizedCourse.serverCacheKey('Kennedy Golf Course - West',
            state: 'CO'),
        'kennedy-golf-course-west-co',
      );
    });
  });
}
