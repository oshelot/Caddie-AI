import 'package:flutter/material.dart';

import '../../../../models/player_profile.dart';

class SwingInfoScreen extends StatefulWidget {
  final PlayerProfile profile;

  const SwingInfoScreen({super.key, required this.profile});

  @override
  State<SwingInfoScreen> createState() => _SwingInfoScreenState();
}

class _SwingInfoScreenState extends State<SwingInfoScreen> {
  late String _woodsShape;
  late String _ironsShape;
  late String _hybridsShape;
  late String _missTendency;
  late String _bunkerConfidence;
  late String _wedgeConfidence;
  late String _chipStyle;
  late String _swingTendency;

  @override
  void initState() {
    super.initState();
    _woodsShape = widget.profile.woodsStockShape;
    _ironsShape = widget.profile.ironsStockShape;
    _hybridsShape = widget.profile.hybridsStockShape;
    _missTendency = widget.profile.missTendency;
    _bunkerConfidence = widget.profile.bunkerConfidence;
    _wedgeConfidence = widget.profile.wedgeConfidence;
    _chipStyle = widget.profile.chipStyle;
    _swingTendency = widget.profile.swingTendency;
  }

  PlayerProfile get _updatedDraft => widget.profile.copyWith(
        woodsStockShape: _woodsShape,
        ironsStockShape: _ironsShape,
        hybridsStockShape: _hybridsShape,
        missTendency: _missTendency,
        bunkerConfidence: _bunkerConfidence,
        wedgeConfidence: _wedgeConfidence,
        chipStyle: _chipStyle,
        swingTendency: _swingTendency,
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _updatedDraft);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Swing Info')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ProfileCard(
              title: 'Shot Shape',
              child: Column(
                children: [
                  _dropdown('Woods', _woodsShape, ['straight', 'fade', 'draw'],
                      (v) => setState(() => _woodsShape = v!)),
                  const SizedBox(height: 12),
                  _dropdown('Irons', _ironsShape, ['straight', 'fade', 'draw'],
                      (v) => setState(() => _ironsShape = v!)),
                  const SizedBox(height: 12),
                  _dropdown('Hybrids', _hybridsShape,
                      ['straight', 'fade', 'draw'],
                      (v) => setState(() => _hybridsShape = v!)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ProfileCard(
              title: 'Tendencies',
              child: Column(
                children: [
                  _dropdown('Miss Tendency', _missTendency,
                      ['none', 'left', 'right', 'thin', 'fat'],
                      (v) => setState(() => _missTendency = v!)),
                  const SizedBox(height: 12),
                  _dropdown('Bunker Confidence', _bunkerConfidence,
                      ['low', 'average', 'high'],
                      (v) => setState(() => _bunkerConfidence = v!)),
                  const SizedBox(height: 12),
                  _dropdown('Wedge Confidence', _wedgeConfidence,
                      ['low', 'average', 'high'],
                      (v) => setState(() => _wedgeConfidence = v!)),
                  const SizedBox(height: 12),
                  _dropdown('Preferred Chip Style', _chipStyle,
                      ['bumpAndRun', 'lofted', 'noPreference'],
                      (v) => setState(() => _chipStyle = v!)),
                  const SizedBox(height: 12),
                  _dropdown('Swing Tendency', _swingTendency,
                      ['steep', 'shallow', 'neutral'],
                      (v) => setState(() => _swingTendency = v!)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> items,
      ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ProfileCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
