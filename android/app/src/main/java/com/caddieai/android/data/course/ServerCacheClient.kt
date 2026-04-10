package com.caddieai.android.data.course

import com.caddieai.android.BuildConfig
import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.model.NormalizedCourse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Server-side course cache. Gives <1s loads on cache hit (vs 3-8s for fresh ingestion).
 * No-ops if COURSE_CACHE_ENDPOINT is not configured.
 *
 * The Lambda accepts a `platform=android` query parameter that converts
 * iOS-uploaded course JSON to Android-native NormalizedCourse format on the
 * server, so no custom deserialization is needed here. See KAN-222 / KAN-220.
 */
@Singleton
class ServerCacheClient @Inject constructor(
    private val httpClient: OkHttpClient,
    private val logger: DiagnosticLogger,
) {
    companion object {
        private val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }
        private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()
    }

    val isEnabled: Boolean get() = BuildConfig.COURSE_CACHE_ENDPOINT.isNotBlank()

    /**
     * Fuzzy search for a course by name (and optional centroid). The server
     * does name + centroid matching and returns the best fit, or 404 if no
     * acceptable match. Use this for cross-platform lookups so Android can
     * find iOS-uploaded courses (and vice versa).
     */
    suspend fun searchCourse(
        query: String,
        latitude: Double? = null,
        longitude: Double? = null,
    ): NormalizedCourse? = withContext(Dispatchers.IO) {
        if (!isEnabled || query.isBlank()) return@withContext null
        try {
            val endpoint = BuildConfig.COURSE_CACHE_ENDPOINT.trimEnd('/')
            val q = java.net.URLEncoder.encode(query, "UTF-8")
            val coords = if (latitude != null && longitude != null) {
                "&lat=" + "%.6f".format(java.util.Locale.US, latitude) +
                    "&lon=" + "%.6f".format(java.util.Locale.US, longitude)
            } else ""
            val url = "$endpoint/courses/search?q=$q$coords&platform=android" +
                "&schema=${NormalizedCourse.CURRENT_SCHEMA_VERSION}"
            val request = Request.Builder()
                .url(url)
                .addHeader("x-api-key", BuildConfig.COURSE_CACHE_API_KEY)
                .get()
                .build()
            val response = httpClient.newCall(request).execute()
            val code = response.code
            val body = response.body?.string() ?: ""
            response.close()
            if (code == 404) {
                logger.log(LogLevel.INFO, LogCategory.CACHE, "server_cache_search_miss",
                    mapOf("query" to query))
                return@withContext null
            }
            if (code != 200 || body.isBlank()) {
                logger.log(LogLevel.WARN, LogCategory.CACHE, "server_cache_search_failed",
                    mapOf("status" to code))
                return@withContext null
            }
            val course = json.decodeFromString<NormalizedCourse>(body)
            logger.log(LogLevel.INFO, LogCategory.CACHE, "server_cache_search_hit",
                mapOf("query" to query, "holeCount" to course.holes.size))
            course
        } catch (e: Exception) {
            logger.log(LogLevel.ERROR, LogCategory.CACHE, "server_cache_search_exception",
                mapOf("error" to "${e.javaClass.simpleName}: ${e.message ?: "unknown"}"))
            android.util.Log.e("CaddieAI/ServerCache", "searchCourse failed", e)
            null
        }
    }

    /**
     * Fetch a cached course by its name-only server cache key
     * (see NormalizedCourse.serverCacheKey). Returns null on miss or if disabled.
     */
    suspend fun getCourse(serverCacheKey: String): NormalizedCourse? = withContext(Dispatchers.IO) {
        if (!isEnabled) return@withContext null
        try {
            val endpoint = BuildConfig.COURSE_CACHE_ENDPOINT.trimEnd('/')
            val encodedKey = java.net.URLEncoder.encode(serverCacheKey, "UTF-8")
            val request = Request.Builder()
                .url("$endpoint/courses/$encodedKey?platform=android" +
                    "&schema=${NormalizedCourse.CURRENT_SCHEMA_VERSION}")
                .addHeader("x-api-key", BuildConfig.COURSE_CACHE_API_KEY)
                .get()
                .build()
            val response = httpClient.newCall(request).execute()
            val code = response.code
            val body = response.body?.string() ?: ""
            response.close()
            if (code == 404) {
                logger.log(LogLevel.INFO, LogCategory.CACHE, "server_cache_miss", mapOf("key" to serverCacheKey))
                return@withContext null
            }
            if (code != 200 || body.isBlank()) {
                logger.log(LogLevel.WARN, LogCategory.CACHE, "server_cache_get_failed", mapOf("status" to code))
                return@withContext null
            }
            val course = json.decodeFromString<NormalizedCourse>(body)
            logger.log(LogLevel.INFO, LogCategory.CACHE, "server_cache_hit",
                mapOf("key" to serverCacheKey, "holeCount" to course.holes.size))
            course
        } catch (e: Exception) {
            logger.log(LogLevel.ERROR, LogCategory.CACHE, "server_cache_get_exception",
                mapOf("error" to "${e.javaClass.simpleName}: ${e.message ?: "unknown"}"))
            android.util.Log.e("CaddieAI/ServerCache", "getCourse failed", e)
            null
        }
    }

    /** Upload a course to the server cache. Fire-and-forget. */
    suspend fun putCourse(course: NormalizedCourse): Boolean = withContext(Dispatchers.IO) {
        if (!isEnabled) return@withContext false
        try {
            val endpoint = BuildConfig.COURSE_CACHE_ENDPOINT.trimEnd('/')
            val key = course.serverCacheKey
            val encodedKey = java.net.URLEncoder.encode(key, "UTF-8")
            val body = json.encodeToString(course).toRequestBody(JSON_MEDIA)
            val request = Request.Builder()
                .url("$endpoint/courses/$encodedKey?schema=${NormalizedCourse.CURRENT_SCHEMA_VERSION}")
                .addHeader("x-api-key", BuildConfig.COURSE_CACHE_API_KEY)
                .put(body)
                .build()
            val response = httpClient.newCall(request).execute()
            val code = response.code
            response.close()
            val ok = code in 200..299
            logger.log(
                if (ok) LogLevel.INFO else LogLevel.WARN,
                LogCategory.CACHE,
                if (ok) "server_cache_put_success" else "server_cache_put_failed",
                mapOf("status" to code, "key" to key),
            )
            ok
        } catch (e: Exception) {
            logger.log(LogLevel.ERROR, LogCategory.CACHE, "server_cache_put_exception",
                mapOf("error" to (e.message ?: "unknown")))
            false
        }
    }
}
