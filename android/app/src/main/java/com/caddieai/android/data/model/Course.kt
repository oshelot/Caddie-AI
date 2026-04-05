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
    val source: String = "", // data source identifier
    val cachedAtMs: Long = System.currentTimeMillis(),
    val teeNames: List<String> = emptyList(),
    // Outer key: tee name, inner key: hole number as string, value: yardage
    val holeYardagesByTee: Map<String, Map<String, Int>> = emptyMap(),
    val schemaVersion: Int = 1,
) {
    val par: Int get() = holes.sumOf { it.par }
    val totalYardage: Int get() = holes.sumOf { it.yardage }
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
