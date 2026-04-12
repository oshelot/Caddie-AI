// HistoryScreen — KAN-282 (S12). The History tab. Renders the
// player's shot history list with filter chips for outcome and
// shot type, plus a tap-to-detail drawer that shows the AI
// reasoning + execution outcome for each shot.
//
// **Scoring tab visibility** is gated on `scoringEnabled` from
// the player profile (per the AC + the iOS native's design). When
// false, the screen is a single tab (Shots). When true, a
// TabBar appears with Shots + Scorecards.
//
// **Architecture: pure widget with constructor injection.** The
// screen takes:
//   - `entries`: pre-loaded `List<ShotHistoryEntry>` (the page
//     wrapper loads from `ShotHistoryRepository` and passes them
//     in)
//   - `scorecards`: pre-loaded `List<ScorecardEntry>` (or empty
//     when scoring is disabled)
//   - `scoringEnabled`: from `PlayerProfile.scoringEnabled`
//   - `onRefresh`: optional pull-to-refresh callback
//
// The page wrapper does the I/O; the leaf widget is a pure
// renderer + filter state.

import 'package:flutter/material.dart';

import '../../../core/icons/caddie_icons.dart';
import '../../../models/scorecard_entry.dart';
import '../../../models/shot_history_entry.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.entries,
    this.scorecards = const [],
    this.scoringEnabled = false,
    this.onRefresh,
  });

  final List<ShotHistoryEntry> entries;
  final List<ScorecardEntry> scorecards;
  final bool scoringEnabled;
  final Future<void> Function()? onRefresh;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _outcomeFilter;
  String? _shotTypeFilter;
  ShotHistoryEntry? _expandedEntry;

  /// All distinct outcome values present in the entries — used to
  /// build the filter chip set without hard-coding the enum.
  Set<String> get _allOutcomes =>
      widget.entries.map((e) => e.outcome).toSet();

  Set<String> get _allShotTypes =>
      widget.entries.map((e) => e.context.shotType).toSet();

  List<ShotHistoryEntry> get _filteredEntries {
    return widget.entries.where((e) {
      if (_outcomeFilter != null && e.outcome != _outcomeFilter) {
        return false;
      }
      if (_shotTypeFilter != null && e.context.shotType != _shotTypeFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.scoringEnabled) {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('History'),
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: CaddieIcons.history(
                size: 24,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Shots'),
                Tab(text: 'Scorecards'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _buildShotsTab(context),
              _buildScorecardsTab(context),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: CaddieIcons.history(
            size: 24,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      body: _buildShotsTab(context),
    );
  }

  Widget _buildShotsTab(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const _EmptyState(
        icon: Icons.golf_course,
        title: 'No shots yet',
        message:
            'Your shot history will appear here once you start using the '
            'caddie screen during a round.',
      );
    }

    final filtered = _filteredEntries;
    return Column(
      children: [
        _FilterBar(
          allOutcomes: _allOutcomes,
          allShotTypes: _allShotTypes,
          selectedOutcome: _outcomeFilter,
          selectedShotType: _shotTypeFilter,
          onOutcomeChanged: (v) => setState(() => _outcomeFilter = v),
          onShotTypeChanged: (v) => setState(() => _shotTypeFilter = v),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const _EmptyState(
                  icon: Icons.filter_alt_off,
                  title: 'No shots match the filter',
                  message: 'Clear a filter chip to see your full history.',
                )
              : RefreshIndicator(
                  onRefresh: widget.onRefresh ?? () async {},
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final entry = filtered[i];
                      final isExpanded = entry == _expandedEntry;
                      return _ShotTile(
                        entry: entry,
                        expanded: isExpanded,
                        onTap: () => setState(() {
                          _expandedEntry = isExpanded ? null : entry;
                        }),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildScorecardsTab(BuildContext context) {
    if (widget.scorecards.isEmpty) {
      return const _EmptyState(
        icon: Icons.scoreboard_outlined,
        title: 'No scorecards yet',
        message:
            'Completed rounds with scoring enabled will appear here. '
            'Start a round from the Course tab to track scores.',
      );
    }
    return ListView.separated(
      itemCount: widget.scorecards.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final card = widget.scorecards[i];
        return ListTile(
          leading: const Icon(Icons.scoreboard_outlined),
          title: Text(card.courseName.isNotEmpty
              ? card.courseName
              : 'Round ${i + 1}'),
          subtitle: Text(
            '${card.holeScores.length} holes • '
            '${card.totalScore} (${card.relativeToPar >= 0 ? '+' : ''}${card.relativeToPar})',
          ),
          trailing: Text(card.status),
        );
      },
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.allOutcomes,
    required this.allShotTypes,
    required this.selectedOutcome,
    required this.selectedShotType,
    required this.onOutcomeChanged,
    required this.onShotTypeChanged,
  });

  final Set<String> allOutcomes;
  final Set<String> allShotTypes;
  final String? selectedOutcome;
  final String? selectedShotType;
  final ValueChanged<String?> onOutcomeChanged;
  final ValueChanged<String?> onShotTypeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Outcome', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              FilterChip(
                key: const Key('history-outcome-all'),
                label: const Text('All'),
                selected: selectedOutcome == null,
                onSelected: (_) => onOutcomeChanged(null),
              ),
              ...allOutcomes.map((o) => FilterChip(
                    key: Key('history-outcome-$o'),
                    label: Text(o),
                    selected: selectedOutcome == o,
                    onSelected: (s) => onOutcomeChanged(s ? o : null),
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Text('Shot type', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              FilterChip(
                key: const Key('history-shottype-all'),
                label: const Text('All'),
                selected: selectedShotType == null,
                onSelected: (_) => onShotTypeChanged(null),
              ),
              ...allShotTypes.map((t) => FilterChip(
                    key: Key('history-shottype-$t'),
                    label: Text(t),
                    selected: selectedShotType == t,
                    onSelected: (s) => onShotTypeChanged(s ? t : null),
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShotTile extends StatelessWidget {
  const _ShotTile({
    required this.entry,
    required this.expanded,
    required this.onTap,
  });

  final ShotHistoryEntry entry;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.fromMillisecondsSinceEpoch(entry.timestampMs);
    final dateLabel =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  entry.recommendedClub.isEmpty
                      ? '(no club)'
                      : entry.recommendedClub,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.context.distanceYards}y',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                Chip(
                  label: Text(entry.outcome),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
              '$dateLabel • ${entry.context.shotType} • ${entry.context.lieType}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              if (entry.courseName.isNotEmpty)
                Text('Course: ${entry.courseName}',
                    style: theme.textTheme.bodySmall),
              Text('Wind: ${entry.context.windStrength} ${entry.context.windDirection}',
                  style: theme.textTheme.bodySmall),
              Text('Slope: ${entry.context.slope}',
                  style: theme.textTheme.bodySmall),
              if (entry.context.hazardNotes.isNotEmpty)
                Text('Hazards: ${entry.context.hazardNotes}',
                    style: theme.textTheme.bodySmall),
              if (entry.actualClubUsed != null)
                Text('Actually used: ${entry.actualClubUsed}',
                    style: theme.textTheme.bodySmall),
              if (entry.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Notes', style: theme.textTheme.bodySmall),
                Text(entry.notes, style: theme.textTheme.bodyMedium),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
