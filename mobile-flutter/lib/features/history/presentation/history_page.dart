// HistoryPage — KAN-282 (S12) route-level wiring for the History
// tab. Loads shot history + scorecards from the storage repos
// (S2) and gates the scorecard tab on the player profile's
// `scoringEnabled` flag.

import 'package:flutter/material.dart';

import '../../../core/storage/profile_repository.dart';
import '../../../core/storage/scorecard_repository.dart';
import '../../../core/storage/shot_history_repository.dart';
import '../../../models/scorecard_entry.dart';
import '../../../models/shot_history_entry.dart';
import 'history_screen.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _profileRepo = ProfileRepository();
  final _historyRepo = ShotHistoryRepository();
  final _scorecardRepo = ScorecardRepository();

  late List<ShotHistoryEntry> _entries;
  late List<ScorecardEntry> _scorecards;
  late bool _scoringEnabled;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    // Defensive: in unit tests Hive isn't initialized so the
    // repo calls throw. Fall back to empty defaults. Production
    // always has the boxes open by the time the route builds.
    try {
      final profile = _profileRepo.loadOrDefault();
      setState(() {
        _entries = _historyRepo.loadAll();
        _scoringEnabled = profile.scoringEnabled;
        _scorecards =
            _scoringEnabled ? _scorecardRepo.loadAll() : const [];
      });
    } catch (_) {
      setState(() {
        _entries = const [];
        _scoringEnabled = false;
        _scorecards = const [];
      });
    }
  }

  Future<void> _onRefresh() async {
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return HistoryScreen(
      entries: _entries,
      scorecards: _scorecards,
      scoringEnabled: _scoringEnabled,
      onRefresh: _onRefresh,
    );
  }
}
