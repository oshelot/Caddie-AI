//
//  SpeechRecognitionService.swift
//  CaddieAI
//

import AVFoundation
import Speech

@Observable
final class SpeechRecognitionService {

    var transcribedText = ""
    var isRecording = false
    var errorMessage: String?
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    // nonisolated(unsafe) to avoid @Observable macro conflict — these are only accessed on MainActor
    @ObservationIgnored private var _speechRecognizerBacking: SFSpeechRecognizer?
    @ObservationIgnored private var _audioEngineBacking: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var speechRecognizer: SFSpeechRecognizer? {
        if _speechRecognizerBacking == nil {
            _speechRecognizerBacking = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
        return _speechRecognizerBacking
    }

    private var audioEngine: AVAudioEngine {
        if _audioEngineBacking == nil {
            _audioEngineBacking = AVAudioEngine()
        }
        return _audioEngineBacking!
    }

    // MARK: - Authorization

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
                if status != .authorized {
                    self?.errorMessage = "Speech recognition not authorized."
                }
            }
        }
    }

    // MARK: - Start / Stop Recording

    func startRecording() {
        guard authorizationStatus == .authorized else {
            requestAuthorization()
            return
        }

        // Cancel any in-progress task
        recognitionTask?.cancel()
        recognitionTask = nil

        errorMessage = nil
        transcribedText = ""

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Could not configure audio session."
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            errorMessage = "Could not create recognition request."
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = "Could not start audio engine."
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
}
