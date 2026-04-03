package com.caddieai.android.ui.screens.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.caddieai.android.data.model.Club
import com.caddieai.android.data.model.Outcome
import com.caddieai.android.data.model.ShotHistoryEntry
import com.caddieai.android.data.store.ShotHistoryStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ClubUsageStat(val club: Club, val count: Int)

data class HistoryState(
    val shots: List<ShotHistoryEntry> = emptyList(),
    val clubUsage: List<ClubUsageStat> = emptyList(),
    val outcomeBreakdown: Map<Outcome, Int> = emptyMap(),
)

@HiltViewModel
class HistoryViewModel @Inject constructor(
    private val historyStore: ShotHistoryStore,
) : ViewModel() {

    val state: StateFlow<HistoryState> = historyStore.shots
        .map { shots ->
            val clubUsage = shots
                .mapNotNull { it.actualClubUsed ?: it.recommendation?.recommendedClub }
                .groupingBy { it }
                .eachCount()
                .entries
                .sortedByDescending { it.value }
                .take(10)
                .map { ClubUsageStat(it.key, it.value) }

            val outcomes = shots
                .groupingBy { it.outcome }
                .eachCount()

            HistoryState(shots = shots.sortedByDescending { it.timestampMs }, clubUsage = clubUsage, outcomeBreakdown = outcomes)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HistoryState())

    fun deleteShot(id: String) {
        viewModelScope.launch { historyStore.removeShot(id) }
    }

    fun updateShot(id: String, outcome: Outcome, actualClub: Club?, notes: String) {
        viewModelScope.launch {
            historyStore.updateShot(id) { shot ->
                shot.copy(outcome = outcome, actualClubUsed = actualClub, notes = notes)
            }
        }
    }
}
