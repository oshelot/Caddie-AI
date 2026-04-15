// Course picker dialog — shown when a multi-course facility is
// detected via the Golf Course API. Lets the user choose 1 or 2
// nine-hole courses to combine for their round.

import 'package:flutter/material.dart';

import '../../../core/courses/course_matcher.dart';

/// Shows a dialog for multi-course facilities. The user picks 1 or 2
/// of the available courses. Returns the selected [ExtractedCourse]s,
/// or null if dismissed.
Future<List<ExtractedCourse>?> showCoursePickerDialog({
  required BuildContext context,
  required List<ExtractedCourse> courses,
}) {
  return showDialog<List<ExtractedCourse>>(
    context: context,
    builder: (ctx) => _CoursePickerDialog(courses: courses),
  );
}

class _CoursePickerDialog extends StatefulWidget {
  const _CoursePickerDialog({required this.courses});
  final List<ExtractedCourse> courses;

  @override
  State<_CoursePickerDialog> createState() => _CoursePickerDialogState();
}

class _CoursePickerDialogState extends State<_CoursePickerDialog> {
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Multiple Courses Found'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This facility has ${widget.courses.length} courses. '
            'Pick 1 or 2 for your round.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < widget.courses.length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selected.contains(i),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    if (_selected.length < 2) _selected.add(i);
                  } else {
                    _selected.remove(i);
                  }
                });
              },
              secondary: const Icon(Icons.golf_course),
              title: Text(widget.courses[i].name),
              subtitle: Text(
                '${widget.courses[i].pars.length} holes \u2022 '
                'Par ${widget.courses[i].pars.fold<int>(0, (s, p) => s + p)}',
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final picks = _selected
                      .map((i) => widget.courses[i])
                      .toList();
                  Navigator.pop(context, picks);
                },
          child: Text(_selected.length == 2 ? 'Play 18' : 'Play 9'),
        ),
      ],
    );
  }
}
