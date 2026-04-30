// Shared body widget used by the four S1 placeholder screens
// (CaddiePlaceholder, CoursePlaceholder, HistoryPlaceholder,
// ProfilePlaceholder). Each placeholder shows a hero icon, the
// canonical screen title (per the KAN-157 naming spec referenced from
// closed-as-WontDo KAN-157), a one-line description of what the real
// screen does, and a "Coming in KAN-XXX" pill.
//
// Throwaway widget — when KAN-281 (caddie), KAN-279 (course),
// KAN-282 (history), KAN-283 (profile) ship, the corresponding
// placeholder screen + this widget should both go away.

import 'package:flutter/material.dart';

class PlaceholderBody extends StatelessWidget {
  const PlaceholderBody({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ticket,
  });

  /// A `CaddieIcons.foo(size: 96, color: ...)` widget. Caller picks
  /// the right icon for the screen.
  final Widget icon;

  /// Canonical screen title from KAN-157's spec.
  final String title;

  /// One sentence describing what the real screen will do.
  final String subtitle;

  /// "KAN-XXX (Sn)" — the ticket that will replace this placeholder.
  final String ticket;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Coming in $ticket',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
