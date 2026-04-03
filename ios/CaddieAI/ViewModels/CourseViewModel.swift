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

    /// Task handle for cancellation support
    private var ingestionTask: Task<Void, Never>?

    var selectedHole: Int?
    var selectedTee: String?

    // Injected via environment
    var cacheService: CourseCacheService?
    var profileStore: ProfileStore?
    var apiUsageStore: APIUsageStore?

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
        let totalStart = CFAbsoluteTimeGetCurrent()

        // Check cache first (skip if forcing refresh)
        let cacheStart = CFAbsoluteTimeGetCurrent()
        let courseId = NormalizedCourse.generateId(name: result.name, centroid: result.centroid)
        if !forceRefresh, let cached = cacheService?.load(id: courseId) {
            let cacheMs = Int((CFAbsoluteTimeGetCurrent() - cacheStart) * 1000)
            LoggingService.shared.info(.map, "cache_check", metadata: [
                "latencyMs": "\(cacheMs)", "courseName": result.name, "cacheHit": "true",
            ])
            selectedCourse = cached
            TelemetryService.shared.recordCoursePlayed(courseName: cached.name)
            isIngesting = false
            return
        }
        let cacheMs = Int((CFAbsoluteTimeGetCurrent() - cacheStart) * 1000)
        LoggingService.shared.info(.map, "cache_check", metadata: [
            "latencyMs": "\(cacheMs)", "courseName": result.name, "cacheHit": "false",
        ])

        guard let bbox = result.boundingBox else {
            ingestionError = "No bounding box available for this course."
            isIngesting = false
            return
        }

        do {
            // Step 1: Fetch features from Overpass
            ingestionStep = "Fetching course features…"
            var stepStart = CFAbsoluteTimeGetCurrent()
            let response = try await OverpassClient.fetchCourseFeatures(boundingBox: bbox)
            try Task.checkCancellation()
            LoggingService.shared.info(.map, "overpass_fetch", metadata: [
                "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))",
                "courseName": result.name,
            ])

            // Step 2: Parse OSM data
            ingestionStep = "Parsing geometry…"
            stepStart = CFAbsoluteTimeGetCurrent()
            let parsed = OSMParser.parse(response)
            try Task.checkCancellation()
            LoggingService.shared.info(.map, "osm_parse", metadata: [
                "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))",
                "courseName": result.name,
            ])

            // Step 3: Normalize into course model(s)
            ingestionStep = "Building course model…"
            stepStart = CFAbsoluteTimeGetCurrent()
            let courses = CourseNormalizer.normalizeAll(
                features: parsed,
                courseName: result.name,
                osmCourseId: result.id,
                city: result.city,
                state: result.state
            )
            try Task.checkCancellation()
            LoggingService.shared.info(.map, "normalize", metadata: [
                "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))",
                "courseName": result.name,
                "holeCount": "\(courses.first?.holes.count ?? 0)",
            ])

            // Step 4: Enrich with scorecard data from Golf Course API
            let golfApiKey = {
                let profileKey = profileStore?.profile.golfCourseApiKey ?? ""
                return profileKey.isEmpty ? (Secrets.golfCourseApiKey ?? "") : profileKey
            }()
            var enrichedCourses = courses
            if !golfApiKey.isEmpty {
                ingestionStep = "Fetching scorecard data…"
                stepStart = CFAbsoluteTimeGetCurrent()
                enrichedCourses = await enrichWithScorecardData(courses: courses, courseName: result.name, apiKey: golfApiKey)
                try Task.checkCancellation()
                LoggingService.shared.info(.map, "scorecard_fetch", metadata: [
                    "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))",
                    "courseName": result.name,
                ])
            }

            // Step 5: Cache all sub-courses
            ingestionStep = "Saving to cache…"
            stepStart = CFAbsoluteTimeGetCurrent()
            for course in enrichedCourses {
                cacheService?.save(course)
            }
            LoggingService.shared.info(.map, "cache_save", metadata: [
                "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))",
                "courseName": result.name,
            ])

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
                TelemetryService.shared.recordCoursePlayed(courseName: course.name)
            }

            // Log total ingestion time
            LoggingService.shared.info(.map, "total_ingestion", metadata: [
                "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000))",
                "courseName": result.name,
                "holeCount": "\(enrichedCourses.first?.holes.count ?? 0)",
            ])
        } catch is CancellationError {
            // User cancelled — reset silently
        } catch {
            ingestionError = error.localizedDescription
            LoggingService.shared.error(.course, "Course ingestion failed: \(error.localizedDescription)")
        }

        isIngesting = false
    }

    /// Starts ingestion in a trackable, cancellable task.
    func startIngestion(_ result: CourseSearchResult, forceRefresh: Bool = false) {
        ingestionTask?.cancel()
        ingestionTask = Task { await ingestCourse(result, forceRefresh: forceRefresh) }
    }

    /// Cancels any in-progress ingestion.
    func cancelIngestion() {
        ingestionTask?.cancel()
        ingestionTask = nil
        isIngesting = false
        ingestionStep = ""
    }

    // MARK: - Load from Cache

    func loadCachedCourse(id: String) {
        if let course = cacheService?.load(id: id) {
            selectedCourse = course
            selectedTee = cacheService?.selectedTee(forCourse: id)
            TelemetryService.shared.recordCoursePlayed(courseName: course.name)
        }
    }

    // MARK: - Cached Courses List

    var cachedCourses: [CourseCacheEntry] {
        cacheService?.cachedCourses ?? []
    }

    // MARK: - Sub-Course Selection

    func selectSubCourse(_ course: NormalizedCourse) {
        selectedCourse = course
        TelemetryService.shared.recordCoursePlayed(courseName: course.name)
        showSubCoursePicker = false
        availableSubCourses = []
    }

    // MARK: - Deduplicated Tees

    /// Deduplicates tee names for display in the tee picker.
    /// 1. Removes combo tees (e.g. "Gold/Black") when a standalone component exists.
    /// 2. Groups remaining tees that share identical per-hole yardages.
    /// Returns (displayName, canonicalTee) pairs sorted longest → shortest by total yardage.
    static func deduplicatedTees(for course: NormalizedCourse) -> [(displayName: String, canonicalTee: String)] {
        guard let teeNames = course.teeNames, !teeNames.isEmpty else { return [] }

        let lowercasedNames = Set(teeNames.map { $0.lowercased() })

        // Step 1: Filter out combo tees when a standalone component exists
        let filtered = teeNames.filter { name in
            let parts = name.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count > 1 else { return true } // standalone tee, keep it
            // Drop combo if ANY component exists as a standalone tee
            return !parts.contains { lowercasedNames.contains($0.lowercased()) }
        }
        guard !filtered.isEmpty else { return [] }

        // Step 2: Group by identical yardage signatures
        let sortedHoles = course.holes.sorted { $0.number < $1.number }
        var signatureToTees: [String: [String]] = [:]

        for tee in filtered {
            let sig = sortedHoles.map { hole in
                hole.yardages?[tee].map(String.init) ?? "-"
            }.joined(separator: ",")
            signatureToTees[sig, default: []].append(tee)
        }

        // Step 3: Sort longest → shortest by total yardage (from teeYardageTotals or summing holes)
        let results = signatureToTees.values.map { group in
            (displayName: group.joined(separator: " / "), canonicalTee: group[0])
        }

        return results.sorted { a, b in
            let aYards = course.teeYardageTotals?[a.canonicalTee]
                ?? course.holes.compactMap { $0.yardages?[a.canonicalTee] }.reduce(0, +)
            let bYards = course.teeYardageTotals?[b.canonicalTee]
                ?? course.holes.compactMap { $0.yardages?[b.canonicalTee] }.reduce(0, +)
            return aYards > bYards
        }
    }

    // MARK: - Clear Selection

    func clearSelection() {
        selectedCourse = nil
        selectedHole = nil
        selectedTee = nil
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
        // Check rate limit before making Golf API calls
        if let store = apiUsageStore, !store.canMakeGolfAPICall {
            return courses
        }

        do {
            // Search returns summary data; fetch full detail for tee/hole info
            let results = try await GolfCourseAPIClient.searchCourses(name: courseName, apiKey: apiKey)
            apiUsageStore?.recordGolfAPICall(method: "searchCourses")
            TelemetryService.shared.recordGolfAPICall(method: "searchCourses")
            guard let bestMatch = results.first else { return courses }

            // The search result may have tees already, but fetch detail to be sure
            let detail = try await GolfCourseAPIClient.getCourse(id: bestMatch.id, apiKey: apiKey)
            apiUsageStore?.recordGolfAPICall(method: "getCourse")
            TelemetryService.shared.recordGolfAPICall(method: "getCourse")
            let courseData = detail ?? bestMatch

            let scorecard = courseData.extractScorecardData()
            guard !scorecard.isEmpty else { return courses }

            return courses.map { course in
                var enriched = course

                // Course-level metadata
                enriched.totalPar = scorecard.totalPar
                enriched.teeNames = scorecard.teeYardages.keys.sorted()

                // Store total yardage per tee for distance-based tee selection
                var totals: [String: Int] = [:]
                for info in scorecard.teeBoxInfos {
                    if let yards = info.totalYards {
                        totals[info.name] = yards
                    }
                }
                if !totals.isEmpty {
                    enriched.teeYardageTotals = totals
                }

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
