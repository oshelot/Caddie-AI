package com.caddieai.android.data.engine

import com.caddieai.android.data.model.Club
import com.caddieai.android.data.model.LieType
import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.model.ShotRecommendation
import com.caddieai.android.data.model.WindDirection
import com.caddieai.android.data.model.WindStrength
import com.caddieai.android.data.model.Aggressiveness
import com.caddieai.android.data.model.LLMProvider
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Deterministic golf logic engine — produces a baseline club recommendation
 * without any LLM call. Used as an instant fallback and to seed the LLM prompt.
 */
object GolfLogicEngine {

    data class EngineResult(
        val effectiveDistance: Int,
        val recommendedClub: Club,
        val windAdjustmentYards: Int,
        val lieMultiplier: Float,
        val slopeAdjustmentYards: Int,
        val notes: String,
    )

    fun analyze(context: ShotContext, profile: PlayerProfile): EngineResult {
        val windAdj = windAdjustmentYards(context.windStrength, context.windDirection)
        val lieMult = lieMultiplier(context.lie)
        val slopeAdj = context.elevationChangeYards // +elevation = club up, -elevation = club down

        val rawDistance = context.distanceToPin + windAdj + slopeAdj
        val effectiveDistance = (rawDistance / lieMult).roundToInt().coerceAtLeast(0)

        val club = selectClub(effectiveDistance, profile)

        val notes = buildString {
            if (windAdj != 0) {
                val dir = if (windAdj > 0) "headwind adding" else "tailwind saving"
                appendLine("• ${context.windStrength.label} $dir ${abs(windAdj)} yards")
            }
            if (lieMult < 1f) {
                val pct = ((1f - lieMult) * 100).roundToInt()
                appendLine("• ${context.lie.name.replace('_', ' ').lowercase()} lie reducing distance by ~$pct%")
            }
            if (slopeAdj != 0) {
                val dir = if (slopeAdj > 0) "uphill" else "downhill"
                appendLine("• Playing $dir (${abs(slopeAdj)} yd elevation)")
            }
        }.trim()

        return EngineResult(
            effectiveDistance = effectiveDistance,
            recommendedClub = club,
            windAdjustmentYards = windAdj,
            lieMultiplier = lieMult,
            slopeAdjustmentYards = slopeAdj,
            notes = notes,
        )
    }

    fun analyzeToRecommendation(context: ShotContext, profile: PlayerProfile): ShotRecommendation {
        val result = analyze(context, profile)
        val altClub = findAlternativeClub(result.recommendedClub, result.effectiveDistance, profile)
        return ShotRecommendation(
            recommendedClub = result.recommendedClub,
            targetDistanceYards = result.effectiveDistance,
            targetDescription = "Center of the green",
            riskLevel = profile.aggressiveness,
            executionPlan = "Strike the ball cleanly. ${result.notes}",
            alternativeClub = altClub,
            windAdjustmentNote = if (result.windAdjustmentYards != 0)
                "${if (result.windAdjustmentYards > 0) "Add" else "Subtract"} ~${abs(result.windAdjustmentYards)} yards for wind"
            else "",
            slopeAdjustmentNote = if (result.slopeAdjustmentYards != 0)
                "${if (result.slopeAdjustmentYards > 0) "Playing uphill" else "Playing downhill"}: ${abs(result.slopeAdjustmentYards)} yard adjustment"
            else "",
            confidenceScore = 0.8f, // Deterministic baseline confidence
            llmProvider = LLMProvider.OPENAI, // Placeholder — overridden when LLM used
        )
    }

    fun windAdjustmentYards(strength: WindStrength, direction: WindDirection): Int {
        val base = when (strength) {
            WindStrength.CALM -> 0
            WindStrength.LIGHT -> 5
            WindStrength.MODERATE -> 10
            WindStrength.STRONG -> 17
            WindStrength.VERY_STRONG -> 25
        }
        return when (direction) {
            WindDirection.HEADWIND -> base
            WindDirection.TAILWIND -> -base
            WindDirection.LEFT_TO_RIGHT, WindDirection.RIGHT_TO_LEFT -> base / 3
            WindDirection.CROSS_HEADWIND_LEFT, WindDirection.CROSS_HEADWIND_RIGHT -> (base * 2) / 3
            WindDirection.CROSS_TAILWIND_LEFT, WindDirection.CROSS_TAILWIND_RIGHT -> -(base / 3)
            WindDirection.NONE -> 0
        }
    }

    fun lieMultiplier(lie: LieType): Float = when (lie) {
        LieType.TEE_BOX, LieType.FAIRWAY, LieType.FRINGE,
        LieType.UPHILL, LieType.DOWNHILL,
        LieType.SIDEHILL_ABOVE, LieType.SIDEHILL_BELOW -> 1.0f
        LieType.ROUGH -> 0.92f
        LieType.WET_ROUGH -> 0.88f
        LieType.FAIRWAY_BUNKER -> 0.88f
        LieType.DIVOT -> 0.90f
        LieType.HARDPAN -> 0.95f
        LieType.DEEP_ROUGH -> 0.82f
        LieType.BUNKER -> 0.80f
        LieType.GREEN -> 1.0f
    }

    /** Find the club whose carry distance best matches the effective distance. */
    fun selectClub(effectiveDistance: Int, profile: PlayerProfile): Club {
        return profile.clubDistances.entries
            .filter { it.key != Club.PUTTER || effectiveDistance < 10 }
            .minByOrNull { abs(it.value - effectiveDistance) }
            ?.key
            ?: Club.SEVEN_IRON
    }

    private fun findAlternativeClub(primary: Club, effectiveDistance: Int, profile: PlayerProfile): Club? {
        return profile.clubDistances.entries
            .filter { it.key != primary && it.key != Club.PUTTER }
            .minByOrNull { abs(it.value - effectiveDistance) }
            ?.key
    }
}
