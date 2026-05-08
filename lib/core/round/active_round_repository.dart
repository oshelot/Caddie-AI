// ActiveRoundRepository — KAN-382 — Hive-backed persistence for
// the singleton active round.
//
// **Single source of truth.** UI code goes through
// ActiveRoundController, which delegates here. Direct Hive reads
// from feature code are forbidden (mirrors ProfileRepository).
//
// Storage shape: one Box&lt;String&gt; (`AppStorage.activeRoundBox`),
// one key (`AppStorage.activeRoundSingletonKey = 'current'`),
// JSON-encoded ActiveRound payload.

import '../storage/app_storage.dart';
import 'active_round.dart';

class ActiveRoundRepository {
  /// Returns the persisted active round, or null if none.
  ActiveRound? load() {
    final raw = AppStorage.activeRoundBox.get(
      AppStorage.activeRoundSingletonKey,
    );
    if (raw == null) return null;
    try {
      return ActiveRound.decode(raw);
    } catch (_) {
      // Corrupt or schema-incompatible payload — treat as no round.
      // The caller can choose to clear() to recover; we don't do it
      // here so a developer can inspect the bad payload if needed.
      return null;
    }
  }

  Future<void> save(ActiveRound round) async {
    await AppStorage.activeRoundBox.put(
      AppStorage.activeRoundSingletonKey,
      round.encode(),
    );
  }

  Future<void> clear() async {
    await AppStorage.activeRoundBox.delete(
      AppStorage.activeRoundSingletonKey,
    );
  }
}
