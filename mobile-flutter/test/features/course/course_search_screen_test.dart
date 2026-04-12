// Widget tests for the CourseSearchScreen — final shape (KAN-279
// + KAN-296 + KAN-29 + Story B/D structural rewrite).
//
// **Logger lifecycle:** `LoggingService` lazy-creates a periodic
// Timer on the first event. The test framework checks for pending
// Timers at the END of the test body (BEFORE `tearDown` runs), so
// every test that fires a search MUST call `logger.dispose()`
// before its last `expect`.
//
// **Search trigger:** the screen no longer auto-fires onSearch on
// debounced text changes. The Search button is the ONLY trigger.
// Tests use the `_runSearch` helper which enters the query then
// taps the button.
//
// Coverage:
//   1. Idle / demo / location-required states
//   2. Search button → onSearch flow + result rendering + dedup
//      empty/error states
//   3. Telemetry: every search emits log_search_latency
//   4. City autocomplete debounce + suggestion tap-to-fill
//   5. Tabs (Search/Saved) — only render when a favoritesController
//      is supplied
//   6. Saved tab → Favorites + Other Saved sections
//   7. Favorite toggle (search-tab quick list + Saved tab)

import 'package:caddieai/core/courses/course_search_results.dart';
import 'package:caddieai/core/courses/places_client.dart';
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

/// In-memory FavoritesController for the Saved-tab + favorites
/// tests. The production wiring uses CourseCacheRepository, which
/// has the same shape but talks to Hive.
class _FakeFavorites {
  final Map<String, CourseSearchEntry> _saved = {};
  final Set<String> _favorites = {};

  void preload(List<CourseSearchEntry> rows, {Set<String> favorites = const {}}) {
    for (final row in rows) {
      _saved[row.cacheKey] = row;
    }
    _favorites.addAll(favorites);
  }

  FavoritesController controller() => FavoritesController(
        listSaved: () {
          final rows = _saved.values
              .map((e) => e.copyWith(isFavorite: _favorites.contains(e.cacheKey)))
              .toList();
          rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return rows;
        },
        isFavorite: (k) => _favorites.contains(k),
        toggleFavorite: (k) async {
          if (_favorites.contains(k)) {
            _favorites.remove(k);
            return false;
          }
          _favorites.add(k);
          return true;
        },
      );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required Future<CourseSearchOutcome> Function(String, String) onSearch,
  required void Function(CourseSearchEntry) onSelectCourse,
  required LoggingService logger,
  bool locationGranted = false,
  CourseSearchEntry? demoEntry,
  Duration debounce = Duration.zero,
  Future<List<PlaceAutocompleteSuggestion>> Function(String)? onCityAutocomplete,
  FavoritesController? favoritesController,
}) async {
  // Wide enough so SegmentedButton lays out without overflow when the
  // tab bar is rendered.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: CourseSearchScreen(
      onSearch: onSearch,
      onSelectCourse: onSelectCourse,
      logger: logger,
      locationGranted: locationGranted,
      initialDemoEntry: demoEntry,
      debounce: debounce,
      onCityAutocomplete: onCityAutocomplete,
      favoritesController: favoritesController,
    ),
  ));
  await tester.pump();
}

/// Drives a full search: types the query, taps the Search button,
/// pumps twice to let the future resolve.
Future<void> _runSearch(WidgetTester tester, String query) async {
  await tester.enterText(
    find.byKey(CourseSearchKeys.courseNameField),
    query,
  );
  await tester.pump();
  await tester.tap(find.byKey(CourseSearchKeys.searchButton));
  await tester.pump();
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
        onSearch: (_, __) async => CourseSearchOutcome.empty,
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
        onSearch: (_, __) async => CourseSearchOutcome.empty,
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
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (e) => selected = e,
        logger: logger,
        demoEntry: _entry1,
      );
      await tester.tap(find.textContaining('Open demo'));
      await tester.pump();
      expect(selected, _entry1);
    });
  });

  group('search → results (button-driven, no auto-fire)', () {
    testWidgets('typing in the name field does NOT auto-fire onSearch',
        (tester) async {
      var callCount = 0;
      await _pumpScreen(
        tester,
        onSearch: (_, __) async {
          callCount++;
          return CourseSearchOutcome.empty;
        },
        onSelectCourse: (_) {},
        logger: logger,
      );
      // Type into the name field and pump for a generous window.
      await tester.enterText(
        find.byKey(CourseSearchKeys.courseNameField),
        'sharp',
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(callCount, 0,
          reason: 'native apps only fire on the Search button');
    });

    testWidgets('tapping the Search button calls onSearch exactly once with '
        'the trimmed query', (tester) async {
      var callCount = 0;
      String? receivedQuery;
      await _pumpScreen(
        tester,
        onSearch: (q, _) async {
          callCount++;
          receivedQuery = q;
          return const CourseSearchOutcome(entries: [_entry1, _entry2]);
        },
        onSelectCourse: (_) {},
        logger: logger,
      );
      await _runSearch(tester, '  sharp  ');
      expect(callCount, 1);
      expect(receivedQuery, 'sharp');
      logger.dispose();
    });

    testWidgets('renders both result entries', (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_, __) async =>
            const CourseSearchOutcome(entries: [_entry1, _entry2]),
        onSelectCourse: (_) {},
        logger: logger,
      );
      await _runSearch(tester, 'park');

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
        onSearch: (_, __) async =>
            const CourseSearchOutcome(entries: [_entry1, _entry2]),
        onSelectCourse: (e) => selected = e,
        logger: logger,
      );
      await _runSearch(tester, 'park');
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
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
      );
      await _runSearch(tester, 'nope');
      expect(find.text('No courses found'), findsOneWidget);
      expect(find.textContaining('"nope"'), findsOneWidget);
      logger.dispose();
    });

    testWidgets('error state when onSearch throws', (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => throw Exception('boom'),
        onSelectCourse: (_) {},
        logger: logger,
      );
      await _runSearch(tester, 'wellshire');
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
        onSearch: (_, __) async =>
            const CourseSearchOutcome(entries: [], error: '503'),
        onSelectCourse: (_) {},
        logger: logger,
      );
      await _runSearch(tester, 'x');
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
        onSearch: (_, __) async => CourseSearchOutcome.empty,
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
        onSearch: (_, __) async => CourseSearchOutcome.empty,
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

  group('city autocomplete (KAN-29 port)', () {
    testWidgets('city field is hidden when no autocomplete callback is given',
        (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
      );
      expect(find.byKey(CourseSearchKeys.cityField), findsNothing);
      expect(find.byKey(CourseSearchKeys.courseNameField), findsOneWidget);
    });

    testWidgets('city field renders when autocomplete callback is supplied',
        (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        onCityAutocomplete: (_) async => const [],
      );
      expect(find.byKey(CourseSearchKeys.cityField), findsOneWidget);
    });

    testWidgets('typing into the city field calls the autocomplete callback '
        'after the debounce', (tester) async {
      var calls = 0;
      String? receivedInput;
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        debounce: const Duration(milliseconds: 50),
        onCityAutocomplete: (input) async {
          calls++;
          receivedInput = input;
          return const [
            PlaceAutocompleteSuggestion(
              description: 'Denver, CO, USA',
              mainText: 'Denver',
              secondaryText: 'CO, USA',
            ),
          ];
        },
      );
      await tester.enterText(find.byKey(CourseSearchKeys.cityField), 'DEN');
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
      expect(calls, 1);
      expect(receivedInput, 'DEN');
      expect(find.text('Denver'), findsOneWidget);
      expect(find.text('CO, USA'), findsOneWidget);
    });

    testWidgets('tapping a suggestion fills the city field and hides the list',
        (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        onCityAutocomplete: (_) async => const [
          PlaceAutocompleteSuggestion(
            description: 'Pacifica, CA, USA',
            mainText: 'Pacifica',
            secondaryText: 'CA, USA',
          ),
        ],
      );
      await tester.enterText(find.byKey(CourseSearchKeys.cityField), 'Pac');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(Key('course-search-city-suggestion-0')), findsOneWidget);

      await tester.tap(find.byKey(Key('course-search-city-suggestion-0')));
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(CourseSearchKeys.cityField),
      );
      expect(field.controller!.text, 'Pacifica, CA, USA');
      expect(find.byKey(Key('course-search-city-suggestion-0')), findsNothing);
    });

    testWidgets('city is forwarded to onSearch on the next button tap',
        (tester) async {
      String? receivedQuery;
      String? receivedCity;
      await _pumpScreen(
        tester,
        onSearch: (q, c) async {
          receivedQuery = q;
          receivedCity = c;
          return CourseSearchOutcome.empty;
        },
        onSelectCourse: (_) {},
        logger: logger,
        onCityAutocomplete: (_) async => const [],
      );
      await tester.enterText(
        find.byKey(CourseSearchKeys.cityField),
        'Pacifica, CA, USA',
      );
      await tester.pump();
      await _runSearch(tester, 'sharp');
      expect(receivedQuery, 'sharp');
      expect(receivedCity, 'Pacifica, CA, USA');
      logger.dispose();
    });
  });

  group('Search/Saved tabs (no favoritesController = single-pane mode)', () {
    testWidgets('with no favoritesController, no tab bar renders',
        (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
      );
      expect(find.byType(SegmentedButton<int>), findsNothing);
    });

    testWidgets('with a favoritesController, the Search/Saved tab bar renders',
        (tester) async {
      final fakes = _FakeFavorites();
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        favoritesController: fakes.controller(),
      );
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
      expect(find.text('Search'), findsWidgets);
      expect(find.text('Saved'), findsWidgets);
    });
  });

  group('Saved tab', () {
    testWidgets('shows empty state when no saved courses exist',
        (tester) async {
      final fakes = _FakeFavorites();
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        favoritesController: fakes.controller(),
      );
      // Switch to Saved tab.
      await tester.tap(find.text('Saved').last);
      await tester.pump();
      expect(find.text('No saved courses'), findsOneWidget);
    });

    testWidgets('renders Favorites and Other Saved sections', (tester) async {
      final fakes = _FakeFavorites();
      fakes.preload(
        [_entry1, _entry2],
        favorites: {'sharp-park'},
      );
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        favoritesController: fakes.controller(),
      );
      await tester.tap(find.text('Saved').last);
      await tester.pump();

      expect(find.byKey(CourseSearchKeys.favoritesSection), findsOneWidget);
      expect(find.byKey(CourseSearchKeys.savedOtherSection), findsOneWidget);
      expect(find.text('Sharp Park Golf Course'), findsOneWidget);
      expect(find.text('Lincoln Park Golf Course'), findsOneWidget);
    });

    testWidgets('tapping a Saved row invokes onSelectCourse', (tester) async {
      final fakes = _FakeFavorites();
      fakes.preload([_entry1]);
      CourseSearchEntry? selected;
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (e) => selected = e,
        logger: logger,
        favoritesController: fakes.controller(),
      );
      await tester.tap(find.text('Saved').last);
      await tester.pump();
      await tester.tap(find.text('Sharp Park Golf Course'));
      await tester.pump();
      expect(selected?.cacheKey, 'sharp-park');
    });
  });

  group('Favorites quick-list on the Search tab', () {
    testWidgets('renders favorited courses under the search form',
        (tester) async {
      final fakes = _FakeFavorites();
      fakes.preload([_entry1], favorites: {'sharp-park'});
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        favoritesController: fakes.controller(),
      );
      // Search tab is the default selected tab.
      expect(find.byKey(CourseSearchKeys.favoritesSection), findsOneWidget);
      expect(find.text('Sharp Park Golf Course'), findsOneWidget);
    });

    testWidgets('only favorited courses appear in the quick-list, not '
        'every saved course', (tester) async {
      final fakes = _FakeFavorites();
      fakes.preload(
        [_entry1, _entry2],
        favorites: {'sharp-park'}, // only sharp-park is favorited
      );
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        favoritesController: fakes.controller(),
      );
      expect(find.text('Sharp Park Golf Course'), findsOneWidget);
      expect(find.text('Lincoln Park Golf Course'), findsNothing);
    });

    testWidgets('tapping the star toggles favorite state via the controller',
        (tester) async {
      final fakes = _FakeFavorites();
      fakes.preload([_entry1], favorites: {'sharp-park'});
      await _pumpScreen(
        tester,
        onSearch: (_, __) async => CourseSearchOutcome.empty,
        onSelectCourse: (_) {},
        logger: logger,
        favoritesController: fakes.controller(),
      );
      // The star icon for the favorited entry — find via the
      // favorite-toggle key (the only place IconButtons appear in
      // the favorites section).
      final starFinder = find.byKey(CourseSearchKeys.favoriteToggle);
      expect(starFinder, findsOneWidget);
      await tester.tap(starFinder);
      await tester.pump();
      // After unstar, the favorites section disappears entirely.
      expect(find.byKey(CourseSearchKeys.favoritesSection), findsNothing);
    });
  });

  group('telemetry contract — log_search_latency', () {
    testWidgets(
        'every completed search emits a log_search_latency event with the '
        'canonical metadata fields', (tester) async {
      await _pumpScreen(
        tester,
        onSearch: (_, __) async =>
            const CourseSearchOutcome(entries: [_entry1, _entry2]),
        onSelectCourse: (_) {},
        logger: logger,
      );
      await _runSearch(tester, 'park');

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
        onSearch: (_, __) async => throw Exception('network down'),
        onSelectCourse: (_) {},
        logger: logger,
      );
      await _runSearch(tester, 'x');

      final searchEvents = sender.sent
          .where((e) => e.message == 'log_search_latency')
          .toList();
      expect(searchEvents, hasLength(1));
      expect(searchEvents.first.metadata['resultCount'], '0');
      logger.dispose();
    });
  });
}
