package com.caddieai.android.data.course

import android.content.Context
import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.model.GeoPoint
import com.caddieai.android.data.model.NormalizedCourse
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
internal data class CourseIndex(
    val courses: List<CourseIndexEntry> = emptyList(),
)

@Serializable
data class CourseIndexEntry(
    val id: String,
    val name: String,
    val city: String,
    val state: String,
    val latitude: Double,
    val longitude: Double,
    val cachedAtMs: Long,
)

@Singleton
class CourseCacheService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val logger: DiagnosticLogger,
) {
    companion object {
        private const val COURSES_DIR = "courses"
        private const val INDEX_FILE = "index.json"
        private const val FAVORITES_FILE = "favorites.json"
        private val json = Json { ignoreUnknownKeys = true; prettyPrint = false }
    }

    private val coursesDir: File
        get() = File(context.filesDir, COURSES_DIR).also { it.mkdirs() }

    private val indexFile: File get() = File(coursesDir, INDEX_FILE)
    private val favoritesFile: File get() = File(coursesDir, FAVORITES_FILE)
    private val teeSelectionsFile: File get() = File(coursesDir, "tee_selections.json")

    /** Save a course to the file cache and update the index. */
    fun saveCourse(course: NormalizedCourse) {
        val file = File(coursesDir, "${course.id}.json")
        file.writeText(json.encodeToString(course))
        updateIndex(course)
        logger.log(LogLevel.INFO, LogCategory.CACHE, "course_saved", mapOf("hole_count" to course.holes.size))
    }

    /** Load a cached course by ID. Returns null if not cached. */
    fun getCourse(id: String): NormalizedCourse? = runCatching {
        val file = File(coursesDir, "$id.json")
        if (!file.exists()) {
            logger.log(LogLevel.INFO, LogCategory.CACHE, "course_cache_miss")
            return null
        }
        val course = json.decodeFromString<NormalizedCourse>(file.readText())
        logger.log(LogLevel.INFO, LogCategory.CACHE, "course_cache_hit")
        course
    }.getOrNull()

    /** List all cached courses from the index. */
    fun listCachedCourses(): List<CourseIndexEntry> = runCatching {
        if (!indexFile.exists()) return emptyList()
        json.decodeFromString<CourseIndex>(indexFile.readText()).courses
    }.getOrDefault(emptyList())

    /** Find courses within a given radius of a location (proximity query). */
    fun coursesNear(location: GeoPoint, radiusYards: Double = 5000.0): List<String> {
        return listCachedCourses().filter { entry ->
            val courseCenter = GeoPoint(entry.latitude, entry.longitude)
            location.distanceInYards(courseCenter) <= radiusYards
        }.map { it.id }
    }

    /** Toggle favorite status for a course. Returns new favorite state. */
    fun toggleFavorite(courseId: String): Boolean {
        val favorites = getFavoriteIds().toMutableSet()
        val isNowFavorite = if (courseId in favorites) {
            favorites.remove(courseId)
            false
        } else {
            favorites.add(courseId)
            true
        }
        saveFavorites(favorites)
        return isNowFavorite
    }

    fun isFavorite(courseId: String): Boolean = courseId in getFavoriteIds()

    fun getFavoriteIds(): Set<String> = runCatching {
        if (!favoritesFile.exists()) return emptySet()
        json.decodeFromString<Set<String>>(favoritesFile.readText())
    }.getOrDefault(emptySet())

    fun saveSelectedTee(courseId: String, teeName: String) {
        val map = loadTeeSelections().toMutableMap()
        map[courseId] = teeName
        teeSelectionsFile.writeText(json.encodeToString(map))
    }

    fun getSelectedTee(courseId: String): String? = loadTeeSelections()[courseId]

    private fun loadTeeSelections(): Map<String, String> = runCatching {
        if (!teeSelectionsFile.exists()) return emptyMap()
        json.decodeFromString<Map<String, String>>(teeSelectionsFile.readText())
    }.getOrDefault(emptyMap())

    fun deleteCourse(id: String) {
        File(coursesDir, "$id.json").delete()
        removeFromIndex(id)
    }

    private fun updateIndex(course: NormalizedCourse) {
        val index = if (indexFile.exists())
            runCatching { json.decodeFromString<CourseIndex>(indexFile.readText()) }.getOrDefault(CourseIndex())
        else CourseIndex()

        val centerLat = course.holes.mapNotNull { it.teeBox?.latitude }.average().takeIf { !it.isNaN() } ?: 0.0
        val centerLon = course.holes.mapNotNull { it.teeBox?.longitude }.average().takeIf { !it.isNaN() } ?: 0.0

        val entry = CourseIndexEntry(
            id = course.id,
            name = course.name,
            city = course.city,
            state = course.state,
            latitude = centerLat,
            longitude = centerLon,
            cachedAtMs = course.cachedAtMs,
        )
        val updated = index.courses.filter { it.id != course.id } + entry
        indexFile.writeText(json.encodeToString(CourseIndex(updated)))
    }

    private fun removeFromIndex(id: String) {
        if (!indexFile.exists()) return
        val index = runCatching { json.decodeFromString<CourseIndex>(indexFile.readText()) }.getOrDefault(CourseIndex())
        indexFile.writeText(json.encodeToString(CourseIndex(index.courses.filter { it.id != id })))
    }

    private fun saveFavorites(favorites: Set<String>) {
        favoritesFile.writeText(json.encodeToString(favorites))
    }
}
