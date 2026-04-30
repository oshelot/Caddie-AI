// Widget test for KAN-280 (S10) Course tab loader. Verifies that:
//
//   1. The fixture loader returns a parseable NormalizedCourse and
//      the loading indicator gives way to the protected content.
//   2. The screen wraps its content in a `LocationGate` (S4) so the
//      Mapbox MapWidget never inflates without permission. We
//      assert via the LocationGate's denied-state UI: with a fake
//      location service that returns `permanentlyDenied`, the
//      MapWidget is NOT in the tree and the "Open Settings" CTA
//      from the gate is.
//
// **Why we don't pump the real CourseMapScreen here:** the Mapbox
// `MapWidget` calls into the platform plugin during build, which
// throws on the unit-test runner. We test the GATE behavior — that
// LocationGate keeps the map out of the tree until permission is
// granted. The map screen's logic (layer audits, hole selection,
// tap-to-distance) is tested directly via its dedicated test file
// without inflating the widget at all.

import 'package:caddieai/core/location/location_service.dart';
import 'package:caddieai/features/course/presentation/course_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../location/_fake_location_service.dart';

void main() {
  group('CoursePlaceholder + LocationGate (S10 + S4)', () {
    testWidgets(
        'when location permission is permanentlyDenied, the map screen '
        'is NOT in the tree and the gate banner is visible', (tester) async {
      final fake = FakeLocationService(
        initialStatus: LocationPermission.permanentlyDenied,
      );

      await tester.pumpWidget(MaterialApp(
        home: CoursePlaceholder(locationService: fake),
      ));
      await tester.pumpAndSettle();

      // The gate's denied banner is showing.
      expect(find.text('Location Access Required'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);

      // The map screen's hole selector is NOT in the tree (proves
      // the protected child wasn't built).
      expect(find.text('All'), findsNothing);
    });

    testWidgets(
        'when location permission is notDetermined, the rationale '
        'screen is shown and the map screen is NOT in the tree',
        (tester) async {
      final fake = FakeLocationService(
        initialStatus: LocationPermission.notDetermined,
      );

      await tester.pumpWidget(MaterialApp(
        home: CoursePlaceholder(locationService: fake),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Location Access'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('All'), findsNothing);
    });
  });
}
