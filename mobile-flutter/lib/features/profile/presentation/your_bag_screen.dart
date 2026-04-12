import 'package:flutter/material.dart';

import '../../../../models/player_profile.dart';

/// All clubs that can appear in a bag, with their default carry yards.
const Map<String, int> _allClubDefaults = {
  'Driver': 230,
  '3-Wood': 210,
  '5-Wood': 195,
  '7-Wood': 180,
  '2-Iron': 190,
  '3-Iron': 180,
  '4-Iron': 170,
  '5-Iron': 160,
  '6-Iron': 150,
  '7-Iron': 140,
  '8-Iron': 130,
  '9-Iron': 120,
  'PW': 110,
  'GW': 100,
  'SW': 90,
  'LW': 70,
  'Putter': 0,
};

const int _maxClubs = 13;

class YourBagScreen extends StatefulWidget {
  final PlayerProfile profile;

  const YourBagScreen({super.key, required this.profile});

  @override
  State<YourBagScreen> createState() => _YourBagScreenState();
}

class _YourBagScreenState extends State<YourBagScreen> {
  late Map<String, int> _clubDistances;
  late String? _ironType;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _clubDistances = Map.of(widget.profile.clubDistances);
    _ironType = widget.profile.ironType;
    for (final entry in _clubDistances.entries) {
      _controllers[entry.key] = TextEditingController(text: '${entry.value}');
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  PlayerProfile get _updatedDraft => widget.profile.copyWith(
        clubDistances: Map.unmodifiable(_clubDistances),
        ironType: _ironType,
      );

  List<MapEntry<String, int>> get _sortedClubs {
    final entries = _clubDistances.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  List<String> get _availableClubs =>
      _allClubDefaults.keys.where((c) => !_clubDistances.containsKey(c)).toList();

  void _addClub(String club) {
    setState(() {
      _clubDistances[club] = _allClubDefaults[club]!;
      _controllers[club] = TextEditingController(text: '${_clubDistances[club]}');
    });
  }

  void _removeClub(String club) {
    setState(() {
      _clubDistances.remove(club);
      _controllers.remove(club)?.dispose();
    });
  }

  void _showAddClubSheet() {
    final available = _availableClubs;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: available.length,
          itemBuilder: (_, i) {
            final club = available[i];
            return ListTile(
              title: Text(club),
              trailing: Text('${_allClubDefaults[club]} yds',
                  style: const TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(ctx);
                _addClub(club);
              },
            );
          },
        ),
      ),
    );
  }

  void _showIronTypeDialog() {
    showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Iron Type'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'gameImprovement'),
            child: const Text('Game Improvement'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'superGameImprovement'),
            child: const Text('Super Game Improvement'),
          ),
        ],
      ),
    ).then((value) {
      if (value != null) {
        setState(() => _ironType = value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = _sortedClubs;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _updatedDraft);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Your Bag')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Clubs section ──────────────────────────────────────
            _ProfileCard(
              title: 'Clubs (${sorted.length}/$_maxClubs)',
              child: Column(
                children: [
                  for (final entry in sorted)
                    Dismissible(
                      key: ValueKey(entry.key),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        color: Colors.red,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _removeClub(entry.key),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(entry.key)),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: _controllers[entry.key],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.end,
                                decoration: const InputDecoration(
                                  suffixText: 'yds',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (v) {
                                  final yards = int.tryParse(v);
                                  if (yards != null) {
                                    _clubDistances[entry.key] = yards;
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (sorted.length < _maxClubs)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton.icon(
                        onPressed: _showAddClubSheet,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Club'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── Iron type section ──────────────────────────────────
            _ProfileCard(
              title: 'Iron Type',
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Game Improvement Irons'),
                    value: _ironType != null,
                    onChanged: (on) {
                      if (on) {
                        _showIronTypeDialog();
                      } else {
                        setState(() => _ironType = null);
                      }
                    },
                  ),
                  if (_ironType != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Text(
                        _ironType == 'superGameImprovement'
                            ? 'Super Game Improvement'
                            : 'Game Improvement',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
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
