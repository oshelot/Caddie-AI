//
//  CaddieAIApp.swift
//  CaddieAI
//
//  Created by Aashish Patel on 3/18/26.
//

import SwiftUI
import MapboxMaps

@main
struct CaddieAIApp: App {
    @State private var profileStore = ProfileStore()
    @State private var shotAdvisor = ShotAdvisorViewModel()
    @State private var speechService = SpeechRecognitionService()
    @State private var ttsService = TextToSpeechService()
    @State private var shotHistoryStore = ShotHistoryStore()
    @State private var courseViewModel = CourseViewModel()
    @State private var courseCacheService = CourseCacheService()
    @State private var apiUsageStore = APIUsageStore()
    @State private var showSplash = true

    init() {
        // Read Mapbox token: prefer user-configured (in profile), fall back to bundled Secrets.plist
        let profileToken: String? = {
            guard let data = UserDefaults.standard.data(forKey: "playerProfile"),
                  let profile = try? JSONDecoder().decode(PlayerProfile.self, from: data),
                  !profile.mapboxAccessToken.isEmpty
            else { return nil }
            return profile.mapboxAccessToken
        }()
        if let token = profileToken ?? Secrets.mapboxAccessToken {
            MapboxOptions.accessToken = token
        }
    }

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
                    .environment(apiUsageStore)
                    .onAppear {
                        courseViewModel.cacheService = courseCacheService
                        courseViewModel.profileStore = profileStore
                        courseViewModel.apiUsageStore = apiUsageStore
                        shotAdvisor.apiUsageStore = apiUsageStore
                        TelemetryService.shared.isEnabled = profileStore.profile.telemetryEnabled
                        ttsService.voiceGender = profileStore.profile.caddieVoiceGender
                        ttsService.voiceAccent = profileStore.profile.caddieVoiceAccent
                    }
                    .onChange(of: profileStore.profile.telemetryEnabled) { _, newValue in
                        TelemetryService.shared.isEnabled = newValue
                    }
                    .onChange(of: profileStore.profile.caddieVoiceGender) { _, newValue in
                        ttsService.voiceGender = newValue
                    }
                    .onChange(of: profileStore.profile.caddieVoiceAccent) { _, newValue in
                        ttsService.voiceAccent = newValue
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
