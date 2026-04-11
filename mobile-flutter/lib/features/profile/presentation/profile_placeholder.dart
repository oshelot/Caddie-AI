// Placeholder for the Profile tab. Replaced by KAN-283 (S13 profile +
// settings + API configuration screen). For S1 (KAN-271), this just
// exists so the bottom nav has something to render when the user taps
// the tab.

import 'package:flutter/material.dart';

import '../../../core/icons/caddie_icons.dart';
import '../../../shell/placeholder_body.dart';

class ProfilePlaceholder extends StatelessWidget {
  const ProfilePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: PlaceholderBody(
        icon: CaddieIcons.profile(
          size: 96,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: 'Profile',
        subtitle: 'Player handicap, club distances, caddie voice, '
            'feature flags, and LLM provider settings.',
        ticket: 'KAN-283 (S13)',
      ),
    );
  }
}
