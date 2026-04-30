import 'package:flutter/material.dart';

import '../../../../models/player_profile.dart';

const List<String> _teeBoxOptions = [
  'championship',
  'blue',
  'white',
  'senior',
  'forward',
];

const Map<String, String> _teeBoxLabels = {
  'championship': 'Championship',
  'blue': 'Blue',
  'white': 'White',
  'senior': 'Senior',
  'forward': 'Forward',
};

class TeeBoxPreferenceScreen extends StatefulWidget {
  final PlayerProfile profile;

  const TeeBoxPreferenceScreen({super.key, required this.profile});

  @override
  State<TeeBoxPreferenceScreen> createState() =>
      _TeeBoxPreferenceScreenState();
}

class _TeeBoxPreferenceScreenState extends State<TeeBoxPreferenceScreen> {
  late String _preferredTeeBox;

  @override
  void initState() {
    super.initState();
    _preferredTeeBox = widget.profile.preferredTeeBox;
  }

  PlayerProfile get _updatedDraft =>
      widget.profile.copyWith(preferredTeeBox: _preferredTeeBox);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _updatedDraft);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Tee Box Preference')),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _teeBoxOptions.length,
                itemBuilder: (context, index) {
                  final option = _teeBoxOptions[index];
                  return ListTile(
                    title: Text(_teeBoxLabels[option] ?? option),
                    trailing: option == _preferredTeeBox
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () => setState(() => _preferredTeeBox = option),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Your tee box preference is used to auto-select the '
                'appropriate tees when loading a course. You can always '
                'change tees for an individual round.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
