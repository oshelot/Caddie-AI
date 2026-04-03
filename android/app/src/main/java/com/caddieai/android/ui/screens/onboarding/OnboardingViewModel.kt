package com.caddieai.android.ui.screens.onboarding

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class OnboardingViewModel @Inject constructor(
    private val dataStore: DataStore<Preferences>
) : ViewModel() {

    companion object {
        private val KEY_SETUP_NOTICE_SEEN = booleanPreferencesKey("setup_notice_seen")
        private val KEY_CONTACT_PROMPT_COUNT = intPreferencesKey("contact_prompt_count")
        private val KEY_LAST_CONTACT_PROMPT_MS = longPreferencesKey("last_contact_prompt_ms")
        private val KEY_SWING_CAPTURE_DONE = booleanPreferencesKey("swing_capture_done")
        const val MAX_CONTACT_PROMPTS = 3
        const val CONTACT_PROMPT_INTERVAL_MS = 30L * 24 * 60 * 60 * 1000 // 30 days
    }

    suspend fun getOnboardingState(): OnboardingState {
        val prefs = dataStore.data.first()
        return OnboardingState(
            hasSeenSetupNotice = prefs[KEY_SETUP_NOTICE_SEEN] ?: false,
            contactPromptCount = prefs[KEY_CONTACT_PROMPT_COUNT] ?: 0,
            lastContactPromptMs = prefs[KEY_LAST_CONTACT_PROMPT_MS] ?: 0L
        )
    }

    fun shouldShowContactPrompt(count: Int, lastMs: Long): Boolean {
        if (count >= MAX_CONTACT_PROMPTS) return false
        if (count == 0) return true
        return System.currentTimeMillis() - lastMs >= CONTACT_PROMPT_INTERVAL_MS
    }

    suspend fun isSwingCaptureDone(): Boolean = dataStore.data.first()[KEY_SWING_CAPTURE_DONE] ?: false

    fun markSwingCaptureDone() = viewModelScope.launch {
        dataStore.edit { it[KEY_SWING_CAPTURE_DONE] = true }
    }

    fun markSetupNoticeSeen() = viewModelScope.launch {
        dataStore.edit { it[KEY_SETUP_NOTICE_SEEN] = true }
    }

    fun recordContactPromptShown() = viewModelScope.launch {
        dataStore.edit { prefs ->
            prefs[KEY_CONTACT_PROMPT_COUNT] = (prefs[KEY_CONTACT_PROMPT_COUNT] ?: 0) + 1
            prefs[KEY_LAST_CONTACT_PROMPT_MS] = System.currentTimeMillis()
        }
    }
}

data class OnboardingState(
    val hasSeenSetupNotice: Boolean,
    val contactPromptCount: Int,
    val lastContactPromptMs: Long
)
