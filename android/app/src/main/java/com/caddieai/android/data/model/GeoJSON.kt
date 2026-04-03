package com.caddieai.android.data.model

import kotlinx.serialization.Serializable
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

@Serializable
data class GeoPoint(
    val latitude: Double,
    val longitude: Double
) {
    /** Haversine distance to another point in yards. */
    fun distanceInYards(other: GeoPoint): Double {
        val earthRadiusYards = 6_371_000 * 1.09361 // meters to yards
        val dLat = Math.toRadians(other.latitude - latitude)
        val dLon = Math.toRadians(other.longitude - longitude)
        val lat1 = Math.toRadians(latitude)
        val lat2 = Math.toRadians(other.latitude)
        val a = sin(dLat / 2) * sin(dLat / 2) +
                sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusYards * c
    }

    /** Haversine distance to another point in meters. */
    fun distanceInMeters(other: GeoPoint): Double {
        val earthRadiusM = 6_371_000.0
        val dLat = Math.toRadians(other.latitude - latitude)
        val dLon = Math.toRadians(other.longitude - longitude)
        val lat1 = Math.toRadians(latitude)
        val lat2 = Math.toRadians(other.latitude)
        val a = sin(dLat / 2) * sin(dLat / 2) +
                sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusM * c
    }
}

@Serializable
data class GeoLineString(val points: List<GeoPoint>) {
    fun totalLengthInYards(): Double {
        return points.zipWithNext().sumOf { (a, b) -> a.distanceInYards(b) }
    }
}

@Serializable
data class GeoPolygon(
    val outerRing: List<GeoPoint>,
    val holes: List<List<GeoPoint>> = emptyList()
) {
    fun contains(point: GeoPoint): Boolean {
        return raycastContains(outerRing, point) &&
                holes.none { hole -> raycastContains(hole, point) }
    }

    private fun raycastContains(ring: List<GeoPoint>, point: GeoPoint): Boolean {
        var inside = false
        var j = ring.lastIndex
        for (i in ring.indices) {
            val xi = ring[i].longitude; val yi = ring[i].latitude
            val xj = ring[j].longitude; val yj = ring[j].latitude
            val intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
                    (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)
            if (intersect) inside = !inside
            j = i
        }
        return inside
    }
}
