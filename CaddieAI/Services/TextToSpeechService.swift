//
//  TextToSpeechService.swift
//  CaddieAI
//

import AVFoundation

@Observable
final class TextToSpeechService {

    var isSpeaking = false
    var voiceGender: CaddieVoiceGender = .female
    var voiceAccent: CaddieVoiceAccent = .american

    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = TTSDelegate()

    init() {
        synthesizer.delegate = delegate
        delegate.onFinish = { [weak self] in
            self?.isSpeaking = false
        }
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)

        // Configure audio session for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .duckOthers)
            try session.setActive(true)
        } catch {
            // Proceed anyway — TTS may still work
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.voice = resolveVoice()

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: - Voice Resolution

    private func resolveVoice() -> AVSpeechSynthesisVoice? {
        let targetLanguage = voiceAccent.languageCode
        let targetGender: AVSpeechSynthesisVoiceGender = voiceGender == .male ? .male : .female

        let voicesForLanguage = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == targetLanguage
        }

        // Prefer matching gender, then enhanced quality
        let genderMatched = voicesForLanguage.filter { $0.gender == targetGender }
        if let enhanced = genderMatched.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        if let any = genderMatched.first {
            return any
        }

        // Fall back to any voice for the language
        if let fallback = voicesForLanguage.first {
            return fallback
        }

        // Last resort: default en-US
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

// MARK: - Delegate

private class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.onFinish?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.onFinish?()
        }
    }
}
