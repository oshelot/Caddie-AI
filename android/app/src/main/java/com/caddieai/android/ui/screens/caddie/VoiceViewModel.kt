package com.caddieai.android.ui.screens.caddie

import android.os.Handler
import android.os.Looper
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.voice.ParsedVoiceInput
import com.caddieai.android.data.voice.RecognitionState
import com.caddieai.android.data.voice.SpeechRecognitionService
import com.caddieai.android.data.voice.TextToSpeechService
import com.caddieai.android.data.voice.VoiceInputParser
import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.update
import javax.inject.Inject

data class VoiceState(
    val isListening: Boolean = false,
    val partialTranscript: String = "",
    val lastTranscript: String = "",
    val parsedInput: ParsedVoiceInput? = null,
    val error: String? = null,
    val isSpeaking: Boolean = false,
    val hasMicPermission: Boolean = false,
)

@HiltViewModel
class VoiceViewModel @Inject constructor(
    private val speechService: SpeechRecognitionService,
    private val ttsService: TextToSpeechService,
    private val parser: VoiceInputParser,
    private val logger: DiagnosticLogger,
) : ViewModel() {

    private val _state = MutableStateFlow(VoiceState())
    val state: StateFlow<VoiceState> = _state.asStateFlow()

    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        speechService.state
            .onEach { recognitionState ->
                when (recognitionState) {
                    is RecognitionState.Idle -> _state.update {
                        it.copy(isListening = false, partialTranscript = "")
                    }
                    is RecognitionState.Listening -> _state.update {
                        it.copy(isListening = true, partialTranscript = "", error = null)
                    }
                    is RecognitionState.Partial -> _state.update {
                        it.copy(partialTranscript = recognitionState.text)
                    }
                    is RecognitionState.Result -> {
                        val sttMs = System.currentTimeMillis() - speechService.listenStartTimeMs
                        val wordCount = recognitionState.text.split("\\s+".toRegex()).size
                        logger.log(LogLevel.INFO, LogCategory.LIFECYCLE, "stt_complete", mapOf(
                            "latencyMs" to sttMs.toString(),
                            "wordCount" to wordCount.toString(),
                        ))
                        val parsed = parser.parse(recognitionState.text)
                        _state.update {
                            it.copy(
                                isListening = false,
                                partialTranscript = "",
                                lastTranscript = recognitionState.text,
                                parsedInput = parsed,
                                error = null,
                            )
                        }
                    }
                    is RecognitionState.Error -> _state.update {
                        it.copy(
                            isListening = false,
                            partialTranscript = "",
                            error = recognitionState.message,
                        )
                    }
                }
            }
            .launchIn(viewModelScope)
    }

    fun onMicPermissionResult(granted: Boolean) {
        _state.update { it.copy(hasMicPermission = granted) }
    }

    /** Must be called from the main thread (or posts to main thread internally). */
    fun startListening() {
        if (!_state.value.hasMicPermission) {
            _state.update { it.copy(error = "Microphone permission required") }
            return
        }
        mainHandler.post { speechService.startListening() }
    }

    fun stopListening() {
        mainHandler.post { speechService.stopListening() }
    }

    fun toggleListening() {
        if (_state.value.isListening) stopListening() else startListening()
    }

    fun speakText(
        text: String,
        accent: com.caddieai.android.data.model.CaddieAccent = com.caddieai.android.data.model.CaddieAccent.AMERICAN,
        gender: com.caddieai.android.data.model.CaddieGender = com.caddieai.android.data.model.CaddieGender.MALE,
    ) {
        ttsService.speak(text, accent, gender)
        _state.update { it.copy(isSpeaking = true) }
    }

    fun stopSpeaking() {
        ttsService.stop()
        _state.update { it.copy(isSpeaking = false) }
    }

    /** Parse last transcript and apply to an existing ShotContext. */
    fun applyToContext(existing: ShotContext): ShotContext {
        val parsed = _state.value.parsedInput ?: return existing
        return parser.applyToCo(parsed, existing)
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }

    fun clearParsedInput() {
        _state.update { it.copy(parsedInput = null, lastTranscript = "", partialTranscript = "") }
        speechService.resetState()
    }

    override fun onCleared() {
        super.onCleared()
        speechService.destroy()
        ttsService.shutdown()
    }
}
