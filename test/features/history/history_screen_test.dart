// Widget tests for KAN-282 (S12) HistoryScreen.
//
// Coverage:
//   1. Empty state when there are no shots
//   2. Renders all shot tiles + filter chips for outcomes/types
//   3. Filtering by outcome shrinks the visible list
//   4. Filtering by shot type shrinks the visible list
//   5. Tapping a tile expands the detail drawer
//   6. scoringEnabled = false → single-tab layout (no Scorecards tab)
//   7. scoringEnabled = true → TabBar with Shots + Scorecards
//   8. Scorecards tab empty state
//   9. Scorecards tab renders entries with score-to-par

import 'package:caddieai/features/history/presentation/history_screen.dart';
import 'package:caddieai/models/scorecard_entry.dart';
import 'package:caddieai/models/shot_history_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ShotHistoryEntry _makeEntry({
  required String id,
  required int distanceYards,
  String shotType = 'approach',
  String lieType = 'fairway',
  String outcome = 'good',
  String club = 'iron7',
  String courseName = '',
  String notes = '',
}) {
  return ShotHistoryEntry(
    id: id,
    timestampMs: DateTime.utc(2026, 4, 5).millisecondsSinceEpoch,
    courseName: courseName,
    context: ShotContext(
      distanceYards: distanceYards,
      shotType: shotType,
      lieType: lieType,
    ),
    recommendedClub: club,
    outcome: outcome,
    notes: notes,
  );
}

ScorecardEntry _makeScorecard(String id, int relativeToPar) {
  return ScorecardEntry(
    id: id,
    courseId: 'wellshire',
    courseName: 'Wellshire',
    dateMs: DateTime.utc(2026, 4, 1).millisecondsSinceEpoch,
    holeScores: List.generate(
      18,
      (i) => HoleScore(
        holeNumber: i + 1,
        par: 4,
        score: 4 + (i == 0 ? relativeToPar : 0),
      ),
    ),
    status: 'completed',
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<ShotHistoryEntry> entries,
  List<ScorecardEntry> scorecards = const [],
  bool scoringEnabled = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: HistoryScreen(
      entries: entries,
      scorecards: scorecards,
      scoringEnabled: scoringEnabled,
    ),
  ));
  await tester.pump();
}

void main() {
  group('empty state', () {
    testWidgets('shows the empty state when there are no entries',
        (tester) async {
      await _pumpScreen(tester, entries: const []);
      expect(find.text('No shots yet'), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
    });
  });

  group('list rendering', () {
    testWidgets('renders all entries with their club + distance',
        (tester) async {
      await _pumpScreen(tester, entries: [
        _makeEntry(id: '1', distanceYards: 150, club: 'iron7'),
        _makeEntry(id: '2', distanceYards: 90, club: 'sandWedge', shotType: 'chip'),
      ]);
      expect(find.text('iron7'), findsOneWidget);
      expect(find.text('sandWedge'), findsOneWidget);
      expect(find.textContaining('150y'), findsOneWidget);
      expect(find.textContaining('90y'), findsOneWidget);
    });

    testWidgets('renders filter chips for every distinct outcome', (tester) async {
      await _pumpScreen(tester, entries: [
        _makeEntry(id: '1', distanceYards: 150, outcome: 'good'),
        _makeEntry(id: '2', distanceYards: 90, outcome: 'mishit'),
        _makeEntry(id: '3', distanceYards: 200, outcome: 'good'),
      ]);
      expect(find.byKey(const Key('history-outcome-good')), findsOneWidget);
      expect(find.byKey(const Key('history-outcome-mishit')), findsOneWidget);
    });
  });

  group('filtering', () {
    testWidgets('outcome filter shrinks the list', (tester) async {
      await _pumpScreen(tester, entries: [
        _makeEntry(id: '1', distanceYards: 150, outcome: 'good'),
        _makeEntry(id: '2', distanceYards: 90, outcome: 'mishit'),
      ]);
      expect(find.text('iron7'), findsWidgets);

      // Filter to mishit only.
      await tester.tap(find.byKey(const Key('history-outcome-mishit')));
      await tester.pump();

      expect(find.textContaining('90y'), findsOneWidget);
      expect(find.textContaining('150y'), findsNothing);
    });

    testWidgets('shot type filter shrinks the list', (tester) async {
      await _pumpScreen(tester, entries: [
        _makeEntry(id: '1', distanceYards: 150, shotType: 'approach'),
        _makeEntry(id: '2', distanceYards: 30, shotType: 'chip'),
      ]);
      await tester.tap(find.byKey(const Key('history-shottype-chip')));
      await tester.pump();
      expect(find.textContaining('30y'), findsOneWidget);
      expect(find.textContaining('150y'), findsNothing);
    });

    testWidgets(
        'combining outcome + shot-type filters can yield zero results',
        (tester) async {
      // Two entries with disjoint (outcome, shotType) pairs.
      // Filter to outcome=good AND shotType=chip → entry 1 has
      // the outcome but not the type; entry 2 has the type but
      // not the outcome → zero matches.
      await _pumpScreen(tester, entries: [
        _makeEntry(id: '1', distanceYards: 150, outcome: 'good', shotType: 'approach'),
        _makeEntry(id: '2', distanceYards: 30, outcome: 'mishit', shotType: 'chip'),
      ]);
      await tester.tap(find.byKey(const Key('history-outcome-good')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('history-shottype-chip')));
      await tester.pump();
      expect(find.text('No shots match the filter'), findsOneWidget);
    });
  });

  group('detail drawer', () {
    testWidgets('tapping a tile expands its detail rows', (tester) async {
      await _pumpScreen(tester, entries: [
        _makeEntry(
          id: '1',
          distanceYards: 150,
          courseName: 'Wellshire Golf Course',
          notes: 'wind picked up at impact',
        ),
      ]);
      // Detail row should not be visible until expanded.
      expect(find.text('Course: Wellshire Golf Course'), findsNothing);

      await tester.tap(find.text('iron7'));
      await tester.pump();

      expect(find.text('Course: Wellshire Golf Course'), findsOneWidget);
      expect(find.text('wind picked up at impact'), findsOneWidget);
    });
  });

  group('scoring tab visibility', () {
    testWidgets('scoringEnabled = false → no Scorecards tab', (tester) async {
      await _pumpScreen(
        tester,
        entries: [_makeEntry(id: '1', distanceYards: 150)],
      );
      expect(find.text('Scorecards'), findsNothing);
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('scoringEnabled = true → TabBar with Shots + Scorecards',
        (tester) async {
      await _pumpScreen(
        tester,
        entries: [_makeEntry(id: '1', distanceYards: 150)],
        scoringEnabled: true,
      );
      expect(find.text('Scorecards'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('Scorecards tab empty state when no scorecards',
        (tester) async {
      await _pumpScreen(
        tester,
        entries: [_makeEntry(id: '1', distanceYards: 150)],
        scoringEnabled: true,
      );
      await tester.tap(find.text('Scorecards'));
      await tester.pumpAndSettle();
      expect(find.text('No scorecards yet'), findsOneWidget);
    });

    testWidgets('Scorecards tab renders entries with score-to-par',
        (tester) async {
      await _pumpScreen(
        tester,
        entries: [_makeEntry(id: '1', distanceYards: 150)],
        scoringEnabled: true,
        scorecards: [_makeScorecard('s1', 3)],
      );
      await tester.tap(find.text('Scorecards'));
      await tester.pumpAndSettle();
      expect(find.text('Wellshire'), findsOneWidget);
      // 18 holes × par 4 = 72; +3 on hole 1 → total 75 = +3.
      expect(find.textContaining('+3'), findsOneWidget);
    });
  });
}
