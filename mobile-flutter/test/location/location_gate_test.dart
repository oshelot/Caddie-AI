// Widget tests for KAN-274 (S4) — LocationGate. Covers every AC:
//
//   1. AC #1: First-run prompt fires BEFORE the wrapped child
//      mounts. The test asserts that the child widget is NOT in
//      the tree until permission is granted.
//   2. AC #2: Denied path renders the "enable in settings" banner
//      and does NOT crash.
//   3. AC #3: LocationService is mockable for tests — this entire
//      file uses a `FakeLocationService` with no platform calls.
//
// Test pattern: each test constructs a `FakeLocationService` with
// a scripted response sequence, pumps a `MaterialApp` containing a
// `LocationGate` wrapping a sentinel `Text('protected child')`,
// and asserts the right widgets are visible at each phase.

import 'package:caddieai/core/location/location_gate.dart';
import 'package:caddieai/core/location/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLocationService implements LocationService {
  FakeLocationService({
    LocationPermission initialStatus = LocationPermission.notDetermined,
    LocationPermission? requestResult,
  })  : _status = initialStatus,
        _requestResult = requestResult;

  LocationPermission _status;
  final LocationPermission? _requestResult;

  int requestCallCount = 0;
  int openSettingsCallCount = 0;

  /// Test hook to flip the status (e.g. simulate the user
  /// returning from settings with permission newly granted).
  void setStatus(LocationPermission status) => _status = status;

  @override
  Future<LocationPermission> permissionStatus() async => _status;

  @override
  Future<LocationPermission> requestPermission() async {
    requestCallCount++;
    final result = _requestResult;
    if (result != null) {
      _status = result;
    }
    return _status;
  }

  @override
  Future<LocationReading> currentLocation() async {
    throw UnimplementedError();
  }

  @override
  Stream<HeadingReading> headingStream() {
    throw UnimplementedError();
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCallCount++;
    return true;
  }
}

const _protectedChildKey = Key('protected-child');

Widget _wrapInApp(LocationGate gate) {
  return MaterialApp(home: gate);
}

void main() {
  group('LocationGate — granted from the start', () {
    testWidgets('renders the protected child immediately when already granted',
        (tester) async {
      final fake = FakeLocationService(
        initialStatus: LocationPermission.granted,
      );

      await tester.pumpWidget(_wrapInApp(LocationGate(
        service: fake,
        child: const Text('protected child', key: _protectedChildKey),
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(_protectedChildKey), findsOneWidget);
      expect(fake.requestCallCount, 0,
          reason: 'should not re-prompt when already granted');
    });
  });

  group('LocationGate — first-run prompt path (AC #1)', () {
    testWidgets(
        'shows the rationale screen first; protected child is NOT in the '
        'tree until permission is granted', (tester) async {
      final fake = FakeLocationService(
        initialStatus: LocationPermission.notDetermined,
        requestResult: LocationPermission.granted,
      );

      await tester.pumpWidget(_wrapInApp(LocationGate(
        service: fake,
        child: const Text('protected child', key: _protectedChildKey),
      )));
      await tester.pumpAndSettle();

      // Rationale screen visible.
      expect(find.text('Location Access'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      // Crucially: the child has NOT been built yet (AC #1).
      expect(find.byKey(_protectedChildKey), findsNothing);
      expect(fake.requestCallCount, 0);

      // User taps Continue.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Now the prompt has been requested AND permission was
      // granted, so the child renders.
      expect(fake.requestCallCount, 1);
      expect(find.byKey(_protectedChildKey), findsOneWidget);
      expect(find.text('Location Access'), findsNothing);
    });
  });

  group('LocationGate — denied path (AC #2)', () {
    testWidgets('shows a "Continue" retry button when denied (not permanent)',
        (tester) async {
      final fake = FakeLocationService(
        initialStatus: LocationPermission.denied,
      );

      await tester.pumpWidget(_wrapInApp(LocationGate(
        service: fake,
        child: const Text('protected child', key: _protectedChildKey),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Location Access Required'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.byKey(_protectedChildKey), findsNothing);
      // Continue should be a normal button, NOT the settings button.
      expect(find.text('Open Settings'), findsNothing);
    });

    testWidgets(
        'permanentlyDenied shows "Open Settings" deep-link button '
        '(AC #2 — denied banner)', (tester) async {
      final fake = FakeLocationService(
        initialStatus: LocationPermission.permanentlyDenied,
      );

      await tester.pumpWidget(_wrapInApp(LocationGate(
        service: fake,
        child: const Text('protected child', key: _protectedChildKey),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Location Access Required'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.byKey(_protectedChildKey), findsNothing);

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(fake.openSettingsCallCount, 1);
    });

    testWidgets('restricted (parental controls) shows the settings button',
        (tester) async {
      final fake = FakeLocationService(
        initialStatus: LocationPermission.restricted,
      );

      await tester.pumpWidget(_wrapInApp(LocationGate(
        service: fake,
        child: const Text('protected child', key: _protectedChildKey),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Open Settings'), findsOneWidget);
    });

    testWidgets('returning from settings with newly-granted permission '
        'unlocks the child', (tester) async {
      final fake = FakeLocationService(
        initialStatus: LocationPermission.permanentlyDenied,
      );

      await tester.pumpWidget(_wrapInApp(LocationGate(
        service: fake,
        child: const Text('protected child', key: _protectedChildKey),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(_protectedChildKey), findsNothing);

      // Simulate the user toggling permission ON in system settings.
      fake.setStatus(LocationPermission.granted);
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(find.byKey(_protectedChildKey), findsOneWidget);
    });
  });

  group('LocationGate — request returning denied stays on the gate',
      () {
    testWidgets('user denies the prompt → gate flips to the denied screen',
        (tester) async {
      final fake = FakeLocationService(
        initialStatus: LocationPermission.notDetermined,
        requestResult: LocationPermission.denied,
      );

      await tester.pumpWidget(_wrapInApp(LocationGate(
        service: fake,
        child: const Text('protected child', key: _protectedChildKey),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Location Access'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(fake.requestCallCount, 1);
      expect(find.byKey(_protectedChildKey), findsNothing);
      expect(find.text('Location Access Required'), findsOneWidget);
    });
  });
}
