//
//  CaddieAIApp.swift
//  CaddieAI
//
//  Created by Aashish Patel on 3/18/26.
//

import SwiftUI
import MapboxMaps
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import AppTrackingTransparency
#endif

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
    @State private var tabRouter = TabRouter()
    @State private var showSplash = true
    @AppStorage("hasSeenSetupNotice") private var hasSeenSetupNotice = false
    @State private var showSetupNotice = false
    @State private var showContactPrompt = false
    @State private var showSwingOnboarding = false
    @State private var showBagReminder = false

    init() {
        // Read Mapbox token from bundled Secrets.plist
        if let token = Secrets.mapboxAccessToken {
            MapboxOptions.accessToken = token
        }

        // Initialize Google Mobile Ads SDK (only when framework is present)
        #if canImport(GoogleMobileAds)
        MobileAds.shared.start(completionHandler: nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
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
                        tryShowContactPrompt()
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }

                if showContactPrompt {
                    OnboardingContactView {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showContactPrompt = false
                        }
                        tryShowSwingOnboarding()
                    }
                    .transition(.opacity)
                    .zIndex(3)
                }

                if showSwingOnboarding {
                    SwingOnboardingView {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showSwingOnboarding = false
                        }
                        tryShowBagReminder()
                    }
                    .transition(.opacity)
                    .zIndex(4)
                }

                if showBagReminder {
                    BagReminderView {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showBagReminder = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(5)
                }
            }
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
            .environment(tabRouter)
            .task {
                // Fetch latest prompts from S3 (non-blocking, falls back to cache/defaults)
                await PromptService.shared.fetchIfNeeded()

                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
                if !hasSeenSetupNotice {
                    withAnimation(.easeIn(duration: 0.3)) {
                        showSetupNotice = true
                    }
                } else {
                    tryShowContactPrompt()
                    // If contact prompt didn't show, try swing onboarding or bag reminder
                    if !showContactPrompt {
                        tryShowSwingOnboarding()
                        if !showSwingOnboarding {
                            tryShowBagReminder()
                        }
                    }
                }

                // Request ATT authorization for ad personalization
                #if canImport(GoogleMobileAds)
                if adManager.shouldShowAds {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        ATTrackingManager.requestTrackingAuthorization { _ in }
                    }
                }
                #endif
            }
        }
    }

    private func tryShowSwingOnboarding() {
        guard !profileStore.profile.hasCompletedSwingOnboarding else { return }
        withAnimation(.easeIn(duration: 0.3)) {
            showSwingOnboarding = true
        }
    }

    private func tryShowBagReminder() {
        let profile = profileStore.profile
        guard profile.hasCompletedSwingOnboarding else { return }
        guard !profile.hasConfiguredBag else { return }
        withAnimation(.easeIn(duration: 0.3)) {
            showBagReminder = true
        }
    }

    private func tryShowContactPrompt() {
        let profile = profileStore.profile
        // Already submitted contact info — don't show
        guard profile.contactName.isEmpty else { return }
        // Already skipped 3 times — stop asking
        guard profile.contactPromptSkipCount < 3 else { return }
        // If shown before, require 30+ days since last prompt
        if let lastShown = profile.contactPromptLastShown {
            let daysSince = Calendar.current.dateComponents([.day], from: lastShown, to: Date()).day ?? 0
            guard daysSince >= 30 else { return }
        }
        withAnimation(.easeIn(duration: 0.3)) {
            showContactPrompt = true
        }
    }
}
