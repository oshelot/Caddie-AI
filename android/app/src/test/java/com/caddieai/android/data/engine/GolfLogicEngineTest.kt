package com.caddieai.android.data.engine

import com.caddieai.android.data.model.Club
import com.caddieai.android.data.model.LieType
import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.model.WindDirection
import com.caddieai.android.data.model.WindStrength
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class GolfLogicEngineTest {

    private val defaultProfile = PlayerProfile()

    // --- Wind adjustments ---

    @Test
    fun windAdj_calm_isZero() {
        assertEquals(0, GolfLogicEngine.windAdjustmentYards(WindStrength.CALM, WindDirection.NONE))
    }

    @Test
    fun windAdj_lightHeadwind_isPositive() {
        val adj = GolfLogicEngine.windAdjustmentYards(WindStrength.LIGHT, WindDirection.HEADWIND)
        assertTrue("Expected positive headwind adj, got $adj", adj > 0)
    }

    @Test
    fun windAdj_tailwind_isNegative() {
        val adj = GolfLogicEngine.windAdjustmentYards(WindStrength.MODERATE, WindDirection.TAILWIND)
        assertTrue("Expected negative tailwind adj, got $adj", adj < 0)
    }

    @Test
    fun windAdj_headwind_greaterThan_crosswind() {
        val headwind = GolfLogicEngine.windAdjustmentYards(WindStrength.STRONG, WindDirection.HEADWIND)
        val cross = GolfLogicEngine.windAdjustmentYards(WindStrength.STRONG, WindDirection.LEFT_TO_RIGHT)
        assertTrue("Headwind ($headwind) should exceed crosswind ($cross)", headwind > cross)
    }

    @Test
    fun windAdj_veryStrongHeadwind_atLeast20Yards() {
        val adj = GolfLogicEngine.windAdjustmentYards(WindStrength.VERY_STRONG, WindDirection.HEADWIND)
        assertTrue("Expected >=20, got $adj", adj >= 20)
    }

    // --- Lie multipliers ---

    @Test
    fun lieMult_fairway_is1() {
        assertEquals(1.0f, GolfLogicEngine.lieMultiplier(LieType.FAIRWAY), 0.001f)
    }

    @Test
    fun lieMult_deepRough_lessThanRough() {
        val rough = GolfLogicEngine.lieMultiplier(LieType.ROUGH)
        val deepRough = GolfLogicEngine.lieMultiplier(LieType.DEEP_ROUGH)
        assertTrue("Deep rough ($deepRough) should be < rough ($rough)", deepRough < rough)
    }

    @Test
    fun lieMult_bunker_lessThan_fairwayBunker() {
        val bunker = GolfLogicEngine.lieMultiplier(LieType.BUNKER)
        val fairwayBunker = GolfLogicEngine.lieMultiplier(LieType.FAIRWAY_BUNKER)
        assertTrue("Greenside bunker ($bunker) harder than fairway bunker ($fairwayBunker)", bunker < fairwayBunker)
    }

    @Test
    fun lieMult_allLies_between0and1() {
        LieType.entries.forEach { lie ->
            val mult = GolfLogicEngine.lieMultiplier(lie)
            assertTrue("Lie $lie multiplier $mult out of [0,1]", mult in 0f..1f)
        }
    }

    // --- Club selection ---

    @Test
    fun selectClub_150yards_returns7IronByDefault() {
        val club = GolfLogicEngine.selectClub(150, defaultProfile)
        // Default 7-iron is 138 yards, 6-iron is 148 — 150 closest to 6-iron
        val dist = defaultProfile.clubDistances[club] ?: 0
        assertTrue("Club $club at $dist yards should be close to 150", abs(dist - 150) <= 15)
    }

    @Test
    fun selectClub_230yards_returnsDriver() {
        val club = GolfLogicEngine.selectClub(230, defaultProfile)
        assertEquals(Club.DRIVER, club)
    }

    @Test
    fun selectClub_0yards_returnsPutter() {
        // Putter should be selected for very short distances
        val club = GolfLogicEngine.selectClub(5, defaultProfile)
        assertEquals(Club.PUTTER, club)
    }

    // --- Full analysis ---

    @Test
    fun analyze_headwindAddsToEffectiveDistance() {
        val noWind = ShotContext(distanceToPin = 150, windStrength = WindStrength.CALM, windDirection = WindDirection.NONE)
        val headwind = ShotContext(distanceToPin = 150, windStrength = WindStrength.MODERATE, windDirection = WindDirection.HEADWIND)

        val noWindResult = GolfLogicEngine.analyze(noWind, defaultProfile)
        val headwindResult = GolfLogicEngine.analyze(headwind, defaultProfile)

        assertTrue("Headwind should increase effective distance", headwindResult.effectiveDistance > noWindResult.effectiveDistance)
    }

    @Test
    fun analyze_roughReducesEffectiveDistance() {
        val fairway = ShotContext(distanceToPin = 150, lie = LieType.FAIRWAY)
        val rough = ShotContext(distanceToPin = 150, lie = LieType.ROUGH)

        val fairwayResult = GolfLogicEngine.analyze(fairway, defaultProfile)
        val roughResult = GolfLogicEngine.analyze(rough, defaultProfile)

        // From rough the ball flies shorter, so effective club-selection distance increases (need more club)
        assertTrue("Rough should increase effective selection distance", roughResult.effectiveDistance > fairwayResult.effectiveDistance)
    }

    @Test
    fun analyze_upslopeAddsYards() {
        val flat = ShotContext(distanceToPin = 150, elevationChangeYards = 0)
        val uphill = ShotContext(distanceToPin = 150, elevationChangeYards = 10)

        val flatResult = GolfLogicEngine.analyze(flat, defaultProfile)
        val uphillResult = GolfLogicEngine.analyze(uphill, defaultProfile)

        assertTrue("Uphill should increase effective distance", uphillResult.effectiveDistance > flatResult.effectiveDistance)
    }

    @Test
    fun analyzeToRecommendation_returnsValidRecommendation() {
        val context = ShotContext(distanceToPin = 175, lie = LieType.FAIRWAY)
        val rec = GolfLogicEngine.analyzeToRecommendation(context, defaultProfile)
        assertTrue("Effective distance should be close to 175", abs(rec.targetDistanceYards - 175) < 30)
        assertTrue("Confidence should be > 0", rec.confidenceScore > 0f)
    }
}
