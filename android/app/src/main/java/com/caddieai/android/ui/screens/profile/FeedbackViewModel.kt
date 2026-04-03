package com.caddieai.android.ui.screens.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.caddieai.android.data.store.ProfileStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import javax.inject.Inject

sealed class FeedbackState {
    data object Idle : FeedbackState()
    data object Sending : FeedbackState()
    data object Success : FeedbackState()
    data class Error(val message: String) : FeedbackState()
}

@HiltViewModel
class FeedbackViewModel @Inject constructor(
    private val profileStore: ProfileStore,
    private val httpClient: OkHttpClient,
) : ViewModel() {

    companion object {
        private const val FEEDBACK_URL = "https://api.caddieai.app/v1/feedback"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }

    private val _state = MutableStateFlow<FeedbackState>(FeedbackState.Idle)
    val state: StateFlow<FeedbackState> = _state.asStateFlow()

    fun sendFeedback(
        name: String,
        email: String,
        description: String,
        screenshotBase64: String?,
    ) {
        viewModelScope.launch {
            _state.value = FeedbackState.Sending
            runCatching {
                val profile = profileStore.getProfile()
                val bodyMap = buildMap<String, Any?> {
                    put("name", name.ifBlank { profile.name }.trim())
                    put("email", email.ifBlank { profile.email }.trim())
                    put("description", description.trim())
                    put("platform", "android")
                    if (screenshotBase64 != null) put("screenshot_base64", screenshotBase64)
                }
                val jsonBody = JsonObject(bodyMap.mapValues { (_, v) ->
                    JsonPrimitive(v?.toString())
                })

                withContext(Dispatchers.IO) {
                    val request = Request.Builder()
                        .url(FEEDBACK_URL)
                        .addHeader("Content-Type", "application/json")
                        .post(Json.encodeToString(jsonBody).toRequestBody(JSON_MEDIA_TYPE))
                        .build()
                    httpClient.newCall(request).execute().use { response ->
                        if (!response.isSuccessful) error("Server error ${response.code}")
                    }
                }
            }.onSuccess {
                _state.value = FeedbackState.Success
            }.onFailure { e ->
                _state.value = FeedbackState.Error(e.message ?: "Unknown error")
            }
        }
    }

    fun resetState() {
        _state.value = FeedbackState.Idle
    }
}
