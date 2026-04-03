package com.caddieai.android.data.model

import kotlinx.serialization.Serializable

@Serializable
data class ShotRecommendation(
    val recommendedClub: Club,
    val targetDistanceYards: Int,
    val targetDescription: String = "",
    val riskLevel: Aggressiveness = Aggressiveness.MODERATE,
    val executionPlan: String = "",
    val alternativeClub: Club? = null,
    val alternativeRationale: String = "",
    val windAdjustmentNote: String = "",
    val slopeAdjustmentNote: String = "",
    val confidenceScore: Float = 1.0f, // 0.0–1.0
    val llmProvider: LLMProvider = LLMProvider.OPENAI,
    val generatedAtMs: Long = System.currentTimeMillis(),
)
