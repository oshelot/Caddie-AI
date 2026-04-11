// ShotHistoryRepository — append-only log access for ShotHistoryEntry.
//
// Per **ADR 0003**, shot history is loaded into memory in full and
// filtered/queried with Dart collection ops — there is no SQL layer.
// This repository exposes:
//
//   - `loadAll()` → all entries, sorted by timestamp DESC (newest
//     first), matching the iOS native ordering
//   - `add(entry)` → write one entry (key = entry.id, so re-saving
//     the same id overwrites)
//   - `remove(id)` / `clear()` for management
//
// Filtering by club, course, shot type, etc. happens in feature
// code on the returned `List<ShotHistoryEntry>`. The repository
// deliberately does NOT expose query methods — adding them would
// invite the kind of "we need an index for that" pressure that
// ADR 0003 declined to take on.

import 'dart:convert';

import '../../models/shot_history_entry.dart';
import 'app_storage.dart';

class ShotHistoryRepository {
  /// Returns every entry in the box, sorted descending by
  /// `timestampMs` (newest first). Cost is O(n log n) on the entry
  /// count; for the working set sizes ADR 0003 anticipates (a few
  /// hundred entries even for active players) this is well under a
  /// millisecond.
  List<ShotHistoryEntry> loadAll() {
    final box = AppStorage.shotHistoryBox;
    final entries = <ShotHistoryEntry>[];
    for (final raw in box.values) {
      entries.add(
        ShotHistoryEntry.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        ),
      );
    }
    entries.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
    return entries;
  }

  /// Adds or replaces an entry. Hive's `put` is upsert, so re-saving
  /// an entry with the same id overwrites in place.
  Future<void> add(ShotHistoryEntry entry) {
    return AppStorage.shotHistoryBox.put(
      entry.id,
      jsonEncode(entry.toJson()),
    );
  }

  /// Bulk insert. Used by the migration importer to write a batch
  /// of native-history entries in one shot. `Hive.putAll` is one
  /// disk write per entry under the hood, but the writes are
  /// batched into a single transaction.
  Future<void> addAll(Iterable<ShotHistoryEntry> entries) {
    return AppStorage.shotHistoryBox.putAll({
      for (final e in entries) e.id: jsonEncode(e.toJson()),
    });
  }

  Future<void> remove(String id) =>
      AppStorage.shotHistoryBox.delete(id);

  Future<void> clear() => AppStorage.shotHistoryBox.clear();

  int get count => AppStorage.shotHistoryBox.length;
}
