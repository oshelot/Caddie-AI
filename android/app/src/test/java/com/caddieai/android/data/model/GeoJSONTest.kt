package com.caddieai.android.data.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class GeoJSONTest {

    @Test
    fun haversine_knownDistance_Augusta18thGreen() {
        // Augusta National hole 18 approximate tee and green coords
        val tee = GeoPoint(33.5030, -82.0203)
        val green = GeoPoint(33.5015, -82.0226)
        val yards = tee.distanceInYards(green)
        // ~320 yards for these approximate coordinates — accept within ±100 yards
        assertTrue("Expected 220–420 yds, got $yards", yards in 220.0..420.0)
    }

    @Test
    fun haversine_samePoint_isZero() {
        val pt = GeoPoint(33.5030, -82.0203)
        assertEquals(0.0, pt.distanceInYards(pt), 0.001)
    }

    @Test
    fun haversine_meters_vs_yards() {
        val a = GeoPoint(33.5030, -82.0203)
        val b = GeoPoint(33.5015, -82.0226)
        val yards = a.distanceInYards(b)
        val meters = a.distanceInMeters(b)
        // 1 yard ≈ 0.9144 meters
        assertEquals(meters / 0.9144, yards, 1.0)
    }

    @Test
    fun geoPolygon_contains_pointInside() {
        // Simple square polygon
        val square = GeoPolygon(
            outerRing = listOf(
                GeoPoint(0.0, 0.0),
                GeoPoint(0.0, 1.0),
                GeoPoint(1.0, 1.0),
                GeoPoint(1.0, 0.0),
                GeoPoint(0.0, 0.0),
            )
        )
        assertTrue(square.contains(GeoPoint(0.5, 0.5)))
    }

    @Test
    fun geoPolygon_contains_pointOutside() {
        val square = GeoPolygon(
            outerRing = listOf(
                GeoPoint(0.0, 0.0),
                GeoPoint(0.0, 1.0),
                GeoPoint(1.0, 1.0),
                GeoPoint(1.0, 0.0),
                GeoPoint(0.0, 0.0),
            )
        )
        assertFalse(square.contains(GeoPoint(2.0, 2.0)))
    }

    @Test
    fun geoLineString_totalLength() {
        // Three collinear points ~100 yards apart
        val a = GeoPoint(33.5000, -82.0000)
        val b = GeoPoint(33.5008, -82.0000) // ~98 yards north
        val c = GeoPoint(33.5016, -82.0000) // another ~98 yards north
        val line = GeoLineString(listOf(a, b, c))
        val total = line.totalLengthInYards()
        assertTrue("Expected ~196 yards, got $total", abs(total - 196) < 10)
    }
}
