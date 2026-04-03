package com.caddieai.android.data.llm

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.caddieai.android.data.model.CaddiePersona
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PromptRepository @Inject constructor(
    private val httpClient: OkHttpClient,
    private val dataStore: DataStore<Preferences>,
    @ApplicationContext private val context: Context,
) {
    companion object {
        private const val PROMPTS_URL = "https://d3qprdq9wd6yo1.cloudfront.net/config/prompts.json"
        private val KEY_PROMPT_ETAG = stringPreferencesKey("prompt_etag")
        private val lenientJson = Json { ignoreUnknownKeys = true }
        private const val CACHE_FILE_NAME = "prompts_cache.json"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val cacheFile: File get() = File(context.filesDir, CACHE_FILE_NAME)

    @Volatile
    private var _config: PromptConfig = PromptConfig()

    /** Current prompt config — always non-null, starts with bundled defaults. */
    val config: PromptConfig get() = _config

    /** Returns the caddie system prompt, appending a PERSONA paragraph for non-Professional personas. */
    fun caddieSystemPromptWithPersona(persona: CaddiePersona): String {
        if (persona == CaddiePersona.PROFESSIONAL) return _config.caddieSystemPrompt
        val fragment = _config.personaFragments[persona.rawValue] ?: return _config.caddieSystemPrompt
        return "${_config.caddieSystemPrompt}\n\nPERSONA: $fragment"
    }

    init {
        scope.launch { loadFromDiskThenNetwork() }
    }

    private suspend fun loadFromDiskThenNetwork() {
        // Load disk cache first so prompts are ready before the network call completes
        if (cacheFile.exists()) {
            runCatching {
                val cached = lenientJson.decodeFromString<PromptConfig>(cacheFile.readText())
                _config = cached
            }
        }
        fetchFromNetwork()
    }

    private suspend fun fetchFromNetwork() {
        runCatching {
            val storedEtag = dataStore.data.first()[KEY_PROMPT_ETAG]
            val requestBuilder = Request.Builder().url(PROMPTS_URL)
            if (storedEtag != null) {
                requestBuilder.addHeader("If-None-Match", storedEtag)
            }

            httpClient.newCall(requestBuilder.build()).execute().use { response ->
                when (response.code) {
                    304 -> { /* Cached copy is still current */ }
                    200 -> {
                        val body = response.body?.string() ?: return
                        val newEtag = response.header("ETag")
                        val parsed = lenientJson.decodeFromString<PromptConfig>(body)
                        _config = parsed
                        cacheFile.writeText(body)
                        if (newEtag != null) {
                            dataStore.edit { it[KEY_PROMPT_ETAG] = newEtag }
                        }
                    }
                }
            }
        }
        // Failures (network unavailable, parse error) leave _config at bundled/cached value
    }
}
