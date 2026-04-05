package com.caddieai.android.ui.screens.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.caddieai.android.data.model.Aggressiveness
import com.caddieai.android.data.model.BunkerConfidence
import com.caddieai.android.data.model.CaddieAccent
import com.caddieai.android.data.model.CaddieGender
import com.caddieai.android.data.model.CaddiePersona
import com.caddieai.android.data.model.ChipStyle
import com.caddieai.android.data.model.Club
import com.caddieai.android.data.model.LLMProvider
import com.caddieai.android.data.model.MissTendency
import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.StockShape
import com.caddieai.android.data.model.SwingTendency
import com.caddieai.android.data.model.UserTier
import com.caddieai.android.data.model.WedgeConfidence
import com.caddieai.android.data.store.ProfileStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val profileStore: ProfileStore,
) : ViewModel() {

    val profile: StateFlow<PlayerProfile> = profileStore.profile
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlayerProfile())

    private fun update(transform: (PlayerProfile) -> PlayerProfile) {
        viewModelScope.launch { profileStore.update(transform) }
    }

    fun setName(v: String) = update { it.copy(name = v).withUpdatedAt() }
    fun setEmail(v: String) = update { it.copy(email = v).withUpdatedAt() }
    fun setPhone(v: String) = update { it.copy(phone = v).withUpdatedAt() }
    fun setHandicap(v: Float) = update { it.copy(handicap = v).withUpdatedAt() }
    fun setStockShape(v: StockShape) = update { it.copy(stockShape = v).withUpdatedAt() }
    fun setMissTendency(v: MissTendency) = update { it.copy(missTendency = v).withUpdatedAt() }
    fun setAggressiveness(v: Aggressiveness) = update { it.copy(aggressiveness = v).withUpdatedAt() }
    fun setBunkerConfidence(v: BunkerConfidence) = update { it.copy(bunkerConfidence = v).withUpdatedAt() }
    fun setWedgeConfidence(v: WedgeConfidence) = update { it.copy(wedgeConfidence = v).withUpdatedAt() }
    fun setChipStyle(v: ChipStyle) = update { it.copy(chipStyle = v).withUpdatedAt() }
    fun setSwingTendency(v: SwingTendency) = update { it.copy(swingTendency = v).withUpdatedAt() }
    fun setCaddiePersona(v: CaddiePersona) = update { it.copy(caddiePersona = v).withUpdatedAt() }
    fun setCaddieGender(v: CaddieGender) = update { it.copy(caddieGender = v).withUpdatedAt() }
    fun setCaddieAccent(v: CaddieAccent) = update { it.copy(caddieAccent = v).withUpdatedAt() }
    fun setVoiceEnabled(v: Boolean) = update { it.copy(voiceEnabled = v).withUpdatedAt() }
    fun setLlmProvider(v: LLMProvider) = update { it.copy(llmProvider = v).withUpdatedAt() }
    fun setOpenAiApiKey(v: String) = update { it.copy(openAiApiKey = v).withUpdatedAt() }
    fun setAnthropicApiKey(v: String) = update { it.copy(anthropicApiKey = v).withUpdatedAt() }
    fun setGoogleApiKey(v: String) = update { it.copy(googleApiKey = v).withUpdatedAt() }
    fun setUsesMetric(v: Boolean) = update { it.copy(usesMetric = v).withUpdatedAt() }
    fun setImageAnalysisBetaEnabled(v: Boolean) = update { it.copy(imageAnalysisBetaEnabled = v).withUpdatedAt() }
    fun setPreferredTeeBox(v: com.caddieai.android.data.model.TeeBoxPreference) = update { it.copy(preferredTeeBox = v).withUpdatedAt() }
    fun setScoringEnabled(v: Boolean) = update { it.copy(scoringEnabled = v).withUpdatedAt() }
    fun setDebugTierOverride(isPro: Boolean) = update {
        it.copy(debugTierOverride = if (isPro) UserTier.PRO else null).withUpdatedAt()
    }
    fun setDebugLoggingEnabled(v: Boolean) = update { it.copy(debugLoggingEnabled = v).withUpdatedAt() }
    fun setClubDistance(club: Club, yards: Int) = update {
        it.copy(clubDistances = it.clubDistances + (club to yards)).withUpdatedAt()
    }

    fun addClub(club: Club) = update {
        it.copy(bagClubs = it.bagClubs + club).withUpdatedAt()
    }

    fun removeClub(club: Club) = update {
        it.copy(bagClubs = it.bagClubs - club).withUpdatedAt()
    }
}
