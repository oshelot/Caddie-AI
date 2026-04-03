package com.caddieai.android.data.voice

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.model.CaddieAccent
import com.caddieai.android.data.model.CaddieGender
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

enum class TTSState { UNINITIALIZED, READY, SPEAKING, ERROR }

@Singleton
class TextToSpeechService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val logger: DiagnosticLogger,
) {
    private var tts: TextToSpeech? = null
    private var speakRequestTimeMs: Long = 0L
    private var lastCharCount: Int = 0

    private val _state = MutableStateFlow(TTSState.UNINITIALIZED)
    val state: StateFlow<TTSState> = _state.asStateFlow()

    init {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                _state.value = TTSState.READY
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        val latencyMs = System.currentTimeMillis() - speakRequestTimeMs
                        logger.log(LogLevel.INFO, LogCategory.LIFECYCLE, "tts_start", mapOf(
                            "latencyMs" to latencyMs.toString(),
                            "charCount" to lastCharCount.toString(),
                        ))
                        _state.value = TTSState.SPEAKING
                    }
                    override fun onDone(utteranceId: String?) { _state.value = TTSState.READY }
                    override fun onError(utteranceId: String?) { _state.value = TTSState.ERROR }
                })
            } else {
                _state.value = TTSState.ERROR
            }
        }
    }

    fun speak(text: String, accent: CaddieAccent = CaddieAccent.AMERICAN, gender: CaddieGender = CaddieGender.MALE) {
        val engine = tts ?: return
        val locale = accentToLocale(accent)

        // Set locale
        val result = engine.setLanguage(locale)
        if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
            engine.setLanguage(Locale.US) // fallback
        }

        // Pitch: higher = more female, lower = more male
        val pitch = when (gender) {
            CaddieGender.MALE -> 0.85f
            CaddieGender.FEMALE -> 1.15f
            CaddieGender.NEUTRAL -> 1.0f
        }
        engine.setPitch(pitch)
        engine.setSpeechRate(0.95f) // slightly slower for clarity

        lastCharCount = text.length
        speakRequestTimeMs = System.currentTimeMillis()
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "caddie_advice")
    }

    fun stop() {
        tts?.stop()
        _state.value = TTSState.READY
    }

    fun isReady() = _state.value == TTSState.READY

    fun shutdown() {
        tts?.shutdown()
        tts = null
        _state.value = TTSState.UNINITIALIZED
    }

    private fun accentToLocale(accent: CaddieAccent): Locale = when (accent) {
        CaddieAccent.AMERICAN -> Locale.US
        CaddieAccent.BRITISH -> Locale.UK
        CaddieAccent.SCOTTISH -> Locale("en", "GB") // closest available
        CaddieAccent.IRISH -> Locale("en", "IE")
        CaddieAccent.AUSTRALIAN -> Locale("en", "AU")
    }
}
