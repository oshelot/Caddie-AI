// CourseSearchScreen — KAN-279 (S9), updated for the KAN-296 / KAN-29
// 3-source search rewrite.
//
// **What this screen does (post-rewrite, mirrors iOS CourseSearchView
// + CourseViewModel exactly):**
//
//   1. Renders a "Course name" search input + an optional "City"
//      input. The city field has a debounced autocomplete dropdown
//      driven by an injected callback (the page wrapper wires this
//      to `PlacesClient.autocomplete`, which proxies Google Places
//      Autocomplete via the KAN-296 Lambda routes).
//   2. On Search button tap, calls `onSearch(query, city)` exactly
//      once. The page wrapper does the parallel fan-out to
//      Nominatim + Google Places + manifest metadata, runs the
//      `CourseSearchMerger`, and returns the merged outcome.
//   3. Renders the result list with name + city/state subtitle.
//      Tapping invokes `onSelectCourse` — the page wrapper handles
//      fetching the full `NormalizedCourse` and navigating.
//   4. Renders distinct empty states for "no results", "location
//      required" (when the user toggles nearby search but
//      permission isn't granted), and "ready to search" (the idle
//      state).
//   5. Logs `log_search_latency` to `LoggingService` on every
//      completed search with the canonical metadata fields.
//
// **Why a callback for `onSearch` instead of taking the clients
// directly:** the widget tests need to drive scripted result
// sequences (empty, populated, error) without standing up fake
// HTTP transports for three different services. Production wires
// the callback at the route level.
//
// **iOS reference:** the layout, the city/name interaction, and the
// debounce all match `ios/CaddieAI/Views/CourseTab/CourseSearchView.swift`
// and the search flow in
// `ios/CaddieAI/ViewModels/CourseViewModel.swift:70-152`.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/courses/course_search_results.dart';
import '../../../core/courses/places_client.dart';
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

/// Widget keys exposed for tests so we can find the two TextFields
/// + the search button without depending on widget order.
abstract final class CourseSearchKeys {
  CourseSearchKeys._();

  static const courseNameField = Key('course-search-name-field');
  static const cityField = Key('course-search-city-field');
  static const searchButton = Key('course-search-button');
  static const citySuggestionTile = Key('course-search-city-suggestion');
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
    this.onCityAutocomplete,
  });

  /// Called once per Search-button tap (or debounced typing fire if
  /// the screen is configured with a non-zero debounce). Receives
  /// the trimmed course-name query and the trimmed city string
  /// (which may be empty).
  ///
  /// Returns a `CourseSearchOutcome` so callers can distinguish
  /// "no results" from "request errored". The screen catches
  /// thrown exceptions and converts them to outcome errors.
  final Future<CourseSearchOutcome> Function(String query, String city)
      onSearch;

  /// Called when the user taps a result. The page wrapper is
  /// responsible for fetching the full `NormalizedCourse` and
  /// navigating to the map screen.
  final void Function(CourseSearchEntry entry) onSelectCourse;

  /// Injected logger so widget tests can capture the
  /// `log_search_latency` events without standing up the global
  /// `logger` singleton.
  final LoggingService logger;

  /// Whether location permission is currently granted. The "Use
  /// my location" toggle is disabled when false; tapping it shows
  /// the "location required" hint.
  final bool locationGranted;

  /// Debounce delay between the last keystroke and the actual
  /// search call. Default 350 ms. Tests pass `Duration.zero` for
  /// determinism.
  final Duration debounce;

  /// Optional offline-development entry that always shows in the
  /// idle state. The page wrapper passes the Sharp Park fallback
  /// fixture entry so engineers without a configured course cache
  /// endpoint can still tap into the map screen.
  final CourseSearchEntry? initialDemoEntry;

  /// Callback the screen invokes when the user types in the City
  /// field. Returns the autocomplete suggestions for the current
  /// input. Pass `null` to disable the city field entirely
  /// (existing tests do this).
  final Future<List<PlaceAutocompleteSuggestion>> Function(String input)?
      onCityAutocomplete;

  @override
  State<CourseSearchScreen> createState() => _CourseSearchScreenState();
}

class _CourseSearchScreenState extends State<CourseSearchScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  Timer? _debounceTimer;
  Timer? _cityDebounceTimer;
  bool _isSearching = false;
  CourseSearchOutcome? _lastOutcome;
  String _lastQuery = '';
  bool _useNearby = false;
  bool _showLocationRequiredHint = false;
  List<PlaceAutocompleteSuggestion> _citySuggestions = const [];
  bool _suppressNextCityAutocomplete = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _cityDebounceTimer?.cancel();
    _nameController.dispose();
    _cityController.dispose();
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

  void _onCityChanged(String value) {
    if (_suppressNextCityAutocomplete) {
      _suppressNextCityAutocomplete = false;
      return;
    }
    if (widget.onCityAutocomplete == null) return;
    _cityDebounceTimer?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _citySuggestions = const []);
      return;
    }
    _cityDebounceTimer = Timer(widget.debounce, () async {
      final suggestions = await widget.onCityAutocomplete!(trimmed);
      if (!mounted) return;
      setState(() => _citySuggestions = suggestions);
    });
  }

  void _onSelectCitySuggestion(PlaceAutocompleteSuggestion suggestion) {
    // Setting the controller text fires onChanged, which would
    // immediately re-run the autocomplete with the same value.
    // Suppress that single re-fire so the suggestion list collapses
    // cleanly.
    _suppressNextCityAutocomplete = true;
    _cityController.text = suggestion.description;
    _cityController.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.description.length),
    );
    setState(() => _citySuggestions = const []);
  }

  Future<void> _runSearchFromButton() async {
    final query = _nameController.text.trim();
    if (query.isEmpty) return;
    await _runSearch(query);
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _lastQuery = query;
      _citySuggestions = const [];
    });
    final start = DateTime.now();
    final city = _cityController.text.trim();
    CourseSearchOutcome outcome;
    try {
      outcome = await widget.onSearch(query, city);
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
        'cityProvided': '${city.isNotEmpty}',
      },
    );
    setState(() {
      _lastOutcome = outcome;
      _isSearching = false;
    });
  }

  void _toggleNearby(bool value) {
    if (value && !widget.locationGranted) {
      // The location-required hint replaces the result body until
      // the user either grants permission or untoggles.
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
            nameController: _nameController,
            cityController: _cityController,
            onNameChanged: _onQueryChanged,
            onCityChanged: _onCityChanged,
            onSubmit: _runSearchFromButton,
            useNearby: _useNearby,
            onToggleNearby: _toggleNearby,
            locationGranted: widget.locationGranted,
            isSearching: _isSearching,
            citySuggestions: _citySuggestions,
            onSelectCitySuggestion: _onSelectCitySuggestion,
            cityFieldEnabled: widget.onCityAutocomplete != null,
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
    required this.nameController,
    required this.cityController,
    required this.onNameChanged,
    required this.onCityChanged,
    required this.onSubmit,
    required this.useNearby,
    required this.onToggleNearby,
    required this.locationGranted,
    required this.isSearching,
    required this.citySuggestions,
    required this.onSelectCitySuggestion,
    required this.cityFieldEnabled,
  });

  final TextEditingController nameController;
  final TextEditingController cityController;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onCityChanged;
  final VoidCallback onSubmit;
  final bool useNearby;
  final ValueChanged<bool> onToggleNearby;
  final bool locationGranted;
  final bool isSearching;
  final List<PlaceAutocompleteSuggestion> citySuggestions;
  final ValueChanged<PlaceAutocompleteSuggestion> onSelectCitySuggestion;
  final bool cityFieldEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: CourseSearchKeys.courseNameField,
            controller: nameController,
            onChanged: onNameChanged,
            onSubmitted: (_) => onSubmit(),
            // autofocus intentionally OFF — `autofocus: true` blocks
            // unit tests waiting for the focus engine to settle. The
            // production UX gets focus on tap, which is fine for the
            // search-first flow.
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Course name (e.g. Sharp Park)',
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
          if (cityFieldEnabled) ...[
            const SizedBox(height: 8),
            TextField(
              key: CourseSearchKeys.cityField,
              controller: cityController,
              onChanged: onCityChanged,
              onSubmitted: (_) => onSubmit(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'City (optional)',
                prefixIcon: const Icon(Icons.location_city_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (citySuggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Material(
                  elevation: 1,
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    children: [
                      for (final suggestion in citySuggestions)
                        ListTile(
                          key: CourseSearchKeys.citySuggestionTile,
                          dense: true,
                          leading: const Icon(
                            Icons.place_outlined,
                            size: 18,
                          ),
                          title: Text(
                            suggestion.mainText.isNotEmpty
                                ? suggestion.mainText
                                : suggestion.description,
                          ),
                          subtitle: suggestion.secondaryText.isNotEmpty
                              ? Text(suggestion.secondaryText)
                              : null,
                          onTap: () => onSelectCitySuggestion(suggestion),
                        ),
                    ],
                  ),
                ),
              ),
          ],
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: CourseSearchKeys.searchButton,
              onPressed: nameController.text.trim().isEmpty || isSearching
                  ? null
                  : onSubmit,
              icon: const Icon(Icons.search),
              label: const Text('Search'),
            ),
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
