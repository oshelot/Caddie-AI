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
        .onChange(of: tabRouter.selectedTab) { _, newTab in
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
