package com.caddieai.android.data.engine

import com.caddieai.android.data.model.GeoPoint
import com.caddieai.android.data.model.Hazard
import com.caddieai.android.data.model.HazardType
import com.caddieai.android.data.model.Hole
import com.caddieai.android.data.model.NormalizedCourse
import com.caddieai.android.data.model.PlayerProfile
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

enum class DoglegDirection { LEFT, RIGHT }

enum class HazardSide { LEFT, RIGHT, GREENSIDE, CROSSING, FRONT_OF_GREEN }

data class HoleHazardInfo(
    val type: HazardType,
    val side: HazardSide,
    val distanceFromTeeYards: Int,
    val description: String,
)

data class HoleWeatherContext(
    val tempF: Float,
    val windMph: Float,
    val compassDir: String,
    val relativeDir: String,
    val summary: String,
)

data class HoleAnalysis(
    val holeNumber: Int,
    val par: Int,
    val yardage: Int,
    val distanceFromTeeToPin: Double?,
    val hasBunkers: Boolean,
    val hasWater: Boolean,
    val isDoglegged: Boolean,
    val doglegDirection: DoglegDirection? = null,
    val doglegDistanceFromTeeYards: Int? = null,
    val doglegBendDegrees: Double? = null,
    val fairwayWidthAtLandingYards: Int? = null,
    val greenDepthYards: Int? = null,
    val greenWidthYards: Int? = null,
    val hazardDetails: List<HoleHazardInfo> = emptyList(),
    val weatherContext: HoleWeatherContext? = null,
    val yardagesByTee: Map<String, Int> = emptyMap(),
    val strategicAdvice: String,
    val landingZoneDescription: String,
    val riskAreas: List<String>,
    val llmEnhancedAnalysis: String? = null,
)

/**
 * Deterministic hole strategy analysis — runs entirely offline using course geometry.
 */
object HoleAnalysisEngine {

    private const val DOGLEG_BEARING_THRESHOLD_DEG = 15.0

    fun analyze(
        course: NormalizedCourse,
        holeNumber: Int,
        playerProfile: PlayerProfile,
        selectedTee: String? = null,
        weather: HoleWeatherContext? = null,
    ): HoleAnalysis {
        val hole = course.holes.firstOrNull { it.number == holeNumber }
            ?: return emptyAnalysis(holeNumber)

        val distTeeToPin = if (hole.teeBox != null && hole.pin != null)
            hole.teeBox.distanceInYards(hole.pin).roundToInt().toDouble()
        else null

        val hasBunkers = hole.hazards.any { it.type == HazardType.BUNKER }
        val hasWater = hole.hazards.any { it.type == HazardType.WATER || it.type == HazardType.LATERAL_WATER }

        // Dogleg analysis using bearing math
        val doglegResult = analyzeDogleg(hole)
        val isDoglegged = doglegResult != null

        val riskAreas = buildList {
            if (hasWater) add("Water hazard")
            if (hasBunkers) add("Bunker(s)")
            if (isDoglegged) add("Dogleg requires accurate tee shot")
            if (hole.hazards.any { it.type == HazardType.OUT_OF_BOUNDS }) add("Out of bounds")
        }

        // Fairway width approximation
        val fairwayWidth = (hole.yardage * 0.05).coerceIn(25.0, 60.0).roundToInt()

        // Green dimensions from polygon
        val (greenDepth, greenWidth) = computeGreenDimensions(hole, distTeeToPin)

        // Hazard detail classification
        val hazardDetails = classifyHazards(hole, distTeeToPin)

        // Yardages by tee
        val yardagesByTee = course.holeYardagesByTee
            .mapValues { (_, holeMap) -> holeMap[holeNumber.toString()] ?: 0 }
            .filterValues { it > 0 }

        val advice = buildStrategicAdvice(hole, playerProfile, hasBunkers, hasWater, isDoglegged, distTeeToPin)
        val landingZone = buildLandingZoneDescription(hole, playerProfile, isDoglegged)

        return HoleAnalysis(
            holeNumber = holeNumber,
            par = hole.par,
            yardage = hole.yardage,
            distanceFromTeeToPin = distTeeToPin,
            hasBunkers = hasBunkers,
            hasWater = hasWater,
            isDoglegged = isDoglegged,
            doglegDirection = doglegResult?.direction,
            doglegDistanceFromTeeYards = doglegResult?.distanceFromTeeYards,
            doglegBendDegrees = doglegResult?.bendDegrees,
            fairwayWidthAtLandingYards = fairwayWidth,
            greenDepthYards = greenDepth,
            greenWidthYards = greenWidth,
            hazardDetails = hazardDetails,
            weatherContext = weather,
            yardagesByTee = yardagesByTee,
            strategicAdvice = advice,
            landingZoneDescription = landingZone,
            riskAreas = riskAreas,
        )
    }

    fun buildLlmPrompt(
        hole: Hole,
        analysis: HoleAnalysis,
        playerProfile: PlayerProfile,
    ): String = buildString {
        appendLine("## Hole ${hole.number} Analysis Request")
        appendLine("- Par: ${hole.par}, Yardage: ${hole.yardage}")
        appendLine("- Hazards: ${if (analysis.riskAreas.isEmpty()) "None" else analysis.riskAreas.joinToString(", ")}")
        appendLine("- Doglegged: ${if (analysis.isDoglegged) "Yes" else "No"}")
        if (analysis.distanceFromTeeToPin != null)
            appendLine("- Measured distance tee-to-pin: ${analysis.distanceFromTeeToPin.roundToInt()} yards")
        appendLine()
        appendLine("## Player Profile")
        appendLine("- Handicap: ${playerProfile.handicap}")
        appendLine("- Stock shape: ${playerProfile.stockShape.name.lowercase()}")
        appendLine("- Driver carry: ${playerProfile.clubDistances[com.caddieai.android.data.model.Club.DRIVER] ?: 230} yards")
        appendLine()
        appendLine("Provide a concise 2-3 paragraph strategic breakdown for this hole. Include: recommended club off the tee, optimal landing zone, approach strategy, and green reading advice. Be specific and practical.")
    }

    private data class DoglegResult(
        val direction: DoglegDirection,
        val distanceFromTeeYards: Int,
        val bendDegrees: Double,
    )

    private fun analyzeDogleg(hole: Hole): DoglegResult? {
        val line = hole.fairwayCenterLine?.points ?: return null
        if (line.size < 3) return null

        // Check simple deviation first (existing heuristic for early return if not doglegged)
        val start = line.first()
        val mid = line[line.size / 2]
        val end = line.last()
        val directDist = start.distanceInYards(end)
        val routeDist = start.distanceInYards(mid) + mid.distanceInYards(end)
        if ((routeDist - directDist) <= 50) return null

        // Find the point where the bearing delta first exceeds the threshold
        var maxDelta = 0.0
        var doglegSegmentIdx = -1
        var accumulatedDist = 0.0
        var doglegDist = 0.0

        for (i in 1 until line.size - 1) {
            val b1 = forwardBearing(line[i - 1], line[i])
            val b2 = forwardBearing(line[i], line[i + 1])
            val delta = bearingDelta(b1, b2)
            val segDist = line[i - 1].distanceInYards(line[i])

            if (Math.abs(delta) >= DOGLEG_BEARING_THRESHOLD_DEG && Math.abs(delta) > Math.abs(maxDelta)) {
                maxDelta = delta
                doglegSegmentIdx = i
                doglegDist = accumulatedDist + segDist
            }
            accumulatedDist += segDist
        }

        if (doglegSegmentIdx < 0 || Math.abs(maxDelta) < DOGLEG_BEARING_THRESHOLD_DEG) return null

        val direction = if (maxDelta > 0) DoglegDirection.RIGHT else DoglegDirection.LEFT
        return DoglegResult(
            direction = direction,
            distanceFromTeeYards = doglegDist.roundToInt(),
            bendDegrees = Math.abs(maxDelta),
        )
    }

    private fun computeGreenDimensions(hole: Hole, distTeeToPin: Double?): Pair<Int?, Int?> {
        val greenPolygon = hole.green ?: return Pair(null, null)
        val points = greenPolygon.outerRing
        if (points.size < 3) return Pair(null, null)

        // Compute approach bearing (tee → pin direction), or use 0 if unavailable
        val approachBearing = if (hole.teeBox != null && hole.pin != null)
            forwardBearing(hole.teeBox, hole.pin)
        else 0.0

        val approachBearingRad = Math.toRadians(approachBearing)
        val perpendicularBearingRad = Math.toRadians((approachBearing + 90.0) % 360.0)

        val ux = sin(approachBearingRad)
        val uy = cos(approachBearingRad)
        val px = sin(perpendicularBearingRad)
        val py = cos(perpendicularBearingRad)

        // Project all polygon points onto the two axes
        val centroid = GeoPoint(
            latitude = points.map { it.latitude }.average(),
            longitude = points.map { it.longitude }.average(),
        )

        // Use a rough approximation: project each point as yardage from centroid
        val projections = points.map { pt ->
            val dLat = (pt.latitude - centroid.latitude) * 1093.61 // degrees → yards approx
            val dLon = (pt.longitude - centroid.longitude) * 1093.61 * cos(Math.toRadians(centroid.latitude))
            val alongAxis = dLat * uy + dLon * ux
            val perpAxis = dLat * py + dLon * px
            Pair(alongAxis, perpAxis)
        }

        val depth = (projections.maxOf { it.first } - projections.minOf { it.first }).roundToInt().coerceAtLeast(1)
        val width = (projections.maxOf { it.second } - projections.minOf { it.second }).roundToInt().coerceAtLeast(1)
        return Pair(depth, width)
    }

    private fun classifyHazards(hole: Hole, distTeeToPin: Double?): List<HoleHazardInfo> {
        val tee = hole.teeBox ?: return emptyList()
        val pin = hole.pin
        val holeYardage = distTeeToPin ?: hole.yardage.toDouble()
        val teeToPinBearing = if (pin != null) forwardBearing(tee, pin) else null

        return hole.hazards.mapNotNull { hazard ->
            val centroid = hazard.boundary?.outerRing?.let { pts ->
                if (pts.isEmpty()) null
                else GeoPoint(
                    latitude = pts.map { it.latitude }.average(),
                    longitude = pts.map { it.longitude }.average(),
                )
            } ?: hazard.location ?: return@mapNotNull null

            val distFromTee = tee.distanceInYards(centroid)
            val bearingToHazard = forwardBearing(tee, centroid)

            val side = when {
                distFromTee > holeYardage * 0.80 && teeToPinBearing != null -> {
                    val bearingDiff = bearingDelta(teeToPinBearing, bearingToHazard)
                    if (Math.abs(bearingDiff) < 20.0) HazardSide.FRONT_OF_GREEN
                    else HazardSide.GREENSIDE
                }
                teeToPinBearing != null -> {
                    val bearingDiff = bearingDelta(teeToPinBearing, bearingToHazard)
                    when {
                        bearingDiff > 20.0 -> HazardSide.RIGHT
                        bearingDiff < -20.0 -> HazardSide.LEFT
                        else -> HazardSide.CROSSING
                    }
                }
                else -> HazardSide.CROSSING
            }

            val description = "${hazard.type.name.lowercase().replace('_', ' ')} ${side.name.lowercase().replace('_', ' ')}" +
                    " (${distFromTee.roundToInt()} yds)"

            HoleHazardInfo(
                type = hazard.type,
                side = side,
                distanceFromTeeYards = distFromTee.roundToInt(),
                description = description,
            )
        }
    }

    private fun buildStrategicAdvice(
        hole: Hole, profile: PlayerProfile,
        hasBunkers: Boolean, hasWater: Boolean,
        isDoglegged: Boolean, distTeeToPin: Double?,
    ): String = buildString {
        val driverDist = profile.clubDistances[com.caddieai.android.data.model.Club.DRIVER] ?: 230

        when (hole.par) {
            3 -> {
                val yds = hole.yardage
                val club = GolfLogicEngine.selectClub(yds, profile)
                appendLine("Par 3 — hit ${club.displayName} directly at the green.")
                if (hasBunkers) appendLine("Avoid the greenside bunkers — aim for the fat part of the green.")
                if (hasWater) appendLine("Water is in play — take one more club and swing smooth.")
            }
            4 -> {
                if (isDoglegged) {
                    appendLine("Doglegged par 4 — accuracy off the tee is critical.")
                    if (driverDist > hole.yardage - 100) {
                        appendLine("You can potentially cut the corner with driver — weigh risk/reward carefully.")
                    } else {
                        appendLine("Play to the corner with a fairway wood or hybrid for the best approach angle.")
                    }
                } else {
                    appendLine("Straight par 4 — driver to set up a short approach.")
                }
                if (hasWater) appendLine("Water requires careful club selection on the approach.")
            }
            5 -> {
                if (driverDist + 220 >= hole.yardage) {
                    appendLine("Reachable par 5 in two — driver then fairway wood/hybrid for the green.")
                    if (hasWater || hasBunkers) appendLine("Hazards protect the green — consider laying up short if not in perfect position.")
                } else {
                    appendLine("Three-shot par 5 — driver, layup to preferred wedge distance, then attack the pin.")
                }
            }
            else -> appendLine("Play smart — prioritize fairways and greens.")
        }
    }

    private fun buildLandingZoneDescription(
        hole: Hole, profile: PlayerProfile, isDoglegged: Boolean
    ): String {
        val driver = profile.clubDistances[com.caddieai.android.data.model.Club.DRIVER] ?: 230
        return when {
            isDoglegged -> "Land ${driver - 20}–$driver yards from the tee, short of the dogleg bend for the best sight line."
            hole.par == 3 -> "Aim for the center of the green — take dead aim."
            hole.yardage > 450 -> "Maximize distance from the tee. Target the center of the fairway at ${driver} yards."
            else -> "Carry it ${driver - 10}–$driver yards from the tee, centering the fairway."
        }
    }

    private fun emptyAnalysis(holeNumber: Int) = HoleAnalysis(
        holeNumber = holeNumber, par = 4, yardage = 400,
        distanceFromTeeToPin = null, hasBunkers = false, hasWater = false,
        isDoglegged = false, strategicAdvice = "No geometry data available.",
        landingZoneDescription = "", riskAreas = emptyList(),
    )

    private fun forwardBearing(from: GeoPoint, to: GeoPoint): Double {
        val dLon = Math.toRadians(to.longitude - from.longitude)
        val lat1 = Math.toRadians(from.latitude)
        val lat2 = Math.toRadians(to.latitude)
        val y = sin(dLon) * cos(lat2)
        val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (Math.toDegrees(atan2(y, x)) + 360) % 360
    }

    private fun bearingDelta(b1: Double, b2: Double): Double {
        val d = ((b2 - b1 + 540) % 360) - 180
        return d
    }
}
