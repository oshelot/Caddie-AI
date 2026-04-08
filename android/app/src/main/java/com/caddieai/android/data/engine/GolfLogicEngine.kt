package com.caddieai.android.data.engine

import com.caddieai.android.data.model.Club
import com.caddieai.android.data.model.IronType
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
        // Defensive: warn on impossible shot/lie combos (KAN-232)
        if (context.lie !in context.shotType.validLies() && context.shotType.validLies().isNotEmpty()) {
            android.util.Log.w("GolfLogicEngine", "Impossible combo: shotType=${context.shotType} lie=${context.lie}")
        }
        val windAdj = windAdjustmentYards(context.windStrength, context.windDirection)
        val lieMult = lieMultiplier(context.lie)
        val slopeAdj = context.elevationChangeYards // +elevation = club up, -elevation = club down

        val rawDistance = context.distanceToPin + windAdj + slopeAdj
        var effectiveDistance = (rawDistance / lieMult).roundToInt().coerceAtLeast(0)

        // GI/SGI iron modifiers — apply before club selection
        val isGI = profile.ironType != null
        val isSGI = profile.ironType == IronType.SUPER_GAME_IMPROVEMENT
        val giNotes = mutableListOf<String>()

        val isBunker = context.lie == LieType.FAIRWAY_BUNKER || context.lie == LieType.BUNKER
        val isTightLie = context.lie == LieType.HARDPAN || context.lie == LieType.DIVOT
        val isThickRough = context.lie == LieType.DEEP_ROUGH || context.lie == LieType.WET_ROUGH
        val isHeadwind = context.windDirection == WindDirection.HEADWIND && context.windStrength.ordinal >= WindStrength.MODERATE.ordinal

        if (isGI) {
            if (isThickRough) {
                // Reduce carry expectation by 15%
                effectiveDistance = (effectiveDistance * 1.15).roundToInt()
                giNotes.add("• GI irons lose ~15% carry from thick rough — clubbing up")
            }
        }

        var club = selectClub(effectiveDistance, profile)

        if (isGI) {
            if (isBunker && club.name.contains("IRON")) {
                // Swap to hybrid or fairway wood if available
                val hybrid = profile.bagClubs.firstOrNull { it.name.contains("HYBRID") }
                    ?: profile.bagClubs.firstOrNull { it.name.contains("WOOD") && !it.name.contains("DRIVER") }
                if (hybrid != null) {
                    club = hybrid
                    giNotes.add("• GI wide sole struggles in bunkers — using ${hybrid.displayName}")
                } else {
                    giNotes.add("• GI irons limited in bunkers — swing 80%, ball back in stance")
                }
            }
            if (isTightLie && effectiveDistance > 160) {
                val hybrid = profile.bagClubs.firstOrNull { it.name.contains("HYBRID") }
                if (hybrid != null) {
                    club = hybrid
                    giNotes.add("• Tight lie + GI irons — ${hybrid.displayName} sweeps cleaner")
                } else {
                    giNotes.add("• Tight lie: ball back, hands forward, shallow strike")
                }
            }
            if (isHeadwind) {
                giNotes.add("• GI irons can't flight down — club up, 3/4 swing, trust the loft")
            }
        }

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
            giNotes.forEach { appendLine(it) }
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
