// Course picker dialog — shown when a multi-course facility is
// detected (e.g., Terra Lago North/South). Lets the user choose
// which course to load on the map.

import 'package:flutter/material.dart';

import '../../../models/normalized_course.dart';

/// Shows a dialog with one row per course. Returns the selected
/// course, or null if the user dismisses.
Future<NormalizedCourse?> showCoursePickerDialog({
  required BuildContext context,
  required List<NormalizedCourse> courses,
}) {
  return showDialog<NormalizedCourse>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Multiple Courses Found'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'This facility has ${courses.length} courses. '
            'Which one are you playing?',
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(ctx).colorScheme.outline,
                ),
          ),
        ),
        const SizedBox(height: 8),
        for (final course in courses)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, course),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.golf_course),
              title: Text(course.name),
              subtitle: Text(
                '${course.holes.length} holes \u2022 '
                'Par ${course.holes.fold<int>(0, (s, h) => s + h.par)}',
              ),
            ),
          ),
      ],
    ),
  );
}
