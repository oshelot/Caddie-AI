// CoursePlaceholder — KAN-280 (S10) wires the production
// `CourseMapScreen` behind a `LocationGate` and a fixture loader.
//
// **Why this still has the "placeholder" name:** the tab content
// today is the bare map screen with the lifted Sharp Park fixture.
// Once KAN-S5 (course cache) gets wired into a search → fetch flow
// in KAN-S9 (course search screen), this widget gets replaced by
// the real list/search UI and the map becomes a destination route.
// The file name will be renamed at that point — keeping it now
// avoids churning every other reference to `CoursePlaceholder`.
//
// **Loader path:** the fixture is loaded from
// `assets/fixtures/sharp_park.json` via `rootBundle`. This is
// intentional fallback behavior for offline development; production
// builds will fetch from `CourseCacheClient` once KAN-S9 is shipped.
//
// **LocationGate** (from S4) wraps the map so the system permission
// prompt fires BEFORE the map renders. Per the S4 AC, the
// protected child (here: `CourseMapScreen`) is not in the widget
// tree until permission has been granted.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/location/geolocator_location_service.dart';
import '../../../core/location/location_gate.dart';
import '../../../core/location/location_service.dart';
import '../../../main.dart' show logger;
import '../../../models/normalized_course.dart';
import 'course_map_screen.dart';

class CoursePlaceholder extends StatefulWidget {
  const CoursePlaceholder({super.key, this.locationService});

  /// Optional injected location service for tests. Production
  /// uses `GeolocatorLocationService` (the S4 default).
  final LocationService? locationService;

  @override
  State<CoursePlaceholder> createState() => _CoursePlaceholderState();
}

class _CoursePlaceholderState extends State<CoursePlaceholder> {
  late final LocationService _locationService =
      widget.locationService ?? GeolocatorLocationService();
  late final Future<NormalizedCourse> _courseFuture = _loadFixture();

  Future<NormalizedCourse> _loadFixture() async {
    final raw =
        await rootBundle.loadString('assets/fixtures/sharp_park.json');
    return NormalizedCourse.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    return LocationGate(
      service: _locationService,
      rationale:
          'CaddieAI uses your location to show your position on the '
          'course map and calculate shot distances.',
      child: FutureBuilder<NormalizedCourse>(
        future: _courseFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Course')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load the fallback course fixture.\n\n'
                    '${snapshot.error ?? 'Unknown error'}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
          return CourseMapScreen(
            course: snapshot.data!,
            logger: logger,
          );
        },
      ),
    );
  }
}
