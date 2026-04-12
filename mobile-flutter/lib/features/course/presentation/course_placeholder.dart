// CoursePlaceholder — KAN-280 (S10) loader for the Course Map
// screen. Behavior changed in KAN-279 (S9): instead of being the
// landing widget for the Course tab, this is now the route widget
// for `/course/map`, pushed from `CourseSearchPage` with a
// resolved `NormalizedCourse` in `GoRouterState.extra`.
//
// **Resolution order for the course to render:**
//
// 1. `widget.injectedCourse` (set by the route builder when the
//    user reached this screen via a search-result tap). Skips
//    the fixture load entirely.
// 2. The bundled `assets/fixtures/sharp_park.json` fallback.
//    Used when the user navigates here directly (deep link, hot
//    restart, or eventually a "recently viewed" jump-back).
//
// In both cases the screen is wrapped in a `LocationGate` (S4)
// so the system permission prompt fires BEFORE `CourseMapScreen`
// builds.
//
// **Why the file name is still `course_placeholder.dart`:** the
// file was originally the placeholder for the Course tab. Renaming
// it would churn every reference in the router and the widget
// tests. Keeping the name avoids the rename diff while the file
// continues to evolve. A cleanup ticket can rename it later.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';

import '../../../core/location/geolocator_location_service.dart';
import '../../../core/location/location_gate.dart';
import '../../../core/location/location_service.dart';
import '../../../core/routing/app_router.dart';
import '../../../main.dart' show logger;
import '../../../models/normalized_course.dart';
import 'course_map_screen.dart';

class CoursePlaceholder extends StatefulWidget {
  const CoursePlaceholder({
    super.key,
    this.locationService,
    this.injectedCourse,
  });

  /// Optional injected location service for tests. Production
  /// uses `GeolocatorLocationService` (the S4 default).
  final LocationService? locationService;

  /// Course passed by the route builder when the user reached
  /// this screen via a search-result tap (KAN-S9). Skips the
  /// asset-load fallback entirely. Null means "load the
  /// Sharp Park fixture".
  final NormalizedCourse? injectedCourse;

  @override
  State<CoursePlaceholder> createState() => _CoursePlaceholderState();
}

class _CoursePlaceholderState extends State<CoursePlaceholder> {
  late final LocationService _locationService =
      widget.locationService ?? GeolocatorLocationService();

  late final Future<NormalizedCourse> _courseFuture =
      widget.injectedCourse != null
          ? Future.value(widget.injectedCourse!)
          : _loadFixture();

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
                    'Failed to load the course.\n\n'
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
            onAskCaddie: () {
              // Navigate to the Caddie tab.
              // ignore: use_build_context_synchronously
              context.go(AppRoutes.caddie);
            },
            // Analyze uses the built-in hole analysis sheet — no
            // navigation needed. Passing null tells the map screen
            // to show its own sheet.
          );
        },
      ),
    );
  }
}
