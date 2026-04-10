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

    // MARK: - Background Download State

    /// Per-course background download tracking (keyed by generated course ID)
    /// Value is progress fraction 0.0–1.0; presence in dict means downloading.
    var downloadProgress: [String: Double] = [:]
    var downloadedCourseIDs: Set<String> = []
    var downloadErrorCourseIDs: Set<String> = []
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    var selectedHole: Int?
    var selectedTee: String?

    // MARK: - Interstitial Ad Dual-Gate

    /// When true, the interstitial ad has finished (dismissed, failed, or skipped).
    var adCompleted = true
    /// When true, ingestion finished while an ad was still showing.
    var ingestionCompleted = false
    /// Holds the ingested course until both ad and ingestion are done.
    var pendingCourse: NormalizedCourse?
    /// Holds the pending warning message until transition.
    var pendingWarning: String?
    /// Whether an interstitial ad is currently being shown.
    var isShowingInterstitialAd = false

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

        // Run searches + server cache metadata lookup in parallel
        async let nominatimTask = safeNominatimSearch(searchTerm)
        async let mapKitTask = searchWithMapKit(query: searchTerm)
        async let manifestTask = safeManifestMetadataSearch(query)

        let nominatimResults = await nominatimTask
        let mapKitResults = await mapKitTask
        let manifestEntries = await manifestTask

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

        // Overlay Google Places-corrected city/state from server cache manifest.
        // The server cache stores city/state validated by Google Places on upload,
        // which is more accurate than Nominatim (e.g. Sharp Park → Pacifica, not SF).
        if !manifestEntries.isEmpty {
            for i in merged.indices {
                let resultNameLower = merged[i].name.lowercased()
                // Find best manifest match by name (substring or exact match)
                if let match = manifestEntries.first(where: { entry in
                    let entryNameLower = entry.name.lowercased()
                    return resultNameLower == entryNameLower
                        || resultNameLower.contains(entryNameLower)
                        || entryNameLower.contains(resultNameLower)
                }) {
                    if let city = match.city, !city.isEmpty {
                        merged[i].city = city
                    }
                    if let state = match.state, !state.isEmpty {
                        merged[i].state = state
                    }
                }
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

        // Populate downloadedCourseIDs from already-cached results
        downloadedCourseIDs = Set(merged.filter { $0.isCached }
            .map { NormalizedCourse.generateId(name: $0.name, centroid: $0.centroid) })

        isSearching = false
    }

    // MARK: - Nominatim (safe wrapper)

    private func safeNominatimSearch(_ query: String) async -> [CourseSearchResult] {
        do {
            return try await NominatimClient.searchCourses(name: query)
        } catch {
            LoggingService.shared.warning(.map, "nominatim_search_error", metadata: [
                "query": query, "error": error.localizedDescription,
            ])
            return []
        }
    }

    // MARK: - Server cache manifest metadata (safe wrapper)

    private func safeManifestMetadataSearch(_ query: String) async -> [CourseManifestEntry] {
        do {
            return try await CourseCacheAPIClient.searchManifestMetadata(query: query)
        } catch {
            // Non-fatal — if the server cache is unreachable, we still show Nominatim results
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

                // Synthesize a bounding box (~1.7km buffer each side, ~3.4km total span).
                // Must be large enough for courses that extend far from the centroid—
                // e.g. Broadlands GC spans ~2km E-W and the MapKit centroid is
                // offset toward the clubhouse. Overpass adds another ~200m buffer.
                let buffer = 0.015
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
            LoggingService.shared.warning(.map, "mapkit_search_error", metadata: [
                "error": error.localizedDescription,
            ])
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

            // If the cached course has suspiciously few holes (9-17), it may have been
            // ingested with a bbox that was too tight. Re-ingest with the current
            // (wider) bbox to pick up missing holes.
            let holeCount = cached.holes.count
            if holeCount >= 9 && holeCount < 18 {
                LoggingService.shared.info(.map, "cache_check", metadata: [
                    "latencyMs": "\(cacheMs)", "courseName": result.name,
                    "cacheHit": "true", "reIngesting": "true",
                    "reason": "incompleteHoles", "holeCount": "\(holeCount)",
                ])
                // Fall through to re-ingest with current bbox
            } else {
                // If the cached course is missing tee/yardage data and we have an API key,
                // try to enrich it before serving. This handles stale caches from before
                // the Golf Course API was configured.
                let golfApiKey = {
                    let profileKey = profileStore?.profile.golfCourseApiKey ?? ""
                    return profileKey.isEmpty ? (Secrets.golfCourseApiKey ?? "") : profileKey
                }()
                let needsEnrichment = (cached.teeNames == nil || cached.teeNames?.isEmpty == true) && !cached.holes.isEmpty && !golfApiKey.isEmpty
                LoggingService.shared.info(.map, "cache_enrichment_check", metadata: [
                    "courseName": result.name,
                    "teeNames": (cached.teeNames ?? []).joined(separator: ","),
                    "teeNamesNil": "\(cached.teeNames == nil)",
                    "needsEnrichment": "\(needsEnrichment)",
                    "hasApiKey": "\(!golfApiKey.isEmpty)",
                    "holeCount": "\(cached.holes.count)",
                ])
                if needsEnrichment {
                    LoggingService.shared.info(.map, "cache_check", metadata: [
                        "latencyMs": "\(cacheMs)", "courseName": result.name,
                        "cacheHit": "true", "reEnriching": "true",
                    ])
                    // Display the cached course immediately so the user isn't blocked
                    selectedCourse = cached
                    TelemetryService.shared.recordCoursePlayed(courseName: cached.name)
                    isIngesting = false

                    // Enrich in background — UI updates when enrichment completes
                    Task {
                        let enriched = await self.enrichWithScorecardData(
                            courses: [cached], courseName: result.name, apiKey: golfApiKey
                        )
                        if let course = enriched.first {
                            self.cacheService?.save(course)
                            self.selectedCourse = course
                        }
                    }
                    return
                }

                LoggingService.shared.info(.map, "cache_check", metadata: [
                    "latencyMs": "\(cacheMs)", "courseName": result.name, "cacheHit": "true",
                ])
                selectedCourse = cached
                TelemetryService.shared.recordCoursePlayed(courseName: cached.name)
                isIngesting = false
                return
            }
        }
        let cacheMs = Int((CFAbsoluteTimeGetCurrent() - cacheStart) * 1000)
        LoggingService.shared.info(.map, "cache_check", metadata: [
            "latencyMs": "\(cacheMs)", "courseName": result.name, "cacheHit": "false",
        ])

        // Step 1b: Check server cache before hitting Overpass
        if Secrets.courseCacheEndpoint != nil {
            ingestionStep = "Checking server cache…"
            let serverStart = CFAbsoluteTimeGetCurrent()
            do {
                if let serverCached = try await CourseCacheAPIClient.searchCourse(
                    query: result.name,
                    latitude: result.centroid.latitude,
                    longitude: result.centroid.longitude
                ) {
                    guard !Task.isCancelled else {
                        isIngesting = false
                        return
                    }
                    let serverMs = Int((CFAbsoluteTimeGetCurrent() - serverStart) * 1000)
                    LoggingService.shared.info(.map, "server_cache_check", metadata: [
                        "latencyMs": "\(serverMs)", "courseName": result.name, "cacheHit": "true",
                    ])
                    // Save to local cache for offline access
                    cacheService?.save(serverCached)
                    selectedCourse = serverCached
                    TelemetryService.shared.recordCoursePlayed(courseName: serverCached.name)
                    isIngesting = false

                    // Update search result with server-corrected city/state
                    // (server cache uses Google Places validation, more accurate than Nominatim)
                    if let idx = searchResults.firstIndex(where: { $0.name == result.name }) {
                        if let city = serverCached.city { searchResults[idx].city = city }
                        if let state = serverCached.state { searchResults[idx].state = state }
                    }

                    // If server-cached course is missing tee data, enrich in background
                    let golfApiKey = {
                        let profileKey = profileStore?.profile.golfCourseApiKey ?? ""
                        return profileKey.isEmpty ? (Secrets.golfCourseApiKey ?? "") : profileKey
                    }()
                    let needsEnrichment = serverCached.teeNames == nil && !serverCached.holes.isEmpty && !golfApiKey.isEmpty
                    if needsEnrichment {
                        LoggingService.shared.info(.map, "server_cache_re_enriching", metadata: [
                            "courseName": result.name,
                        ])
                        let courseName = result.name
                        Task {
                            let enriched = await self.enrichWithScorecardData(
                                courses: [serverCached], courseName: courseName, apiKey: golfApiKey
                            )
                            if let course = enriched.first {
                                self.cacheService?.save(course)
                                self.selectedCourse = course
                                // Update server cache with enriched version
                                if Secrets.courseCacheEndpoint != nil {
                                    do {
                                        try await CourseCacheAPIClient.putCourse(course)
                                        LoggingService.shared.info(.map, "server_cache_upload", metadata: [
                                            "courseName": course.name, "courseId": course.id, "source": "server_re_enrich",
                                        ])
                                    } catch {
                                        LoggingService.shared.warning(.map, "server_cache_upload_error", metadata: [
                                            "courseName": course.name, "courseId": course.id, "error": error.localizedDescription, "source": "server_re_enrich",
                                        ])
                                    }
                                }
                            }
                        }
                    }
                    return
                }
                LoggingService.shared.info(.map, "server_cache_check", metadata: [
                    "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - serverStart) * 1000))",
                    "courseName": result.name, "cacheHit": "false",
                ])
            } catch is CancellationError {
                isIngesting = false
                return
            } catch {
                // Server cache failure is non-fatal — fall through to Overpass
                LoggingService.shared.warning(.map, "server_cache_error", metadata: [
                    "courseName": result.name, "error": error.localizedDescription,
                ])
            }
        }

        guard let bbox = result.boundingBox else {
            ingestionError = "No bounding box available for this course."
            isIngesting = false
            return
        }

        do {
            // Step 1: Fetch features from Overpass
            ingestionStep = "Fetching course features…"
            var stepStart = CFAbsoluteTimeGetCurrent()
            var response = try await OverpassClient.fetchCourseFeatures(boundingBox: bbox)
            try Task.checkCancellation()
            LoggingService.shared.info(.map, "overpass_fetch", metadata: [
                "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))",
                "courseName": result.name,
            ])

            // Step 2: Parse OSM data
            ingestionStep = "Parsing geometry…"
            stepStart = CFAbsoluteTimeGetCurrent()
            var parsed = OSMParser.parse(response)
            try Task.checkCancellation()
            LoggingService.shared.info(.map, "osm_parse", metadata: [
                "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))",
                "courseName": result.name,
            ])

            // Step 2b: If we got a suspiciously low hole count from a synthetic
            // (MapKit) bbox, retry with a wider search area. The centroid-based
            // bbox can miss peripheral holes on courses that extend far from center.
            if parsed.holeLines.count >= 9 && parsed.holeLines.count < 18
                && result.source == .appleMapKit {
                let widerBbox = bbox.buffered(by: 0.008) // ~900m extra each side
                LoggingService.shared.info(.map, "bbox_expand_retry", metadata: [
                    "courseName": result.name,
                    "initialHoles": "\(parsed.holeLines.count)",
                ])
                ingestionStep = "Expanding search area…"
                stepStart = CFAbsoluteTimeGetCurrent()
                let widerResponse = try await OverpassClient.fetchCourseFeatures(boundingBox: widerBbox)
                try Task.checkCancellation()
                let widerParsed = OSMParser.parse(widerResponse)
                if widerParsed.holeLines.count > parsed.holeLines.count {
                    response = widerResponse
                    parsed = widerParsed
                    LoggingService.shared.info(.map, "bbox_expand_success", metadata: [
                        "courseName": result.name,
                        "expandedHoles": "\(widerParsed.holeLines.count)",
                        "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))",
                    ])
                }
            }

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

            // Step 4: Cache geometry-only courses immediately so the map can display
            ingestionStep = "Saving to cache…"
            stepStart = CFAbsoluteTimeGetCurrent()
            for course in courses {
                cacheService?.save(course)
            }
            LoggingService.shared.info(.map, "cache_save", metadata: [
                "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))",
                "courseName": result.name,
            ])

            // Step 5: Display the course immediately (geometry + pars from OSM)
            if courses.count > 1 {
                availableSubCourses = courses
                showSubCoursePicker = true
                adCompleted = true
                isIngesting = false
            } else if let course = courses.first {
                var warning: String?
                if course.holes.isEmpty {
                    warning = "This course hasn't been mapped in OpenStreetMap yet. The satellite map will show the area, but hole layouts, greens, and hazards aren't available."
                } else if course.stats.overallConfidence < 0.3 {
                    warning = "This course has limited map data. Some holes, greens, or hazards may be missing."
                }

                if isShowingInterstitialAd {
                    pendingCourse = course
                    pendingWarning = warning
                    ingestionCompleted = true
                    completeTransitionIfReady()
                } else {
                    if let warning { ingestionWarning = warning }
                    selectedCourse = course
                    TelemetryService.shared.recordCoursePlayed(courseName: course.name)
                    isIngesting = false
                }
            } else {
                isIngesting = false
            }

            // Step 6: Enrich with scorecard data in background (non-blocking)
            let golfApiKey = {
                let profileKey = profileStore?.profile.golfCourseApiKey ?? ""
                return profileKey.isEmpty ? (Secrets.golfCourseApiKey ?? "") : profileKey
            }()
            if !golfApiKey.isEmpty {
                let coursesToEnrich = courses
                let courseName = result.name
                Task {
                    let enrichStart = CFAbsoluteTimeGetCurrent()
                    let enrichedCourses = await self.enrichWithScorecardData(
                        courses: coursesToEnrich, courseName: courseName, apiKey: golfApiKey
                    )
                    LoggingService.shared.info(.map, "scorecard_fetch", metadata: [
                        "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - enrichStart) * 1000))",
                        "courseName": courseName,
                    ])

                    // Update cache and displayed course with enriched data
                    for course in enrichedCourses {
                        self.cacheService?.save(course)
                    }
                    if enrichedCourses.count == 1, let enriched = enrichedCourses.first {
                        LoggingService.shared.info(.map, "enrich_applying", metadata: [
                            "courseName": enriched.name,
                            "teeNames": (enriched.teeNames ?? []).joined(separator: ","),
                            "totalPar": "\(enriched.totalPar ?? -1)",
                        ])
                        self.selectedCourse = enriched
                    } else if enrichedCourses.count > 1 {
                        self.availableSubCourses = enrichedCourses
                    }

                    // Upload enriched versions to server cache
                    if Secrets.courseCacheEndpoint != nil {
                        for course in enrichedCourses {
                            Task {
                                do {
                                    try await CourseCacheAPIClient.putCourse(course)
                                    LoggingService.shared.info(.map, "server_cache_upload", metadata: [
                                        "courseName": course.name, "courseId": course.id,
                                    ])
                                } catch {
                                    LoggingService.shared.warning(.map, "server_cache_upload_error", metadata: [
                                        "courseName": course.name, "error": error.localizedDescription,
                                    ])
                                }
                            }
                        }
                    }
                }
            } else {
                // No API key — still upload geometry-only courses to server cache
                if Secrets.courseCacheEndpoint != nil {
                    for course in courses {
                        Task {
                            do {
                                try await CourseCacheAPIClient.putCourse(course)
                            } catch {
                                LoggingService.shared.warning(.map, "server_cache_upload_error", metadata: [
                                    "courseName": course.name, "error": error.localizedDescription,
                                ])
                            }
                        }
                    }
                }
            }

            // Log total ingestion time (geometry-ready, enrichment may still be in progress)
            LoggingService.shared.info(.map, "total_ingestion", metadata: [
                "latencyMs": "\(Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000))",
                "courseName": result.name,
                "holeCount": "\(courses.first?.holes.count ?? 0)",
            ])
            return
        } catch is CancellationError {
            // User cancelled — reset silently
        } catch {
            ingestionError = error.localizedDescription
            LoggingService.shared.error(.course, "Course ingestion failed: \(error.localizedDescription)")
            isShowingInterstitialAd = false
        }

        isIngesting = false
    }

    /// Starts ingestion in a trackable, cancellable task.
    func startIngestion(_ result: CourseSearchResult, forceRefresh: Bool = false) {
        ingestionTask?.cancel()
        // Reset dual-gate state
        adCompleted = true
        ingestionCompleted = false
        pendingCourse = nil
        pendingWarning = nil
        isShowingInterstitialAd = false
        ingestionTask = Task { await ingestCourse(result, forceRefresh: forceRefresh) }
    }

    /// Cancels any in-progress ingestion.
    func cancelIngestion() {
        ingestionTask?.cancel()
        ingestionTask = nil
        isIngesting = false
        ingestionStep = ""
        isShowingInterstitialAd = false
        adCompleted = true
        ingestionCompleted = false
        pendingCourse = nil
        pendingWarning = nil
    }

    // MARK: - Interstitial Ad Coordination

    /// Called when the interstitial ad is about to be presented.
    /// Sets the dual-gate: ingestion must also complete before transitioning.
    func willShowInterstitialAd() {
        adCompleted = false
        ingestionCompleted = false
        isShowingInterstitialAd = true
    }

    /// Called when the interstitial ad finishes (dismissed by user or completed).
    func didCompleteInterstitialAd() {
        adCompleted = true
        isShowingInterstitialAd = false
        TelemetryService.shared.recordInterstitialCompleted()
        completeTransitionIfReady()
    }

    /// Transitions to the course map when both ad and ingestion are done.
    private func completeTransitionIfReady() {
        guard adCompleted, ingestionCompleted, let course = pendingCourse else { return }

        if let warning = pendingWarning {
            ingestionWarning = warning
        }
        selectedCourse = course
        TelemetryService.shared.recordCoursePlayed(courseName: course.name)
        isIngesting = false

        // Clean up
        pendingCourse = nil
        pendingWarning = nil
        ingestionCompleted = false
    }

    // MARK: - Load from Cache

    func loadCachedCourse(id: String) {
        guard let course = cacheService?.load(id: id) else { return }

        // Display the course immediately regardless of enrichment status
        selectedCourse = course
        selectedTee = cacheService?.selectedTee(forCourse: id)
        TelemetryService.shared.recordCoursePlayed(courseName: course.name)

        // If missing tee/yardage data, enrich in background without blocking the UI
        let golfApiKey = {
            let profileKey = profileStore?.profile.golfCourseApiKey ?? ""
            return profileKey.isEmpty ? (Secrets.golfCourseApiKey ?? "") : profileKey
        }()
        if course.teeNames == nil && !course.holes.isEmpty && !golfApiKey.isEmpty {
            Task {
                let enriched = await self.enrichWithScorecardData(
                    courses: [course], courseName: course.name, apiKey: golfApiKey
                )
                if let updated = enriched.first {
                    self.cacheService?.save(updated)
                    self.selectedCourse = updated
                }
            }
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

    // MARK: - Tee Preference Matching

    /// Matches the user's tee preference against available course tees using keyword matching.
    /// If no exact tier match is found, walks to the next-closest tier (shorter first, then longer).
    static func bestTeeForPreference(
        _ preference: TeeBoxPreference,
        from dedupedTees: [(displayName: String, canonicalTee: String)]
    ) -> String? {
        let allTiers = TeeBoxPreference.allCases.sorted { $0.rawValue < $1.rawValue }
        let startIndex = preference.rawValue

        // Build search order: preferred tier first, then alternate shorter/longer
        var searchOrder: [TeeBoxPreference] = [preference]
        for offset in 1..<allTiers.count {
            let shorter = startIndex + offset
            let longer = startIndex - offset
            if shorter < allTiers.count { searchOrder.append(allTiers[shorter]) }
            if longer >= 0 { searchOrder.append(allTiers[longer]) }
        }

        for tier in searchOrder {
            for entry in dedupedTees {
                let name = entry.displayName.lowercased()
                if tier.matchKeywords.contains(where: { name.contains($0) }) {
                    return entry.canonicalTee
                }
            }
        }
        return nil
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
            // Weather is optional — log but don't fail
            LoggingService.shared.warning(.map, "weather_fetch_error", metadata: [
                "courseName": course.name,
                "error": "\(error)",
            ])
        }
    }

    // MARK: - Background Download

    /// Returns the current download state for a search result.
    func downloadState(for result: CourseSearchResult) -> CourseDownloadState {
        let courseId = NormalizedCourse.generateId(name: result.name, centroid: result.centroid)
        if result.isCached || downloadedCourseIDs.contains(courseId) { return .cached }
        if let progress = downloadProgress[courseId] { return .downloading(progress: progress) }
        if downloadErrorCourseIDs.contains(courseId) { return .error }
        return .notDownloaded
    }

    /// Downloads a course in the background without navigating away.
    func downloadCourseInBackground(_ result: CourseSearchResult) {
        let courseId = NormalizedCourse.generateId(name: result.name, centroid: result.centroid)
        guard downloadProgress[courseId] == nil,
              !downloadedCourseIDs.contains(courseId) else { return }

        downloadProgress[courseId] = 0.0
        downloadErrorCourseIDs.remove(courseId)

        downloadTasks[courseId] = Task {
            do {
                let _ = try await fetchAndCacheCourse(result) { progress in
                    self.downloadProgress[courseId] = progress
                }
                downloadProgress.removeValue(forKey: courseId)
                downloadedCourseIDs.insert(courseId)
                if let idx = searchResults.firstIndex(where: { $0.id == result.id }) {
                    searchResults[idx].isCached = true
                }
            } catch {
                downloadProgress.removeValue(forKey: courseId)
                downloadErrorCourseIDs.insert(courseId)
                LoggingService.shared.error(.map, "background_download_error", metadata: [
                    "courseId": courseId,
                    "courseName": result.name,
                    "error": "\(error)",
                ])
            }
            downloadTasks.removeValue(forKey: courseId)
        }
    }

    /// Runs the full ingestion pipeline (cache → server cache → Overpass → parse → normalize → save → enrich)
    /// without touching any UI navigation state. Returns the cached/ingested courses.
    /// Progress steps: cache check (0.05) → server cache (0.15) → Overpass fetch (0.50) → parse (0.65) → normalize (0.75) → save (0.85) → enrich (1.0)
    private func fetchAndCacheCourse(
        _ result: CourseSearchResult,
        forceRefresh: Bool = false,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> [NormalizedCourse] {
        // Check local cache first
        onProgress?(0.05)
        let courseId = NormalizedCourse.generateId(name: result.name, centroid: result.centroid)
        if !forceRefresh, let cached = cacheService?.load(id: courseId) {
            let holeCount = cached.holes.count
            // If full 18 (or close), return immediately
            if !(holeCount >= 9 && holeCount < 18) {
                onProgress?(1.0)
                return [cached]
            }
            // Otherwise fall through to re-ingest for incomplete courses
        }

        // Check server cache
        onProgress?(0.10)
        if Secrets.courseCacheEndpoint != nil {
            do {
                if let serverCached = try await CourseCacheAPIClient.searchCourse(
                    query: result.name,
                    latitude: result.centroid.latitude,
                    longitude: result.centroid.longitude
                ) {
                    cacheService?.save(serverCached)
                    onProgress?(1.0)
                    return [serverCached]
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Server cache failure is non-fatal — log for diagnostics
                LoggingService.shared.warning(.map, "server_cache_get_error", metadata: [
                    "courseId": courseId,
                    "courseName": result.name,
                    "error": "\(error)",
                ])
            }
        }

        guard let bbox = result.boundingBox else {
            throw NSError(domain: "CourseViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No bounding box available for this course."])
        }

        // Fetch from Overpass
        onProgress?(0.15)
        var response = try await OverpassClient.fetchCourseFeatures(boundingBox: bbox)
        try Task.checkCancellation()
        onProgress?(0.50)

        var parsed = OSMParser.parse(response)
        try Task.checkCancellation()
        onProgress?(0.60)

        // Retry with wider bbox if incomplete holes from MapKit source
        if parsed.holeLines.count >= 9 && parsed.holeLines.count < 18
            && result.source == .appleMapKit {
            let widerBbox = bbox.buffered(by: 0.008)
            let widerResponse = try await OverpassClient.fetchCourseFeatures(boundingBox: widerBbox)
            try Task.checkCancellation()
            let widerParsed = OSMParser.parse(widerResponse)
            if widerParsed.holeLines.count > parsed.holeLines.count {
                response = widerResponse
                parsed = widerParsed
            }
        }
        onProgress?(0.65)

        // Normalize
        let courses = CourseNormalizer.normalizeAll(
            features: parsed,
            courseName: result.name,
            osmCourseId: result.id,
            city: result.city,
            state: result.state
        )
        try Task.checkCancellation()
        onProgress?(0.75)

        // Cache locally
        for course in courses {
            cacheService?.save(course)
        }
        onProgress?(0.85)

        // Enrich with scorecard data
        let golfApiKey = {
            let profileKey = profileStore?.profile.golfCourseApiKey ?? ""
            return profileKey.isEmpty ? (Secrets.golfCourseApiKey ?? "") : profileKey
        }()
        var finalCourses = courses
        if !golfApiKey.isEmpty {
            let enriched = await enrichWithScorecardData(
                courses: courses, courseName: result.name, apiKey: golfApiKey
            )
            for course in enriched {
                cacheService?.save(course)
            }
            finalCourses = enriched
        }
        onProgress?(1.0)

        // Upload to server cache
        if Secrets.courseCacheEndpoint != nil {
            for course in finalCourses {
                Task {
                    do {
                        try await CourseCacheAPIClient.putCourse(course)
                        LoggingService.shared.info(.map, "server_cache_upload", metadata: [
                            "courseId": course.id,
                            "courseName": course.name,
                            "holeCount": "\(course.holes.count)",
                        ])
                    } catch {
                        LoggingService.shared.error(.map, "server_cache_upload_error", metadata: [
                            "courseId": course.id,
                            "courseName": course.name,
                            "error": "\(error)",
                        ])
                    }
                }
            }
        }

        return finalCourses
    }

    // MARK: - Scorecard Enrichment

    /// Strips common suffixes that the Golf Course API doesn't handle well.
    /// e.g. "Sharp Park Golf Course" → "Sharp Park", "Pebble Beach Golf Links" → "Pebble Beach"
    private static let golfNameSuffixes = [
        "Golf Course", "Golf Club", "Country Club", "Golf Links",
        "Golf & Country Club", "Golf and Country Club",
        "Municipal Golf Course", "Public Golf Course",
    ]

    private func enrichWithScorecardData(courses: [NormalizedCourse], courseName: String, apiKey: String) async -> [NormalizedCourse] {
        // Check rate limit before making Golf API calls
        if let store = apiUsageStore, !store.canMakeGolfAPICall {
            LoggingService.shared.warning(.map, "enrich_rate_limited", metadata: ["courseName": courseName])
            return courses
        }

        do {
            // Search returns summary data; fetch full detail for tee/hole info
            LoggingService.shared.info(.map, "enrich_searching", metadata: ["courseName": courseName, "apiKeyPrefix": String(apiKey.prefix(4))])
            var results = try await GolfCourseAPIClient.searchCourses(name: courseName, apiKey: apiKey)
            apiUsageStore?.recordGolfAPICall(method: "searchCourses")
            TelemetryService.shared.recordGolfAPICall(method: "searchCourses")
            LoggingService.shared.info(.map, "enrich_search_results", metadata: ["courseName": courseName, "count": "\(results.count)"])

            // If no results, retry with common suffixes stripped
            // (e.g. "Sharp Park Golf Course" → "Sharp Park")
            if results.isEmpty {
                var stripped = Self.golfNameSuffixes.reduce(courseName) { name, suffix in
                    name.replacingOccurrences(of: suffix, with: "", options: .caseInsensitive)
                }.trimmingCharacters(in: .whitespaces)
                // Also strip trailing digits that Nominatim sometimes concatenates
                // (e.g. "Sharp Park 50" → "Sharp Park")
                while let last = stripped.last, last.isNumber {
                    stripped.removeLast()
                }
                stripped = stripped.trimmingCharacters(in: .whitespaces)

                if !stripped.isEmpty && stripped != courseName {
                    LoggingService.shared.info(.map, "enrich_retry_stripped", metadata: ["original": courseName, "stripped": stripped])
                    results = try await GolfCourseAPIClient.searchCourses(name: stripped, apiKey: apiKey)
                    apiUsageStore?.recordGolfAPICall(method: "searchCourses")
                    TelemetryService.shared.recordGolfAPICall(method: "searchCourses")
                    LoggingService.shared.info(.map, "enrich_retry_results", metadata: ["stripped": stripped, "count": "\(results.count)"])
                }
            }

            guard let bestMatch = results.first else {
                LoggingService.shared.warning(.map, "enrich_no_match", metadata: ["courseName": courseName])
                return courses
            }

            // The search result may have tees already, but fetch detail to be sure
            let detail = try await GolfCourseAPIClient.getCourse(id: bestMatch.id, apiKey: apiKey)
            apiUsageStore?.recordGolfAPICall(method: "getCourse")
            TelemetryService.shared.recordGolfAPICall(method: "getCourse")
            let courseData = detail ?? bestMatch

            let scorecard = courseData.extractScorecardData()
            LoggingService.shared.info(.map, "enrich_scorecard", metadata: [
                "courseName": courseName,
                "totalPar": "\(scorecard.totalPar ?? 0)",
                "teeCount": "\(scorecard.teeBoxInfos.count)",
                "teeNames": scorecard.teeBoxInfos.map(\.name).joined(separator: ","),
                "isEmpty": "\(scorecard.isEmpty)",
            ])
            guard !scorecard.isEmpty else { return courses }

            return courses.map { course in
                var enriched = course

                // Course-level metadata
                enriched.totalPar = scorecard.totalPar
                // Use all tee box names (not just those with per-hole yardage)
                let allTeeNames = Set(
                    scorecard.teeBoxInfos.map(\.name) + Array(scorecard.teeYardages.keys)
                )
                enriched.teeNames = allTeeNames.sorted()

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
            LoggingService.shared.error(.map, "enrich_error", metadata: [
                "courseName": courseName,
                "error": "\(error)",
            ])
            return courses
        }
    }
}

// MARK: - Download State

enum CourseDownloadState {
    case notDownloaded
    case downloading(progress: Double)
    case cached
    case error
}
