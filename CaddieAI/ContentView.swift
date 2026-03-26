//
//  ContentView.swift
//  CaddieAI
//
//  Created by Aashish Patel on 3/18/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Caddie", systemImage: "figure.golf") {
                ShotInputView()
            }
            Tab("Course", systemImage: "map") {
                CourseSearchView()
            }
            Tab("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                ShotHistoryView()
            }
            Tab("Profile", systemImage: "person.circle") {
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
}
