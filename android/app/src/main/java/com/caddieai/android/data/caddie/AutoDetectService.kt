package com.caddieai.android.data.caddie

import com.caddieai.android.data.model.Club
import com.caddieai.android.data.model.GeoPoint
import com.caddieai.android.data.model.Hole
import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.model.ShotType
import com.caddieai.android.data.model.WindDirection
import com.caddieai.android.data.weather.WeatherService
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.*

@Singleton
class AutoDetectService @Inject constructor(
    private val weatherService: WeatherService,
) {
    suspend fun autoDetect(
        playerLocation: GeoPoint,
        hole: Hole,
        profile: PlayerProfile,
    ): ShotContext {
        val pinLocation = hole.pin
            ?: hole.green?.outerRing?.let { ring ->
                GeoPoint(
                    ring.map { it.latitude }.average(),
                    ring.map { it.longitude }.average(),
                )
            }
            ?: error("No pin data for hole ${hole.number}")

        val distanceYards = playerLocation.distanceInYards(pinLocation).roundToInt()

        val weather = weatherService.getWeather(
            playerLocation.latitude,
            playerLocation.longitude,
        ).getOrThrow()

        val holeBearing = bearingDegrees(playerLocation, pinLocation)
        val relativeWindDir = computeRelativeWindDir(weather.windDirectionDegrees, holeBearing)
        val shotType = inferShotType(distanceYards, profile)

        return ShotContext(
            distanceToPin = distanceYards,
            shotType = shotType,
            windStrength = weather.windStrength,
            windDirection = relativeWindDir,
            holeNumber = hole.number,
            par = hole.par,
            playerLocation = playerLocation,
            pinLocation = pinLocation,
        )
    }

    private fun bearingDegrees(from: GeoPoint, to: GeoPoint): Double {
        val lat1 = Math.toRadians(from.latitude)
        val lat2 = Math.toRadians(to.latitude)
        val dLon = Math.toRadians(to.longitude - from.longitude)
        val y = sin(dLon) * cos(lat2)
        val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (Math.toDegrees(atan2(y, x)) + 360) % 360
    }

    private fun computeRelativeWindDir(windFromDeg: Int, holeBearing: Double): WindDirection {
        val relative = ((windFromDeg - holeBearing) + 360) % 360
        return when {
            relative < 22.5 || relative >= 337.5 -> WindDirection.HEADWIND
            relative < 67.5 -> WindDirection.CROSS_HEADWIND_RIGHT
            relative < 112.5 -> WindDirection.RIGHT_TO_LEFT
            relative < 157.5 -> WindDirection.CROSS_TAILWIND_RIGHT
            relative < 202.5 -> WindDirection.TAILWIND
            relative < 247.5 -> WindDirection.CROSS_TAILWIND_LEFT
            relative < 292.5 -> WindDirection.LEFT_TO_RIGHT
            else -> WindDirection.CROSS_HEADWIND_LEFT
        }
    }

    private fun inferShotType(distanceYards: Int, profile: PlayerProfile): ShotType {
        val bagDists = profile.clubDistances.filterKeys { it in profile.bagClubs }
        val driverDist = bagDists[Club.DRIVER] ?: 230
        val lobWedgeDist = bagDists[Club.LOB_WEDGE] ?: 68
        val sandWedgeDist = bagDists[Club.SAND_WEDGE] ?: 88
        return when {
            distanceYards <= 3 -> ShotType.PUTT
            distanceYards <= (lobWedgeDist / 2) -> ShotType.CHIP
            distanceYards <= sandWedgeDist -> ShotType.PITCH
            distanceYards >= driverDist -> ShotType.DRIVER
            else -> ShotType.APPROACH
        }
    }
}
