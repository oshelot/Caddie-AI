package com.caddieai.android.data.store

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.caddieai.android.data.model.ShotHistoryEntry
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ShotHistoryStore @Inject constructor(
    private val dataStore: DataStore<Preferences>
) {
    companion object {
        private val KEY_SHOT_HISTORY = stringPreferencesKey("shot_history_v1")
        private const val THREE_MONTHS_MS = 90L * 24 * 60 * 60 * 1000
    }

    /** All shot history entries, automatically pruned to last 3 months on each read. */
    val shots: Flow<List<ShotHistoryEntry>> = dataStore.data
        .map { prefs ->
            prefs[KEY_SHOT_HISTORY]
                ?.let { Json.decodeFromString<List<ShotHistoryEntry>>(it) }
                ?.filter { it.timestampMs >= System.currentTimeMillis() - THREE_MONTHS_MS }
                ?: emptyList()
        }
        .catch { emit(emptyList()) }

    suspend fun getShots(): List<ShotHistoryEntry> = shots.first()

    suspend fun addShot(entry: ShotHistoryEntry) {
        dataStore.edit { prefs ->
            val current = prefs[KEY_SHOT_HISTORY]
                ?.let { Json.decodeFromString<List<ShotHistoryEntry>>(it) }
                ?.filter { it.timestampMs >= System.currentTimeMillis() - THREE_MONTHS_MS }
                ?: emptyList()
            prefs[KEY_SHOT_HISTORY] = Json.encodeToString(current + entry)
        }
    }

    suspend fun updateShot(id: String, transform: (ShotHistoryEntry) -> ShotHistoryEntry) {
        dataStore.edit { prefs ->
            val current = prefs[KEY_SHOT_HISTORY]
                ?.let { Json.decodeFromString<List<ShotHistoryEntry>>(it) }
                ?: emptyList()
            prefs[KEY_SHOT_HISTORY] = Json.encodeToString(current.map { if (it.id == id) transform(it) else it })
        }
    }

    suspend fun removeShot(id: String) {
        dataStore.edit { prefs ->
            val current = prefs[KEY_SHOT_HISTORY]
                ?.let { Json.decodeFromString<List<ShotHistoryEntry>>(it) }
                ?: emptyList()
            prefs[KEY_SHOT_HISTORY] = Json.encodeToString(current.filter { it.id != id })
        }
    }

    suspend fun clearAll() {
        dataStore.edit { it.remove(KEY_SHOT_HISTORY) }
    }
}
