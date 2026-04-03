package com.caddieai.android.data.voice

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

sealed class RecognitionState {
    data object Idle : RecognitionState()
    data object Listening : RecognitionState()
    data class Partial(val text: String) : RecognitionState()
    data class Result(val text: String, val alternatives: List<String>) : RecognitionState()
    data class Error(val code: Int, val message: String) : RecognitionState()
}

/**
 * Wraps Android's SpeechRecognizer.
 *
 * NOTE: SpeechRecognizer must be created and used on the main thread.
 * Callers must ensure [startListening] and [stopListening] are called from the main thread.
 */
@Singleton
class SpeechRecognitionService @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var recognizer: SpeechRecognizer? = null
    var listenStartTimeMs: Long = 0L
        private set

    private val _state = MutableStateFlow<RecognitionState>(RecognitionState.Idle)
    val state: StateFlow<RecognitionState> = _state.asStateFlow()

    val isAvailable: Boolean
        get() = SpeechRecognizer.isRecognitionAvailable(context)

    /** Must be called from the main thread. */
    fun startListening(languageTag: String = "en-US") {
        if (!isAvailable) {
            _state.value = RecognitionState.Error(-1, "Speech recognition not available on this device")
            return
        }

        recognizer?.destroy()
        recognizer = SpeechRecognizer.createSpeechRecognizer(context).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    _state.value = RecognitionState.Listening
                }
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onError(error: Int) {
                    val msg = when (error) {
                        SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
                        SpeechRecognizer.ERROR_CLIENT -> "Client error"
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission required"
                        SpeechRecognizer.ERROR_NETWORK -> "Network error"
                        SpeechRecognizer.ERROR_NO_MATCH -> "No speech detected"
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer busy"
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Speech timeout"
                        else -> "Recognition error ($error)"
                    }
                    _state.value = RecognitionState.Error(error, msg)
                }
                override fun onResults(results: Bundle?) {
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?: return
                    _state.value = RecognitionState.Result(
                        text = matches.firstOrNull() ?: "",
                        alternatives = matches.drop(1),
                    )
                }
                override fun onPartialResults(partialResults: Bundle?) {
                    val partial = partialResults
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull() ?: return
                    _state.value = RecognitionState.Partial(partial)
                }
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Describe your shot situation")
        }

        listenStartTimeMs = System.currentTimeMillis()
        recognizer?.startListening(intent)
    }

    /** Must be called from the main thread. */
    fun stopListening() {
        recognizer?.stopListening()
    }

    fun resetState() {
        _state.value = RecognitionState.Idle
    }

    fun destroy() {
        recognizer?.destroy()
        recognizer = null
        _state.value = RecognitionState.Idle
    }
}
