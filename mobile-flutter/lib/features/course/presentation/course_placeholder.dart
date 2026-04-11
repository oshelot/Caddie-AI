// Placeholder for the Course tab. Replaced by KAN-279 (S9 course
// search screen) for the search/list path and KAN-280 (S10 course map
// screen) for the map view. For S1 (KAN-271), this is the default
// landing tab per KAN-157's canonical naming spec.

import 'package:flutter/material.dart';

import '../../../core/icons/caddie_icons.dart';
import '../../../shell/placeholder_body.dart';

class CoursePlaceholder extends StatelessWidget {
  const CoursePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Courses')),
      body: PlaceholderBody(
        icon: CaddieIcons.course(
          size: 96,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: 'Courses',
        subtitle: 'Search nearby courses, browse details, and view the '
            'hole-by-hole satellite map with the 7-layer overlay.',
        ticket: 'KAN-279 (S9) + KAN-280 (S10)',
      ),
    );
  }
}
