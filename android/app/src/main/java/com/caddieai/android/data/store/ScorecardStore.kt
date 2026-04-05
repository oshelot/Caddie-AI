package com.caddieai.android.data.store

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.caddieai.android.data.model.Scorecard
import com.caddieai.android.data.model.ScorecardStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Local persistence for scorecards. At most one in-progress scorecard at a time.
 * KAN-224.
 */
@Singleton
class ScorecardStore @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) {
    companion object {
        private val KEY_SCORECARDS = stringPreferencesKey("scorecards_v1")
    }

    val scorecards: Flow<List<Scorecard>> = dataStore.data
        .map { prefs ->
            prefs[KEY_SCORECARDS]?.let { Json.decodeFromString<List<Scorecard>>(it) } ?: emptyList()
        }
        .catch { emit(emptyList()) }

    suspend fun list(): List<Scorecard> = scorecards.first()

    suspend fun activeScorecard(): Scorecard? =
        list().firstOrNull { it.status == ScorecardStatus.IN_PROGRESS }

    suspend fun save(scorecard: Scorecard) {
        dataStore.edit { prefs ->
            val current = prefs[KEY_SCORECARDS]
                ?.let { Json.decodeFromString<List<Scorecard>>(it) }
                ?: emptyList()
            // If saving a new IN_PROGRESS scorecard, complete any existing in-progress ones
            val updated = if (scorecard.status == ScorecardStatus.IN_PROGRESS) {
                current.map {
                    if (it.status == ScorecardStatus.IN_PROGRESS && it.id != scorecard.id) {
                        it.copy(status = ScorecardStatus.COMPLETED)
                    } else it
                }
            } else current
            val existingIndex = updated.indexOfFirst { it.id == scorecard.id }
            val result = if (existingIndex >= 0) {
                updated.toMutableList().also { it[existingIndex] = scorecard }
            } else {
                updated + scorecard
            }
            prefs[KEY_SCORECARDS] = Json.encodeToString(result)
        }
    }

    suspend fun delete(id: String) {
        dataStore.edit { prefs ->
            val current = prefs[KEY_SCORECARDS]
                ?.let { Json.decodeFromString<List<Scorecard>>(it) }
                ?: emptyList()
            prefs[KEY_SCORECARDS] = Json.encodeToString(current.filter { it.id != id })
        }
    }

    suspend fun complete(id: String) {
        dataStore.edit { prefs ->
            val current = prefs[KEY_SCORECARDS]
                ?.let { Json.decodeFromString<List<Scorecard>>(it) }
                ?: emptyList()
            prefs[KEY_SCORECARDS] = Json.encodeToString(
                current.map { if (it.id == id) it.copy(status = ScorecardStatus.COMPLETED) else it }
            )
        }
    }

    suspend fun clearAll() {
        dataStore.edit { it.remove(KEY_SCORECARDS) }
    }
}
