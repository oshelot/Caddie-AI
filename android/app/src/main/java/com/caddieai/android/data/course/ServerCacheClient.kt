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
 * See KAN-222 / KAN-220 for details.
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

    /** Fetch a cached course by ID. Returns null on miss or if disabled. */
    suspend fun getCourse(courseId: String): NormalizedCourse? = withContext(Dispatchers.IO) {
        if (!isEnabled) return@withContext null
        try {
            val endpoint = BuildConfig.COURSE_CACHE_ENDPOINT.trimEnd('/')
            val request = Request.Builder()
                .url("$endpoint/courses/$courseId")
                .addHeader("x-api-key", BuildConfig.COURSE_CACHE_API_KEY)
                .get()
                .build()
            val response = httpClient.newCall(request).execute()
            val code = response.code
            val body = response.body?.string() ?: ""
            response.close()
            if (code == 404) {
                logger.log(LogLevel.INFO, LogCategory.CACHE, "server_cache_miss", mapOf("courseId" to courseId))
                return@withContext null
            }
            if (code != 200 || body.isBlank()) {
                logger.log(LogLevel.WARN, LogCategory.CACHE, "server_cache_get_failed", mapOf("status" to code))
                return@withContext null
            }
            val course = json.decodeFromString<NormalizedCourse>(body)
            logger.log(LogLevel.INFO, LogCategory.CACHE, "server_cache_hit",
                mapOf("courseId" to courseId, "holeCount" to course.holes.size))
            course
        } catch (e: Exception) {
            logger.log(LogLevel.ERROR, LogCategory.CACHE, "server_cache_get_exception",
                mapOf("error" to (e.message ?: "unknown")))
            null
        }
    }

    /** Upload a course to the server cache. Fire-and-forget. */
    suspend fun putCourse(course: NormalizedCourse): Boolean = withContext(Dispatchers.IO) {
        if (!isEnabled) return@withContext false
        try {
            val endpoint = BuildConfig.COURSE_CACHE_ENDPOINT.trimEnd('/')
            val body = json.encodeToString(course).toRequestBody(JSON_MEDIA)
            val request = Request.Builder()
                .url("$endpoint/courses/${course.id}")
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
                mapOf("status" to code, "courseId" to course.id),
            )
            ok
        } catch (e: Exception) {
            logger.log(LogLevel.ERROR, LogCategory.CACHE, "server_cache_put_exception",
                mapOf("error" to (e.message ?: "unknown")))
            false
        }
    }
}
