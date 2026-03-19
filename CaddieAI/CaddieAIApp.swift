//
//  CaddieAIApp.swift
//  CaddieAI
//
//  Created by Aashish Patel on 3/18/26.
//

import SwiftUI

@main
struct CaddieAIApp: App {
    @State private var profileStore = ProfileStore()
    @State private var shotAdvisor = ShotAdvisorViewModel()
    @State private var speechService = SpeechRecognitionService()
    @State private var ttsService = TextToSpeechService()
    @State private var shotHistoryStore = ShotHistoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(profileStore)
                .environment(shotAdvisor)
                .environment(speechService)
                .environment(ttsService)
                .environment(shotHistoryStore)
        }
    }
}
