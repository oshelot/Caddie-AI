package com.caddieai.android.data.diagnostics

import android.content.Context
import android.os.Build
import android.provider.Settings
import com.caddieai.android.BuildConfig
import com.caddieai.android.data.store.ProfileStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

enum class LogLevel { INFO, WARN, ERROR }

enum class LogCategory { API, CACHE, LLM, SUBSCRIPTION, NAVIGATION, LIFECYCLE, MAP }

private const val RING_BUFFER_MAX = 200
private const val FLUSH_THRESHOLD = 50
private const val AUTO_FLUSH_INTERVAL_MS = 30_000L

@Singleton
class DiagnosticLogger @Inject constructor(
    @ApplicationContext private val context: Context,
    private val okHttpClient: OkHttpClient,
    private val profileStore: ProfileStore,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private val buffer = ArrayDeque<JSONObject>(RING_BUFFER_MAX)

    val sessionId: String = UUID.randomUUID().toString()

    // In debug builds, respect the runtime toggle from the Debug section of Profile.
    // In release builds, logging is always on when LOGGING_ENDPOINT is configured.
    @Volatile private var debugLoggingEnabled: Boolean = false

    private val deviceId: String by lazy {
        val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            ?: "unknown"
        val hash = MessageDigest.getInstance("SHA-256").digest(androidId.toByteArray())
        hash.take(8).joinToString("") { "%02x".format(it) }
    }

    init {
        scope.launch {
            if (BuildConfig.DEBUG) {
                profileStore.profile.collect { profile ->
                    debugLoggingEnabled = profile.debugLoggingEnabled
                }
            }
        }
        scope.launch {
            while (true) {
                delay(AUTO_FLUSH_INTERVAL_MS)
                flush()
            }
        }
    }

    private fun isEnabled(): Boolean {
        if (BuildConfig.LOGGING_ENDPOINT.isBlank()) return false
        return if (BuildConfig.DEBUG) debugLoggingEnabled else true
    }

    fun log(
        level: LogLevel,
        category: LogCategory,
        event: String,
        properties: Map<String, Any> = emptyMap(),
        message: String = event,
    ) {
        if (!isEnabled()) return
        scope.launch {
            val entry = JSONObject().apply {
                put("level", level.name.lowercase())
                put("category", category.name.lowercase())
                put("event", event)
                put("message", message)
                put("timestampMs", System.currentTimeMillis())
                if (properties.isNotEmpty()) {
                    val props = JSONObject()
                    properties.forEach { (k, v) -> props.put(k, v) }
                    put("properties", props)
                }
            }
            mutex.withLock {
                if (buffer.size >= RING_BUFFER_MAX) buffer.removeFirst()
                buffer.addLast(entry)
            }
            if (buffer.size >= FLUSH_THRESHOLD) flush()
        }
    }

    fun flush() {
        if (!isEnabled()) return
        scope.launch {
            val batch = mutex.withLock {
                if (buffer.isEmpty()) return@launch
                val copy = buffer.toList()
                buffer.clear()
                copy
            }
            sendBatch(batch)
        }
    }

    private fun sendBatch(entries: List<JSONObject>) {
        val body = JSONObject().apply {
            put("deviceId", deviceId)
            put("sessionId", sessionId)
            put("platform", "android")
            put("appVersion", BuildConfig.VERSION_NAME)
            put("buildNumber", BuildConfig.VERSION_CODE)
            put("osVersion", Build.VERSION.RELEASE)
            put("deviceModel", Build.MODEL)
            put("entries", JSONArray(entries))
        }
        val request = Request.Builder()
            .url(BuildConfig.LOGGING_ENDPOINT)
            .addHeader("x-api-key", BuildConfig.LOGGING_API_KEY)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        try {
            okHttpClient.newCall(request).execute().use { /* fire-and-forget */ }
        } catch (_: Exception) {
            // Best-effort: diagnostic logs are dropped on network failure
        }
    }
}