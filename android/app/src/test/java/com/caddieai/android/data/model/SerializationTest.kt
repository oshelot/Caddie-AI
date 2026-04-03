package com.caddieai.android.data.model

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class SerializationTest {

    @Test
    fun playerProfile_roundTrip() {
        val profile = PlayerProfile(
            name = "Test Golfer",
            handicap = 12.5f,
            stockShape = StockShape.FADE,
            missTendency = MissTendency.SLICE,
            llmProvider = LLMProvider.ANTHROPIC,
        )
        val json = Json.encodeToString(profile)
        val decoded = Json.decodeFromString<PlayerProfile>(json)
        assertEquals(profile.name, decoded.name)
        assertEquals(profile.handicap, decoded.handicap)
        assertEquals(profile.stockShape, decoded.stockShape)
        assertEquals(profile.llmProvider, decoded.llmProvider)
    }

    @Test
    fun playerProfile_defaultValues_notNull() {
        val profile = PlayerProfile()
        assertNotNull(profile.clubDistances)
        assertEquals(Club.entries.size, profile.clubDistances.size)
        assertEquals(Club.DRIVER.defaultCarryYards, profile.clubDistances[Club.DRIVER])
    }

    @Test
    fun shotContext_roundTrip() {
        val context = ShotContext(
            distanceToPin = 175,
            shotType = ShotType.APPROACH,
            lie = LieType.FAIRWAY,
            windStrength = WindStrength.MODERATE,
            windDirection = WindDirection.HEADWIND,
            slope = Slope.UPHILL_SLIGHT,
            elevationChangeYards = 5,
        )
        val json = Json.encodeToString(context)
        val decoded = Json.decodeFromString<ShotContext>(json)
        assertEquals(context.distanceToPin, decoded.distanceToPin)
        assertEquals(context.windStrength, decoded.windStrength)
        assertEquals(context.slope, decoded.slope)
    }

    @Test
    fun shotRecommendation_roundTrip() {
        val rec = ShotRecommendation(
            recommendedClub = Club.SEVEN_IRON,
            targetDistanceYards = 150,
            executionPlan = "Swing smooth, aim at center of green",
            riskLevel = Aggressiveness.MODERATE,
        )
        val json = Json.encodeToString(rec)
        val decoded = Json.decodeFromString<ShotRecommendation>(json)
        assertEquals(rec.recommendedClub, decoded.recommendedClub)
        assertEquals(rec.targetDistanceYards, decoded.targetDistanceYards)
    }

    @Test
    fun club_enum_has30Entries() {
        assertEquals(30, Club.entries.size)
    }

    @Test
    fun allEnums_serializeCorrectly() {
        // Spot-check each enum serializes and deserializes
        assertEquals(StockShape.DRAW, Json.decodeFromString<StockShape>("\"DRAW\""))
        assertEquals(LLMProvider.ANTHROPIC, Json.decodeFromString<LLMProvider>("\"ANTHROPIC\""))
        assertEquals(UserTier.PRO, Json.decodeFromString<UserTier>("\"PRO\""))
        assertEquals(Outcome.SUCCESS, Json.decodeFromString<Outcome>("\"SUCCESS\""))
    }

    @Test
    fun playerProfile_backwardCompat_unknownFieldsIgnored() {
        // Simulate reading a profile JSON with an unknown field (future schema)
        val json = """{"name":"Golfer","handicap":8.0,"_futureField":"ignored"}"""
        val lenientJson = Json { ignoreUnknownKeys = true }
        val decoded = lenientJson.decodeFromString<PlayerProfile>(json)
        assertEquals("Golfer", decoded.name)
        assertEquals(8.0f, decoded.handicap)
    }
}
