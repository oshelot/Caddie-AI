package com.caddieai.android.data.store

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.caddieai.android.data.model.LLMProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.YearMonth
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
data class MonthlyUsage(
    val month: String, // "2026-03"
    val callsByProvider: Map<String, Int> = emptyMap()
) {
    fun totalCalls(): Int = callsByProvider.values.sum()
    fun callsFor(provider: LLMProvider): Int = callsByProvider[provider.name] ?: 0
}

@Singleton
class APIUsageStore @Inject constructor(
    private val dataStore: DataStore<Preferences>
) {
    companion object {
        private val KEY_API_USAGE = stringPreferencesKey("api_usage_v1")
        private const val MONTHS_TO_KEEP = 3
    }

    val currentMonthUsage: Flow<MonthlyUsage> = dataStore.data
        .map { prefs ->
            val currentMonth = YearMonth.now().toString()
            val all = prefs[KEY_API_USAGE]
                ?.let { Json.decodeFromString<List<MonthlyUsage>>(it) }
                ?: emptyList()
            all.firstOrNull { it.month == currentMonth } ?: MonthlyUsage(currentMonth)
        }
        .catch { emit(MonthlyUsage(YearMonth.now().toString())) }

    suspend fun getCurrentMonthUsage(): MonthlyUsage = currentMonthUsage.first()

    suspend fun recordCall(provider: LLMProvider, count: Int = 1) {
        val currentMonth = YearMonth.now().toString()
        dataStore.edit { prefs ->
            val all = prefs[KEY_API_USAGE]
                ?.let { Json.decodeFromString<List<MonthlyUsage>>(it) }
                ?.toMutableList()
                ?: mutableListOf()

            val idx = all.indexOfFirst { it.month == currentMonth }
            val existing = if (idx >= 0) all[idx] else MonthlyUsage(currentMonth)
            val updated = existing.copy(
                callsByProvider = existing.callsByProvider.toMutableMap().also {
                    it[provider.name] = (it[provider.name] ?: 0) + count
                }
            )
            if (idx >= 0) all[idx] = updated else all.add(updated)

            // Prune old months
            val cutoff = YearMonth.now().minusMonths(MONTHS_TO_KEEP.toLong()).toString()
            val pruned = all.filter { it.month >= cutoff }
            prefs[KEY_API_USAGE] = Json.encodeToString(pruned)
        }
    }
}
