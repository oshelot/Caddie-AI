//
//  ContentView.swift
//  CaddieAI
//
//  Created by Aashish Patel on 3/18/26.
//

import SwiftUI

@Observable
final class TabRouter {
    var selectedTab = "course"
}

struct ContentView: View {
    @Environment(TabRouter.self) private var tabRouter
    @State private var tabSwitchTime = CFAbsoluteTimeGetCurrent()
    @State private var previousTab = "course"
    @State private var hasLoggedStartup = false

    var body: some View {
        @Bindable var router = tabRouter
        TabView(selection: $router.selectedTab) {
            Tab("Caddie", systemImage: "figure.golf", value: "caddie") {
                ShotInputView()
            }
            Tab("Course", systemImage: "map", value: "course") {
                CourseSearchView()
            }
            Tab("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90", value: "history") {
                ShotHistoryView()
            }
            Tab("Profile", systemImage: "person.circle", value: "profile") {
                ProfileView()
            }
        }
        .onAppear {
            if !hasLoggedStartup {
                let startupMs = Int((CFAbsoluteTimeGetCurrent() - appLaunchTime) * 1000)
                LoggingService.shared.info(.general, "app_startup", metadata: [
                    "latencyMs": "\(startupMs)",
                ])
                hasLoggedStartup = true
            }
        }
        .onChange(of: tabRouter.selectedTab) { oldTab, newTab in
            let dwellMs = Int((CFAbsoluteTimeGetCurrent() - tabSwitchTime) * 1000)
            LoggingService.shared.info(.general, "tab_dwell", metadata: [
                "tab": oldTab,
                "dwellMs": "\(dwellMs)",
            ])
            tabSwitchTime = CFAbsoluteTimeGetCurrent()
            LoggingService.shared.info(.general, "Tab switched", metadata: ["tab": newTab])
        }
    }
}

#Preview {
    ContentView()
        .environment(ShotAdvisorViewModel())
        .environment(ProfileStore())
        .environment(ShotHistoryStore())
        .environment(SpeechRecognitionService())
        .environment(TextToSpeechService())
        .environment(CourseViewModel())
        .environment(CourseCacheService())
        .environment(APIUsageStore())
        .environment(AdManager())
        .environment(LocationManager())
        .environment(TabRouter())
}
