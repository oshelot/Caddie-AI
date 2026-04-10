package com.caddieai.android.data.llm

import com.caddieai.android.BuildConfig
import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.model.LLMProvider
import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.model.ShotRecommendation
import com.caddieai.android.data.store.APIUsageStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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

/**
 * Backend proxy used by paid-tier subscribers (KAN-103/105).
 * Sends OpenAI-compatible requests to the CaddieAI proxy endpoint,
 * which handles model selection and API key management server-side.
 */
class LLMProxyService @Inject constructor(
    private val httpClient: OkHttpClient,
    private val promptRepository: PromptRepository,
    private val apiUsageStore: APIUsageStore,
    private val logger: DiagnosticLogger,
) : LLMService {

    companion object {
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private val lenientJson = Json { ignoreUnknownKeys = true }

        fun isAvailable(): Boolean =
            BuildConfig.LLM_PROXY_ENDPOINT.isNotBlank() && BuildConfig.LLM_PROXY_API_KEY.isNotBlank()
    }

    // Shot recommendations: 1500 tokens, JSON mode
    override suspend fun getRecommendation(
        context: ShotContext,
        profile: PlayerProfile,
        imageBase64: String?
    ): Result<ShotRecommendation> = runCatching {
        val systemPrompt = promptRepository.caddieSystemPromptWithPersona(profile.caddiePersona)
        val messages = listOf(
            JsonObject(mapOf("role" to JsonPrimitive("system"), "content" to JsonPrimitive(systemPrompt))),
            JsonObject(mapOf("role" to JsonPrimitive("user"), "content" to buildContent(PromptBuilder.buildShotPrompt(context, profile), imageBase64))),
        )
        val responseText = sendRequest(messages, maxTokens = 1500, jsonMode = true)
        val cleaned = extractJsonObject(responseText)
        lenientJson.decodeFromString<LLMShotResponse>(flattenProxyResponse(cleaned)).toShotRecommendation(LLMProvider.BEDROCK)
    }

    /**
     * Defensive JSON extraction. Bedrock Nova Micro may wrap JSON in markdown fences
     * (```json ... ```) or add preamble text. Strip fences and find the first {...} block.
     */
    private fun extractJsonObject(raw: String): String {
        val trimmed = raw.trim()
        // Strip markdown code fences
        val unfenced = trimmed
            .removePrefix("```json").removePrefix("```JSON").removePrefix("```")
            .removeSuffix("```")
            .trim()
        // If already starts with {, return as-is
        if (unfenced.startsWith("{")) return unfenced
        // Otherwise find the first { and last } and extract that range
        val first = unfenced.indexOf('{')
        val last = unfenced.lastIndexOf('}')
        return if (first >= 0 && last > first) unfenced.substring(first, last + 1) else unfenced
    }

    // Hole analysis & follow-ups: 500 tokens, plain text
    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        profile: PlayerProfile,
        maxTokens: Int,
        jsonMode: Boolean,
        imageBase64: String?,
    ): Result<String> = runCatching {
        val jsonMessages = messages.mapIndexed { idx, msg ->
            val isLastUser = msg.role == "user" && idx == messages.lastIndex
            val content: JsonElement = if (imageBase64 != null && isLastUser)
                buildContent(msg.content, imageBase64)
            else
                JsonPrimitive(msg.content)
            JsonObject(mapOf("role" to JsonPrimitive(msg.role), "content" to content))
        }
        sendRequest(jsonMessages, maxTokens = maxTokens, jsonMode = jsonMode)
    }

    /**
     * Streaming chat completion via SSE. Calls onChunk with the ACCUMULATED text after each
     * delta arrives. Returns the final accumulated text on success.
     */
    suspend fun chatCompletionStreaming(
        messages: List<ChatMessage>,
        maxTokens: Int = 500,
        onChunk: (String) -> Unit,
    ): Result<String> = runCatching {
        val jsonMessages = messages.map { msg ->
            JsonObject(mapOf("role" to JsonPrimitive(msg.role), "content" to JsonPrimitive(msg.content)))
        }
        sendRequestStreaming(jsonMessages, maxTokens, onChunk)
    }

    private suspend fun sendRequestStreaming(
        messages: List<JsonObject>,
        maxTokens: Int,
        onChunk: (String) -> Unit,
    ): String = withContext(Dispatchers.IO) {
        val bodyMap = mutableMapOf<String, JsonElement>(
            "messages"    to JsonArray(messages),
            "max_tokens"  to JsonPrimitive(maxTokens),
            "temperature" to JsonPrimitive(0.7),
            "stream"      to JsonPrimitive(true),
        )
        // BuildConfig fields are static — Kotlin re-reads them per request via
        // getstatic, so we always pick up whatever the freshly installed APK has.
        val buildBody = { Json.encodeToString(JsonObject(bodyMap)).toRequestBody(JSON_MEDIA_TYPE) }
        val buildRequest: () -> Request = {
            Request.Builder()
                .url(BuildConfig.LLM_PROXY_ENDPOINT)
                .addHeader("x-api-key", BuildConfig.LLM_PROXY_API_KEY)
                .addHeader("Content-Type", "application/json")
                .addHeader("Accept", "text/event-stream")
                .post(buildBody())
                .build()
        }

        val response = executeWithRetry(buildRequest, callSite = "stream")
        if (!response.isSuccessful) {
            val errBody = runCatching { response.body?.string().orEmpty() }.getOrDefault("")
            response.close()
            logProxyFailure("stream", response.code, errBody)
            error("Streaming proxy error ${response.code}")
        }

        val source = response.body?.source() ?: error("Empty streaming response body")
        val accumulated = StringBuilder()
        var totalTokens: Int? = null
        try {
            while (!source.exhausted()) {
                val line = source.readUtf8Line() ?: break
                if (line.isBlank()) continue
                if (!line.startsWith("data:")) continue
                val payload = line.removePrefix("data:").trim()
                if (payload == "[DONE]") break
                try {
                    val obj = lenientJson.parseToJsonElement(payload) as? JsonObject ?: continue
                    // Content delta
                    (obj["content"] as? JsonPrimitive)?.content?.let { delta ->
                        accumulated.append(delta)
                        onChunk(accumulated.toString())
                    }
                    // Usage event
                    (obj["usage"] as? JsonObject)?.let { usage ->
                        totalTokens = (usage["total_tokens"] as? JsonPrimitive)?.content?.toIntOrNull()
                    }
                } catch (_: Exception) {
                    // Skip malformed SSE lines
                }
            }
        } finally {
            response.close()
        }

        totalTokens?.let { tokens ->
            apiUsageStore.recordCall(LLMProvider.BEDROCK, tokens)
            logger.log(LogLevel.INFO, LogCategory.LLM, "proxy_stream_success", mapOf("tokens" to tokens))
        }
        accumulated.toString()
    }

    private suspend fun sendRequest(
        messages: List<JsonObject>,
        maxTokens: Int,
        jsonMode: Boolean,
    ): String = withContext(Dispatchers.IO) {
        val bodyMap = mutableMapOf<String, JsonElement>(
            "messages"    to JsonArray(messages),
            "max_tokens"  to JsonPrimitive(maxTokens),
            "temperature" to JsonPrimitive(0.7),
        )
        if (jsonMode) {
            bodyMap["response_format"] = JsonObject(mapOf("type" to JsonPrimitive("json_object")))
        }

        // BuildConfig.* are re-read on every call (static getstatic), so we
        // always pick up the latest installed key/endpoint.
        val buildRequest: () -> Request = {
            Request.Builder()
                .url(BuildConfig.LLM_PROXY_ENDPOINT)
                .addHeader("x-api-key", BuildConfig.LLM_PROXY_API_KEY)
                .addHeader("Content-Type", "application/json")
                .post(Json.encodeToString(JsonObject(bodyMap)).toRequestBody(JSON_MEDIA_TYPE))
                .build()
        }

        val responseBody = executeWithRetry(buildRequest, callSite = "request").use { response ->
            val body = response.body?.string() ?: error("Empty proxy response")
            if (!response.isSuccessful) {
                logProxyFailure("request", response.code, body)
                val errMsg = runCatching {
                    (lenientJson.parseToJsonElement(body) as? JsonObject)
                        ?.get("error")?.let { (it as? JsonPrimitive)?.content }
                }.getOrNull() ?: "Proxy error ${response.code}"
                error(errMsg)
            }
            body
        }

        val parsed = lenientJson.parseToJsonElement(responseBody) as JsonObject

        // Track token usage
        val totalTokens = (parsed["usage"] as? JsonObject)
            ?.get("total_tokens")
            ?.let { (it as? JsonPrimitive)?.content?.toIntOrNull() }
        totalTokens?.let { tokens ->
            apiUsageStore.recordCall(LLMProvider.BEDROCK, tokens)
            logger.log(LogLevel.INFO, LogCategory.LLM, "proxy_call_success", mapOf("tokens" to tokens))
        }

        (parsed["choices"] as JsonArray)
            .first().let { it as JsonObject }["message"]
            .let { it as JsonObject }["content"]
            .let { (it as JsonPrimitive).content }
    }

    /**
     * Normalizes the proxy/remote-schema response so LLMShotResponse can deserialize it.
     *
     * The remote prompts.json schema returns executionPlan as a rich object and rationale as
     * an array. This function converts them to human-readable strings so the UI renders cleanly.
     */
    private fun flattenProxyResponse(json: String): String {
        val obj = lenientJson.parseToJsonElement(json) as? JsonObject ?: return json
        val normalized = obj.toMutableMap()

        // executionPlan: extract the human-readable fields from the archetype object
        val executionPlanKey = if ("executionPlan" in normalized) "executionPlan" else "execution_plan"
        (normalized[executionPlanKey] as? JsonObject)?.let { plan ->
            fun str(key: String) = (plan[key] as? JsonPrimitive)?.content.orEmpty()
            val parts = listOfNotNull(
                str("setupSummary").takeIf { it.isNotBlank() },
                str("swingThought").takeIf { it.isNotBlank() }?.let { "Swing thought: $it" },
                str("strikeIntention").takeIf { it.isNotBlank() }?.let { "Strike: $it" },
                str("mistakeToAvoid").takeIf { it.isNotBlank() }?.let { "Avoid: $it" },
            )
            normalized[executionPlanKey] = JsonPrimitive(parts.joinToString("\n"))
        }

        // rationale array: join bullets into a single string for alternativeRationale
        (normalized["rationale"] as? JsonArray)?.let { arr ->
            val bullets = arr.filterIsInstance<JsonPrimitive>().joinToString("\n") { "• ${it.content}" }
            normalized["rationale"] = JsonPrimitive(bullets)
        }

        // Any remaining object/array fields that map to strings: fall back to toString
        val otherStringFields = setOf(
            "target_description", "targetDescription", "target",
            "alternative_rationale", "alternativeRationale",
            "wind_adjustment_note", "windAdjustmentNote",
            "slope_adjustment_note", "slopeAdjustmentNote",
            "conservativeOption", "swingThought",
        )
        otherStringFields.forEach { key ->
            val value = normalized[key]
            if (value is JsonObject || value is JsonArray) {
                normalized[key] = JsonPrimitive(value.toString())
            }
        }

        return JsonObject(normalized).toString()
    }

    /**
     * Executes a request with one automatic retry on transient failures
     * (5xx, 408 timeout, IOException). 4xx — including 401/403 auth errors
     * — are returned immediately because retrying with the same key won't
     * help and would just amplify rate-limit problems.
     */
    private suspend fun executeWithRetry(
        buildRequest: () -> Request,
        callSite: String,
        maxRetries: Int = 1,
    ): okhttp3.Response {
        var lastError: Throwable? = null
        var attempt = 0
        while (true) {
            try {
                val response = httpClient.newCall(buildRequest()).execute()
                val transient = response.code == 408 || response.code in 500..599
                if (transient && attempt < maxRetries) {
                    logger.log(LogLevel.WARN, LogCategory.LLM, "proxy_retry",
                        mapOf("status" to response.code, "attempt" to attempt, "site" to callSite))
                    response.close()
                    attempt++
                    kotlinx.coroutines.delay(500L * attempt)
                    continue
                }
                return response
            } catch (e: java.io.IOException) {
                lastError = e
                if (attempt < maxRetries) {
                    logger.log(LogLevel.WARN, LogCategory.LLM, "proxy_retry_io",
                        mapOf("error" to (e.message ?: "io"), "attempt" to attempt, "site" to callSite))
                    attempt++
                    kotlinx.coroutines.delay(500L * attempt)
                    continue
                }
                throw e
            }
        }
    }

    /**
     * Emits a structured failure log with enough context to diagnose auth
     * mismatches against CloudWatch (status, key prefix, endpoint host, body
     * preview). Auth errors (401/403) get an extra ERROR-level event so they
     * stand out.
     */
    private fun logProxyFailure(callSite: String, status: Int, body: String) {
        val key = BuildConfig.LLM_PROXY_API_KEY
        val keyPrefix = if (key.length >= 6) key.take(6) else "(empty)"
        val endpoint = BuildConfig.LLM_PROXY_ENDPOINT
        val host = runCatching { java.net.URI(endpoint).host }.getOrNull() ?: ""
        val event = if (status == 401 || status == 403) "proxy_auth_failed" else "proxy_call_failed"
        val level = if (status == 401 || status == 403) LogLevel.ERROR else LogLevel.WARN
        logger.log(level, LogCategory.LLM, event, mapOf(
            "status" to status,
            "site" to callSite,
            "keyPrefix" to keyPrefix,
            "host" to host,
            "bodyPreview" to body.take(200),
        ))
        android.util.Log.e("CaddieAI/Proxy",
            "$event status=$status site=$callSite key=$keyPrefix… host=$host body=${body.take(200)}")
    }

    private fun buildContent(text: String, imageBase64: String?): JsonElement {
        if (imageBase64 == null) return JsonPrimitive(text)
        return JsonArray(listOf(
            JsonObject(mapOf("type" to JsonPrimitive("text"), "text" to JsonPrimitive(text))),
            JsonObject(mapOf(
                "type" to JsonPrimitive("image_url"),
                "image_url" to JsonObject(mapOf("url" to JsonPrimitive("data:image/jpeg;base64,$imageBase64"))),
            )),
        ))
    }
}
