package com.caddieai.android.data.course

import com.caddieai.android.data.model.GeoLineString
import com.caddieai.android.data.model.GeoPoint
import com.caddieai.android.data.model.GeoPolygon
import com.caddieai.android.data.model.Hazard
import com.caddieai.android.data.model.HazardType
import com.caddieai.android.data.model.Hole
import com.caddieai.android.data.model.NormalizedCourse
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CourseNormalizer @Inject constructor() {

    /**
     * Merge scorecard data (par, yardages) with OSM geometry data into a NormalizedCourse.
     * Confidence score reflects how well the two sources aligned.
     */
    fun normalize(
        scorecard: CourseScorecard,
        osmElements: List<OverpassElement>,
    ): NormalizedCourse {
        val holeElements = osmElements
            .filter { it.tags["golf"] == "hole" || it.tags["golf:hole"] != null }
            .sortedBy { it.tags["ref"]?.toIntOrNull() ?: it.tags["hole"]?.toIntOrNull() ?: 99 }

        val greens = osmElements.filter { it.tags["golf"] == "green" }
        val tees = osmElements.filter { it.tags["golf"] == "tee" }
        val fairways = osmElements.filter { it.tags["golf"] == "fairway" }
        val bunkers = osmElements.filter { it.tags["golf"] == "bunker" }
        val water = osmElements.filter { it.tags["golf"] == "water_hazard" || it.tags["water"] == "hazard" }

        val holes = scorecard.holes.mapIndexed { idx, sc ->
            val holeNum = sc.number
            val osmHole = holeElements.firstOrNull {
                it.tags["ref"]?.toIntOrNull() == holeNum
            }
            val green = greens.firstOrNull { it.tags["ref"]?.toIntOrNull() == holeNum }
            val tee = tees.firstOrNull { it.tags["ref"]?.toIntOrNull() == holeNum }
            val fairway = fairways.firstOrNull { it.tags["ref"]?.toIntOrNull() == holeNum }

            val holeBunkers = bunkers.filter { b ->
                val bCenter = b.geometry.centroid()
                osmHole?.geometry?.let { hg -> bCenter?.isNear(hg.centroid()) } ?: false
            }
            val holeWater = water.filter { w ->
                val wCenter = w.geometry.centroid()
                osmHole?.geometry?.let { hg -> wCenter?.isNear(hg.centroid()) } ?: false
            }

            Hole(
                number = holeNum,
                par = sc.par,
                yardage = sc.yardage,
                handicapIndex = sc.handicapIndex,
                teeBox = tee?.geometry?.firstOrNull()?.toGeoPoint(),
                pin = green?.geometry?.centroid(),
                fairwayCenterLine = fairway?.geometry
                    ?.takeIf { it.size >= 2 }
                    ?.let { pts -> GeoLineString(pts.map { it.toGeoPoint() }) },
                green = green?.geometry
                    ?.takeIf { it.size >= 3 }
                    ?.let { pts -> GeoPolygon(pts.map { it.toGeoPoint() }) },
                hazards = buildList {
                    holeBunkers.forEach { b ->
                        add(Hazard(
                            type = HazardType.BUNKER,
                            boundary = b.geometry.takeIf { it.size >= 3 }
                                ?.let { GeoPolygon(it.map { pt -> pt.toGeoPoint() }) }
                        ))
                    }
                    holeWater.forEach { w ->
                        add(Hazard(
                            type = HazardType.WATER,
                            boundary = w.geometry.takeIf { it.size >= 3 }
                                ?.let { GeoPolygon(it.map { pt -> pt.toGeoPoint() }) }
                        ))
                    }
                },
            )
        }

        val confidence = calculateConfidence(scorecard, osmElements, holes)

        // If the API didn't return tee data, synthesize a "Standard" tee from the default hole yardages
        val finalTeeNames = scorecard.teeNames.ifEmpty {
            val hasYardages = holes.any { it.yardage > 0 }
            if (hasYardages) listOf("Standard") else emptyList()
        }
        val finalHoleYardagesByTee = scorecard.holeYardagesByTee.ifEmpty {
            if (finalTeeNames.isNotEmpty()) {
                mapOf("Standard" to holes.associate { it.number.toString() to it.yardage })
            } else emptyMap()
        }

        return NormalizedCourse(
            id = scorecard.id.ifBlank { "${scorecard.name}-${scorecard.city}".sanitizeId() },
            name = scorecard.name,
            city = scorecard.city,
            state = scorecard.state,
            country = scorecard.country,
            holes = holes,
            confidenceScore = confidence,
            source = "golf_api+osm",
            teeNames = finalTeeNames,
            holeYardagesByTee = finalHoleYardagesByTee,
        )
    }

    private fun calculateConfidence(
        scorecard: CourseScorecard,
        osmElements: List<OverpassElement>,
        holes: List<Hole>,
    ): Float {
        var score = 0f
        if (scorecard.holes.isNotEmpty()) score += 0.3f
        if (osmElements.any { it.tags["golf"] == "hole" }) score += 0.3f
        val holesWithGeometry = holes.count { it.teeBox != null || it.green != null }
        score += (holesWithGeometry.toFloat() / holes.size.coerceAtLeast(1)) * 0.4f
        return score.coerceIn(0f, 1f)
    }

    private fun List<OverpassGeometryPoint>.centroid(): GeoPoint? {
        if (isEmpty()) return null
        return GeoPoint(
            latitude = sumOf { it.lat } / size,
            longitude = sumOf { it.lon } / size,
        )
    }

    private fun GeoPoint.isNear(other: GeoPoint?, thresholdYards: Double = 500.0): Boolean {
        if (other == null) return false
        return distanceInYards(other) <= thresholdYards
    }

    private fun String.sanitizeId(): String = lowercase()
        .replace(Regex("[^a-z0-9-]"), "-")
        .replace(Regex("-+"), "-")
        .trim('-')
}
