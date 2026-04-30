// Placeholder for the Caddie tab. Replaced by KAN-281 (S11 caddie
// shot input + AI chat screen). For S1 (KAN-271), this just exists so
// the bottom nav has something to render when the user taps the tab.

import 'package:flutter/material.dart';

import '../../../core/icons/caddie_icons.dart';
import '../../../shell/placeholder_body.dart';

class CaddiePlaceholder extends StatelessWidget {
  const CaddiePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Caddie')),
      body: PlaceholderBody(
        icon: CaddieIcons.golfer(
          size: 96,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: 'Caddie',
        subtitle: 'AI shot advisor — voice input, distance / lie / wind, '
            'and a streaming recommendation.',
        ticket: 'KAN-281 (S11)',
      ),
    );
  }
}
