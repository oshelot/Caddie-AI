package com.caddieai.android.data.llm

import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.model.Aggressiveness
import com.caddieai.android.data.model.Club
import com.caddieai.android.data.model.LLMProvider
import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.model.ShotRecommendation
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import javax.inject.Inject

class OpenAIService @Inject constructor(
    private val httpClient: OkHttpClient,
    private val promptRepository: PromptRepository,
    private val logger: DiagnosticLogger,
) : LLMService {

    companion object {
        private const val BASE_URL = "https://api.openai.com/v1/chat/completions"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private val lenientJson = Json { ignoreUnknownKeys = true }
    }

    override suspend fun getRecommendation(
        context: ShotContext,
        profile: PlayerProfile,
        imageBase64: String?
    ): Result<ShotRecommendation> = runCatching {
        val apiKey = profile.openAiApiKey.ifBlank {
            error("OpenAI API key not configured")
        }
        val model = when (profile.effectiveTier) {
            com.caddieai.android.data.model.UserTier.PRO -> "gpt-4o"
            com.caddieai.android.data.model.UserTier.FREE -> "gpt-4o-mini"
        }

        val userContent = if (imageBase64 != null) {
            JsonArray(listOf(
                JsonObject(mapOf(
                    "type" to JsonPrimitive("text"),
                    "text" to JsonPrimitive(PromptBuilder.buildShotPrompt(context, profile))
                )),
                JsonObject(mapOf(
                    "type" to JsonPrimitive("image_url"),
                    "image_url" to JsonObject(mapOf(
                        "url" to JsonPrimitive("data:image/jpeg;base64,$imageBase64")
                    ))
                ))
            ))
        } else {
            JsonPrimitive(PromptBuilder.buildShotPrompt(context, profile))
        }

        val requestBody = JsonObject(mapOf(
            "model" to JsonPrimitive(model),
            "response_format" to JsonObject(mapOf("type" to JsonPrimitive("json_object"))),
            "messages" to JsonArray(listOf(
                JsonObject(mapOf(
                    "role" to JsonPrimitive("system"),
                    "content" to JsonPrimitive(promptRepository.caddieSystemPromptWithPersona(profile.caddiePersona))
                )),
                JsonObject(mapOf(
                    "role" to JsonPrimitive("user"),
                    "content" to userContent
                ))
            ))
        ))

        val request = Request.Builder()
            .url(BASE_URL)
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Content-Type", "application/json")
            .post(Json.encodeToString(requestBody).toRequestBody(JSON_MEDIA_TYPE))
            .build()

        logger.log(LogLevel.INFO, LogCategory.LLM, "llm_request_started",
            message = "OpenAI getRecommendation started",
            properties = mapOf("model" to model, "provider" to "openai"))

        val startMs = System.currentTimeMillis()
        val (responseBody, statusCode) = httpClient.newCall(request).execute().use { response ->
            val body = response.body?.string() ?: error("Empty response from OpenAI")
            if (!response.isSuccessful) {
                logger.log(LogLevel.ERROR, LogCategory.LLM, "llm_http_error",
                    message = "OpenAI HTTP error ${response.code}: ${body.take(200)}",
                    properties = mapOf("model" to model, "statusCode" to response.code,
                        "responseSnippet" to body.take(200)))
                error("OpenAI API error ${response.code}: $body")
            }
            Pair(body, response.code)
        }
        val latencyMs = System.currentTimeMillis() - startMs
        logger.log(LogLevel.INFO, LogCategory.LLM, "llm_response_received",
            message = "OpenAI response received in ${latencyMs}ms",
            properties = mapOf("model" to model, "latencyMs" to latencyMs, "statusCode" to statusCode))

        val parsed = lenientJson.parseToJsonElement(responseBody) as JsonObject
        val content = (parsed["choices"] as JsonArray)
            .first()
            .let { it as JsonObject }["message"]
            .let { it as JsonObject }["content"]
            .let { (it as JsonPrimitive).content }

        try {
            val shotResponse = lenientJson.decodeFromString<LLMShotResponse>(content)
            shotResponse.toShotRecommendation(LLMProvider.OPENAI)
        } catch (e: Exception) {
            logger.log(LogLevel.ERROR, LogCategory.LLM, "llm_json_parse_failed",
                message = "JSON parse failed: ${e.message}",
                properties = mapOf(
                    "model" to model,
                    "exceptionType" to (e::class.simpleName ?: "Unknown"),
                    "rawResponseSnippet" to content.take(200),
                    "stackTrace" to e.stackTrace.take(3).joinToString(" | ") { "${it.className}.${it.methodName}:${it.lineNumber}" },
                ))
            throw e
        }
    }

    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        profile: PlayerProfile,
        maxTokens: Int,
        jsonMode: Boolean,
        imageBase64: String?,
    ): Result<String> = runCatching {
        val apiKey = profile.openAiApiKey.ifBlank { error("OpenAI API key not configured") }
        val model = when (profile.effectiveTier) {
            com.caddieai.android.data.model.UserTier.PRO -> "gpt-4o"
            com.caddieai.android.data.model.UserTier.FREE -> "gpt-4o-mini"
        }
        val jsonMessages = messages.mapIndexed { idx, msg ->
            val isLastUser = msg.role == "user" && idx == messages.lastIndex
            val content: JsonElement = if (imageBase64 != null && isLastUser) {
                JsonArray(listOf(
                    JsonObject(mapOf("type" to JsonPrimitive("text"), "text" to JsonPrimitive(msg.content))),
                    JsonObject(mapOf("type" to JsonPrimitive("image_url"), "image_url" to JsonObject(mapOf("url" to JsonPrimitive("data:image/jpeg;base64,$imageBase64"))))),
                ))
            } else JsonPrimitive(msg.content)
            JsonObject(mapOf("role" to JsonPrimitive(msg.role), "content" to content))
        }
        val bodyMap = mutableMapOf<String, JsonElement>(
            "model"       to JsonPrimitive(model),
            "messages"    to JsonArray(jsonMessages),
            "max_tokens"  to JsonPrimitive(maxTokens),
            "temperature" to JsonPrimitive(0.7),
        )
        if (jsonMode) bodyMap["response_format"] = JsonObject(mapOf("type" to JsonPrimitive("json_object")))

        val request = Request.Builder()
            .url(BASE_URL)
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Content-Type", "application/json")
            .post(Json.encodeToString(JsonObject(bodyMap)).toRequestBody(JSON_MEDIA_TYPE))
            .build()

        logger.log(LogLevel.INFO, LogCategory.LLM, "llm_request_started",
            message = "OpenAI chatCompletion started",
            properties = mapOf("model" to model, "provider" to "openai", "messageCount" to messages.size))

        val startMs = System.currentTimeMillis()
        val responseBody = httpClient.newCall(request).execute().use { response ->
            val body = response.body?.string() ?: error("Empty response")
            if (!response.isSuccessful) {
                logger.log(LogLevel.ERROR, LogCategory.LLM, "llm_http_error",
                    message = "OpenAI HTTP error ${response.code}: ${body.take(200)}",
                    properties = mapOf("model" to model, "statusCode" to response.code,
                        "responseSnippet" to body.take(200)))
                error("OpenAI error ${response.code}: $body")
            }
            body
        }
        val latencyMs = System.currentTimeMillis() - startMs
        logger.log(LogLevel.INFO, LogCategory.LLM, "llm_response_received",
            message = "OpenAI chatCompletion response received in ${latencyMs}ms",
            properties = mapOf("model" to model, "latencyMs" to latencyMs))

        val parsed = lenientJson.parseToJsonElement(responseBody) as JsonObject
        (parsed["choices"] as JsonArray)
            .first().let { it as JsonObject }["message"]
            .let { it as JsonObject }["content"]
            .let { (it as JsonPrimitive).content }
    }
}

internal fun LLMShotResponse.toShotRecommendation(provider: LLMProvider): ShotRecommendation {
    val club = runCatching { Club.valueOf(recommended_club) }.getOrDefault(Club.SEVEN_IRON)
    val altClub = alternative_club?.let { runCatching { Club.valueOf(it) }.getOrNull() }
    val risk = runCatching { Aggressiveness.valueOf(risk_level) }.getOrDefault(Aggressiveness.MODERATE)
    return ShotRecommendation(
        recommendedClub = club,
        targetDistanceYards = target_distance_yards,
        targetDescription = target_description,
        riskLevel = risk,
        executionPlan = execution_plan,
        alternativeClub = altClub,
        alternativeRationale = alternative_rationale,
        windAdjustmentNote = wind_adjustment_note,
        slopeAdjustmentNote = slope_adjustment_note,
        confidenceScore = confidence_score.toFloat().coerceIn(0f, 1f),
        llmProvider = provider,
    )
}