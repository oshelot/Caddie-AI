//
//  APISettingsView.swift
//  CaddieAI
//
//  API key configuration and usage statistics on a dedicated page.
//

import SwiftUI

struct APISettingsView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(APIUsageStore.self) private var apiUsageStore
    @State private var showAPIKey = false
    @State private var showGolfAPIKey = false

    var body: some View {
        @Bindable var store = profileStore

        Form {
            // MARK: - OpenAI API Key

            Section {
                HStack {
                    if showAPIKey {
                        Text(store.profile.apiKey.isEmpty ? "No key set" : store.profile.apiKey)
                            .foregroundStyle(store.profile.apiKey.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(store.profile.apiKey.isEmpty ? "No key set" : String(repeating: "\u{2022}", count: min(store.profile.apiKey.count, 24)))
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
                Text("OpenAI API Key")
            } footer: {
                Text("Powers AI caddie recommendations")
            }

            // MARK: - Golf Course API Key

            Section {
                HStack {
                    if showGolfAPIKey {
                        Text(store.profile.golfCourseApiKey.isEmpty ? "No key set" : store.profile.golfCourseApiKey)
                            .foregroundStyle(store.profile.golfCourseApiKey.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(store.profile.golfCourseApiKey.isEmpty ? "No key set" : String(repeating: "\u{2022}", count: min(store.profile.golfCourseApiKey.count, 24)))
                            .foregroundStyle(store.profile.golfCourseApiKey.isEmpty ? .secondary : .primary)
                    }
                    Spacer()
                    Button {
                        showGolfAPIKey.toggle()
                    } label: {
                        Image(systemName: showGolfAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    if let clipboardString = UIPasteboard.general.string {
                        profileStore.profile.golfCourseApiKey = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Label("Paste API Key from Clipboard", systemImage: "doc.on.clipboard")
                }
                if !store.profile.golfCourseApiKey.isEmpty {
                    Button(role: .destructive) {
                        profileStore.profile.golfCourseApiKey = ""
                    } label: {
                        Label("Clear API Key", systemImage: "trash")
                    }
                }
            } header: {
                Text("Golf Course API Key")
            } footer: {
                Text("Enriches courses with par, yardage, and slope data from golfcourseapi.com")
            }

            // MARK: - Usage Stats

            Section("API Usage") {
                // OpenAI stats
                HStack {
                    Label("OpenAI Calls", systemImage: "brain")
                    Spacer()
                    Text("\(apiUsageStore.data.openAITotalCalls)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Prompt Tokens")
                    Spacer()
                    Text(apiUsageStore.data.openAITotalPromptTokens.formatted())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Completion Tokens")
                    Spacer()
                    Text(apiUsageStore.data.openAITotalCompletionTokens.formatted())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Total Tokens")
                    Spacer()
                    Text(apiUsageStore.data.openAITotalTokens.formatted())
                        .foregroundStyle(.secondary)
                }
                if apiUsageStore.openAISessionCalls > 0 {
                    HStack {
                        Text("This Session")
                        Spacer()
                        Text("\(apiUsageStore.openAISessionCalls) calls, \(apiUsageStore.openAISessionTokens.formatted()) tokens")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Divider()

                // Golf Course API stats
                HStack {
                    Label("Golf Course API", systemImage: "figure.golf")
                    Spacer()
                    if apiUsageStore.data.golfAPIRateLimitEnabled {
                        Text("\(apiUsageStore.data.golfAPICallsThisMonth) / \(apiUsageStore.data.golfAPIMonthlyLimit)")
                            .foregroundStyle(
                                apiUsageStore.data.isGolfAPIOverLimit ? .red : .secondary
                            )
                    } else {
                        Text("\(apiUsageStore.data.golfAPICallsThisMonth) this month")
                            .foregroundStyle(.secondary)
                    }
                }

                @Bindable var usageStore = apiUsageStore
                Toggle("Limit to \(apiUsageStore.data.golfAPIMonthlyLimit) calls/month",
                       isOn: $usageStore.data.golfAPIRateLimitEnabled)

                if apiUsageStore.data.isGolfAPIOverLimit {
                    Label("Monthly limit reached. Scorecard enrichment paused.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Divider()

                Button(role: .destructive) {
                    apiUsageStore.resetAll()
                } label: {
                    Label("Reset All Usage Data", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("API Settings")
    }
}

#Preview {
    NavigationStack {
        APISettingsView()
            .environment(ProfileStore())
            .environment(APIUsageStore())
    }
}
