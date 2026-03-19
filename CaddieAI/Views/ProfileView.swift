//
//  ProfileView.swift
//  CaddieAI
//

import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(ProfileStore.self) private var profileStore
    @State private var showAPIKey = false

    var body: some View {
        @Bindable var store = profileStore

        NavigationStack {
            Form {
                Section("Player Info") {
                    HStack {
                        Text("Handicap")
                        Spacer()
                        TextField("15", value: $store.profile.handicap, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Picker("Stock Shape", selection: $store.profile.stockShape) {
                        ForEach(StockShape.allCases) { shape in
                            Text(shape.displayName).tag(shape)
                        }
                    }
                    Picker("Miss Tendency", selection: $store.profile.missTendency) {
                        ForEach(MissTendency.allCases) { miss in
                            Text(miss.displayName).tag(miss)
                        }
                    }
                    Picker("Default Aggressiveness", selection: $store.profile.defaultAggressiveness) {
                        ForEach(Aggressiveness.allCases) { a in
                            Text(a.displayName).tag(a)
                        }
                    }
                }

                Section {
                    HStack {
                        if showAPIKey {
                            Text(store.profile.apiKey.isEmpty ? "No key set" : store.profile.apiKey)
                                .foregroundStyle(store.profile.apiKey.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text(store.profile.apiKey.isEmpty ? "No key set" : String(repeating: "•", count: min(store.profile.apiKey.count, 24)))
                                .foregroundStyle(store.profile.apiKey.isEmpty ? .secondary : .primary)
                        }
                        Spacer()
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        if let clipboardString = UIPasteboard.general.string {
                            profileStore.profile.apiKey = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label("Paste API Key from Clipboard", systemImage: "doc.on.clipboard")
                    }
                    if !store.profile.apiKey.isEmpty {
                        Button(role: .destructive) {
                            profileStore.profile.apiKey = ""
                        } label: {
                            Label("Clear API Key", systemImage: "trash")
                        }
                    }
                    if store.profile.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                        Label("Required for AI-powered recommendations", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("API Configuration")
                }

                Section("Short Game & Tendencies") {
                    Picker("Bunker Confidence", selection: $store.profile.bunkerConfidence) {
                        ForEach(SelfConfidence.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    Picker("Wedge Confidence", selection: $store.profile.wedgeConfidence) {
                        ForEach(SelfConfidence.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    Picker("Preferred Chip Style", selection: $store.profile.preferredChipStyle) {
                        ForEach(ChipStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    Picker("Swing Tendency", selection: $store.profile.swingTendency) {
                        ForEach(SwingTendency.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                }

                Section("Club Distances (Carry Yards)") {
                    ClubDistanceEditor(clubDistances: $store.profile.clubDistances)
                }
            }
            .navigationTitle("Profile")
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

#Preview {
    ProfileView()
        .environment(ProfileStore())
}
