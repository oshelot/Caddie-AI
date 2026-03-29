//
//  ContentView.swift
//  CaddieAI
//
//  Created by Aashish Patel on 3/18/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = "course"

    var body: some View {
        TabView(selection: $selectedTab) {
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
        .environment(LocationManager())
}
