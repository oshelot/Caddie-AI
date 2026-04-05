package com.caddieai.android.data.store

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.caddieai.android.BuildConfig
import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.UserTier
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ProfileStore @Inject constructor(
    private val dataStore: DataStore<Preferences>
) {
    companion object {
        private val KEY_PROFILE = stringPreferencesKey("player_profile_v1")
    }

    private fun defaultProfile(): PlayerProfile {
        // Debug builds default to Pro tier (overrideable from Profile > Settings > Debug)
        return if (BuildConfig.DEBUG) PlayerProfile(debugTierOverride = UserTier.PRO)
               else PlayerProfile()
    }

    val profile: Flow<PlayerProfile> = dataStore.data
        .map { prefs ->
            prefs[KEY_PROFILE]?.let { json ->
                Json.decodeFromString<PlayerProfile>(json)
            } ?: defaultProfile()
        }
        .catch { emit(defaultProfile()) }

    suspend fun getProfile(): PlayerProfile = profile.first()

    suspend fun save(profile: PlayerProfile) {
        dataStore.edit { prefs ->
            prefs[KEY_PROFILE] = Json.encodeToString(profile.withUpdatedAt())
        }
    }

    suspend fun update(transform: (PlayerProfile) -> PlayerProfile) {
        val current = getProfile()
        save(transform(current))
    }
}
