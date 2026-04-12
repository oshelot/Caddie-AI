// Widget tests for KAN-279 (S9) CourseSearchScreen.
//
// **Logger lifecycle (read this before adding new tests):**
// `LoggingService` lazy-creates a periodic Timer on the first
// event. The Flutter test framework checks for pending Timers at
// the END of the test body (BEFORE `tearDown` runs), so disposing
// the logger from `tearDown`/`addTearDown` is too late — the
// pending-timer assertion fires first. Every test below that
// triggers a search MUST call `disposeLogger()` before its last
// `expect`. Tests that never log (e.g. pure idle-state tests)
// don't need it. The `_pumpAndDispose` helper bundles
// search + assertion + disposal for the common case.
//
// Coverage:
//   1. Idle state — no query, demo entry visible if supplied
//   2. Debounced search — typing fires the callback exactly once
//      after the debounce window
//   3. Result list — entries render with name + city/state
//   4. Empty state — onSearch returning [] shows the "no results" UI
//   5. Error state — onSearch throwing shows the error UI with the
//      message
//   6. Location-required state — toggling "use my location" without
//      permission shows the location-required hint
//   7. Tap result — invokes onSelectCourse with the right entry
//   8. Telemetry contract — every search emits a `log_search_latency`
//      event with the canonical metadata fields

import 'package:caddieai/core/courses/course_search_results.dart';
import 'package:caddieai/core/logging/log_event.dart';
import 'package:caddieai/core/logging/log_sender.dart';
import 'package:caddieai/core/logging/logging_service.dart';
import 'package:caddieai/features/course/presentation/course_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class CapturingLogSender implements LogSender {
  final List<LogEntry> sent = [];
  @override
  Future<bool> send({
    required List<LogEntry> entries,
    required String deviceId,
    required String sessionId,
  }) async {
    sent.addAll(entries);
    return true;
  }
}

/// Builds a logger with a 1-event flush threshold and a long
/// flushInterval so events drain to the sender immediately AND
/// the periodic timer (lazy-created on the first event) only
/// fires once per hour. Tests still must call `dispose()` before
/// the test body returns — the Timer is alive until then.
LoggingService _newLogger(CapturingLogSender sender) => LoggingService(
      sender: sender,
      deviceId: 'd',
      sessionId: 's',
      enabled: true,
      flushThreshold: 1,
      flushInterval: const Duration(hours: 1),
    );

const _entry1 = CourseSearchEntry(
  cacheKey: 'sharp-park',
  name: 'Sharp Park Golf Course',
  city: 'Pacifica',
  state: 'CA',
  latitude: 37.6244,
  longitude: -122.4885,
);

const _entry2 = CourseSearchEntry(
  cacheKey: 'lincoln-park',
  name: 'Lincoln Park Golf Course',
  city: 'San Francisco',
  state: 'CA',
  latitude: 37.7833,
  longitude: -122.5000,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required Future<CourseSearchOutcome> Function(String) onSearch,
  required void Function(CourseSearchEntry) onSelectCourse,
  required LoggingService logger,
  bool locationGranted = false,
  CourseSearchEntry? demoEntry,
  Duration debounce = Duration.zero,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: CourseSearchScreen(
      onSearch: onSearch,
      onSelectCourse: onSelectCourse,
      logger: logger,
      locationGranted: locationGranted,
      initialDemoEntry: demoEntry,
      debounce: debounce,
    ),
  ));
  await tester.pump();
}

void main() {
  late CapturingLogSender sender;
  late LoggingService logger;

  setUp(() {
    sender = CapturingLogSender();
    logger = _newLogger(sender);
  });

  group('idle state (no logger events — no disposal needed)', () {
    testWidgets('shows the prompt and the demo entry button when supplied',
        (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        demoEntry: _entry1,
      );
      expect(find.text('Type a course name to begin'), findsOneWidget);
      expect(find.textContaining('Open demo'), findsOneWidget);
    });

    testWidgets('hides the demo button when no entry is supplied',
        (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
      );
      expect(find.textContaining('Open demo'), findsNothing);
    });

    testWidgets('tapping the demo button invokes onSelectCourse',
        (tester) async {
      CourseSearchEntry? selected;
      await _pumpScreen(
        tester,
        onSearch: (_) async => CourseSearchOutcome.empty,
        onSelectCourse: (e) => selected = e,
        logger: logger,
        demoEntry: _entry1,
      );
      await tester.tap(find.textContaining('Open demo'));
      await tester.pump();
      expect(selected, _entry1);
    });
  });

  group('search → results', () {
    testWidgets('debounced search calls onSearch exactly once', (tester) async {
      var callCount = 0;
      String? receivedQuery;
      await _pumpScreen(
        tester,
        onSearch: (q) async {
          callCount++;
          receivedQuery = q;
          return const CourseSearchOutcome(entries: [_entry1, _entry2]);
        },
        onSelectCourse: (_) {},
        logger: logger,
        debounce: const Duration(milliseconds: 50),
      );

      // Multiple keystrokes within the debounce window collapse
      // to a single search.
      await tester.enterText(find.byType(TextField), 'sh');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.enterText(find.byType(TextField), 'sha');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.enterText(find.byType(TextField), 'shar');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.enterText(find.byType(TextField), 'sharp');
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();

      expect(callCount, 1);
      expect(receivedQuery, 'sharp');
      logger.dispose();
    });

    testWidgets('renders both result entries', (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_) async =>
            const CourseSearchOutcome(entries: [_entry1, _entry2]),
        onSelectCourse: (_) {},
        logger: logger,
      );
      await tester.enterText(find.byType(TextField), 'park');
      await tester.pump();
      await tester.pump();

      expect(find.text('Sharp Park Golf Course'), findsOneWidget);
      expect(find.text('Pacifica, CA'), findsOneWidget);
      expect(find.text('Lincoln Park Golf Course'), findsOneWidget);
      expect(find.text('San Francisco, CA'), findsOneWidget);
      logger.dispose();
    });

    testWidgets('tapping a result invokes onSelectCourse with the entry',
        (tester) async {
      CourseSearchEntry? selected;
      await _pumpScreen(
        tester,
        onSearch: (_) async =>
            const CourseSearchOutcome(entries: [_entry1, _entry2]),
        onSelectCourse: (e) => selected = e,
        logger: logger,
      );
      await tester.enterText(find.byType(TextField), 'park');
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Sharp Park Golf Course'));
      await tester.pump();

      expect(selected, _entry1);
      logger.dispose();
    });
  });

  group('empty + error states', () {
    testWidgets('"no results" state when onSearch returns []',
        (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
      );
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.pump();
      await tester.pump();

      expect(find.text('No courses found'), findsOneWidget);
      expect(find.textContaining('"nope"'), findsOneWidget);
      logger.dispose();
    });

    testWidgets('error state when onSearch throws', (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_) async => throw Exception('boom'),
        onSelectCourse: (_) {},
        logger: logger,
      );
      await tester.enterText(find.byType(TextField), 'wellshire');
      await tester.pump();
      await tester.pump();

      expect(find.textContaining("Couldn't reach the course cache"),
          findsOneWidget);
      expect(find.textContaining('boom'), findsOneWidget);
      logger.dispose();
    });

    testWidgets(
        'error state when onSearch returns an outcome with an error message',
        (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_) async =>
            const CourseSearchOutcome(entries: [], error: '503'),
        onSelectCourse: (_) {},
        logger: logger,
      );
      await tester.enterText(find.byType(TextField), 'x');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('503'), findsOneWidget);
      logger.dispose();
    });
  });

  group('location-required state (no logger events — no disposal needed)',
      () {
    testWidgets(
        'toggling "use my location" without permission shows the hint',
        (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        locationGranted: false,
      );
      expect(find.text('permission required'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.text('Location required'), findsOneWidget);
    });

    testWidgets('with permission granted, the toggle works without hint',
        (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        locationGranted: true,
      );
      expect(find.text('permission required'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.text('Location required'), findsNothing);
    });
  });

  group('telemetry contract — log_search_latency', () {
    testWidgets(
        'every completed search emits a log_search_latency event with the '
        'canonical metadata fields', (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_) async =>
            const CourseSearchOutcome(entries: [_entry1, _entry2]),
        onSelectCourse: (_) {},
        logger: logger,
      );
      await tester.enterText(find.byType(TextField), 'park');
      await tester.pump();
      await tester.pump();

      expect(sender.sent, isNotEmpty);
      final searchEvents = sender.sent
          .where((e) => e.message == 'log_search_latency')
          .toList();
      expect(searchEvents, hasLength(1));
      final entry = searchEvents.first;
      expect(entry.metadata['query'], 'park');
      expect(entry.metadata['resultCount'], '2');
      expect(entry.metadata['hasLocation'], 'false');
      expect(entry.metadata['latencyMs'], isNotNull);
      logger.dispose();
    });

    testWidgets('error path also emits a log_search_latency event with '
        'resultCount=0', (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_) async => throw Exception('network down'),
        onSelectCourse: (_) {},
        logger: logger,
      );
      await tester.enterText(find.byType(TextField), 'x');
      await tester.pump();
      await tester.pump();

      final searchEvents = sender.sent
          .where((e) => e.message == 'log_search_latency')
          .toList();
      expect(searchEvents, hasLength(1));
      expect(searchEvents.first.metadata['resultCount'], '0');
      logger.dispose();
    });
  });
}
