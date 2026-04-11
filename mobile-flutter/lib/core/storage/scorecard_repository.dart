// ScorecardRepository — read/write scorecards in the Hive box
// opened by `AppStorage`.
//
// Same shape as ShotHistoryRepository — keyed by `id`, JSON-encoded
// values, no SQL. Adds two helpers feature code will need:
// `activeScorecard` (the in-progress one, if any) and
// `completedScorecards` (sorted newest first).

import 'dart:convert';

import '../../models/scorecard_entry.dart';
import 'app_storage.dart';

class ScorecardRepository {
  static const String _statusInProgress = 'inProgress';
  static const String _statusCompleted = 'completed';

  List<ScorecardEntry> loadAll() {
    final entries = <ScorecardEntry>[];
    for (final raw in AppStorage.scorecardBox.values) {
      entries.add(
        ScorecardEntry.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        ),
      );
    }
    entries.sort((a, b) => b.dateMs.compareTo(a.dateMs));
    return entries;
  }

  /// The single in-progress scorecard, if one exists. Mirrors the
  /// iOS `ScorecardStore.activeScorecard` getter. Returns null if
  /// the player isn't currently playing a round.
  ScorecardEntry? get activeScorecard {
    for (final entry in loadAll()) {
      if (entry.status == _statusInProgress) return entry;
    }
    return null;
  }

  /// Completed scorecards sorted newest-first. Used by the History
  /// tab's scorecard list.
  List<ScorecardEntry> get completedScorecards =>
      loadAll().where((e) => e.status == _statusCompleted).toList();

  Future<void> save(ScorecardEntry scorecard) {
    return AppStorage.scorecardBox.put(
      scorecard.id,
      jsonEncode(scorecard.toJson()),
    );
  }

  Future<void> saveAll(Iterable<ScorecardEntry> scorecards) {
    return AppStorage.scorecardBox.putAll({
      for (final s in scorecards) s.id: jsonEncode(s.toJson()),
    });
  }

  Future<void> remove(String id) => AppStorage.scorecardBox.delete(id);

  Future<void> clear() => AppStorage.scorecardBox.clear();
}
