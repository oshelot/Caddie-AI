package com.caddieai.android.data.course

import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
data class CourseScorecard(
    val id: String,
    val name: String,
    val city: String = "",
    val state: String = "",
    val country: String = "US",
    val holes: List<HoleScorecard> = emptyList(),
    val courseRating: Float = 72.0f,
    val slopeRating: Int = 113,
    val par: Int = 72,
    val teeNames: List<String> = emptyList(),
    // Outer key: tee name, inner key: hole number as string, value: yardage
    val holeYardagesByTee: Map<String, Map<String, Int>> = emptyMap(),
)

@Serializable
data class HoleScorecard(
    val number: Int,
    val par: Int,
    val yardage: Int,
    val handicapIndex: Int = 0,
)

/**
 * Client for the Golf Course API (golfcourseapi.com).
 * Fetches scorecard data including par, yardages, slope/course rating.
 *
 * API docs: https://golfcourseapi.com/
 * Note: Requires a valid API key in player profile.
 */
@Singleton
class GolfCourseAPIClient @Inject constructor(
    private val httpClient: OkHttpClient,
    private val logger: DiagnosticLogger,
) {
    companion object {
        private const val BASE_URL = "https://api.golfcourseapi.com/v1"
        private val lenientJson = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }
    }

    /** Search for a course by name. Returns a list of matching courses. */
    suspend fun searchCourses(query: String, apiKey: String): List<CourseScorecard> {
        if (apiKey.isBlank()) return emptyList()
        return withContext(Dispatchers.IO) {
            try {
                logger.log(LogLevel.INFO, LogCategory.API, "golf_api_search", mapOf("query_len" to query.length))
                val url = "$BASE_URL/search?search_query=${query.urlEncode()}"
                val request = Request.Builder()
                    .url(url)
                    .addHeader("Authorization", "Key $apiKey")
                    .build()

                val response = httpClient.newCall(request).execute()
                val code = response.code
                val body = response.body?.string() ?: ""
                response.close()
                if (code != 200 || body.isBlank()) {
                    logger.log(LogLevel.WARN, LogCategory.API, "golf_api_search_failed", mapOf("status" to code))
                    return@withContext emptyList()
                }

                val results = lenientJson.decodeFromString<GolfAPISearchResponse>(body).courses.map { it.toScorecard() }
                android.util.Log.d("CaddieAI/GolfAPI", "Parsed ${results.size} results: ${results.map { it.name }}")
                logger.log(LogLevel.INFO, LogCategory.API, "golf_api_search_success", mapOf("result_count" to results.size))
                results
            } catch (e: Exception) {
                android.util.Log.e("CaddieAI/GolfAPI", "Search failed: ${e.message}", e)
                emptyList()
            }
        }
    }

    /** Fetch detailed scorecard for a course by its ID. */
    suspend fun getCourse(courseId: String, apiKey: String): CourseScorecard? {
        if (apiKey.isBlank()) return null
        return withContext(Dispatchers.IO) { runCatching {
            logger.log(LogLevel.INFO, LogCategory.API, "golf_api_get_course")
            val url = "$BASE_URL/courses/$courseId"
            val request = Request.Builder()
                .url(url)
                .addHeader("Authorization", "Key $apiKey")
                .build()

            val response = httpClient.newCall(request).execute()
            val code = response.code
            val body = response.body?.string() ?: ""
            response.close()
            if (code == 404) {
                logger.log(LogLevel.WARN, LogCategory.API, "golf_api_course_not_found")
                return@runCatching null
            }
            if (code != 200 || body.isBlank()) {
                logger.log(LogLevel.ERROR, LogCategory.API, "golf_api_get_failed", mapOf("status" to code))
                return@runCatching null
            }

            val scorecard = lenientJson.decodeFromString<GolfAPICourseDetailResponse>(body).course.toScorecard()
            logger.log(LogLevel.INFO, LogCategory.API, "golf_api_get_success", mapOf("tee_count" to scorecard.teeNames.size))
            scorecard
        }.getOrNull() }
    }

    private fun String.urlEncode(): String = java.net.URLEncoder.encode(this, "UTF-8")
}

@Serializable
private data class GolfAPISearchResponse(
    val courses: List<GolfAPIDetailResponse> = emptyList(),
)

@Serializable
private data class GolfAPICourseDetailResponse(
    val course: GolfAPIDetailResponse = GolfAPIDetailResponse(),
)

@Serializable
private data class GolfAPIDetailResponse(
    val id: Int = 0,
    val club_name: String = "",
    val location: GolfAPILocation = GolfAPILocation(),
    val tees: GolfAPITees = GolfAPITees(),
) {
    fun toScorecard(): CourseScorecard {
        val primaryTeeSet = tees.male?.firstOrNull()
        val holes = primaryTeeSet?.holes?.mapIndexed { idx, box ->
            HoleScorecard(
                number = idx + 1,
                par = box.par,
                yardage = box.yardage,
                handicapIndex = box.handicap ?: (idx + 1),
            )
        } ?: emptyList()

        val allTeeSets: List<GolfAPITeeSet> = buildList {
            tees.male?.let { addAll(it) }
            tees.female?.let { addAll(it) }
        }

        val teeNamesList = allTeeSets
            .map { it.tee_name }
            .filter { it.isNotBlank() }
            .distinct()
            .sorted()

        val holeYardagesByTee: Map<String, Map<String, Int>> = allTeeSets
            .filter { it.tee_name.isNotBlank() }
            .groupBy { it.tee_name }
            .mapValues { (_, teeSets) ->
                val teeSet = teeSets.first()
                teeSet.holes.associate { h -> h.hole_number.toString() to h.yardage }
            }

        return CourseScorecard(
            id = id.toString(),
            name = club_name,
            city = location.city,
            state = location.state,
            country = location.country,
            holes = holes,
            par = holes.sumOf { it.par }.takeIf { it > 0 } ?: 72,
            teeNames = teeNamesList,
            holeYardagesByTee = holeYardagesByTee,
        )
    }
}

@Serializable
private data class GolfAPILocation(
    val city: String = "",
    val state: String = "",
    val country: String = "US",
)

@Serializable
private data class GolfAPITees(
    val male: List<GolfAPITeeSet>? = null,
    val female: List<GolfAPITeeSet>? = null,
)

@Serializable
private data class GolfAPITeeSet(
    val tee_name: String = "",
    val course_rating: Float = 72.0f,
    val slope_rating: Int = 113,
    val holes: List<GolfAPIHole> = emptyList(),
)

@Serializable
private data class GolfAPIHole(
    val hole_number: Int = 0,
    val par: Int = 4,
    val yardage: Int = 400,
    val handicap: Int? = null,
)
