package com.caddieai.android.data.telemetry

import android.content.Context
import android.provider.Settings
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

enum class TelemetryEvent {
    LLM_CALL,
    GOLF_API_CALL,
    WEATHER_CALL,
    COURSE_PLAYED,
    AD_IMPRESSION,
    AD_CLICK,
    AD_LOAD_FAILURE,
    CONTACT_INFO_SUBMITTED,
}

private const val TELEMETRY_ENDPOINT = "https://api.caddieai.app/v1/telemetry"
private const val MAX_BATCH_SIZE = 25
private const val FLUSH_INTERVAL_MINUTES = 1L

@Singleton
class TelemetryService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val okHttpClient: OkHttpClient,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private val queue = mutableListOf<JSONObject>()

    private val deviceId: String by lazy {
        Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            ?: "unknown"
    }

    var optOut: Boolean = false

    init {
        schedulePeriodicFlush()
    }

    fun track(event: TelemetryEvent, properties: Map<String, Any> = emptyMap()) {
        if (optOut) return
        scope.launch {
            val payload = JSONObject().apply {
                put("event", event.name.lowercase())
                put("device_id", deviceId)
                put("timestamp_ms", System.currentTimeMillis())
                put("platform", "android")
                val props = JSONObject()
                properties.forEach { (k, v) -> props.put(k, v) }
                put("properties", props)
            }
            mutex.withLock { queue.add(payload) }
            if (queue.size >= MAX_BATCH_SIZE) flush()
        }
    }

    fun flush() {
        if (optOut) return
        scope.launch {
            val batch = mutex.withLock {
                if (queue.isEmpty()) return@launch
                val copy = queue.toList()
                queue.clear()
                copy
            }
            sendBatch(batch)
        }
    }

    private fun sendBatch(events: List<JSONObject>) {
        val body = JSONObject().apply {
            put("events", JSONArray(events))
        }
        val request = Request.Builder()
            .url(TELEMETRY_ENDPOINT)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        try {
            okHttpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    // Re-queue on failure
                    scope.launch { mutex.withLock { queue.addAll(0, events) } }
                }
            }
        } catch (e: Exception) {
            scope.launch { mutex.withLock { queue.addAll(0, events) } }
        }
    }

    private fun schedulePeriodicFlush() {
        val request = PeriodicWorkRequestBuilder<TelemetryFlushWorker>(
            FLUSH_INTERVAL_MINUTES, TimeUnit.MINUTES
        )
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            "telemetry_flush",
            ExistingPeriodicWorkPolicy.KEEP,
            request,
        )
    }
}
