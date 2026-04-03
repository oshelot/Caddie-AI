package com.caddieai.android.data.llm

import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.model.ShotRecommendation
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNames

interface LLMService {
    suspend fun getRecommendation(
        context: ShotContext,
        profile: PlayerProfile,
        imageBase64: String? = null
    ): Result<ShotRecommendation>

    /** Plain-text chat completion for hole analysis and follow-up questions. */
    suspend fun chatCompletion(
        messages: List<ChatMessage>,
        profile: PlayerProfile,
        maxTokens: Int = 500,
        jsonMode: Boolean = false,
        imageBase64: String? = null,
    ): Result<String> = Result.failure(UnsupportedOperationException("chatCompletion not implemented for ${this::class.simpleName}"))
}

@Serializable
data class ChatMessage(
    val role: String,   // "system", "user", "assistant"
    val content: String,
)

/** Shared structured JSON format expected back from all LLM providers.
 *  Accepts snake_case (direct OpenAI/Claude/Gemini), camelCase (proxy), and the remote
 *  prompts.json schema (club/effectiveDistanceYards/target/riskLevel/executionPlan). */
@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class LLMShotResponse(
    @JsonNames("recommended_club", "recommendedClub", "club") val recommended_club: String,
    @JsonNames("target_distance_yards", "targetDistanceYards", "effectiveDistanceYards") val target_distance_yards: Int,
    @JsonNames("target_description", "targetDescription", "target") val target_description: String = "",
    @JsonNames("risk_level", "riskLevel") val risk_level: String = "MODERATE",
    @JsonNames("execution_plan", "executionPlan") val execution_plan: String = "",
    @JsonNames("alternative_club", "alternativeClub", "conservativeOption") val alternative_club: String? = null,
    @JsonNames("alternative_rationale", "alternativeRationale") val alternative_rationale: String = "",
    @JsonNames("wind_adjustment_note", "windAdjustmentNote") val wind_adjustment_note: String = "",
    @JsonNames("slope_adjustment_note", "slopeAdjustmentNote") val slope_adjustment_note: String = "",
    @JsonNames("confidence_score", "confidenceScore") val confidence_score: Double = 1.0,
)
