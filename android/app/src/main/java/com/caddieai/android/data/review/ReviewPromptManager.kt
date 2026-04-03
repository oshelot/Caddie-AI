package com.caddieai.android.data.review

import android.app.Activity
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import com.google.android.play.core.review.ReviewInfo
import com.google.android.play.core.review.ReviewManagerFactory
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

@Singleton
class ReviewPromptManager @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) {
    companion object {
        private val KEY_FIRST_LAUNCH_MS = longPreferencesKey("review_first_launch_ms")
        private val KEY_LAST_PROMPT_MS = longPreferencesKey("review_last_prompt_ms")
        private val KEY_PROMPT_COUNT = intPreferencesKey("review_prompt_count")

        private const val MAX_PROMPTS = 3
        private val PROMPT_INTERVAL_MS = TimeUnit.DAYS.toMillis(90)
    }

    /**
     * Records the first launch timestamp if not yet set.
     * Call this on every app launch before eligibility check.
     */
    suspend fun recordLaunch() {
        val prefs = dataStore.data.first()
        if (prefs[KEY_FIRST_LAUNCH_MS] == null) {
            dataStore.edit { it[KEY_FIRST_LAUNCH_MS] = System.currentTimeMillis() }
        }
    }

    /**
     * Returns true if the user is eligible for a review prompt:
     * - Not the first launch (firstLaunchDate must be set)
     * - Prompt count < 3
     * - At least 90 days since last prompt (or first launch if never prompted)
     */
    suspend fun isEligibleForPrompt(): Boolean {
        val prefs = dataStore.data.first()
        val firstLaunchMs = prefs[KEY_FIRST_LAUNCH_MS] ?: return false
        val promptCount = prefs[KEY_PROMPT_COUNT] ?: 0
        val lastPromptMs = prefs[KEY_LAST_PROMPT_MS] ?: firstLaunchMs
        val now = System.currentTimeMillis()

        if (promptCount >= MAX_PROMPTS) return false
        if (now - lastPromptMs < PROMPT_INTERVAL_MS) return false
        return true
    }

    /**
     * Records that a review prompt was shown.
     */
    suspend fun recordPromptShown() {
        dataStore.edit { prefs ->
            prefs[KEY_LAST_PROMPT_MS] = System.currentTimeMillis()
            prefs[KEY_PROMPT_COUNT] = (prefs[KEY_PROMPT_COUNT] ?: 0) + 1
        }
    }

    /**
     * Triggers the Google Play In-App Review flow.
     * Silently no-ops if the Play quota has been exceeded.
     */
    suspend fun triggerReviewFlow(activity: Activity) {
        val manager = ReviewManagerFactory.create(activity)
        runCatching {
            val reviewInfo = suspendCancellableCoroutine<ReviewInfo?> { cont ->
                manager.requestReviewFlow().addOnCompleteListener { task ->
                    cont.resume(if (task.isSuccessful) task.result else null)
                }
            } ?: return

            suspendCancellableCoroutine { cont ->
                manager.launchReviewFlow(activity, reviewInfo)
                    .addOnCompleteListener { cont.resume(Unit) }
            }
        }
    }
}
