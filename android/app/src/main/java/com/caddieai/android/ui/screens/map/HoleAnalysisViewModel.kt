package com.caddieai.android.ui.screens.map

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.caddieai.android.data.course.CourseCacheService
import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.engine.HoleAnalysis
import com.caddieai.android.data.engine.HoleAnalysisEngine
import com.caddieai.android.data.engine.HoleWeatherContext
import com.caddieai.android.data.llm.ChatMessage
import com.caddieai.android.data.llm.InputGuard
import com.caddieai.android.data.llm.LLMRouter
import com.caddieai.android.data.llm.PromptRepository
import com.caddieai.android.data.model.NormalizedCourse
import com.caddieai.android.data.store.ProfileStore
import com.caddieai.android.data.voice.TTSState
import com.caddieai.android.data.voice.TextToSpeechService
import com.caddieai.android.data.weather.WeatherService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class HoleAnalysisState(
    val selectedHoleNumber: Int? = null,
    val analysis: HoleAnalysis? = null,
    val isLoadingLLM: Boolean = false,
    val conversation: List<ConversationMessage> = emptyList(),
    val followUpInput: String = "",
    val showOffTopicDialog: Boolean = false,
    val selectedTee: String? = null,
    val availableTees: List<String> = emptyList(),
    val showTeeReminder: Boolean = false,
    val isAnalyzed: Boolean = false,
    val isSpeaking: Boolean = false,
)

data class ConversationMessage(
    val role: MessageRole,
    val content: String,
)

enum class MessageRole { USER, CADDIE }

@HiltViewModel
class HoleAnalysisViewModel @Inject constructor(
    private val profileStore: ProfileStore,
    private val llmRouter: LLMRouter,
    private val promptRepository: PromptRepository,
    private val ttsService: TextToSpeechService,
    private val weatherService: WeatherService,
    private val courseCacheService: CourseCacheService,
    private val logger: DiagnosticLogger,
) : ViewModel() {

    private val _state = MutableStateFlow(HoleAnalysisState())
    val state: StateFlow<HoleAnalysisState> = _state.asStateFlow()

    init {
        // Track TTS speaking state
        viewModelScope.launch {
            ttsService.state.collect { ttsState ->
                _state.update { it.copy(isSpeaking = ttsState == TTSState.SPEAKING) }
            }
        }
    }

    fun logMapStyleLoad(latencyMs: Long, courseName: String) {
        logger.log(LogLevel.INFO, LogCategory.MAP, "map_style_load", mapOf(
            "latencyMs" to latencyMs.toString(),
            "courseName" to courseName,
        ))
    }

    fun logLayerRender(latencyMs: Long, courseName: String, holeCount: Int) {
        logger.log(LogLevel.INFO, LogCategory.MAP, "layer_render", mapOf(
            "latencyMs" to latencyMs.toString(),
            "courseName" to courseName,
            "holeCount" to holeCount.toString(),
        ))
    }

    /** Initialize tee selection for a course — call once when course is first shown. */
    fun initTeeSelection(course: NormalizedCourse) {
        android.util.Log.d("CaddieAI/Tee", "initTeeSelection: courseId=${course.id} teeNames=${course.teeNames}")
        val savedTee = courseCacheService.getSelectedTee(course.id)
        val teeNames = course.teeNames

        val (selectedTee, showReminder) = when {
            savedTee != null && savedTee in teeNames -> Pair(savedTee, false)
            teeNames.size > 1 -> Pair(teeNames.firstOrNull(), true)
            teeNames.size == 1 -> Pair(teeNames.first(), false)
            else -> Pair(null, false)
        }

        _state.update {
            it.copy(
                availableTees = teeNames,
                selectedTee = selectedTee,
                showTeeReminder = showReminder,
            )
        }
    }

    /** Deselect all holes and zoom out to full course view. */
    fun selectAll() {
        _state.update {
            it.copy(
                selectedHoleNumber = null,
                isAnalyzed = false,
                conversation = emptyList(),
            )
        }
    }

    /** Select a hole without triggering analysis — just updates selection and camera target. */
    fun selectHole(course: NormalizedCourse, holeNumber: Int) {
        _state.update {
            it.copy(
                selectedHoleNumber = holeNumber,
                isAnalyzed = false,
                conversation = emptyList(),
            )
        }
    }

    /** Select a tee box and persist the choice. */
    fun selectTee(course: NormalizedCourse, teeName: String) {
        _state.update { it.copy(selectedTee = teeName, showTeeReminder = false) }
        courseCacheService.saveSelectedTee(course.id, teeName)
    }

    /** Dismiss the tee reminder callout. */
    fun dismissTeeReminder() {
        _state.update { it.copy(showTeeReminder = false) }
    }

    /** Run tier 1 + LLM analysis for the selected hole. */
    fun analyzeHole(course: NormalizedCourse, holeNumber: Int) {
        logger.log(LogLevel.INFO, LogCategory.NAVIGATION, "hole_analyze_requested", mapOf("hole" to holeNumber))
        viewModelScope.launch {
            val profile = profileStore.getProfile()

            // Fetch weather using course centroid
            val teePts = course.holes.mapNotNull { it.teeBox }
            val centerLat = if (teePts.isNotEmpty()) teePts.map { it.latitude }.average() else 0.0
            val centerLon = if (teePts.isNotEmpty()) teePts.map { it.longitude }.average() else 0.0

            val weatherContext = if (teePts.isNotEmpty()) {
                weatherService.getWeather(centerLat, centerLon).getOrNull()?.let { wd ->
                    val hole = course.holes.firstOrNull { it.number == holeNumber }
                    val compassDir = compassDirection(wd.windDirectionDegrees)
                    val relativeDir = if (hole?.teeBox != null && hole.pin != null) {
                        computeRelativeWindDir(
                            holeBearingDeg = forwardBearing(hole.teeBox, hole.pin),
                            windFromDeg = wd.windDirectionDegrees.toDouble(),
                        )
                    } else compassDir
                    val summary = buildWeatherSummary(wd.temperatureFahrenheit, wd.windSpeedMph, relativeDir)
                    HoleWeatherContext(
                        tempF = wd.temperatureFahrenheit,
                        windMph = wd.windSpeedMph,
                        compassDir = compassDir,
                        relativeDir = relativeDir,
                        summary = summary,
                    )
                }
            } else null

            val analysis = HoleAnalysisEngine.analyze(
                course = course,
                holeNumber = holeNumber,
                playerProfile = profile,
                selectedTee = _state.value.selectedTee,
                weather = weatherContext,
            )

            _state.update {
                it.copy(
                    selectedHoleNumber = holeNumber,
                    analysis = analysis,
                    isAnalyzed = true,
                    conversation = emptyList(),
                    isLoadingLLM = true,
                )
            }

            // Fetch LLM-enhanced analysis via chatCompletion
            val hole = course.holes.firstOrNull { it.number == holeNumber }
            if (hole != null) {
                val teeYardage = analysis.yardagesByTee[_state.value.selectedTee] ?: hole.yardage
                val teeLine = _state.value.selectedTee?.let { " Playing from the $it tees ($teeYardage yards)." } ?: ""
                val systemPrompt = promptRepository.caddieSystemPromptWithPersona(profile.caddiePersona)
                val userPrompt = buildString {
                    appendLine("Course: ${course.name}")
                    appendLine("Hole ${holeNumber} — Par ${hole.par},$teeLine")
                    appendLine(analysis.strategicAdvice)
                    weatherContext?.let { appendLine("Weather: ${it.summary}") }
                    appendLine()
                    append("What should I hit off the tee and where should I aim?")
                }
                val messages = listOf(
                    ChatMessage("system", systemPrompt),
                    ChatMessage("user", userPrompt),
                )
                llmRouter.chatCompletion(messages, profile, maxTokens = 500)
                    .onSuccess { rawAdvice ->
                        val advice = flattenJsonToText(rawAdvice)
                        _state.update {
                            it.copy(
                                isLoadingLLM = false,
                                analysis = analysis.copy(llmEnhancedAnalysis = advice),
                                conversation = listOf(ConversationMessage(MessageRole.CADDIE, advice)),
                            )
                        }
                    }
                    .onFailure {
                        _state.update {
                            it.copy(
                                isLoadingLLM = false,
                                conversation = listOf(ConversationMessage(MessageRole.CADDIE, analysis.strategicAdvice)),
                            )
                        }
                    }
            } else {
                _state.update { it.copy(isLoadingLLM = false) }
            }
        }
    }

    /** Speak the last caddie advice via TTS. */
    fun speakAdvice() {
        val text = _state.value.conversation.lastOrNull { it.role == MessageRole.CADDIE }?.content
            ?: _state.value.analysis?.strategicAdvice
            ?: return
        viewModelScope.launch {
            val profile = profileStore.getProfile()
            ttsService.speak(text, profile.caddieAccent, profile.caddieGender)
        }
    }

    /** Stop TTS playback. */
    fun stopSpeaking() {
        ttsService.stop()
        _state.update { it.copy(isSpeaking = false) }
    }

    fun onFollowUpChange(text: String) {
        _state.update { it.copy(followUpInput = InputGuard.enforceLimit(text)) }
    }

    fun dismissOffTopicDialog() {
        _state.update { it.copy(showOffTopicDialog = false) }
    }

    fun sendFollowUp(course: NormalizedCourse) {
        val question = _state.value.followUpInput.trim()
        if (question.isBlank()) return

        if (!InputGuard.isGolfRelated(question, promptRepository.config.golfKeywords)) {
            _state.update { it.copy(showOffTopicDialog = true) }
            return
        }

        _state.update {
            it.copy(
                followUpInput = "",
                conversation = it.conversation + ConversationMessage(MessageRole.USER, question),
                isLoadingLLM = true,
            )
        }

        viewModelScope.launch {
            val followUpStart = System.currentTimeMillis()
            val profile = profileStore.getProfile()
            val analysis = _state.value.analysis
            val systemPrompt = promptRepository.caddieSystemPromptWithPersona(profile.caddiePersona)
            val messages = buildList {
                add(ChatMessage("system", systemPrompt))
                _state.value.conversation.forEach { msg ->
                    add(ChatMessage(if (msg.role == MessageRole.USER) "user" else "assistant", msg.content))
                }
            }
            llmRouter.chatCompletion(messages, profile, maxTokens = 500)
                .onSuccess { reply ->
                    logger.log(LogLevel.INFO, LogCategory.LLM, "askHoleFollowUp", mapOf(
                        "latencyMs" to (System.currentTimeMillis() - followUpStart).toString(),
                    ))
                    _state.update { state ->
                        state.copy(
                            isLoadingLLM = false,
                            conversation = state.conversation + ConversationMessage(MessageRole.CADDIE, reply),
                        )
                    }
                }
                .onFailure {
                    _state.update { state ->
                        state.copy(
                            isLoadingLLM = false,
                            conversation = state.conversation + ConversationMessage(
                                MessageRole.CADDIE,
                                "I couldn't get an AI response right now. ${analysis?.strategicAdvice ?: ""}"
                            ),
                        )
                    }
                }
        }
    }

    // -----------------------------------------------------------------------
    // Private helpers
    // -----------------------------------------------------------------------

    private fun forwardBearing(from: com.caddieai.android.data.model.GeoPoint, to: com.caddieai.android.data.model.GeoPoint): Double {
        val dLon = Math.toRadians(to.longitude - from.longitude)
        val lat1 = Math.toRadians(from.latitude)
        val lat2 = Math.toRadians(to.latitude)
        val y = kotlin.math.sin(dLon) * kotlin.math.cos(lat2)
        val x = kotlin.math.cos(lat1) * kotlin.math.sin(lat2) -
                kotlin.math.sin(lat1) * kotlin.math.cos(lat2) * kotlin.math.cos(dLon)
        return (Math.toDegrees(kotlin.math.atan2(y, x)) + 360) % 360
    }

    private fun computeRelativeWindDir(holeBearingDeg: Double, windFromDeg: Double): String {
        // Wind "from" direction: wind coming FROM that compass direction (meteorological convention)
        // Angle of wind relative to hole direction
        val windToBearing = (windFromDeg + 180.0) % 360.0  // direction wind is blowing toward
        val diff = ((windToBearing - holeBearingDeg + 540) % 360) - 180
        return when {
            diff in -30.0..30.0 -> "helping (tailwind)"
            diff > 150.0 || diff < -150.0 -> "into (headwind)"
            diff in 30.0..150.0 -> "right-to-left"
            else -> "left-to-right"
        }
    }

    private fun compassDirection(degrees: Int): String {
        val dirs = listOf("N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW")
        val index = ((degrees + 11.25) / 22.5).toInt() % 16
        return dirs[index]
    }

    private fun buildWeatherSummary(tempF: Float, windMph: Float, relativeDir: String): String {
        return buildString {
            append("${tempF.toInt()}°F")
            if (windMph > 0) append(", ${windMph.toInt()} mph wind $relativeDir")
        }
    }

    /** If the LLM returns JSON instead of plain text, extract readable content. */
    private fun flattenJsonToText(raw: String): String {
        val trimmed = raw.trim()
        if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return raw
        return try {
            val obj = org.json.JSONObject(trimmed)
            val parts = mutableListOf<String>()
            for (key in obj.keys()) {
                val value = obj.get(key)
                val label = key.replace(Regex("([a-z])([A-Z])"), "$1 $2")
                    .replace('_', ' ')
                    .replaceFirstChar { it.uppercase() }
                when (value) {
                    is String -> if (value.isNotBlank()) parts.add("$label: $value")
                    is org.json.JSONArray -> {
                        val items = (0 until value.length()).mapNotNull { value.optString(it).takeIf { s -> s.isNotBlank() } }
                        if (items.isNotEmpty()) parts.add("$label:\n${items.joinToString("\n") { "• $it" }}")
                    }
                    is Number -> parts.add("$label: $value")
                    is org.json.JSONObject -> {
                        // Flatten nested object
                        val nested = (value.keys() as Iterator<String>).asSequence()
                            .mapNotNull { k -> value.optString(k).takeIf { it.isNotBlank() }?.let { "$k: $it" } }
                            .joinToString(", ")
                        if (nested.isNotBlank()) parts.add("$label: $nested")
                    }
                }
            }
            parts.joinToString("\n\n").ifBlank { raw }
        } catch (_: Exception) {
            raw
        }
    }
}
