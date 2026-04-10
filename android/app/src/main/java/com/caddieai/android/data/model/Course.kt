package com.caddieai.android.data.model

import kotlinx.serialization.Serializable

@Serializable
data class NormalizedCourse(
    val id: String,
    val name: String,
    val city: String = "",
    val state: String = "",
    val country: String = "US",
    val holes: List<Hole> = emptyList(),
    val confidenceScore: Float = 1.0f, // how well the course geometry is known
    val source: String = "",
    val cachedAtMs: Long = System.currentTimeMillis(),
    val teeNames: List<String> = emptyList(),
    // Outer key: tee name, inner key: hole number as string, value: yardage
    val holeYardagesByTee: Map<String, Map<String, Int>> = emptyMap(),
    val schemaVersion: Int = 1,
) {
    val par: Int get() = holes.sumOf { it.par }
    val totalYardage: Int get() = holes.sumOf { it.yardage }

    /** Name-only key used for cross-platform server cache sharing with iOS. */
    val serverCacheKey: String get() = serverCacheKey(name)

    companion object {
        /** Cross-platform schema version. Must stay in sync with iOS. */
        const val CURRENT_SCHEMA_VERSION = "1.0"

        /**
         * Deterministic course ID shared with iOS so both platforms hit the same
         * server cache key. Format: {normalized-name}_{lat4}_{lon4}_osm-v{schema}.
         * Example: "sharp-park-golf-course_37.6244_-122.4885_osm-v1.0".
         */
        /**
         * Name-only key used for cross-platform server cache sharing. iOS and
         * Android derive coordinates differently (MapKit vs Nominatim), so any
         * coordinate-based key would fragment the cache. Dropping coordinates
         * here lets both platforms hit the same S3 object.
         */
        fun serverCacheKey(name: String): String = name
            .lowercase()
            .replace(" ", "-")
            .replace("'", "")
            .replace("\"", "")

        fun generateId(name: String, latitude: Double, longitude: Double): String {
            val normalized = name
                .lowercase()
                .replace(" ", "-")
                .replace("'", "")
                .replace("\"", "")
            // Force Locale.US so decimal separator is always "." — otherwise a
            // German-locale device would emit "37,6244" and break the iOS match.
            val latStr = "%.4f".format(java.util.Locale.US, latitude)
            val lonStr = "%.4f".format(java.util.Locale.US, longitude)
            return "${normalized}_${latStr}_${lonStr}_osm-v$CURRENT_SCHEMA_VERSION"
        }
    }
}

@Serializable
data class Hole(
    val number: Int,
    val par: Int,
    val yardage: Int,
    val handicapIndex: Int = number,
    val teeBox: GeoPoint? = null,
    val pin: GeoPoint? = null,
    val fairwayCenterLine: GeoLineString? = null,
    val green: GeoPolygon? = null,
    val hazards: List<Hazard> = emptyList(),
    val notes: String = "",
)

@Serializable
data class Hazard(
    val type: HazardType,
    val label: String = "",
    val boundary: GeoPolygon? = null,
    val location: GeoPoint? = null,
)

@Serializable
enum class HazardType {
    WATER,
    BUNKER,
    OUT_OF_BOUNDS,
    TREES,
    LATERAL_WATER,
    PENALTY_AREA,
}
