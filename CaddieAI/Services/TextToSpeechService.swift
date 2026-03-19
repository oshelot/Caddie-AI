//
//  TextToSpeechService.swift
//  CaddieAI
//

import AVFoundation

@Observable
final class TextToSpeechService {

    var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        isSpeaking = true
        synthesizer.speak(utterance)

        // Monitor completion
        Task {
            // Poll until done — AVSpeechSynthesizer delegate is complex to wire with @Observable
            while synthesizer.isSpeaking {
                try? await Task.sleep(for: .milliseconds(200))
            }
            isSpeaking = false
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}
