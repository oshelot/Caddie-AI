// Tests for CourseSearchEntry.findSubCourses — the resolution helper
// that drives multi-course picker grouping (KAN-343).

import 'package:caddieai/core/courses/course_search_results.dart';
import 'package:flutter_test/flutter_test.dart';

CourseSearchEntry _entry({
  required String name,
  String? facilityId,
  String? facilityName,
  String? subCourseSlug,
  String state = 'CO',
}) =>
    CourseSearchEntry(
      cacheKey: name.toLowerCase().replaceAll(' ', '-'),
      name: name,
      city: '',
      state: state,
      latitude: 39.7,
      longitude: -104.9,
      facilityId: facilityId,
      facilityName: facilityName,
      subCourseSlug: subCourseSlug,
    );

void main() {
  group('CourseSearchEntry.findSubCourses', () {
    test('groups by facilityId when tapped entry has facilityId', () {
      final tapped = _entry(
        name: 'Kennedy Golf Course - Creek',
        facilityId: 'kennedy-golf-course-co',
        facilityName: 'Kennedy Golf Course',
        subCourseSlug: 'creek',
      );
      final manifest = [
        tapped,
        _entry(
          name: 'Kennedy Golf Course - Lind',
          facilityId: 'kennedy-golf-course-co',
          facilityName: 'Kennedy Golf Course',
          subCourseSlug: 'lind',
        ),
        _entry(
          name: 'Kennedy Golf Course - West',
          facilityId: 'kennedy-golf-course-co',
          facilityName: 'Kennedy Golf Course',
          subCourseSlug: 'west',
        ),
        _entry(name: 'Cherry Creek Golf Course'),
      ];

      final result = CourseSearchEntry.findSubCourses(tapped, manifest);

      expect(result.length, 3);
      expect(result.map((p) => p.legName).toSet(), {'creek', 'lind', 'west'});
    });

    test('discovers facilityId from manifest when tapped lacks it', () {
      // Tapped entry from Nominatim/Places — no manifest-side fields.
      final tapped = _entry(name: 'Kennedy Golf Course');
      final manifest = [
        _entry(
          name: 'Kennedy Golf Course - Creek',
          facilityId: 'kennedy-golf-course-co',
          facilityName: 'Kennedy Golf Course',
          subCourseSlug: 'creek',
        ),
        _entry(
          name: 'Kennedy Golf Course - West',
          facilityId: 'kennedy-golf-course-co',
          facilityName: 'Kennedy Golf Course',
          subCourseSlug: 'west',
        ),
      ];

      final result = CourseSearchEntry.findSubCourses(tapped, manifest);

      expect(result.length, 2);
      expect(result.map((p) => p.legName).toSet(), {'creek', 'west'});
    });

    test('falls back to name-prefix when manifest lacks facilityId', () {
      // Old manifest payload — no schema fields populated.
      final tapped = _entry(name: 'Kennedy Golf Course');
      final manifest = [
        _entry(name: 'Kennedy Golf Course - Creek'),
        _entry(name: 'Kennedy Golf Course - West'),
        _entry(name: 'Cherry Creek Golf Course'),
      ];

      final result = CourseSearchEntry.findSubCourses(tapped, manifest);

      expect(result.length, 2);
      expect(result.map((p) => p.legName).toSet(), {'Creek', 'West'});
    });

    test('returns empty when no sub-courses match', () {
      final tapped = _entry(name: 'Sharp Park Golf Course');
      final manifest = [
        _entry(name: 'Sharp Park Golf Course'),
        _entry(name: 'Lincoln Park Golf Course'),
      ];

      expect(CourseSearchEntry.findSubCourses(tapped, manifest), isEmpty);
    });

    test('legName uses subCourseSlug when present, else parses from name', () {
      final tapped = _entry(name: 'Half Moon Bay Golf Links');
      final manifest = [
        _entry(
          name: 'Half Moon Bay Golf Links - Ocean Course',
          facilityId: 'half-moon-bay-golf-links-ca',
          facilityName: 'Half Moon Bay Golf Links',
          // No subCourseSlug — exercise the parse-from-name fallback.
          state: 'CA',
        ),
        _entry(
          name: 'Half Moon Bay Golf Links - Old Course',
          facilityId: 'half-moon-bay-golf-links-ca',
          facilityName: 'Half Moon Bay Golf Links',
          subCourseSlug: 'old-course',
          state: 'CA',
        ),
      ];

      final byLegName = {
        for (final p in CourseSearchEntry.findSubCourses(tapped, manifest))
          p.legName: p.entry,
      };

      expect(byLegName.keys.toSet(), {'Ocean Course', 'old-course'});
    });
  });
}
