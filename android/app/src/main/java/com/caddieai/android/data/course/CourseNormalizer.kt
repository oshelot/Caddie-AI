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
        // KAN-248: also match natural=water — many courses tag water features
        // with natural=water instead of golf=water_hazard.
        val water = osmElements.filter {
            it.tags["golf"] == "water_hazard" ||
                it.tags["water"] == "hazard" ||
                it.tags["natural"] == "water"
        }

        // PASS 1 — build hole-number -> osmHole map (ref matching only; hole
        // way-lines reliably carry ref tags even when tees/greens don't).
        val osmHoleByNum: Map<Int, OverpassElement> = buildMap {
            for (h in holeElements) {
                val n = h.tags["ref"]?.toIntOrNull() ?: h.tags["hole"]?.toIntOrNull() ?: continue
                putIfAbsent(n, h)
            }
        }
        val holeNums = scorecard.holes.map { it.number }

        // PASS 2 — associate greens. Ref match first; fall back to nearest hole
        // end-point within 547 yards (~500m). Each green assigned at most once.
        // Each hole keeps its first green.
        val greenByHole = mutableMapOf<Int, OverpassElement>()
        val unrefGreens = mutableListOf<OverpassElement>()
        for (g in greens) {
            val refNum = g.tags["ref"]?.toIntOrNull()
            if (refNum != null && refNum in holeNums && refNum !in greenByHole) {
                greenByHole[refNum] = g
            } else {
                unrefGreens.add(g)
            }
        }
        for (g in unrefGreens) {
            val gCenter = g.geometry.centroid() ?: continue
            var bestHole: Int? = null
            var bestDist = Double.MAX_VALUE
            for (n in holeNums) {
                if (n in greenByHole) continue
                val holeLine = osmHoleByNum[n]?.geometry ?: continue
                val endPt = holeLine.lastOrNull()?.toGeoPoint() ?: continue
                val d = gCenter.distanceInYards(endPt)
                if (d < bestDist) { bestDist = d; bestHole = n }
            }
            if (bestHole != null && bestDist <= 547.0) {
                greenByHole[bestHole] = g
            }
        }

        // PASS 3 — associate tees. Ref match first; fall back to nearest hole
        // start-point within 328 yards (~300m). Multiple tees may map to the
        // same hole (different tee boxes), so only the FIRST becomes the
        // hole's primary teeBox.
        val teeByHole = mutableMapOf<Int, OverpassElement>()
        val unrefTees = mutableListOf<OverpassElement>()
        for (t in tees) {
            val refNum = t.tags["ref"]?.toIntOrNull()
            if (refNum != null && refNum in holeNums && refNum !in teeByHole) {
                teeByHole[refNum] = t
            } else if (refNum == null) {
                unrefTees.add(t)
            }
        }
        for (t in unrefTees) {
            val tCenter = t.geometry.centroid() ?: continue
            var bestHole: Int? = null
            var bestDist = Double.MAX_VALUE
            for (n in holeNums) {
                val holeLine = osmHoleByNum[n]?.geometry ?: continue
                val startPt = holeLine.firstOrNull()?.toGeoPoint() ?: continue
                val d = tCenter.distanceInYards(startPt)
                if (d < bestDist) { bestDist = d; bestHole = n }
            }
            if (bestHole != null && bestDist <= 328.0) {
                teeByHole.putIfAbsent(bestHole, t)
            }
        }

        // PASS 4 — build final Hole objects. Bunkers and water still attach by
        // hole-corridor proximity (unchanged, but now using the osmHoleByNum map).
        val holes = scorecard.holes.map { sc ->
            val holeNum = sc.number
            val osmHole = osmHoleByNum[holeNum]
            val green = greenByHole[holeNum]
            val tee = teeByHole[holeNum]
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
                teeBox = tee?.geometry?.centroid() ?: tee?.geometry?.firstOrNull()?.toGeoPoint(),
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
