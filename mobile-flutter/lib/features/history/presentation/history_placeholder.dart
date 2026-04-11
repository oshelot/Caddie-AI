// Placeholder for the History tab. Replaced by KAN-282 (S12 history +
// scoring screen). For S1 (KAN-271), this just exists so the bottom
// nav has something to render when the user taps the tab.

import 'package:flutter/material.dart';

import '../../../core/icons/caddie_icons.dart';
import '../../../shell/placeholder_body.dart';

class HistoryPlaceholder extends StatelessWidget {
  const HistoryPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: PlaceholderBody(
        icon: CaddieIcons.history(
          size: 96,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: 'Shot History',
        subtitle: 'Past shot recommendations, the AI reasoning, and the '
            'execution outcomes you logged. Sortable by date, course, '
            'and club.',
        ticket: 'KAN-282 (S12)',
      ),
    );
  }
}
