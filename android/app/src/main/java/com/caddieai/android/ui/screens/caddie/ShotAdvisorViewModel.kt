package com.caddieai.android.ui.screens.caddie

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.caddieai.android.data.caddie.AutoDetectService
import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.engine.ExecutionEngine
import com.caddieai.android.data.engine.GolfLogicEngine
import com.caddieai.android.data.engine.ShotArchetype
import com.caddieai.android.data.llm.InputGuard
import com.caddieai.android.data.llm.LLMRouter
import com.caddieai.android.data.llm.PromptRepository
import com.caddieai.android.data.location.LocationService
import com.caddieai.android.data.model.Club
import com.caddieai.android.data.model.LieType
import com.caddieai.android.data.model.NormalizedCourse
import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.model.ShotHistoryEntry
import com.caddieai.android.data.model.ShotRecommendation
import com.caddieai.android.data.model.ShotType
import com.caddieai.android.data.store.ActiveRoundStore
import com.caddieai.android.data.store.ProfileStore
import com.caddieai.android.data.store.ShotHistoryStore
import com.caddieai.android.data.voice.TTSState
import com.caddieai.android.data.voice.TextToSpeechService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed class AutoDetectState {
    data object Idle : AutoDetectState()
    data object Loading : AutoDetectState()
    data object Done : AutoDetectState()
    data class Error(val message: String) : AutoDetectState()
}

sealed class ShotAdvisorState {
    data object Idle : ShotAdvisorState()
    data object Loading : ShotAdvisorState()
    data class Deterministic(
        val recommendation: ShotRecommendation,
        val archetype: ShotArchetype,
        val engineNotes: String,
    ) : ShotAdvisorState()
    data class Enhanced(
        val recommendation: ShotRecommendation,
        val archetype: ShotArchetype,
    ) : ShotAdvisorState()
    data class Error(val message: String, val fallback: ShotRecommendation? = null, val archetype: ShotArchetype? = null) : ShotAdvisorState()
}

@HiltViewModel
class ShotAdvisorViewModel @Inject constructor(
    private val profileStore: ProfileStore,
    private val historyStore: ShotHistoryStore,
    private val llmRouter: LLMRouter,
    private val promptRepository: PromptRepository,
    private val activeRoundStore: ActiveRoundStore,
    private val autoDetectService: AutoDetectService,
    private val locationService: LocationService,
    private val ttsService: TextToSpeechService,
    private val logger: DiagnosticLogger,
) : ViewModel() {

    val profile: StateFlow<PlayerProfile> = profileStore.profile
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlayerProfile())

    val activeCourse: StateFlow<NormalizedCourse?> = activeRoundStore.activeCourse
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val activeHoleNumber: StateFlow<Int?> = activeRoundStore.activeHoleNumber
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    private val _autoDetectState = MutableStateFlow<AutoDetectState>(AutoDetectState.Idle)
    val autoDetectState: StateFlow<AutoDetectState> = _autoDetectState.asStateFlow()

    fun setActiveHole(number: Int) { activeRoundStore.setActiveHole(number) }

    fun triggerAutoDetect() {
        val course = activeCourse.value ?: return
        val holeNum = activeHoleNumber.value ?: return
        val hole = course.holes.find { it.number == holeNum } ?: return

        viewModelScope.launch {
            _autoDetectState.value = AutoDetectState.Loading
            locationService.getCurrentLocation()
                .onSuccess { location ->
                    runCatching { autoDetectService.autoDetect(location, hole, profileStore.getProfile()) }
                        .onSuccess { ctx ->
                            _shotContext.value = ctx
                            _autoDetectState.value = AutoDetectState.Done
                        }
                        .onFailure { e ->
                            _autoDetectState.value = AutoDetectState.Error(e.message ?: "Auto detect failed")
                        }
                }
                .onFailure { e ->
                    _autoDetectState.value = AutoDetectState.Error(e.message ?: "Location unavailable")
                }
        }
    }

    private val _shotContext = MutableStateFlow(ShotContext())
    val shotContext: StateFlow<ShotContext> = _shotContext.asStateFlow()

    private val _state = MutableStateFlow<ShotAdvisorState>(ShotAdvisorState.Idle)
    val state: StateFlow<ShotAdvisorState> = _state.asStateFlow()

    val isSpeaking: StateFlow<Boolean> = ttsService.state
        .map { it == TTSState.SPEAKING }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    fun speakAdvice() {
        val rec = when (val s = _state.value) {
            is ShotAdvisorState.Enhanced -> s.recommendation
            is ShotAdvisorState.Deterministic -> s.recommendation
            is ShotAdvisorState.Error -> s.fallback
            else -> null
        } ?: return
        val text = buildString {
            append("Hit your ${rec.recommendedClub.name.replace('_', ' ')}. ")
            if (rec.targetDescription.isNotBlank()) append("${rec.targetDescription}. ")
            if (rec.executionPlan.isNotBlank()) append(rec.executionPlan)
        }
        viewModelScope.launch {
            val profile = profileStore.getProfile()
            ttsService.speak(text, profile.caddieAccent, profile.caddieGender)
        }
    }

    fun stopSpeaking() {
        ttsService.stop()
    }

    fun updateContext(transform: (ShotContext) -> ShotContext) {
        _shotContext.update(transform)
    }

    fun analyze(imageBase64: String? = null) {
        val ctx = _shotContext.value
        logger.log(LogLevel.INFO, LogCategory.NAVIGATION, "get_advice_tapped",
            properties = mapOf("distanceToPin" to ctx.distanceToPin, "lie" to ctx.lie.name,
                "shotType" to ctx.shotType.name, "hasImage" to (imageBase64 != null)),
            message = "Get Advice tapped: ${ctx.distanceToPin}yds, lie=${ctx.lie}, shotType=${ctx.shotType}")
        viewModelScope.launch {
            _state.value = ShotAdvisorState.Loading

            val profile = profileStore.getProfile()
            val context = _shotContext.value
            val effectiveImage = imageBase64?.takeIf {
                profile.effectiveTier == com.caddieai.android.data.model.UserTier.PRO &&
                        profile.imageAnalysisBetaEnabled
            }

            // Step 1: Instant deterministic recommendation
            val engineResult = GolfLogicEngine.analyze(context, profile)
            val deterministicRec = GolfLogicEngine.analyzeToRecommendation(context, profile)
            val archetype = ExecutionEngine.buildArchetype(engineResult.recommendedClub, context, profile)

            _state.value = ShotAdvisorState.Deterministic(
                recommendation = deterministicRec,
                archetype = archetype,
                engineNotes = engineResult.notes,
            )

            // Step 2: Enhanced LLM recommendation (async)
            val hasApiKey = profile.openAiApiKey.isNotBlank() ||
                    profile.anthropicApiKey.isNotBlank() ||
                    profile.googleApiKey.isNotBlank() ||
                    profile.effectiveTier == com.caddieai.android.data.model.UserTier.PRO

            if (hasApiKey) {
                llmRouter.getRecommendation(context, profile, effectiveImage)
                    .onSuccess { llmRec ->
                        val llmArchetype = ExecutionEngine.buildArchetype(llmRec.recommendedClub, context, profile)
                        _state.value = ShotAdvisorState.Enhanced(llmRec, llmArchetype)
                        saveToHistory(context, llmRec)
                    }
                    .onFailure { e ->
                        // Keep the deterministic result as fallback
                        _state.value = ShotAdvisorState.Error(
                            message = e.message ?: "AI recommendation failed",
                            fallback = deterministicRec,
                            archetype = archetype,
                        )
                        saveToHistory(context, deterministicRec)
                    }
            } else {
                // No LLM available — save the deterministic result to history
                saveToHistory(context, deterministicRec)
            }
        }
    }

    private fun saveToHistory(context: ShotContext, recommendation: ShotRecommendation) {
        val course = activeCourse.value
        viewModelScope.launch {
            historyStore.addShot(ShotHistoryEntry(
                context = context,
                recommendation = recommendation,
                courseId = course?.id,
                courseName = course?.name ?: "",
            ))
        }
    }

    fun reset() {
        _shotContext.value = ShotContext()
        _state.value = ShotAdvisorState.Idle
    }

    fun isGolfRelated(input: String): Boolean =
        InputGuard.isGolfRelated(input, promptRepository.config.golfKeywords)

    val offTopicResponse: String get() = promptRepository.config.offTopicResponse
}
