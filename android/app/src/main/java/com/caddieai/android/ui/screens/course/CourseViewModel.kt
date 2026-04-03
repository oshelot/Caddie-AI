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
import com.caddieai.android.data.course.PlacesSuggestion
import com.caddieai.android.data.model.NormalizedCourse
import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.store.ActiveRoundStore
import com.caddieai.android.data.store.ProfileStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
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
            val profile = profileStore.getProfile()
            val suggestions = if (profile.googleApiKey.isNotBlank()) {
                placesClient.autocompleteCity(location, profile.googleApiKey)
                    .map { it.mainText + if (it.secondaryText.isNotBlank()) ", ${it.secondaryText}" else "" }
            } else {
                nominatimClient.searchCities(location)
            }
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
            _state.update { it.copy(isSearching = true, nominatimResults = emptyList()) }
            val location = _state.value.locationQuery.trim()
            val fullQuery = if (location.isNotBlank()) "$courseName $location" else courseName
            val results = nominatimClient.searchGolfCourses(fullQuery)
            _state.update { it.copy(isSearching = false, nominatimResults = results) }
        }
    }

    fun selectAndIngestCourse(result: NominatimResult) {
        viewModelScope.launch {
            // Use cache only if tee data is already present; otherwise re-ingest to fetch full detail
            val existingId = result.osm_id.toString()
            val cacheStart = System.currentTimeMillis()
            val cached = cacheService.getCourse(existingId)
            val cacheMs = System.currentTimeMillis() - cacheStart
            val cacheHit = cached != null && cached.teeNames.isNotEmpty()
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

            ingestCourse(result)
        }
    }

    private suspend fun ingestCourse(result: NominatimResult) {
        val profile = profileStore.getProfile()
        val ingestionStart = System.currentTimeMillis()
        val courseName = result.name.ifBlank { result.display_name.substringBefore(",") }

        // Step 1: Fetch scorecard
        _state.update { it.copy(ingestionState = IngestionState.InProgress(IngestionStep.FETCHING_SCORECARD, 0.1f)) }
        val scorecardStart = System.currentTimeMillis()
        val scorecard = if (com.caddieai.android.BuildConfig.GOLF_COURSE_API_KEY.isNotBlank()) {
            val apiKey = com.caddieai.android.BuildConfig.GOLF_COURSE_API_KEY
            val searchResult = golfApiClient.searchCourses(result.display_name, apiKey).firstOrNull()
            android.util.Log.d("CaddieAI/Tee", "search result: id='${searchResult?.id}' teeNames=${searchResult?.teeNames}")
            val detail = if (searchResult != null && searchResult.id.isNotBlank()) {
                golfApiClient.getCourse(searchResult.id, apiKey)
            } else null
            android.util.Log.d("CaddieAI/Tee", "detail result: id='${detail?.id}' teeNames=${detail?.teeNames}")
            detail ?: searchResult
        } else null
        android.util.Log.d("CaddieAI/Tee", "final scorecard: id='${scorecard?.id}' teeNames=${scorecard?.teeNames}")
        logger.log(LogLevel.INFO, LogCategory.MAP, "scorecard_fetch", mapOf(
            "latencyMs" to (System.currentTimeMillis() - scorecardStart).toString(),
            "courseName" to courseName,
        ))

        val fallbackScorecard = com.caddieai.android.data.course.CourseScorecard(
            id = result.osm_id.toString(),
            name = courseName,
            city = result.address["city"] ?: "",
            state = result.address["state"] ?: "",
            holes = (1..18).map {
                com.caddieai.android.data.course.HoleScorecard(number = it, par = 4, yardage = 400)
            }
        )
        val finalScorecard = scorecard ?: fallbackScorecard

        // Step 2: Fetch OSM geometry (osm_parse logged inside OverpassClient)
        _state.update { it.copy(ingestionState = IngestionState.InProgress(IngestionStep.FETCHING_GEOMETRY, 0.35f)) }
        val overpassStart = System.currentTimeMillis()
        val bbox = buildBbox(result.latitude, result.longitude, radiusDegrees = 0.02)
        val osmElements = overpassClient.fetchGolfCourseData(
            name = result.name,
            osmId = result.osm_id.takeIf { it > 0 },
            bbox = bbox,
        )
        logger.log(LogLevel.INFO, LogCategory.MAP, "overpass_fetch", mapOf(
            "latencyMs" to (System.currentTimeMillis() - overpassStart).toString(),
            "courseName" to courseName,
        ))

        // Step 3: Normalize
        _state.update { it.copy(ingestionState = IngestionState.InProgress(IngestionStep.NORMALIZING, 0.75f)) }
        val normalizeStart = System.currentTimeMillis()
        val course = normalizer.normalize(finalScorecard, osmElements)
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
        // If tee data is missing (pre-KAN-102 cache entry), fetch it in the background
        if (course.teeNames.isEmpty() && com.caddieai.android.BuildConfig.GOLF_COURSE_API_KEY.isNotBlank()) {
            viewModelScope.launch {
                val apiKey = com.caddieai.android.BuildConfig.GOLF_COURSE_API_KEY
                val detail = golfApiClient.searchCourses("${course.name} ${course.city}", apiKey)
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

    fun clearSelectedCourse() {
        _state.update { it.copy(selectedCourse = null, ingestionState = IngestionState.Idle) }
        activeRoundStore.setActiveCourse(null)
        activeRoundStore.setActiveHole(null)
    }

    fun dismissIngestion() {
        _state.update { it.copy(ingestionState = IngestionState.Idle) }
    }

    private fun buildBbox(lat: Double, lon: Double, radiusDegrees: Double): String {
        val s = lat - radiusDegrees
        val w = lon - radiusDegrees
        val n = lat + radiusDegrees
        val e = lon + radiusDegrees
        return "$s,$w,$n,$e"
    }
}
