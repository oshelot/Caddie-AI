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
    @State private var showMapboxToken = false

    var body: some View {
        @Bindable var store = profileStore

        Form {
            // MARK: - AI Provider Selection

            Section {
                Picker("AI Provider", selection: $store.profile.llmProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                Picker("Model", selection: $store.profile.llmModel) {
                    ForEach(store.profile.llmProvider.availableModels) { model in
                        Text(model.displayName).tag(model)
                    }
                }
            } header: {
                Text("AI Provider")
            } footer: {
                Text("Powers AI caddie recommendations. Only one provider can be active at a time.")
            }
            .onChange(of: store.profile.llmProvider) { _, newProvider in
                if store.profile.llmModel.provider != newProvider {
                    store.profile.llmModel = newProvider.defaultModel
                }
            }

            // MARK: - API Key for Selected Provider

            Section {
                HStack {
                    if showAPIKey {
                        Text(activeKeyValue.isEmpty ? "No key set" : activeKeyValue)
                            .foregroundStyle(activeKeyValue.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(activeKeyValue.isEmpty ? "No key set" : String(repeating: "\u{2022}", count: min(activeKeyValue.count, 24)))
                            .foregroundStyle(activeKeyValue.isEmpty ? .secondary : .primary)
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
                        setActiveKey(clipboardString.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                } label: {
                    Label("Paste API Key from Clipboard", systemImage: "doc.on.clipboard")
                }
                if !activeKeyValue.isEmpty {
                    Button(role: .destructive) {
                        setActiveKey("")
                    } label: {
                        Label("Clear API Key", systemImage: "trash")
                    }
                }
                if activeKeyValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    Label("Required for AI-powered recommendations", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("\(profileStore.profile.llmProvider.displayName) API Key")
            } footer: {
                switch profileStore.profile.llmProvider {
                case .openAI: Text("Get your key at platform.openai.com")
                case .claude: Text("Get your key at console.anthropic.com")
                case .gemini: Text("Get your key at aistudio.google.com")
                }
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

            // MARK: - Mapbox Access Token

            Section {
                HStack {
                    if showMapboxToken {
                        Text(store.profile.mapboxAccessToken.isEmpty ? "No token set" : store.profile.mapboxAccessToken)
                            .foregroundStyle(store.profile.mapboxAccessToken.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(store.profile.mapboxAccessToken.isEmpty ? "No token set" : String(repeating: "\u{2022}", count: min(store.profile.mapboxAccessToken.count, 24)))
                            .foregroundStyle(store.profile.mapboxAccessToken.isEmpty ? .secondary : .primary)
                    }
                    Spacer()
                    Button {
                        showMapboxToken.toggle()
                    } label: {
                        Image(systemName: showMapboxToken ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    if let clipboardString = UIPasteboard.general.string {
                        profileStore.profile.mapboxAccessToken = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Label("Paste Token from Clipboard", systemImage: "doc.on.clipboard")
                }
                if !store.profile.mapboxAccessToken.isEmpty {
                    Button(role: .destructive) {
                        profileStore.profile.mapboxAccessToken = ""
                    } label: {
                        Label("Clear Token", systemImage: "trash")
                    }
                }
            } header: {
                Text("Mapbox Access Token")
            } footer: {
                Text("Powers satellite course maps. Requires app restart to take effect.")
            }

            // MARK: - Telemetry

            Section {
                Toggle("Share Usage Data", isOn: $store.profile.telemetryEnabled)
            } header: {
                Text("Telemetry")
            } footer: {
                Text("Sends anonymous API call counts (no personal data or conversation content) to help improve CaddieAI.")
            }

            // MARK: - Usage Stats

            Section("API Usage") {
                // OpenAI stats
                HStack {
                    Label("LLM Calls", systemImage: "brain")
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

    // MARK: - Active Key Helpers

    private var activeKeyValue: String {
        switch profileStore.profile.llmProvider {
        case .openAI: return profileStore.profile.apiKey
        case .claude: return profileStore.profile.claudeApiKey
        case .gemini: return profileStore.profile.geminiApiKey
        }
    }

    private func setActiveKey(_ value: String) {
        switch profileStore.profile.llmProvider {
        case .openAI: profileStore.profile.apiKey = value
        case .claude: profileStore.profile.claudeApiKey = value
        case .gemini: profileStore.profile.geminiApiKey = value
        }
    }
}

#Preview {
    NavigationStack {
        APISettingsView()
            .environment(ProfileStore())
            .environment(APIUsageStore())
    }
}
