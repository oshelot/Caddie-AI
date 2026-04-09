package com.caddieai.android.ui.screens.course

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.caddieai.android.data.course.CourseCacheService
import com.caddieai.android.data.course.CourseNormalizer
import com.caddieai.android.data.course.GolfCourseAPIClient
import com.caddieai.android.data.course.GooglePlacesClient
import com.caddieai.android.data.course.NominatimClient
import com.caddieai.android.data.course.NominatimResult
import com.caddieai.android.data.course.OverpassClient
import com.caddieai.android.data.course.ServerCacheClient
import com.caddieai.android.data.course.PlacesSuggestion
import com.caddieai.android.data.model.NormalizedCourse
import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.store.ActiveRoundStore
import com.caddieai.android.data.store.ProfileStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

private val US_STATES: Map<String, String> = mapOf(
    "alabama" to "AL", "alaska" to "AK", "arizona" to "AZ", "arkansas" to "AR",
    "california" to "CA", "colorado" to "CO", "connecticut" to "CT", "delaware" to "DE",
    "district of columbia" to "DC", "florida" to "FL", "georgia" to "GA", "hawaii" to "HI",
    "idaho" to "ID", "illinois" to "IL", "indiana" to "IN", "iowa" to "IA",
    "kansas" to "KS", "kentucky" to "KY", "louisiana" to "LA", "maine" to "ME",
    "maryland" to "MD", "massachusetts" to "MA", "michigan" to "MI", "minnesota" to "MN",
    "mississippi" to "MS", "missouri" to "MO", "montana" to "MT", "nebraska" to "NE",
    "nevada" to "NV", "new hampshire" to "NH", "new jersey" to "NJ", "new mexico" to "NM",
    "new york" to "NY", "north carolina" to "NC", "north dakota" to "ND", "ohio" to "OH",
    "oklahoma" to "OK", "oregon" to "OR", "pennsylvania" to "PA", "rhode island" to "RI",
    "south carolina" to "SC", "south dakota" to "SD", "tennessee" to "TN", "texas" to "TX",
    "utah" to "UT", "vermont" to "VT", "virginia" to "VA", "washington" to "WA",
    "west virginia" to "WV", "wisconsin" to "WI", "wyoming" to "WY",
)
private val US_STATE_CODES: Set<String> = US_STATES.values.map { it.lowercase() }.toSet()

sealed class DownloadState {
    data object NotStarted : DownloadState()
    data class Downloading(val progress: Float) : DownloadState()
    data object Complete : DownloadState()
    data object Error : DownloadState()
}

data class CourseSearchState(
    val courseName: String = "",
    val locationQuery: String = "",
    val locationSuggestions: List<String> = emptyList(),
    val isSearching: Boolean = false,
    val hasSearched: Boolean = false,
    val nominatimResults: List<NominatimResult> = emptyList(),
    val cachedCourses: List<NormalizedCourse> = emptyList(),
    val favoriteIds: Set<String> = emptySet(),
    val selectedCourse: NormalizedCourse? = null,
    val ingestionState: IngestionState = IngestionState.Idle,
    /** Per-course download state keyed by course ID (osm_id or mapbox_* synthetic ID). */
    val downloadStates: Map<String, DownloadState> = emptyMap(),
)

sealed class IngestionState {
    data object Idle : IngestionState()
    data class InProgress(val step: IngestionStep, val progress: Float) : IngestionState()
    data class Success(val course: NormalizedCourse) : IngestionState()
    data class Error(val message: String) : IngestionState()
}

enum class IngestionStep(val label: String) {
    FETCHING_SCORECARD("Fetching scorecard data…"),
    FETCHING_GEOMETRY("Fetching course geometry from OSM…"),
    NORMALIZING("Normalizing course data…"),
    SAVING("Saving to cache…"),
}

@HiltViewModel
class CourseViewModel @Inject constructor(
    private val profileStore: ProfileStore,
    private val nominatimClient: NominatimClient,
    private val placesClient: GooglePlacesClient,
    private val golfApiClient: GolfCourseAPIClient,
    private val overpassClient: OverpassClient,
    private val serverCacheClient: ServerCacheClient,
    private val normalizer: CourseNormalizer,
    private val cacheService: CourseCacheService,
    private val activeRoundStore: ActiveRoundStore,
    private val logger: DiagnosticLogger,
) : ViewModel() {

    private val _state = MutableStateFlow(CourseSearchState())
    val state: StateFlow<CourseSearchState> = _state.asStateFlow()

    private var searchJob: Job? = null
    private var locationJob: Job? = null

    init {
        loadCachedCourses()
    }

    private fun loadCachedCourses() {
        val cached = cacheService.listCachedCourses().mapNotNull { cacheService.getCourse(it.id) }
        val favorites = cacheService.getFavoriteIds()
        _state.update { it.copy(cachedCourses = cached, favoriteIds = favorites) }
    }

    fun onCourseNameChange(name: String) {
        _state.update { it.copy(courseName = name) }
    }

    fun onLocationQueryChange(location: String) {
        _state.update { it.copy(locationQuery = location, locationSuggestions = emptyList()) }
        locationJob?.cancel()
        if (location.length < 2) return
        locationJob = viewModelScope.launch {
            delay(300)
            val suggestions = mapboxCityAutocomplete(location)
            _state.update { it.copy(locationSuggestions = suggestions) }
        }
    }

    fun onLocationSelected(suggestion: String) {
        _state.update { it.copy(locationQuery = suggestion, locationSuggestions = emptyList()) }
    }

    fun search() {
        val courseName = _state.value.courseName.trim()
        if (courseName.isBlank()) return
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            try {
            _state.update { it.copy(isSearching = true, hasSearched = true, nominatimResults = emptyList()) }
            val location = _state.value.locationQuery.trim()
            val searchQuery = if (location.isNotBlank()) "$courseName $location" else courseName

            // Primary: Golf Course API — use just course name (location makes it too specific)
            val apiKey = com.caddieai.android.BuildConfig.GOLF_COURSE_API_KEY
            val golfApiResults = golfApiClient.searchCourses(courseName, apiKey)
            android.util.Log.d("CaddieAI/Search", "GolfAPI returned ${golfApiResults.size} results")

            // Secondary: Nominatim (for OSM coordinates)
            val nominatimResults = try { nominatimClient.searchGolfCourses(searchQuery) } catch (e: Exception) { emptyList() }
            android.util.Log.d("CaddieAI/Search", "Nominatim returned ${nominatimResults.size} results")

            // KAN-248: detect a US state code anywhere in the user's input
            // (course name OR location) and hard-filter by it. Also drop any
            // Golf API result outside the US (Nominatim already restricts via
            // countrycodes=us, so non-US results can only come from Golf API).
            val userCity = location.substringBefore(",").trim().lowercase()
            val detectedStateCode = detectUsStateCode("$courseName $location")
            val detectedStateName = detectedStateCode?.let { code ->
                US_STATES.entries.firstOrNull { it.value == code }?.key
            }

            fun nomCity(nom: NominatimResult) = (nom.address["city"]
                ?: nom.address["town"]
                ?: nom.address["village"]
                ?: nom.address["hamlet"]
                ?: "").lowercase()
            fun nomState(nom: NominatimResult) = (nom.address["state"] ?: "").lowercase()

            val filteredGolfApi = golfApiResults.filter { sc ->
                val isUs = sc.country.isBlank() ||
                    sc.country.equals("US", ignoreCase = true) ||
                    sc.country.equals("USA", ignoreCase = true) ||
                    sc.country.equals("United States", ignoreCase = true)
                if (!isUs) return@filter false
                if (detectedStateCode == null) return@filter true
                val s = sc.state.lowercase()
                s == detectedStateCode.lowercase() ||
                    (detectedStateName != null && s == detectedStateName)
            }

            val filteredNominatim = if (detectedStateCode != null) {
                nominatimResults.filter { nom ->
                    val ns = nomState(nom)
                    val display = nom.display_name.lowercase()
                    (detectedStateName != null && (ns == detectedStateName ||
                        display.contains(", $detectedStateName,") ||
                        display.contains(", $detectedStateName "))) ||
                        ns == detectedStateCode.lowercase() ||
                        display.contains(", ${detectedStateCode.lowercase()},") ||
                        display.contains(", ${detectedStateCode.lowercase()} ")
                }
            } else nominatimResults

            // Convert Golf API results to NominatimResult for the UI.
            // Only pair with a Nominatim entry when city/state also agree — otherwise
            // we can graft a California course's coordinates onto a Texas course.
            val results = filteredGolfApi.map { scorecard ->
                val scName = scorecard.name.lowercase()
                val scCity = scorecard.city.lowercase()
                val scState = scorecard.state.lowercase()
                val osmMatch = filteredNominatim.firstOrNull { nom ->
                    val nName = nom.name.lowercase()
                    val nameOk = nName.isNotBlank() && (nName.contains(scName) || scName.contains(nName))
                    val nc = nomCity(nom)
                    val ns = nomState(nom)
                    val cityOk = scCity.isBlank() || nc.isBlank() || nc.contains(scCity) || scCity.contains(nc)
                    val stateOk = scState.isBlank() || ns.isBlank() || ns.contains(scState) || scState.contains(ns)
                    nameOk && cityOk && stateOk
                }
                NominatimResult(
                    // Use Golf API id as place_id so courseIdFor() can produce a unique
                    // ID even when there's no OSM match (prevents mass-download collision).
                    place_id = scorecard.id.toLongOrNull() ?: 0L,
                    osm_id = osmMatch?.osm_id ?: 0L,
                    osm_type = osmMatch?.osm_type ?: "",
                    display_name = "${scorecard.name}, ${scorecard.city}, ${scorecard.state}",
                    name = scorecard.name,
                    lat = osmMatch?.lat ?: "0",
                    lon = osmMatch?.lon ?: "0",
                    type = "golf_course",
                    address = mapOf("city" to scorecard.city, "state" to scorecard.state),
                )
            }

            // Dedup by full name + city only. State is excluded because Golf API uses
            // "CA" while Nominatim uses "California", which would cause false dupes.
            fun dedupKey(name: String, city: String) =
                "${name.lowercase().trim()}|${city.lowercase().trim()}"

            val usedKeys = results.map {
                dedupKey(it.name, it.address["city"] ?: "")
            }.toMutableSet()
            val extraNominatim = filteredNominatim.filter { nom ->
                val key = dedupKey(
                    nom.name.ifBlank { nom.display_name.substringBefore(",") },
                    nomCity(nom),
                )
                usedKeys.add(key)
            }

            val merged = results + extraNominatim

            // Hard distance gate: geocode the user's location once, drop any result
            // whose coordinates are >200km away. Results without coordinates fall back
            // to the city/state text match already applied upstream.
            val locCoords: Pair<Double, Double>? =
                if (location.isNotBlank()) mapboxGeocode(location) else null
            val maxKm = 200.0

            val distanceFiltered = if (locCoords != null) {
                merged.filter { r ->
                    val lat = r.lat.toDoubleOrNull() ?: 0.0
                    val lon = r.lon.toDoubleOrNull() ?: 0.0
                    if (lat != 0.0 || lon != 0.0) {
                        haversineKm(locCoords.first, locCoords.second, lat, lon) <= maxKm
                    } else {
                        // No coordinates — fall back to state/city text match.
                        // Already enforced by filteredGolfApi / filteredNominatim above,
                        // so this branch is a safety net.
                        val rs = (r.address["state"] ?: "").lowercase()
                        val display = r.display_name.lowercase()
                        val stateOk = detectedStateCode == null ||
                            rs == detectedStateCode.lowercase() ||
                            (detectedStateName != null && rs == detectedStateName) ||
                            display.contains(detectedStateCode.lowercase())
                        val cityOk = userCity.isBlank() || display.contains(userCity)
                        stateOk && cityOk
                    }
                }
            } else merged

            val sorted = if (locCoords != null) {
                distanceFiltered.sortedBy { r ->
                    val lat = r.lat.toDoubleOrNull() ?: 0.0
                    val lon = r.lon.toDoubleOrNull() ?: 0.0
                    if (lat != 0.0 || lon != 0.0)
                        haversineKm(locCoords.first, locCoords.second, lat, lon)
                    else 9999.0
                }
            } else distanceFiltered

            _state.update { it.copy(isSearching = false, nominatimResults = sorted) }
            } catch (e: Exception) {
                android.util.Log.e("CaddieAI/Search", "Search crashed: ${e.message}", e)
                _state.update { it.copy(isSearching = false) }
            }
        }
    }

    fun selectAndIngestCourse(result: NominatimResult) {
        viewModelScope.launch {
            // Use cache only if tee data is already present; otherwise re-ingest to fetch full detail
            val existingId = courseIdFor(result)
            val cacheStart = System.currentTimeMillis()
            val cached = cacheService.getCourse(existingId)
            val cacheMs = System.currentTimeMillis() - cacheStart
            // Cache is valid only if we have real tee data (not just fallback "Standard")
            // Also bypass cache if hole count is incomplete (9-17 holes — iOS KAN-212 parity)
            val cacheHit = cached != null && cached.teeNames.isNotEmpty() &&
                    !(cached.teeNames.size == 1 && cached.teeNames.first() == "Standard") &&
                    cached.holes.size !in 9..17
            logger.log(LogLevel.INFO, LogCategory.MAP, "cache_check", mapOf(
                "latencyMs" to cacheMs.toString(),
                "courseName" to result.name,
                "cacheHit" to cacheHit.toString(),
            ))
            if (cacheHit) {
                _state.update { it.copy(selectedCourse = cached!!, ingestionState = IngestionState.Success(cached)) }
                activeRoundStore.setActiveCourse(cached!!)
                return@launch
            }

            // On local miss: race server cache vs full ingestion pipeline
            // First result with valid data wins
            if (serverCacheClient.isEnabled) {
                val serverDeferred = async { serverCacheClient.getCourse(existingId) }
                val ingestionDeferred = async { ingestCourse(result) }

                val serverCached = serverDeferred.await()
                if (serverCached != null && serverCached.teeNames.isNotEmpty() &&
                    !(serverCached.teeNames.size == 1 && serverCached.teeNames.first() == "Standard") &&
                    serverCached.holes.size !in 9..17
                ) {
                    ingestionDeferred.cancel() // server cache won — cancel ingestion
                    cacheService.saveCourse(serverCached)
                    _state.update { it.copy(
                        selectedCourse = serverCached,
                        ingestionState = IngestionState.Success(serverCached),
                        cachedCourses = cacheService.listCachedCourses().mapNotNull { e -> cacheService.getCourse(e.id) },
                    )}
                    activeRoundStore.setActiveCourse(serverCached)
                    return@launch
                }
                // Server cache miss — let ingestion complete
                ingestionDeferred.await()
            } else {
                ingestCourse(result)
            }
        }
    }

    private suspend fun ingestCourse(
        result: NominatimResult,
        backgroundOnly: Boolean = false,
        onBackgroundProgress: ((Float) -> Unit)? = null,
    ) = coroutineScope {
        fun updateProgress(step: IngestionStep, progress: Float) {
            if (!backgroundOnly) {
                _state.update { it.copy(ingestionState = IngestionState.InProgress(step, progress)) }
            }
        }
        fun reportBg(p: Float) { onBackgroundProgress?.invoke(p) }
        val profile = profileStore.getProfile()
        val ingestionStart = System.currentTimeMillis()
        val courseName = result.name.ifBlank { result.display_name.substringBefore(",") }

        updateProgress(IngestionStep.FETCHING_SCORECARD, 0.1f)
        reportBg(0.15f) // starting Overpass fetch

        // Parallelize Overpass + Golf Course API calls (independent network requests)
        val overpassStart = System.currentTimeMillis()
        val bbox = buildBbox(result.latitude, result.longitude, radiusDegrees = 0.02)
        val overpassDeferred = async {
            overpassClient.fetchGolfCourseData(
                name = result.name,
                osmId = result.osm_id.takeIf { it > 0 },
                bbox = bbox,
            )
        }
        val scorecardDeferred = async {
            if (com.caddieai.android.BuildConfig.GOLF_COURSE_API_KEY.isNotBlank()) {
                val apiKey = com.caddieai.android.BuildConfig.GOLF_COURSE_API_KEY
                val searchResult = golfApiClient.searchCourses(courseName, apiKey).firstOrNull()
                // Skip detail call if search already has tee data
                if (searchResult != null && searchResult.teeNames.isNotEmpty() &&
                    searchResult.holeYardagesByTee.isNotEmpty()) {
                    searchResult
                } else {
                    val detail = if (searchResult != null && searchResult.id.isNotBlank()) {
                        golfApiClient.getCourse(searchResult.id, apiKey)
                    } else null
                    detail ?: searchResult
                }
            } else null
        }

        val scorecardStart = System.currentTimeMillis()
        val scorecard = scorecardDeferred.await()
        android.util.Log.d("CaddieAI/Tee", "scorecard: id='${scorecard?.id}' teeNames=${scorecard?.teeNames}")
        logger.log(LogLevel.INFO, LogCategory.MAP, "scorecard_fetch", mapOf(
            "latencyMs" to (System.currentTimeMillis() - scorecardStart).toString(),
            "courseName" to courseName,
        ))

        val courseId = courseIdFor(result)
        val fallbackScorecard = com.caddieai.android.data.course.CourseScorecard(
            id = courseId,
            name = courseName,
            city = result.address["city"] ?: "",
            state = result.address["state"] ?: "",
            holes = (1..18).map {
                com.caddieai.android.data.course.HoleScorecard(number = it, par = 4, yardage = 400)
            }
        )
        // Force the scorecard ID to match courseIdFor(result) so the ingested course
        // is cached under the same key that downloadStateFor / getCourse look up.
        // Otherwise a Golf API scorecard would save under its own int ID and cache
        // lookups by osm_id / golfapi_<id> / mapbox_... would miss.
        val finalScorecard = (scorecard ?: fallbackScorecard).copy(id = courseId)

        updateProgress(IngestionStep.FETCHING_GEOMETRY, 0.35f)
        var osmElements = overpassDeferred.await()
        reportBg(0.50f) // Overpass fetch complete
        logger.log(LogLevel.INFO, LogCategory.MAP, "overpass_fetch", mapOf(
            "latencyMs" to (System.currentTimeMillis() - overpassStart).toString(),
            "courseName" to courseName,
        ))
        reportBg(0.60f) // OSM parse complete

        // Step 3: Normalize
        updateProgress(IngestionStep.NORMALIZING, 0.75f)
        val normalizeStart = System.currentTimeMillis()
        var course = normalizer.normalize(finalScorecard, osmElements)

        // Retry with wider bbox if hole count is incomplete (9-17 holes — iOS KAN-212 parity)
        if (course.holes.size in 9..17) {
            logger.log(LogLevel.WARN, LogCategory.MAP, "overpass_retry_wider_bbox",
                mapOf("courseName" to courseName, "initialHoles" to course.holes.size))
            val widerBbox = buildBbox(result.latitude, result.longitude, radiusDegrees = 0.028)
            osmElements = overpassClient.fetchGolfCourseData(
                name = result.name,
                osmId = result.osm_id.takeIf { it > 0 },
                bbox = widerBbox,
            )
            course = normalizer.normalize(finalScorecard, osmElements)
            reportBg(0.65f) // bbox retry complete
        }
        logger.log(LogLevel.INFO, LogCategory.MAP, "normalize", mapOf(
            "latencyMs" to (System.currentTimeMillis() - normalizeStart).toString(),
            "courseName" to courseName,
            "holeCount" to course.holes.size.toString(),
        ))
        reportBg(0.75f) // Normalize complete

        // Reject courses with no usable map geometry. If Overpass failed or returned
        // nothing, the normalizer still emits 18 "holes" from the scorecard but every
        // teeBox/green/pin is null — the map screen can't render that, and saving it
        // would leave the download button permanently green pointing at garbage.
        val hasGeometry = course.holes.any { h ->
            h.teeBox != null || h.green != null || h.pin != null
        }
        if (!hasGeometry) {
            logger.log(LogLevel.ERROR, LogCategory.MAP, "ingestion_no_geometry",
                mapOf("courseName" to courseName, "osmElements" to osmElements.size.toString()))
            // Clear any stale cache entry so downloadStateFor() goes back to NotStarted.
            cacheService.deleteCourse(course.id)
            throw IllegalStateException("No OSM geometry returned for $courseName")
        }

        // Step 4: Save to cache
        updateProgress(IngestionStep.SAVING, 0.95f)
        val saveStart = System.currentTimeMillis()
        cacheService.saveCourse(course)
        reportBg(0.85f) // Saved to local cache
        logger.log(LogLevel.INFO, LogCategory.MAP, "cache_save", mapOf(
            "latencyMs" to (System.currentTimeMillis() - saveStart).toString(),
            "courseName" to courseName,
        ))

        // Fire-and-forget upload to server cache (only if course has complete data)
        if (course.holes.size !in 9..17 && course.teeNames.isNotEmpty()) {
            viewModelScope.launch { serverCacheClient.putCourse(course) }
        }

        logger.log(LogLevel.INFO, LogCategory.MAP, "total_ingestion", mapOf(
            "latencyMs" to (System.currentTimeMillis() - ingestionStart).toString(),
            "courseName" to courseName,
            "holeCount" to course.holes.size.toString(),
        ))

        reportBg(1.0f) // Enrichment complete

        if (backgroundOnly) {
            _state.update { it.copy(
                cachedCourses = cacheService.listCachedCourses().mapNotNull { e -> cacheService.getCourse(e.id) },
            )}
        } else {
            _state.update { it.copy(
                selectedCourse = course,
                ingestionState = IngestionState.Success(course),
                cachedCourses = cacheService.listCachedCourses().mapNotNull { e -> cacheService.getCourse(e.id) },
            )}
            activeRoundStore.setActiveCourse(course)
        }
    }

    /** Computes the stable course ID used for caching, matching selectAndIngestCourse logic. */
    fun courseIdFor(result: NominatimResult): String = when {
        result.osm_id > 0 -> result.osm_id.toString()
        // Golf API id is stashed in place_id by search() — unique per scorecard.
        result.place_id > 0 -> "golfapi_${result.place_id}"
        else -> "mapbox_${result.name.lowercase().replace(" ", "_")}_${result.lat}_${result.lon}"
    }

    /** Returns the current download state for a search result (checks cache). */
    fun downloadStateFor(result: NominatimResult): DownloadState {
        val id = courseIdFor(result)
        _state.value.downloadStates[id]?.let { return it }
        val cached = cacheService.getCourse(id)
        val isValid = cached != null && cached.teeNames.isNotEmpty() &&
            !(cached.teeNames.size == 1 && cached.teeNames.first() == "Standard") &&
            cached.holes.size !in 9..17
        return if (isValid) DownloadState.Complete else DownloadState.NotStarted
    }

    private fun setDownloadState(id: String, state: DownloadState) {
        _state.update { it.copy(downloadStates = it.downloadStates + (id to state)) }
    }

    /** Background download — ingests course without navigating. Does not set selectedCourse. */
    fun downloadCourse(result: NominatimResult) {
        val id = courseIdFor(result)
        // Skip if already in progress or complete
        val current = _state.value.downloadStates[id]
        if (current is DownloadState.Downloading || current is DownloadState.Complete) return

        // Skip if already validly cached — short-circuit to 1.0 / Complete
        if (downloadStateFor(result) is DownloadState.Complete) {
            setDownloadState(id, DownloadState.Complete)
            return
        }

        setDownloadState(id, DownloadState.Downloading(0.05f)) // local cache check
        viewModelScope.launch {
            try {
                ingestCourseInBackground(result) { progress ->
                    setDownloadState(id, DownloadState.Downloading(progress))
                }
                setDownloadState(id, DownloadState.Complete)
                _state.update { it.copy(
                    cachedCourses = cacheService.listCachedCourses().mapNotNull { e -> cacheService.getCourse(e.id) },
                )}
            } catch (e: Exception) {
                logger.log(LogLevel.ERROR, LogCategory.MAP, "course_download_failed",
                    mapOf("error" to (e.message ?: "unknown"), "courseName" to result.name))
                setDownloadState(id, DownloadState.Error)
            }
        }
    }

    /** Wraps ingestCourse in background-only mode — no navigation, no progress banner. */
    private suspend fun ingestCourseInBackground(
        result: NominatimResult,
        onProgress: (Float) -> Unit,
    ) {
        ingestCourse(result, backgroundOnly = true, onBackgroundProgress = onProgress)
    }

    fun toggleFavorite(courseId: String) {
        val isNowFavorite = cacheService.toggleFavorite(courseId)
        _state.update { it.copy(favoriteIds = cacheService.getFavoriteIds()) }
    }

    fun selectCachedCourse(course: NormalizedCourse) {
        _state.update { it.copy(selectedCourse = course, ingestionState = IngestionState.Success(course)) }
        activeRoundStore.setActiveCourse(course)
        // If tee data is missing or only fallback "Standard", fetch from Golf API
        val needsTeeRefresh = course.teeNames.isEmpty() ||
                (course.teeNames.size == 1 && course.teeNames.first() == "Standard")
        if (needsTeeRefresh && com.caddieai.android.BuildConfig.GOLF_COURSE_API_KEY.isNotBlank()) {
            viewModelScope.launch {
                val apiKey = com.caddieai.android.BuildConfig.GOLF_COURSE_API_KEY
                val detail = golfApiClient.searchCourses(course.name, apiKey)
                    .firstOrNull()
                    ?.id?.takeIf { it.isNotBlank() }
                    ?.let { golfApiClient.getCourse(it, apiKey) }
                android.util.Log.d("CaddieAI/Tee", "selectCachedCourse refresh: teeNames=${detail?.teeNames}")
                if (detail != null && detail.teeNames.isNotEmpty()) {
                    val updated = course.copy(
                        teeNames = detail.teeNames,
                        holeYardagesByTee = detail.holeYardagesByTee,
                    )
                    cacheService.saveCourse(updated)
                    _state.update { it.copy(selectedCourse = updated) }
                    activeRoundStore.setActiveCourse(updated)
                }
            }
        }
    }

    fun deleteCachedCourse(courseId: String) {
        cacheService.deleteCourse(courseId)
        _state.update { it.copy(
            cachedCourses = cacheService.listCachedCourses().mapNotNull { e -> cacheService.getCourse(e.id) },
        )}
    }

    fun clearSelectedCourse() {
        _state.update { it.copy(selectedCourse = null, ingestionState = IngestionState.Idle) }
        activeRoundStore.setActiveCourse(null)
        activeRoundStore.setActiveHole(null)
    }

    fun dismissIngestion() {
        _state.update { it.copy(ingestionState = IngestionState.Idle) }
    }

    private suspend fun mapboxCityAutocomplete(query: String): List<String> =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            try {
                val token = com.caddieai.android.BuildConfig.MAPBOX_API_KEY
                if (token.isBlank()) return@withContext emptyList()
                val url = "https://api.mapbox.com/geocoding/v5/mapbox.places/${java.net.URLEncoder.encode(query, "UTF-8")}.json" +
                        "?country=us&types=place&limit=5&access_token=$token"
                val request = okhttp3.Request.Builder().url(url).build()
                val body = overpassClient.let {
                    // Reuse the app's OkHttpClient via a simple call
                    okhttp3.OkHttpClient().newCall(request).execute().use { resp ->
                        if (!resp.isSuccessful) return@withContext emptyList()
                        resp.body?.string() ?: return@withContext emptyList()
                    }
                }
                val json = org.json.JSONObject(body)
                val features = json.getJSONArray("features")
                (0 until features.length()).map { features.getJSONObject(it).getString("place_name") }
            } catch (e: Exception) {
                emptyList()
            }
        }

    private suspend fun mapboxSearchGolfCourses(query: String): List<NominatimResult> =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            try {
                val token = com.caddieai.android.BuildConfig.MAPBOX_API_KEY
                if (token.isBlank()) return@withContext emptyList()
                val url = "https://api.mapbox.com/geocoding/v5/mapbox.places/${java.net.URLEncoder.encode(query, "UTF-8")}.json" +
                        "?country=us&limit=10&access_token=$token"
                val request = okhttp3.Request.Builder().url(url).build()
                val body = okhttp3.OkHttpClient().newCall(request).execute().use { resp ->
                    if (!resp.isSuccessful) return@withContext emptyList()
                    resp.body?.string() ?: return@withContext emptyList()
                }
                val json = org.json.JSONObject(body)
                val features = json.getJSONArray("features")
                (0 until features.length()).mapNotNull { i ->
                    val f = features.getJSONObject(i)
                    val center = f.getJSONArray("center")
                    val lon = center.getDouble(0)
                    val lat = center.getDouble(1)
                    val placeName = f.getString("place_name")
                    val name = f.optString("text", placeName.substringBefore(","))
                    NominatimResult(
                        place_id = 0L,
                        osm_id = 0L,
                        display_name = placeName,
                        name = name,
                        lat = lat.toString(),
                        lon = lon.toString(),
                        type = "golf_course",
                    )
                }
            } catch (e: Exception) {
                logger.log(LogLevel.ERROR, LogCategory.API, "mapbox_search_failed",
                    mapOf("error" to (e.message ?: "unknown")))
                emptyList()
            }
        }

    /** Geocode a location string to lat/lon using Mapbox. */
    private fun mapboxGeocode(location: String): Pair<Double, Double>? {
        return try {
            val token = com.caddieai.android.BuildConfig.MAPBOX_API_KEY
            if (token.isBlank()) return null
            val url = "https://api.mapbox.com/geocoding/v5/mapbox.places/${java.net.URLEncoder.encode(location, "UTF-8")}.json" +
                    "?country=us&types=place&limit=1&access_token=$token"
            val request = okhttp3.Request.Builder().url(url).build()
            val body = okhttp3.OkHttpClient().newCall(request).execute().use { resp ->
                if (!resp.isSuccessful) return null
                resp.body?.string() ?: return null
            }
            val features = org.json.JSONObject(body).getJSONArray("features")
            if (features.length() == 0) return null
            val center = features.getJSONObject(0).getJSONArray("center")
            Pair(center.getDouble(1), center.getDouble(0)) // lat, lon
        } catch (_: Exception) { null }
    }

    private fun haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6371.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2).let { it * it } +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLon / 2).let { it * it }
        return 2 * r * Math.asin(Math.sqrt(a))
    }

    /**
     * Detects a US state in free-form user text. Matches full state names first
     * (so "New York" wins before "NY"), then word-bounded 2-letter codes.
     * Returns the 2-letter code (uppercase) or null.
     */
    private fun detectUsStateCode(text: String): String? {
        if (text.isBlank()) return null
        val lower = " ${text.lowercase().replace(",", " ")} "
        // Full names — try longest first so "north carolina" matches before "carolina"
        for ((name, code) in US_STATES.entries.sortedByDescending { it.key.length }) {
            if (lower.contains(" $name ")) return code
        }
        // 2-letter codes — must be a standalone token to avoid matching "co" inside "country"
        val tokens = text.lowercase().split(Regex("[\\s,]+")).filter { it.isNotBlank() }
        for (token in tokens) {
            if (token.length == 2 && US_STATE_CODES.contains(token)) return token.uppercase()
        }
        return null
    }

    private fun buildBbox(lat: Double, lon: Double, radiusDegrees: Double): String {
        val s = lat - radiusDegrees
        val w = lon - radiusDegrees
        val n = lat + radiusDegrees
        val e = lon + radiusDegrees
        return "$s,$w,$n,$e"
    }
}
