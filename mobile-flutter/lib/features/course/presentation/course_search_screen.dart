// CourseSearchScreen — KAN-279 (S9). The new default content of the
// Course tab. Replaces the direct-to-map experience that
// `CoursePlaceholder` provided in S10.
//
// **What this screen does:**
//   1. Renders a search input that debounces user typing
//      (default 350 ms — well under the 1 s AC target).
//   2. On debounce fire, calls a caller-supplied
//      `Future<CourseSearchResults> Function(String query)`
//      callback. The route widget wires this to
//      `CourseCacheClient.searchManifest` (KAN-S5) in production
//      and to a fake list in tests.
//   3. Renders the result list with name + city/state subtitle.
//      Tapping a result invokes `onSelectCourse` — the route
//      widget handles fetching the full `NormalizedCourse` and
//      navigating to the map.
//   4. Renders distinct empty states for "no results", "location
//      required" (when the user toggles nearby search but
//      permission isn't granted), and "ready to search" (the
//      initial idle state).
//   5. Logs `log_search_latency` to `LoggingService` on every
//      completed search with `latencyMs` + `query` length +
//      `resultCount` + `hasLocation` metadata. This is the C-3
//      measurement contract — the actual ≤ 1 s target is verified
//      by the production CloudWatch dashboard.
//
// **Why a callback for `onSearch` instead of taking a
// `CourseCacheClient` directly:** the widget tests need to drive
// scripted result sequences (empty, populated, error) without
// standing up a fake HTTP transport. Production wires the
// callback to the real client at the route level.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/courses/course_search_results.dart';
import '../../../core/icons/caddie_icons.dart';
import '../../../core/logging/log_event.dart';
import '../../../core/logging/logging_service.dart';

/// Result of one search call. The screen never sees a raw
/// `Future<List>` — it always sees this typed wrapper so the
/// "error" state is distinct from the "no results" state.
class CourseSearchOutcome {
  const CourseSearchOutcome({
    required this.entries,
    this.error,
  });

  final List<CourseSearchEntry> entries;
  final String? error;

  bool get hasError => error != null;
  bool get isEmpty => entries.isEmpty;

  static const CourseSearchOutcome empty =
      CourseSearchOutcome(entries: []);
}

class CourseSearchScreen extends StatefulWidget {
  const CourseSearchScreen({
    super.key,
    required this.onSearch,
    required this.onSelectCourse,
    required this.logger,
    this.locationGranted = false,
    this.debounce = const Duration(milliseconds: 350),
    this.initialDemoEntry,
  });

  /// Called once per debounced search. Gets the trimmed query
  /// (never empty — the screen short-circuits before calling).
  /// Returns a `CourseSearchOutcome` so callers can distinguish
  /// "no results" from "request errored". The screen catches
  /// thrown exceptions and converts them to outcome errors.
  final Future<CourseSearchOutcome> Function(String query) onSearch;

  /// Called when the user taps a result. The route widget is
  /// responsible for fetching the full `NormalizedCourse` and
  /// navigating to the map screen.
  final void Function(CourseSearchEntry entry) onSelectCourse;

  /// Injected logger so widget tests can capture the
  /// `log_search_latency` events without standing up the global
  /// `logger` singleton.
  final LoggingService logger;

  /// Whether location permission is currently granted. The "Use
  /// my location" toggle in the search bar is disabled when
  /// false; tapping it shows the "location required" empty state.
  /// The route widget computes this from `LocationService`.
  final bool locationGranted;

  /// Debounce delay between the last keystroke and the actual
  /// search call. Default 350 ms. Tests pass `Duration.zero` to
  /// run searches synchronously.
  final Duration debounce;

  /// Optional offline-development entry that always shows in the
  /// idle state. The route widget passes the Sharp Park fallback
  /// fixture entry so engineers without a configured course
  /// cache endpoint can still tap into the map screen.
  final CourseSearchEntry? initialDemoEntry;

  @override
  State<CourseSearchScreen> createState() => _CourseSearchScreenState();
}

class _CourseSearchScreenState extends State<CourseSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;
  bool _isSearching = false;
  CourseSearchOutcome? _lastOutcome;
  String _lastQuery = '';
  bool _useNearby = false;
  bool _showLocationRequiredHint = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _lastOutcome = null;
        _lastQuery = '';
        _isSearching = false;
      });
      return;
    }
    _debounceTimer = Timer(widget.debounce, () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _lastQuery = query;
    });
    final start = DateTime.now();
    CourseSearchOutcome outcome;
    try {
      outcome = await widget.onSearch(query);
    } catch (e) {
      outcome = CourseSearchOutcome(entries: const [], error: '$e');
    }
    if (!mounted) return;
    final latencyMs =
        DateTime.now().millisecondsSinceEpoch - start.millisecondsSinceEpoch;
    widget.logger.info(
      LogCategory.network,
      LoggingService.events.searchLatency,
      metadata: {
        'latencyMs': '$latencyMs',
        'query': query,
        'resultCount': '${outcome.entries.length}',
        'hasLocation': '${widget.locationGranted && _useNearby}',
      },
    );
    setState(() {
      _lastOutcome = outcome;
      _isSearching = false;
    });
  }

  void _toggleNearby(bool value) {
    if (value && !widget.locationGranted) {
      // The location-required hint replaces the result body
      // until the user either grants permission or untoggles.
      setState(() {
        _useNearby = false;
        _showLocationRequiredHint = true;
      });
      return;
    }
    setState(() {
      _useNearby = value;
      _showLocationRequiredHint = false;
    });
    // Re-run the last query with the new "nearby" preference if
    // there's already a query in flight.
    if (_lastQuery.isNotEmpty) {
      _runSearch(_lastQuery);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a Course'),
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: CaddieIcons.course(
            size: 24,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _controller,
            onChanged: _onQueryChanged,
            useNearby: _useNearby,
            onToggleNearby: _toggleNearby,
            locationGranted: widget.locationGranted,
            isSearching: _isSearching,
          ),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_showLocationRequiredHint) {
      return const _EmptyState(
        icon: Icons.location_off_outlined,
        title: 'Location required',
        message:
            'Grant CaddieAI location access from your device settings to '
            'search for courses near you. Or keep typing — name search '
            'still works without location.',
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    final outcome = _lastOutcome;
    if (outcome == null) {
      return _IdleState(
        demoEntry: widget.initialDemoEntry,
        onSelectDemo: widget.onSelectCourse,
      );
    }

    if (outcome.hasError) {
      return _EmptyState(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't reach the course cache",
        message:
            'The server cache request failed. Pull to retry, or open the '
            'demo course while we get the connection back.\n\n${outcome.error}',
      );
    }

    if (outcome.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off_outlined,
        title: 'No courses found',
        message: 'No matches for "$_lastQuery". Try a different search '
            'term, or shorten the name (e.g. drop "Golf Course").',
      );
    }

    return _ResultList(
      entries: outcome.entries,
      onSelect: widget.onSelectCourse,
    );
  }
}

// ── presentational sub-widgets ─────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.useNearby,
    required this.onToggleNearby,
    required this.locationGranted,
    required this.isSearching,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool useNearby;
  final ValueChanged<bool> onToggleNearby;
  final bool locationGranted;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            onChanged: onChanged,
            // autofocus intentionally OFF — `autofocus: true` blocks
            // unit tests waiting for the focus engine to settle. The
            // production UX gets focus on tap, which is fine for the
            // search-first flow.
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by name (e.g. Sharp Park)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: useNearby,
                onChanged: onToggleNearby,
              ),
              const SizedBox(width: 4),
              Text(
                'Use my location',
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              if (!locationGranted)
                Text(
                  'permission required',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.entries, required this.onSelect});

  final List<CourseSearchEntry> entries;
  final void Function(CourseSearchEntry) onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = entries[i];
        final subtitleParts = <String>[
          if (e.city.isNotEmpty) e.city,
          if (e.state.isNotEmpty) e.state,
        ];
        return ListTile(
          leading: CaddieIcons.course(size: 28),
          title: Text(e.name),
          subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(', ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onSelect(e),
        );
      },
    );
  }
}

class _IdleState extends StatelessWidget {
  const _IdleState({this.demoEntry, required this.onSelectDemo});

  final CourseSearchEntry? demoEntry;
  final void Function(CourseSearchEntry) onSelectDemo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'Type a course name to begin',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'CaddieAI searches the shared course cache and shows matching '
            'courses with their hole-by-hole satellite map.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
          if (demoEntry != null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => onSelectDemo(demoEntry!),
              icon: const Icon(Icons.map_outlined),
              label: Text('Open demo: ${demoEntry!.name}'),
            ),
          ],
        ],
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
    );
  }
}
