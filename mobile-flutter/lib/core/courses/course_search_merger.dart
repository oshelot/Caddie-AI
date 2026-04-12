// CourseSearchMerger — pure-function merge step for the 3-source
// course search (Nominatim + Google Places + server-cache manifest).
//
// **Direct port of `ios/CaddieAI/ViewModels/CourseViewModel.swift:90-129`.**
// The iOS code does Nominatim + MapKit (we replace MapKit with Google
// Places) + manifest metadata in parallel, merges them with a
// fuzzy-name dedup, then overlays the manifest's Google-Places-corrected
// city/state on top of any matched Nominatim/Places result.
//
// Keeping this as a pure function (no I/O, no state) means it's
// trivial to unit test against scripted lists, and the page wrapper
// can swap implementations later without touching the screen.

import 'course_search_results.dart';

class CourseSearchMerger {
  const CourseSearchMerger();

  /// Merges three result lists using the same rules as iOS:
  ///
  /// 1. **Order:** Nominatim results first (best name fidelity from
  ///    OSM), then Google Places results that don't overlap by
  ///    fuzzy substring match.
  /// 2. **Dedup:** a Places row is dropped if its lowercased name is
  ///    already in the Nominatim set OR if either name fuzzy-contains
  ///    the other (case-insensitive substring).
  /// 3. **Overlay:** for every merged row, look up the manifest by
  ///    name (case-insensitive substring); if found, **replace** the
  ///    row's city/state with the manifest values. The manifest
  ///    city/state is Google-Places-corrected at PUT time on the
  ///    server side, which is more accurate than Nominatim's address
  ///    data (Nominatim reports Sharp Park as San Francisco; the
  ///    manifest reports Pacifica, which is correct).
  List<CourseSearchEntry> merge({
    required List<CourseSearchEntry> nominatim,
    required List<CourseSearchEntry> googlePlaces,
    required List<CourseSearchEntry> manifestEntries,
  }) {
    final merged = <CourseSearchEntry>[...nominatim];
    final nominatimNames =
        nominatim.map((e) => e.name.toLowerCase()).toSet();

    for (final place in googlePlaces) {
      final placeName = place.name.toLowerCase();
      if (nominatimNames.contains(placeName)) continue;
      final isDuplicate = nominatim.any((existing) {
        final existingName = existing.name.toLowerCase();
        return placeName.contains(existingName) ||
            existingName.contains(placeName);
      });
      if (!isDuplicate) {
        merged.add(place);
      }
    }

    if (manifestEntries.isEmpty) {
      return merged;
    }

    // Overlay manifest city/state. Mirrors CourseViewModel.swift:108-129.
    return [
      for (final row in merged) _overlayManifest(row, manifestEntries),
    ];
  }

  CourseSearchEntry _overlayManifest(
    CourseSearchEntry row,
    List<CourseSearchEntry> manifestEntries,
  ) {
    final rowName = row.name.toLowerCase();
    for (final entry in manifestEntries) {
      final entryName = entry.name.toLowerCase();
      final isMatch = rowName == entryName ||
          rowName.contains(entryName) ||
          entryName.contains(rowName);
      if (!isMatch) continue;
      final newCity = entry.city.isNotEmpty ? entry.city : null;
      final newState = entry.state.isNotEmpty ? entry.state : null;
      if (newCity == null && newState == null) return row;
      return row.copyWith(city: newCity, state: newState);
    }
    return row;
  }
}
