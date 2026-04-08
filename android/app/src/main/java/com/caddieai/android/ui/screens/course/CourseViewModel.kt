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

            // Convert Golf API results to NominatimResult for the UI
            // Try to match each Golf API result with a Nominatim result (for OSM coordinates)
            val results = golfApiResults.map { scorecard ->
                // Find matching Nominatim result by fuzzy name
                val osmMatch = nominatimResults.firstOrNull { nom ->
                    nom.name.lowercase().contains(scorecard.name.lowercase().take(10)) ||
                        scorecard.name.lowercase().contains(nom.name.lowercase().take(10))
                }
                NominatimResult(
                    place_id = 0L,
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

            // Add any Nominatim golf courses not already in Golf API results
            val golfApiNames = golfApiResults.map { it.name.lowercase() }.toSet()
            val extraNominatim = nominatimResults.filter { nom ->
                golfApiNames.none { apiName ->
                    apiName.contains(nom.name.lowercase().take(10)) ||
                        nom.name.lowercase().contains(apiName.take(10))
                }
            }

            val merged = results + extraNominatim

            // Sort: location matches first, then by proximity or name relevance
            val sorted = if (location.isNotBlank()) {
                val locationLower = location.lowercase()
                val locationCity = locationLower.substringBefore(",").trim()
                // Geocode location for distance sorting
                val locCoords = mapboxGeocode(location)

                merged.sortedWith(compareBy<NominatimResult> { r ->
                    // Priority 1: city/state in display_name matches location
                    val displayLower = r.display_name.lowercase()
                    val cityMatch = r.address["city"]?.lowercase()?.contains(locationCity) == true
                    val stateMatch = r.address["state"]?.lowercase()?.let { locationLower.contains(it) } == true
                    val displayMatch = displayLower.contains(locationCity)
                    when {
                        cityMatch -> 0
                        displayMatch || stateMatch -> 1
                        else -> 2
                    }
                }.thenBy { r ->
                    // Priority 2: distance if we have coordinates
                    if (locCoords != null) {
                        val lat = r.lat.toDoubleOrNull() ?: 0.0
                        val lon = r.lon.toDoubleOrNull() ?: 0.0
                        if (lat != 0.0 || lon != 0.0) haversineKm(locCoords.first, locCoords.second, lat, lon)
                        else 9999.0
                    } else 0.0
                })
            } else merged

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
            // Use osm_id if available, otherwise generate stable ID from name+coords
            val existingId = if (result.osm_id > 0) result.osm_id.toString()
                else "mapbox_${result.name.lowercase().replace(" ", "_")}_${result.lat}_${result.lon}"
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

    private suspend fun ingestCourse(result: NominatimResult) = coroutineScope {
        val profile = profileStore.getProfile()
        val ingestionStart = System.currentTimeMillis()
        val courseName = result.name.ifBlank { result.display_name.substringBefore(",") }

        _state.update { it.copy(ingestionState = IngestionState.InProgress(IngestionStep.FETCHING_SCORECARD, 0.1f)) }

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

        val courseId = if (result.osm_id > 0) result.osm_id.toString()
            else "mapbox_${courseName.lowercase().replace(" ", "_")}_${result.lat}_${result.lon}"
        val fallbackScorecard = com.caddieai.android.data.course.CourseScorecard(
            id = courseId,
            name = courseName,
            city = result.address["city"] ?: "",
            state = result.address["state"] ?: "",
            holes = (1..18).map {
                com.caddieai.android.data.course.HoleScorecard(number = it, par = 4, yardage = 400)
            }
        )
        val finalScorecard = scorecard ?: fallbackScorecard

        _state.update { it.copy(ingestionState = IngestionState.InProgress(IngestionStep.FETCHING_GEOMETRY, 0.35f)) }
        var osmElements = overpassDeferred.await()
        logger.log(LogLevel.INFO, LogCategory.MAP, "overpass_fetch", mapOf(
            "latencyMs" to (System.currentTimeMillis() - overpassStart).toString(),
            "courseName" to courseName,
        ))

        // Step 3: Normalize
        _state.update { it.copy(ingestionState = IngestionState.InProgress(IngestionStep.NORMALIZING, 0.75f)) }
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
        }
        logger.log(LogLevel.INFO, LogCategory.MAP, "normalize", mapOf(
            "latencyMs" to (System.currentTimeMillis() - normalizeStart).toString(),
            "courseName" to courseName,
            "holeCount" to course.holes.size.toString(),
        ))

        // Step 4: Save to cache
        _state.update { it.copy(ingestionState = IngestionState.InProgress(IngestionStep.SAVING, 0.95f)) }
        val saveStart = System.currentTimeMillis()
        cacheService.saveCourse(course)
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

        _state.update { it.copy(
            selectedCourse = course,
            ingestionState = IngestionState.Success(course),
            cachedCourses = cacheService.listCachedCourses().mapNotNull { e -> cacheService.getCourse(e.id) },
        )}
        activeRoundStore.setActiveCourse(course)
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

    private fun buildBbox(lat: Double, lon: Double, radiusDegrees: Double): String {
        val s = lat - radiusDegrees
        val w = lon - radiusDegrees
        val n = lat + radiusDegrees
        val e = lon + radiusDegrees
        return "$s,$w,$n,$e"
    }
}
