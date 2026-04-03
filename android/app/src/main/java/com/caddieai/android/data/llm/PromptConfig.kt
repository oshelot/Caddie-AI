package com.caddieai.android.data.llm

import com.caddieai.android.data.model.Club
import kotlinx.serialization.Serializable

@Serializable
data class PromptConfig(
    val caddieSystemPrompt: String = BUNDLED_CADDIE_SYSTEM_PROMPT,
    val holeAnalysisSystemPrompt: String = BUNDLED_HOLE_ANALYSIS_SYSTEM_PROMPT,
    val followUpAugmentation: String = BUNDLED_FOLLOW_UP_AUGMENTATION,
    val golfKeywords: List<String> = BUNDLED_GOLF_KEYWORDS,
    val offTopicResponse: String = BUNDLED_OFF_TOPIC_RESPONSE,
    val personaFragments: Map<String, String> = emptyMap(),
)

/** Matches the hardcoded prompt in LLMService but kept here as the canonical bundled default. */
internal val BUNDLED_CADDIE_SYSTEM_PROMPT = """
You are an expert golf caddie with decades of experience. Given a shot situation, provide a concise recommendation in JSON format only.

Respond ONLY with a JSON object matching this exact schema:
{
  "recommended_club": "<CLUB_ENUM_NAME>",
  "target_distance_yards": <int>,
  "target_description": "<string>",
  "risk_level": "<CONSERVATIVE|MODERATE|AGGRESSIVE>",
  "execution_plan": "<string - 2-3 sentences max>",
  "alternative_club": "<CLUB_ENUM_NAME or null>",
  "alternative_rationale": "<string>",
  "wind_adjustment_note": "<string>",
  "slope_adjustment_note": "<string>",
  "confidence_score": <0.0 to 1.0>
}

Valid club names: ${Club.entries.joinToString(", ") { it.name }}
""".trimIndent()

internal const val BUNDLED_HOLE_ANALYSIS_SYSTEM_PROMPT =
    "You are an expert golf course strategist and caddie. Analyze the provided hole data and give strategic advice for playing it. Focus on: tee shot strategy, landing zone recommendations, approach shot considerations, and scoring opportunity. Be concise and practical."

internal const val BUNDLED_FOLLOW_UP_AUGMENTATION =
    "The player has a follow-up question about their current shot situation. Use the context already provided to give a focused, helpful answer. Stay concise and golf-relevant."

internal val BUNDLED_GOLF_KEYWORDS = listOf(
    "golf", "club", "iron", "driver", "wood", "hybrid", "wedge", "putter", "putt",
    "fairway", "rough", "green", "bunker", "hazard", "water", "sand", "tee", "pin",
    "flag", "hole", "par", "birdie", "eagle", "bogey", "stroke", "swing", "shot",
    "chip", "pitch", "flop", "draw", "fade", "slice", "hook", "yardage", "distance",
    "carry", "wind", "slope", "elevation", "lie", "stance", "grip", "backswing",
    "downswing", "impact", "course", "scorecard", "handicap", "caddie", "approach",
    "layup", "aim", "target", "landing", "loft", "shaft", "bounce", "offset",
    "dogleg", "blind", "uphill", "downhill", "sidehill", "punch", "bump",
)

internal const val BUNDLED_OFF_TOPIC_RESPONSE =
    "I'm your AI golf caddie! I can only help with golf-related questions — club selection, shot strategy, course management, and more. Please ask me something golf-related!"
