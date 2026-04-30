// ProfileRepository — read/write the singleton PlayerProfile in the
// Hive box opened by `AppStorage`.
//
// **Single source of truth.** UI code should never reach into Hive
// directly; it goes through this repository. The repository is the
// only place that knows the profile is JSON-encoded under a single
// key — feature code just sees `load()` / `save(profile)`.
//
// **Update timestamps.** Every `save()` stamps `updatedAtMs` with
// the current epoch ms. If the profile being saved has
// `createdAtMs == 0` (i.e. it was just constructed via the default
// constructor or freshly imported from a native blob without
// metadata), `createdAtMs` is also set to "now".

import 'dart:convert';

import '../../models/player_profile.dart';
import 'app_storage.dart';

class ProfileRepository {
  /// Optional clock injection for tests. Defaults to wall-clock.
  ProfileRepository({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Returns the stored profile or `null` if no profile has been
  /// written yet (first-launch case). Callers usually use
  /// `loadOrDefault()` instead.
  PlayerProfile? load() {
    final raw = AppStorage.profileBox.get(AppStorage.profileSingletonKey);
    if (raw == null) return null;
    return PlayerProfile.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  /// Returns the stored profile or a default `PlayerProfile()` if
  /// nothing has been written yet. Use this in UI code that always
  /// needs a profile to render against.
  PlayerProfile loadOrDefault() {
    final profile = load() ?? const PlayerProfile();
    // Backfill: if an existing profile has an empty bag (saved before
    // the default bag was added), apply the defaults so the user
    // doesn't start with zero clubs.
    if (profile.clubDistances.isEmpty) {
      return profile.copyWith(
        clubDistances: const PlayerProfile().clubDistances,
        bagClubs: const PlayerProfile().bagClubs,
      );
    }
    return profile;
  }

  /// Persists the profile, stamping `updatedAtMs` (and `createdAtMs`
  /// on first write).
  Future<void> save(PlayerProfile profile) async {
    final nowMs = _clock().millisecondsSinceEpoch;
    final stamped = profile.copyWith(
      createdAtMs: profile.createdAtMs == 0 ? nowMs : profile.createdAtMs,
      updatedAtMs: nowMs,
    );
    await AppStorage.profileBox.put(
      AppStorage.profileSingletonKey,
      jsonEncode(stamped.toJson()),
    );
  }

  /// Convenience for the common "load → mutate → save" pattern.
  Future<PlayerProfile> update(
    PlayerProfile Function(PlayerProfile current) transform,
  ) async {
    final next = transform(loadOrDefault());
    await save(next);
    return next;
  }

  /// Test/debug helper — wipes the profile from the box. Production
  /// code should not call this; profile reset belongs in a future
  /// "Reset app data" settings flow with explicit confirmation UI.
  Future<void> clear() => AppStorage.profileBox.delete(
        AppStorage.profileSingletonKey,
      );
}
