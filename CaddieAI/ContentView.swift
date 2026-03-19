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
}
