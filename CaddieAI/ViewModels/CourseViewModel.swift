//
//  CourseViewModel.swift
//  CaddieAI
//
//  Orchestrates course search, Overpass ingestion, normalization, and caching.
//  Search runs Nominatim and MKLocalSearch in parallel, merges results.
//

import Foundation
import MapKit

@Observable
final class CourseViewModel {

    // MARK: - State

    var searchText = ""
    var cityText = ""
    var searchResults: [CourseSearchResult] = []
    var isSearching = false
    var searchError: String?

    var selectedCourse: NormalizedCourse?
    var currentWeather: WeatherData?
    var isIngesting = false
    var ingestionStep = ""
    var ingestionError: String?
    /// Set after ingestion completes with sparse data
    var ingestionWarning: String?

    /// When a facility has multiple sub-courses, user picks one
    var availableSubCourses: [NormalizedCourse] = []
    var showSubCoursePicker = false

    var selectedHole: Int?

    // Injected via environment
    var cacheService: CourseCacheService?
    var profileStore: ProfileStore?

    // MARK: - Search (Nominatim + MKLocalSearch in parallel)

    func searchCourses() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        searchError = nil
        searchResults = []

        let city = cityText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchTerm = city.isEmpty ? query : "\(query) \(city)"

        // Run both searches in parallel
        async let nominatimTask = safeNominatimSearch(searchTerm)
        async let mapKitTask = searchWithMapKit(query: searchTerm)

        let nominatimResults = await nominatimTask
        let mapKitResults = await mapKitTask

        // Merge: OSM results first, then MapKit results not already covered
        var merged = nominatimResults
        let osmNames = Set(nominatimResults.map { $0.name.lowercased() })

        for mkResult in mapKitResults {
            let nameKey = mkResult.name.lowercased()
            // Skip if we already have a close name match from Nominatim
            if osmNames.contains(nameKey) { continue }
            // Check for fuzzy overlap (one name contains the other)
            let isDuplicate = nominatimResults.contains { existing in
                nameKey.contains(existing.name.lowercased()) ||
                existing.name.lowercased().contains(nameKey)
            }
            if !isDuplicate {
                merged.append(mkResult)
            }
        }

        // Mark cached courses
        if let cache = cacheService {
            merged = merged.map { result in
                var r = result
                let courseId = NormalizedCourse.generateId(name: r.name, centroid: r.centroid)
                r.isCached = cache.isCached(id: courseId)
                return r
            }
        }

        if merged.isEmpty {
            searchError = "No golf courses found. Try a different name or add a city."
        }

        searchResults = merged
        isSearching = false
    }

    // MARK: - Nominatim (safe wrapper)

    private func safeNominatimSearch(_ query: String) async -> [CourseSearchResult] {
        do {
            return try await NominatimClient.searchCourses(name: query)
        } catch {
            return []
        }
    }

    // MARK: - MKLocalSearch

    private func searchWithMapKit(query: String) async -> [CourseSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "golf course \(query)"
        request.resultTypes = .pointOfInterest

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            return response.mapItems.compactMap { item -> CourseSearchResult? in
                guard let name = item.name else { return nil }
                let coord = item.placemark.coordinate

                // Synthesize a bounding box (~1km buffer)
                let buffer = 0.009
                let bbox = CourseBoundingBox(
                    south: coord.latitude - buffer,
                    west: coord.longitude - buffer,
                    north: coord.latitude + buffer,
                    east: coord.longitude + buffer
                )

                return CourseSearchResult(
                    id: "mk_\(coord.latitude)_\(coord.longitude)",
                    name: name,
                    city: item.placemark.locality,
                    state: item.placemark.administrativeArea,
                    centroid: GeoJSONPoint(latitude: coord.latitude, longitude: coord.longitude),
                    boundingBox: bbox,
                    isCached: false,
                    source: .appleMapKit
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Ingest Course

    func ingestCourse(_ result: CourseSearchResult, forceRefresh: Bool = false) async {
        isIngesting = true
        ingestionError = nil
        ingestionWarning = nil
        ingestionStep = "Checking cache…"

        // Check cache first (skip if forcing refresh)
        let courseId = NormalizedCourse.generateId(name: result.name, centroid: result.centroid)
        if !forceRefresh, let cached = cacheService?.load(id: courseId) {
            selectedCourse = cached
            isIngesting = false
            return
        }

        guard let bbox = result.boundingBox else {
            ingestionError = "No bounding box available for this course."
            isIngesting = false
            return
        }

        do {
            // Step 1: Fetch features from Overpass
            ingestionStep = "Fetching course features…"
            let response = try await OverpassClient.fetchCourseFeatures(boundingBox: bbox)

            // Step 2: Parse OSM data
            ingestionStep = "Parsing geometry…"
            let parsed = OSMParser.parse(response)

            // Step 3: Normalize into course model(s)
            ingestionStep = "Building course model…"
            let courses = CourseNormalizer.normalizeAll(
                features: parsed,
                courseName: result.name,
                osmCourseId: result.id,
                city: result.city,
                state: result.state
            )

            // Step 4: Enrich with scorecard data from Golf Course API
            let golfApiKey = profileStore?.profile.golfCourseApiKey ?? ""
            var enrichedCourses = courses
            if !golfApiKey.isEmpty {
                ingestionStep = "Fetching scorecard data…"
                enrichedCourses = await enrichWithScorecardData(courses: courses, courseName: result.name, apiKey: golfApiKey)
            }

            // Step 5: Cache all sub-courses
            ingestionStep = "Saving to cache…"
            for course in enrichedCourses {
                cacheService?.save(course)
            }

            // Step 6: Handle results
            if enrichedCourses.count > 1 {
                // Multiple sub-courses — let user pick
                availableSubCourses = enrichedCourses
                showSubCoursePicker = true
            } else if let course = enrichedCourses.first {
                // Single course
                if course.holes.isEmpty {
                    ingestionWarning = "This course hasn't been mapped in OpenStreetMap yet. The satellite map will show the area, but hole layouts, greens, and hazards aren't available."
                } else if course.stats.overallConfidence < 0.3 {
                    ingestionWarning = "This course has limited map data. Some holes, greens, or hazards may be missing."
                }
                selectedCourse = course
            }
        } catch {
            ingestionError = error.localizedDescription
        }

        isIngesting = false
    }

    // MARK: - Load from Cache

    func loadCachedCourse(id: String) {
        if let course = cacheService?.load(id: id) {
            selectedCourse = course
        }
    }

    // MARK: - Cached Courses List

    var cachedCourses: [CourseCacheEntry] {
        cacheService?.cachedCourses ?? []
    }

    // MARK: - Sub-Course Selection

    func selectSubCourse(_ course: NormalizedCourse) {
        selectedCourse = course
        showSubCoursePicker = false
        availableSubCourses = []
    }

    // MARK: - Clear Selection

    func clearSelection() {
        selectedCourse = nil
        selectedHole = nil
        currentWeather = nil
        ingestionWarning = nil
        availableSubCourses = []
        showSubCoursePicker = false
    }

    // MARK: - Weather

    /// Fetches weather for the selected course (best-effort)
    func fetchWeather() async {
        guard let course = selectedCourse else { return }
        do {
            currentWeather = try await WeatherService.fetchWeather(
                latitude: course.centroid.latitude,
                longitude: course.centroid.longitude
            )
        } catch {
            // Weather is optional
        }
    }

    // MARK: - Scorecard Enrichment

    private func enrichWithScorecardData(courses: [NormalizedCourse], courseName: String, apiKey: String) async -> [NormalizedCourse] {
        do {
            // Search returns summary data; fetch full detail for tee/hole info
            let results = try await GolfCourseAPIClient.searchCourses(name: courseName, apiKey: apiKey)
            guard let bestMatch = results.first else { return courses }

            // The search result may have tees already, but fetch detail to be sure
            let detail = try await GolfCourseAPIClient.getCourse(id: bestMatch.id, apiKey: apiKey)
            let courseData = detail ?? bestMatch

            let scorecard = courseData.extractScorecardData()
            guard !scorecard.isEmpty else { return courses }

            return courses.map { course in
                var enriched = course

                // Course-level metadata
                enriched.totalPar = scorecard.totalPar
                enriched.teeNames = scorecard.teeYardages.keys.sorted()

                // Pick first tee box with slope/rating data
                if let teeInfo = scorecard.teeBoxInfos.first(where: { $0.slopeRating != nil }) ?? scorecard.teeBoxInfos.first {
                    enriched.slopeRating = teeInfo.slopeRating
                    enriched.courseRating = teeInfo.courseRating
                }

                // Enrich each hole
                enriched.holes = enriched.holes.map { hole in
                    var h = hole
                    if let par = scorecard.pars[hole.number] {
                        h.par = par
                    }
                    if let si = scorecard.strokeIndexes[hole.number] {
                        h.strokeIndex = si
                    }
                    var yardages: [String: Int] = [:]
                    for (teeName, holeYardages) in scorecard.teeYardages {
                        if let yards = holeYardages[hole.number] {
                            yardages[teeName] = yards
                        }
                    }
                    if !yardages.isEmpty {
                        h.yardages = yardages
                    }
                    return h
                }

                return enriched
            }
        } catch {
            // Enrichment is best-effort — don't fail ingestion
            return courses
        }
    }
}
