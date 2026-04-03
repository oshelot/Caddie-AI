package com.caddieai.android.data.llm

import com.caddieai.android.data.model.LLMProvider
import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.model.ShotRecommendation
import com.caddieai.android.data.model.UserTier
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

class GeminiService @Inject constructor(
    private val httpClient: OkHttpClient,
    private val promptRepository: PromptRepository,
) : LLMService {

    companion object {
        private const val BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private val lenientJson = Json { ignoreUnknownKeys = true }
    }

    override suspend fun getRecommendation(
        context: ShotContext,
        profile: PlayerProfile,
        imageBase64: String?
    ): Result<ShotRecommendation> = runCatching {
        val apiKey = profile.googleApiKey.ifBlank {
            error("Google API key not configured")
        }
        val model = when (profile.effectiveTier) {
            UserTier.PRO -> "gemini-2.0-flash"
            UserTier.FREE -> "gemini-1.5-flash"
        }
        val url = "$BASE_URL/$model:generateContent?key=$apiKey"

        val parts = buildList {
            if (imageBase64 != null) {
                add(JsonObject(mapOf(
                    "inline_data" to JsonObject(mapOf(
                        "mime_type" to JsonPrimitive("image/jpeg"),
                        "data" to JsonPrimitive(imageBase64)
                    ))
                )))
            }
            add(JsonObject(mapOf(
                "text" to JsonPrimitive(
                    "${promptRepository.caddieSystemPromptWithPersona(profile.caddiePersona)}\n\n${PromptBuilder.buildShotPrompt(context, profile)}"
                )
            )))
        }

        val requestBody = JsonObject(mapOf(
            "contents" to JsonArray(listOf(
                JsonObject(mapOf("parts" to JsonArray(parts)))
            )),
            "generationConfig" to JsonObject(mapOf(
                "responseMimeType" to JsonPrimitive("application/json")
            ))
        ))

        val request = Request.Builder()
            .url(url)
            .addHeader("Content-Type", "application/json")
            .post(Json.encodeToString(requestBody).toRequestBody(JSON_MEDIA_TYPE))
            .build()

        val responseBody = httpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Gemini API error ${response.code}: ${response.body?.string()}")
            response.body?.string() ?: error("Empty response from Gemini")
        }

        val parsed = lenientJson.parseToJsonElement(responseBody) as JsonObject
        val content = ((parsed["candidates"] as JsonArray)
            .first() as JsonObject)["content"]
            .let { it as JsonObject }["parts"]
            .let { it as JsonArray }
            .first()
            .let { it as JsonObject }["text"]
            .let { (it as JsonPrimitive).content }

        val shotResponse = lenientJson.decodeFromString<LLMShotResponse>(content)
        shotResponse.toShotRecommendation(LLMProvider.GOOGLE)
    }

    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        profile: PlayerProfile,
        maxTokens: Int,
        jsonMode: Boolean,
        imageBase64: String?,
    ): Result<String> = runCatching {
        val apiKey = profile.googleApiKey.ifBlank { error("Google API key not configured") }
        val model = when (profile.effectiveTier) {
            UserTier.PRO -> "gemini-2.0-flash"
            UserTier.FREE -> "gemini-1.5-flash"
        }
        val url = "$BASE_URL/$model:generateContent?key=$apiKey"
        // Flatten messages into a single prompt for Gemini (no native multi-turn in this format)
        val fullText = messages.joinToString("\n\n") { "[${it.role.uppercase()}]\n${it.content}" }
        val parts = buildList {
            if (imageBase64 != null) {
                add(JsonObject(mapOf("inline_data" to JsonObject(mapOf(
                    "mime_type" to JsonPrimitive("image/jpeg"), "data" to JsonPrimitive(imageBase64),
                )))))
            }
            add(JsonObject(mapOf("text" to JsonPrimitive(fullText))))
        }
        val genConfig = mutableMapOf<String, JsonElement>(
            "maxOutputTokens" to JsonPrimitive(maxTokens),
        )
        if (jsonMode) genConfig["responseMimeType"] = JsonPrimitive("application/json")
        val requestBody = JsonObject(mapOf(
            "contents" to JsonArray(listOf(JsonObject(mapOf("parts" to JsonArray(parts))))),
            "generationConfig" to JsonObject(genConfig),
        ))
        val request = Request.Builder().url(url).addHeader("Content-Type", "application/json")
            .post(Json.encodeToString(requestBody).toRequestBody(JSON_MEDIA_TYPE)).build()
        val responseBody = httpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Gemini error ${response.code}: ${response.body?.string()}")
            response.body?.string() ?: error("Empty response")
        }
        val parsed = lenientJson.parseToJsonElement(responseBody) as JsonObject
        ((parsed["candidates"] as JsonArray).first() as JsonObject)["content"]
            .let { it as JsonObject }["parts"].let { it as JsonArray }
            .first().let { it as JsonObject }["text"].let { (it as JsonPrimitive).content }
    }
}
