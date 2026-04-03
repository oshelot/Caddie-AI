package com.caddieai.android.data.llm

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

class ClaudeService @Inject constructor(
    private val httpClient: OkHttpClient,
    private val promptRepository: PromptRepository,
) : LLMService {

    companion object {
        private const val BASE_URL = "https://api.anthropic.com/v1/messages"
        private const val ANTHROPIC_VERSION = "2023-06-01"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private val lenientJson = Json { ignoreUnknownKeys = true }
    }

    override suspend fun getRecommendation(
        context: ShotContext,
        profile: PlayerProfile,
        imageBase64: String?
    ): Result<ShotRecommendation> = runCatching {
        val apiKey = profile.anthropicApiKey.ifBlank {
            error("Anthropic API key not configured")
        }
        val model = when (profile.effectiveTier) {
            com.caddieai.android.data.model.UserTier.PRO -> "claude-sonnet-4-6"
            com.caddieai.android.data.model.UserTier.FREE -> "claude-haiku-4-5-20251001"
        }

        val userContent = if (imageBase64 != null) {
            JsonArray(listOf(
                JsonObject(mapOf(
                    "type" to JsonPrimitive("image"),
                    "source" to JsonObject(mapOf(
                        "type" to JsonPrimitive("base64"),
                        "media_type" to JsonPrimitive("image/jpeg"),
                        "data" to JsonPrimitive(imageBase64)
                    ))
                )),
                JsonObject(mapOf(
                    "type" to JsonPrimitive("text"),
                    "text" to JsonPrimitive(PromptBuilder.buildShotPrompt(context, profile))
                ))
            ))
        } else {
            JsonPrimitive(PromptBuilder.buildShotPrompt(context, profile))
        }

        val requestBody = JsonObject(mapOf(
            "model" to JsonPrimitive(model),
            "max_tokens" to JsonPrimitive(1024),
            "system" to JsonPrimitive(promptRepository.caddieSystemPromptWithPersona(profile.caddiePersona)),
            "messages" to JsonArray(listOf(
                JsonObject(mapOf(
                    "role" to JsonPrimitive("user"),
                    "content" to userContent
                ))
            ))
        ))

        val request = Request.Builder()
            .url(BASE_URL)
            .addHeader("x-api-key", apiKey)
            .addHeader("anthropic-version", ANTHROPIC_VERSION)
            .addHeader("Content-Type", "application/json")
            .post(Json.encodeToString(requestBody).toRequestBody(JSON_MEDIA_TYPE))
            .build()

        val responseBody = httpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Claude API error ${response.code}: ${response.body?.string()}")
            response.body?.string() ?: error("Empty response from Claude")
        }

        val parsed = lenientJson.parseToJsonElement(responseBody) as JsonObject
        val content = (parsed["content"] as JsonArray)
            .first()
            .let { it as JsonObject }["text"]
            .let { (it as JsonPrimitive).content }
            .trim()
            .let { if (it.startsWith("```")) it.lines().drop(1).dropLast(1).joinToString("\n") else it }

        val shotResponse = lenientJson.decodeFromString<LLMShotResponse>(content)
        shotResponse.toShotRecommendation(LLMProvider.ANTHROPIC)
    }

    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        profile: PlayerProfile,
        maxTokens: Int,
        jsonMode: Boolean,
        imageBase64: String?,
    ): Result<String> = runCatching {
        val apiKey = profile.anthropicApiKey.ifBlank { error("Anthropic API key not configured") }
        val model = when (profile.effectiveTier) {
            com.caddieai.android.data.model.UserTier.PRO -> "claude-sonnet-4-6"
            com.caddieai.android.data.model.UserTier.FREE -> "claude-haiku-4-5-20251001"
        }
        val systemMsg = messages.firstOrNull { it.role == "system" }?.content
        val nonSystem = messages.filter { it.role != "system" }
        val jsonMessages = nonSystem.mapIndexed { idx, msg ->
            val isLastUser = msg.role == "user" && idx == nonSystem.lastIndex
            val content: JsonElement = if (imageBase64 != null && isLastUser) {
                JsonArray(listOf(
                    JsonObject(mapOf("type" to JsonPrimitive("image"), "source" to JsonObject(mapOf(
                        "type" to JsonPrimitive("base64"), "media_type" to JsonPrimitive("image/jpeg"), "data" to JsonPrimitive(imageBase64),
                    )))),
                    JsonObject(mapOf("type" to JsonPrimitive("text"), "text" to JsonPrimitive(msg.content))),
                ))
            } else JsonPrimitive(msg.content)
            JsonObject(mapOf("role" to JsonPrimitive(msg.role), "content" to content))
        }
        val bodyMap = mutableMapOf<String, JsonElement>(
            "model" to JsonPrimitive(model), "max_tokens" to JsonPrimitive(maxTokens), "messages" to JsonArray(jsonMessages),
        )
        if (systemMsg != null) bodyMap["system"] = JsonPrimitive(systemMsg)
        val request = Request.Builder()
            .url(BASE_URL).addHeader("x-api-key", apiKey)
            .addHeader("anthropic-version", ANTHROPIC_VERSION).addHeader("Content-Type", "application/json")
            .post(Json.encodeToString(JsonObject(bodyMap)).toRequestBody(JSON_MEDIA_TYPE)).build()
        val responseBody = httpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Claude error ${response.code}: ${response.body?.string()}")
            response.body?.string() ?: error("Empty response")
        }
        val parsed = lenientJson.parseToJsonElement(responseBody) as JsonObject
        (parsed["content"] as JsonArray).first().let { it as JsonObject }["text"].let { (it as JsonPrimitive).content }
    }
}
