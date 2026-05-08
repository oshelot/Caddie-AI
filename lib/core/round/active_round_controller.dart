// ActiveRoundController — KAN-382 — top-level ValueNotifier
// holding the current ActiveRound (or null if no round is active).
//
// Mirrors the ThemeController pattern in `lib/core/theme/`: a
// process-global singleton constructed once in `main()` and
// listened to by feature widgets via `ValueListenableBuilder`.
//
// **Persistence contract:** every mutation persists to Hive
// before notifying listeners, so a backgrounded app that's killed
// by the OS between mutations never loses state. Reads on
// startup go through `hydrate()` (called from `main()` after
// AppStorage.init).
//
// **Foreground restore:** `hydrate()` is also called when the app
// comes back to foreground. The Hive box is the source of truth
// — if the user resumed onto a different process, the in-memory
// value is replaced with whatever Hive has.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'active_round.dart';
import 'active_round_repository.dart';

class ActiveRoundController extends ValueNotifier<ActiveRound?> {
  ActiveRoundController({
    ActiveRoundRepository? repository,
    DateTime Function()? clock,
  })  : _repository = repository ?? ActiveRoundRepository(),
        _clock = clock ?? DateTime.now,
        super(null);

  final ActiveRoundRepository _repository;
  final DateTime Function() _clock;

  /// True if a round is in flight.
  bool get isActive => value != null;

  /// Read the persisted round into memory. Idempotent and safe to
  /// call multiple times (e.g. on every foreground transition).
  Future<void> hydrate() async {
    final loaded = _repository.load();
    if (!_roundsEqual(loaded, value)) {
      value = loaded;
    }
  }

  /// Begin a new round. Overwrites any existing in-memory round
  /// and any persisted round — the singleton constraint means we
  /// only track one round at a time. UI callers that want to warn
  /// the user before clobbering should check `isActive` first.
  Future<void> startRound({
    required String courseId,
    required String courseName,
    required int totalHoles,
    int currentHoleNumber = 1,
    String? subCourseSlug,
    String? city,
    String? state,
  }) async {
    final round = ActiveRound(
      courseId: courseId,
      courseName: courseName,
      subCourseSlug: subCourseSlug,
      city: city,
      state: state,
      totalHoles: totalHoles,
      currentHoleNumber: currentHoleNumber,
      startedAtMs: _clock().millisecondsSinceEpoch,
    );
    await _repository.save(round);
    value = round;
  }

  /// Manual hole advance. Caps at totalHoles — pressing Next on
  /// hole 18 of an 18-hole course is a no-op (the user should
  /// End Round instead).
  Future<void> nextHole() async {
    final r = value;
    if (r == null) return;
    if (r.currentHoleNumber >= r.totalHoles) return;
    final updated = r.copyWith(currentHoleNumber: r.currentHoleNumber + 1);
    await _repository.save(updated);
    value = updated;
  }

  /// Manual hole rewind. Floor at 1.
  Future<void> previousHole() async {
    final r = value;
    if (r == null) return;
    if (r.currentHoleNumber <= 1) return;
    final updated = r.copyWith(currentHoleNumber: r.currentHoleNumber - 1);
    await _repository.save(updated);
    value = updated;
  }

  /// Jump to an arbitrary hole (clamped to [1, totalHoles]). Used
  /// by the hole-picker chip strip on the course screen.
  Future<void> jumpToHole(int holeNumber) async {
    final r = value;
    if (r == null) return;
    final clamped = holeNumber.clamp(1, r.totalHoles);
    if (clamped == r.currentHoleNumber) return;
    final updated = r.copyWith(currentHoleNumber: clamped);
    await _repository.save(updated);
    value = updated;
  }

  /// Conclude the round. Clears Hive + memory. Future post-round
  /// summary (KAN-382 P1) will read from this controller before
  /// it clears, so UI calling endRound should pump the summary
  /// surface first.
  Future<void> endRound() async {
    await _repository.clear();
    value = null;
  }

  static bool _roundsEqual(ActiveRound? a, ActiveRound? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.courseId == b.courseId &&
        a.subCourseSlug == b.subCourseSlug &&
        a.totalHoles == b.totalHoles &&
        a.currentHoleNumber == b.currentHoleNumber &&
        a.startedAtMs == b.startedAtMs;
  }
}

/// Process-global singleton. Initialized empty and hydrated by
/// `main()` after `AppStorage.init`. Feature code consumes this
/// via `ValueListenableBuilder<ActiveRound?>(valueListenable:
/// activeRoundController, ...)`.
final ActiveRoundController activeRoundController = ActiveRoundController();
