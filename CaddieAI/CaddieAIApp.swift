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
    @State private var courseViewModel = CourseViewModel()
    @State private var courseCacheService = CourseCacheService()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(profileStore)
                    .environment(shotAdvisor)
                    .environment(speechService)
                    .environment(ttsService)
                    .environment(shotHistoryStore)
                    .environment(courseViewModel)
                    .environment(courseCacheService)
                    .onAppear {
                        courseViewModel.cacheService = courseCacheService
                        courseViewModel.profileStore = profileStore
                    }

                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}
