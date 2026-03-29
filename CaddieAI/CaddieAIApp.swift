//
//  CaddieAIApp.swift
//  CaddieAI
//
//  Created by Aashish Patel on 3/18/26.
//

import SwiftUI
import MapboxMaps
import GoogleMobileAds
import AppTrackingTransparency

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
    @State private var subscriptionManager = SubscriptionManager()
    @State private var adManager = AdManager()
    @State private var locationManager = LocationManager()
    @State private var showSplash = true
    @AppStorage("hasSeenSetupNotice") private var hasSeenSetupNotice = false
    @State private var showSetupNotice = false

    init() {
        // Read Mapbox token from bundled Secrets.plist
        if let token = Secrets.mapboxAccessToken {
            MapboxOptions.accessToken = token
        }

        // Initialize Google Mobile Ads SDK
        MobileAds.shared.start(completionHandler: nil)
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
                    .environment(subscriptionManager)
                    .environment(adManager)
                    .environment(locationManager)
                    .onAppear {
                        courseViewModel.cacheService = courseCacheService
                        courseViewModel.profileStore = profileStore
                        courseViewModel.apiUsageStore = apiUsageStore
                        shotAdvisor.apiUsageStore = apiUsageStore
                        shotAdvisor.subscriptionManager = subscriptionManager
                        adManager.subscriptionManager = subscriptionManager
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

                if showSetupNotice {
                    SetupNoticeView {
                        hasSeenSetupNotice = true
                        withAnimation(.easeOut(duration: 0.3)) {
                            showSetupNotice = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
                if !hasSeenSetupNotice {
                    withAnimation(.easeIn(duration: 0.3)) {
                        showSetupNotice = true
                    }
                }

                // Request ATT authorization for ad personalization
                if adManager.shouldShowAds {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        ATTrackingManager.requestTrackingAuthorization { _ in }
                    }
                }
            }
        }
    }
}
