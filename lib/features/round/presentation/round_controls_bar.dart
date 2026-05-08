// RoundControlsBar — KAN-382 — the in-round overlay docked on
// the course map.
//
// Three states:
//
//   1. No active round: shows a "Start Round" button. Tap → calls
//      onStartRound. The course map screen wires that to
//      `activeRoundController.startRound(...)` with the displayed
//      course's identity.
//
//   2. Active round on THIS course: shows the current hole +
//      Prev / Next / End buttons. Hole position drives the map's
//      flyTo via `onHoleChanged` (the course map's existing
//      `_selectHole` callback).
//
//   3. Active round on a DIFFERENT course: shows a banner — "Round
//      in progress at &lt;other course&gt;" — with a Resume action that
//      navigates to the other course, and an End action that
//      clears the round so the user can start a new one here.
//      (Resume nav is a future hook; today the user manually
//      navigates back; End is the loaded-bearing action.)
//
// The bar is intentionally compact — it sits above the existing
// hole picker / Ask Caddie / Analyze controls and shouldn't
// dominate the map. Visual style mirrors the existing surfaces in
// the course map (Material 3 elevated card, theme-aware colors).

import 'package:flutter/material.dart';

import '../../../core/round/active_round.dart';

class RoundControlsBar extends StatelessWidget {
  const RoundControlsBar({
    super.key,
    required this.round,
    required this.courseId,
    required this.courseName,
    required this.totalHoles,
    required this.onStartRound,
    required this.onHoleChanged,
    required this.onEndRound,
  });

  /// Current ActiveRound from the controller, or null when no
  /// round is active.
  final ActiveRound? round;

  /// Identity of the course currently displayed on the map.
  /// `round.courseId == courseId` decides whether the bar is in
  /// "this course" or "different course" mode.
  final String courseId;
  final String courseName;
  final int totalHoles;

  /// Tapped when no round is active. The caller hydrates the
  /// controller with the displayed course's identity.
  final VoidCallback onStartRound;

  /// Tapped when the user advances/rewinds the hole. Receives the
  /// new 1-based hole number. The caller wires this through to the
  /// existing `_selectHole(int?)` so the map flies to the hole.
  final ValueChanged<int> onHoleChanged;

  /// Tapped when the user concludes (or abandons) the round.
  final VoidCallback onEndRound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = round;

    if (r == null) {
      return _StartRoundCta(
        onStartRound: onStartRound,
        courseName: courseName,
      );
    }

    if (r.courseId != courseId) {
      return _OtherCourseBanner(
        otherCourseName: r.courseName,
        currentHole: r.currentHoleNumber,
        totalHoles: r.totalHoles,
        onEndRound: onEndRound,
      );
    }

    // Active round on this course — main control surface.
    final atFirst = r.currentHoleNumber <= 1;
    final atLast = r.currentHoleNumber >= r.totalHoles;

    return Material(
      color: theme.colorScheme.primaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.golf_course,
                        size: 20, color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Hole ${r.currentHoleNumber} of ${r.totalHoles}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Previous hole',
                icon: const Icon(Icons.chevron_left),
                color: theme.colorScheme.onPrimaryContainer,
                onPressed: atFirst
                    ? null
                    : () => onHoleChanged(r.currentHoleNumber - 1),
              ),
              IconButton(
                tooltip: 'Next hole',
                icon: const Icon(Icons.chevron_right),
                color: theme.colorScheme.onPrimaryContainer,
                onPressed: atLast
                    ? null
                    : () => onHoleChanged(r.currentHoleNumber + 1),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                ),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('End'),
                onPressed: () => _confirmEnd(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End round?'),
        content: Text(
          'You\'re on hole ${round!.currentHoleNumber} of ${round!.totalHoles}. '
          'Ending the round clears the saved progress.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End round'),
          ),
        ],
      ),
    );
    if (ok == true) onEndRound();
  }
}

class _StartRoundCta extends StatelessWidget {
  const _StartRoundCta({
    required this.onStartRound,
    required this.courseName,
  });

  final VoidCallback onStartRound;
  final String courseName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.play_circle_outline,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ready to play?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onStartRound,
                icon: const Icon(Icons.flag, size: 18),
                label: const Text('Start round'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtherCourseBanner extends StatelessWidget {
  const _OtherCourseBanner({
    required this.otherCourseName,
    required this.currentHole,
    required this.totalHoles,
    required this.onEndRound,
  });

  final String otherCourseName;
  final int currentHole;
  final int totalHoles;
  final VoidCallback onEndRound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 20, color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Round in progress at $otherCourseName · hole $currentHole/$totalHoles',
                  style: TextStyle(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onTertiaryContainer,
                ),
                onPressed: onEndRound,
                child: const Text('End'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
