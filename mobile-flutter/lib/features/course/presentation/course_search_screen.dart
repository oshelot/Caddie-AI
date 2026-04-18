// CourseSearchScreen — KAN-279 + KAN-296 + KAN-29 final form.
//
// Direct port of the iOS `CourseSearchView.swift` and Android
// `CourseScreen.kt` layouts. The screen has TWO tabs at the top:
//
//   ┌───────────┬───────────┐
//   │  Search   │   Saved   │
//   └───────────┴───────────┘
//
// **Search tab** (mirrors `CourseSearchView.swift:42-159` and
// `CourseScreen.kt:255-417`):
//   1. Course name TextField
//   2. City TextField with debounced Google Places autocomplete
//      (driven by the injected `onCityAutocomplete` callback,
//      which the page wrapper wires to the KAN-296 Lambda route)
//   3. Search button — the ONLY thing that fires the search.
//      Typing in the name field does NOT auto-search.
//   4. Favorites quick-access section (when the user has any
//      starred courses) — shows below the form so users can jump
//      back into a favorite without typing.
//   5. Search results / progress / empty / error states
//
// **Saved tab** (mirrors `CourseSearchView.swift:160-268` and
// `CourseScreen.kt:420-460`):
//   1. Favorites section
//   2. Other Saved Courses section (downloaded but not favorited)
//   3. Empty state when both are empty
//
// **Result rows on the Saved tabs and the Favorites quick-list**
// have a star icon that toggles favorite state via the injected
// `favoritesController.toggleFavorite`. Search-result rows don't
// — that matches iOS, where you can only star a course AFTER
// opening it (which writes it to the local cache).
//
// **Why a callback for `onSearch` instead of taking the clients
// directly:** the widget tests need to drive scripted result
// sequences without standing up fake HTTP transports for three
// services. Production wires the callback at the route level.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/courses/course_search_results.dart';
import '../../../core/monetization/ad_service.dart';
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

/// Read-and-mutate seam for the Favorites quick-list and the
/// Saved tab. Production wires this to `CourseCacheRepository`
/// (the methods line up 1:1). Tests inject an in-memory fake.
class FavoritesController {
  const FavoritesController({
    required this.listSaved,
    required this.isFavorite,
    required this.toggleFavorite,
    required this.deleteCourse,
  });

  /// Returns every course currently in the disk cache.
  final List<CourseSearchEntry> Function() listSaved;

  /// Synchronous favorite-state lookup.
  final bool Function(String cacheKey) isFavorite;

  /// Toggles favorite state. Returns the new state.
  final Future<bool> Function(String cacheKey) toggleFavorite;

  /// Deletes a course from the local disk cache.
  final Future<void> Function(String cacheKey) deleteCourse;
}

/// Widget keys exposed for tests so we can find the two TextFields
/// + the search button + the tab buttons without depending on
/// widget order.
abstract final class CourseSearchKeys {
  CourseSearchKeys._();

  static const courseNameField = Key('course-search-name-field');
  static const cityField = Key('course-search-city-field');
  static const searchButton = Key('course-search-button');
  static const citySuggestionTile = Key('course-search-city-suggestion');
  static const tabSearch = Key('course-search-tab-search');
  static const tabSaved = Key('course-search-tab-saved');
  static const favoritesSection = Key('course-search-favorites-section');
  static const savedOtherSection = Key('course-search-saved-other-section');
  static const favoriteToggle = Key('course-search-favorite-toggle');
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
    this.favoritesController,
    this.adService,
  });

  /// Called once per Search-button tap. Receives the trimmed
  /// course-name query and the trimmed city string (which may
  /// be empty).
  ///
  /// **Behavior change vs the original S9 screen:** the screen no
  /// longer auto-fires `onSearch` from a debounced text-change
  /// timer. The Search button is the ONLY trigger. This matches
  /// the native iOS and Android behavior — typing in the name
  /// field never kicks off a network call.
  final Future<CourseSearchOutcome> Function(String query, String city)
      onSearch;

  /// Called when the user taps a result row.
  final void Function(CourseSearchEntry entry) onSelectCourse;

  /// Injected logger so widget tests can capture the
  /// `log_search_latency` events.
  final LoggingService logger;

  /// Whether location permission is currently granted.
  final bool locationGranted;

  /// Debounce delay for the city autocomplete. Default 350 ms.
  /// Tests pass `Duration.zero` for determinism.
  final Duration debounce;

  /// Optional offline-development entry that always shows in the
  /// Search-tab idle state when no favorites exist.
  final CourseSearchEntry? initialDemoEntry;

  /// Callback the screen invokes when the user types in the City
  /// field. Pass `null` to hide the city field entirely.
  final Future<List<PlaceAutocompleteSuggestion>> Function(String input)?
      onCityAutocomplete;

  /// Optional favorites + saved-courses store.
  final FavoritesController? favoritesController;

  /// Optional ad service. When provided and the user is on the
  /// free tier, a banner ad renders at the bottom of the screen.
  final AdService? adService;

  @override
  State<CourseSearchScreen> createState() => _CourseSearchScreenState();
}

class _CourseSearchScreenState extends State<CourseSearchScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  Timer? _cityDebounceTimer;
  bool _isSearching = false;
  CourseSearchOutcome? _lastOutcome;
  String _lastQuery = '';
  bool _useNearby = false;
  bool _showLocationRequiredHint = false;
  List<PlaceAutocompleteSuggestion> _citySuggestions = const [];
  bool _suppressNextCityAutocomplete = false;
  int _selectedTab = 0; // 0 = Search, 1 = Saved

  @override
  void dispose() {
    _cityDebounceTimer?.cancel();
    _nameController.dispose();
    _cityController.dispose();
    super.dispose();
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
    } catch (e, st) {
      // ignore: avoid_print
      print('SEARCH ERROR: $e');
      // ignore: avoid_print
      print('SEARCH STACK: $st');
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
        if (outcome.error != null) 'error': outcome.error!,
      },
    );
    setState(() {
      _lastOutcome = outcome;
      _isSearching = false;
    });
  }

  void _toggleNearby(bool value) {
    if (value && !widget.locationGranted) {
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
    if (_lastQuery.isNotEmpty) {
      _runSearchFromButton();
    }
  }

  Future<void> _onToggleFavorite(CourseSearchEntry entry) async {
    final controller = widget.favoritesController;
    if (controller == null) return;
    await controller.toggleFavorite(entry.cacheKey);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onDeleteCourse(CourseSearchEntry entry) async {
    final controller = widget.favoritesController;
    if (controller == null) return;
    await controller.deleteCourse(entry.cacheKey);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFavoritesController = widget.favoritesController != null;
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
          if (hasFavoritesController)
            _TabBar(
              selectedIndex: _selectedTab,
              onSelected: (i) => setState(() => _selectedTab = i),
            ),
          Expanded(
            child: !hasFavoritesController || _selectedTab == 0
                ? _buildSearchTab(theme)
                : _buildSavedTab(theme),
          ),
          // Banner ad at the bottom — matches iOS safeAreaInset pattern.
          // Hidden for Pro subscribers via adService.bannerVisible.
          if (widget.adService != null) widget.adService!.bannerAd(),
        ],
      ),
    );
  }

  Widget _buildSearchTab(ThemeData theme) {
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

    final favorites = widget.favoritesController == null
        ? const <CourseSearchEntry>[]
        : widget.favoritesController!
            .listSaved()
            .where((e) => e.isFavorite)
            .toList(growable: false);

    final outcome = _lastOutcome;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SearchBar(
          nameController: _nameController,
          cityController: _cityController,
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
        if (favorites.isNotEmpty)
          _FavoritesSection(
            entries: favorites,
            onSelect: widget.onSelectCourse,
            onToggleFavorite: _onToggleFavorite,
          ),
        if (_isSearching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (outcome != null && outcome.hasError)
          _EmptyState(
            icon: Icons.cloud_off_outlined,
            title: "Couldn't reach the course cache",
            message:
                'The server cache request failed. Tap Search to retry.\n\n${outcome.error}',
          )
        else if (outcome != null && outcome.isEmpty)
          _EmptyState(
            icon: Icons.search_off_outlined,
            title: 'No courses found',
            message:
                'No matches for "$_lastQuery". Try a different search term, '
                'or shorten the name (e.g. drop "Golf Course").',
          )
        else if (outcome != null)
          _ResultsSection(
            entries: outcome.entries,
            onSelect: widget.onSelectCourse,
          )
        else if (favorites.isEmpty)
          _IdleState(
            demoEntry: widget.initialDemoEntry,
            onSelectDemo: widget.onSelectCourse,
          ),
      ],
    );
  }

  Widget _buildSavedTab(ThemeData theme) {
    final controller = widget.favoritesController!;
    final saved = controller.listSaved();
    final favorites = saved.where((e) => e.isFavorite).toList(growable: false);
    final other = saved.where((e) => !e.isFavorite).toList(growable: false);

    if (saved.isEmpty) {
      return const _EmptyState(
        icon: Icons.bookmark_border,
        title: 'No saved courses',
        message:
            'Search for a course and open it — it will appear here for '
            'one-tap access on your next round.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (favorites.isNotEmpty)
          _FavoritesSection(
            entries: favorites,
            onSelect: widget.onSelectCourse,
            onToggleFavorite: _onToggleFavorite,
            onDelete: _onDeleteCourse,
          ),
        if (other.isNotEmpty)
          _SavedOtherSection(
            entries: other,
            onSelect: widget.onSelectCourse,
            onToggleFavorite: _onToggleFavorite,
            onDelete: _onDeleteCourse,
          ),
      ],
    );
  }
}

// ── presentational sub-widgets ─────────────────────────────────────

class _TabBar extends StatelessWidget {
  const _TabBar({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SegmentedButton<int>(
        segments: [
          ButtonSegment<int>(
            value: 0,
            icon: CaddieIcons.course(size: 18),
            label: const Text('Search'),
          ),
          ButtonSegment<int>(
            value: 1,
            icon: CaddieIcons.course(size: 18),
            label: const Text('Saved'),
          ),
        ],
        selected: {selectedIndex},
        onSelectionChanged: (set) => onSelected(set.first),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.nameController,
    required this.cityController,
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
            // Intentionally NO onChanged. The native apps don't
            // auto-search on type either; the Search button is the
            // only trigger. onSubmitted (return key) doubles as a
            // way to fire the button without leaving the keyboard.
            onSubmitted: (_) => onSubmit(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Course name (e.g. Sharp Park)',
              prefixIcon: CaddieIcons.course(size: 20),
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
                prefixIcon: CaddieIcons.pinTarget(size: 20),
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
                      for (int i = 0; i < citySuggestions.length; i++)
                        ListTile(
                          key: Key('course-search-city-suggestion-$i'),
                          dense: true,
                          leading: CaddieIcons.pinTarget(size: 18),
                          title: Text(
                            citySuggestions[i].mainText.isNotEmpty
                                ? citySuggestions[i].mainText
                                : citySuggestions[i].description,
                          ),
                          subtitle: citySuggestions[i].secondaryText.isNotEmpty
                              ? Text(citySuggestions[i].secondaryText)
                              : null,
                          onTap: () => onSelectCitySuggestion(citySuggestions[i]),
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
              onPressed: isSearching ? null : onSubmit,
              icon: CaddieIcons.course(size: 18),
              label: const Text('Search'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.outline,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _FavoritesSection extends StatelessWidget {
  const _FavoritesSection({
    required this.entries,
    required this.onSelect,
    required this.onToggleFavorite,
    this.onDelete,
  });

  final List<CourseSearchEntry> entries;
  final void Function(CourseSearchEntry) onSelect;
  final Future<void> Function(CourseSearchEntry) onToggleFavorite;
  final Future<void> Function(CourseSearchEntry)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: CourseSearchKeys.favoritesSection,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('FAVORITES'),
        for (final e in entries)
          _CourseRow(
            entry: e,
            isStarFilled: true,
            onSelect: onSelect,
            onToggleFavorite: onToggleFavorite,
            onDelete: onDelete,
          ),
      ],
    );
  }
}

class _SavedOtherSection extends StatelessWidget {
  const _SavedOtherSection({
    required this.entries,
    required this.onSelect,
    required this.onToggleFavorite,
    this.onDelete,
  });

  final List<CourseSearchEntry> entries;
  final void Function(CourseSearchEntry) onSelect;
  final Future<void> Function(CourseSearchEntry) onToggleFavorite;
  final Future<void> Function(CourseSearchEntry)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: CourseSearchKeys.savedOtherSection,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('OTHER SAVED COURSES'),
        for (final e in entries)
          _CourseRow(
            entry: e,
            isStarFilled: false,
            onSelect: onSelect,
            onToggleFavorite: onToggleFavorite,
            onDelete: onDelete,
          ),
      ],
    );
  }
}

class _ResultsSection extends StatelessWidget {
  const _ResultsSection({required this.entries, required this.onSelect});

  final List<CourseSearchEntry> entries;
  final void Function(CourseSearchEntry) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('SEARCH RESULTS'),
        for (final e in entries)
          _CourseRow(
            entry: e,
            // Search results never show a star — favoriting is only
            // possible AFTER opening a course (which writes it to
            // the local cache). Matches iOS / Android.
            isStarFilled: null,
            onSelect: onSelect,
            onToggleFavorite: null,
          ),
      ],
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({
    required this.entry,
    required this.isStarFilled,
    required this.onSelect,
    required this.onToggleFavorite,
    this.onDelete,
  });

  final CourseSearchEntry entry;
  final bool? isStarFilled;
  final void Function(CourseSearchEntry) onSelect;
  final Future<void> Function(CourseSearchEntry)? onToggleFavorite;
  final Future<void> Function(CourseSearchEntry)? onDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    // KAN-181: exact iOS copy for the confirmation dialog.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Course?'),
        content: Text(
          'Course data for ${entry.name} is cached for faster loading. '
          'If you plan to play here again, consider keeping it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await onDelete!(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (entry.city.isNotEmpty) entry.city,
      if (entry.state.isNotEmpty) entry.state,
    ];
    final subtitle = subtitleParts.isEmpty ? null : subtitleParts.join(', ');

    // Pending entries (backend processing) — spinner, tappable to
    // check if ready.
    if (entry.isPending) {
      return ListTile(
        leading: CaddieIcons.course(size: 28),
        title: Text(
          entry.name,
          style: TextStyle(color: Colors.grey.shade500),
        ),
        subtitle: Text(
          'Preparing course maps\u2026 Tap to check.',
          style: TextStyle(
            color: Colors.grey.shade400,
            fontStyle: FontStyle.italic,
          ),
        ),
        trailing: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        onTap: () => onSelect(entry),
      );
    }

    Widget tile = ListTile(
      leading: CaddieIcons.course(size: 28),
      title: Text(entry.name),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: () => onSelect(entry),
      trailing: isStarFilled == null
          ? CaddieIcons.chevronRight(size: 20)
          : IconButton(
              key: CourseSearchKeys.favoriteToggle,
              icon: Icon(
                isStarFilled! ? Icons.star : Icons.star_border,
                color: isStarFilled! ? Colors.amber : null,
              ),
              tooltip: isStarFilled!
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              onPressed: onToggleFavorite == null
                  ? null
                  : () => onToggleFavorite!(entry),
            ),
    );
    // Wrap in Dismissible for swipe-to-delete on Saved tab rows.
    if (onDelete != null) {
      tile = Dismissible(
        key: ValueKey('dismiss-${entry.cacheKey}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          await _confirmDelete(context);
          return false; // dialog handles the delete; don't auto-remove
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Colors.red,
          child: CaddieIcons.delete(size: 24, color: Colors.white),
        ),
        child: tile,
      );
    }
    return tile;
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
            'CaddieAI searches Nominatim, Google Places, and the shared '
            'course cache for matching golf courses.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
          if (demoEntry != null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => onSelectDemo(demoEntry!),
              icon: CaddieIcons.course(size: 18),
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
