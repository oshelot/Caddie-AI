package com.caddieai.android.data.llm

import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.model.LLMProvider
import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.model.ShotRecommendation
import com.caddieai.android.data.model.UserTier
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class LLMRouter @Inject constructor(
    private val openAIService: OpenAIService,
    private val claudeService: ClaudeService,
    private val geminiService: GeminiService,
    private val proxyService: LLMProxyService,
    private val logger: DiagnosticLogger,
) : LLMService {

    override suspend fun getRecommendation(
        context: ShotContext,
        profile: PlayerProfile,
        imageBase64: String?
    ): Result<ShotRecommendation> {
        val service = selectService(profile)
        val serviceName = service::class.simpleName.orEmpty()
        logger.log(LogLevel.INFO, LogCategory.LLM, "llm_shot_request",
            message = "LLM shot request via $serviceName",
            properties = mapOf("service" to serviceName))
        return service.getRecommendation(context, profile, imageBase64)
            .also { result ->
                if (result.isFailure) {
                    val err = result.exceptionOrNull()
                    logger.log(LogLevel.ERROR, LogCategory.LLM, "llm_shot_failed",
                        message = "LLM shot failed: ${err?.message ?: "unknown"}",
                        properties = mapOf("service" to serviceName, "error" to (err?.message ?: "unknown"),
                            "exceptionType" to (err?.javaClass?.simpleName ?: "Unknown")))
                }
            }
    }

    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        profile: PlayerProfile,
        maxTokens: Int,
        jsonMode: Boolean,
        imageBase64: String?,
    ): Result<String> {
        val service = selectService(profile)
        val serviceName = service::class.simpleName.orEmpty()
        logger.log(LogLevel.INFO, LogCategory.LLM, "llm_chat_request",
            message = "LLM chat request via $serviceName (${messages.size} messages)",
            properties = mapOf("service" to serviceName, "message_count" to messages.size))
        return service.chatCompletion(messages, profile, maxTokens, jsonMode, imageBase64)
            .also { result ->
                if (result.isSuccess) {
                    logger.log(LogLevel.INFO, LogCategory.LLM, "llm_chat_success",
                        message = "LLM chat completed successfully via $serviceName")
                } else {
                    val err = result.exceptionOrNull()
                    logger.log(LogLevel.ERROR, LogCategory.LLM, "llm_chat_failed",
                        message = "LLM chat failed: ${err?.message ?: "unknown"}",
                        properties = mapOf("service" to serviceName, "error" to (err?.message ?: "unknown"),
                            "exceptionType" to (err?.javaClass?.simpleName ?: "Unknown")))
                }
            }
    }

    private fun selectService(profile: PlayerProfile): LLMService {
        // Paid users with no personal key → proxy (only when proxy credentials are configured)
        if (profile.effectiveTier == UserTier.PRO && LLMProxyService.isAvailable()) {
            val hasPersonalKey = when (profile.llmProvider) {
                LLMProvider.OPENAI -> profile.openAiApiKey.isNotBlank()
                LLMProvider.ANTHROPIC -> profile.anthropicApiKey.isNotBlank()
                LLMProvider.GOOGLE -> profile.googleApiKey.isNotBlank()
            }
            if (!hasPersonalKey) return proxyService
        }
        return when (profile.llmProvider) {
            LLMProvider.OPENAI -> openAIService
            LLMProvider.ANTHROPIC -> claudeService
            LLMProvider.GOOGLE -> geminiService
        }
    }
}
