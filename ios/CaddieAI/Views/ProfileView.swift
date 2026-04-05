//
//  ProfileView.swift
//  CaddieAI
//

import SwiftUI

struct ProfileView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(APIUsageStore.self) private var apiUsageStore
    @Environment(SubscriptionManager.self) private var subscriptionManager

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

                Section("Caddie Voice & Personality") {
                    Picker("Accent", selection: $store.profile.caddieVoiceAccent) {
                        ForEach(CaddieVoiceAccent.allCases) { accent in
                            Text(accent.displayName).tag(accent)
                        }
                    }
                    Picker("Gender", selection: $store.profile.caddieVoiceGender) {
                        ForEach(CaddieVoiceGender.allCases) { gender in
                            Text(gender.displayName).tag(gender)
                        }
                    }
                    Picker("Personality", selection: $store.profile.caddiePersona) {
                        ForEach(CaddiePersona.allCases) { persona in
                            VStack(alignment: .leading) {
                                Text(persona.displayName)
                                Text(persona.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(persona)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        YourBagView()
                    } label: {
                        Label("Your Bag", systemImage: "bag.fill")
                    }

                    NavigationLink {
                        SwingInfoView()
                    } label: {
                        Label("Swing Info", systemImage: "figure.golf")
                    }

                    NavigationLink {
                        TeeBoxPreferenceView()
                    } label: {
                        Label("Tee Box Preference", systemImage: "flag.fill")
                    }
                }

                Section("Scoring") {
                    Toggle("Enable Scorecard", isOn: $store.profile.scoringEnabled)
                    if store.profile.scoringEnabled
                        && store.profile.contactEmail.isEmpty
                        && store.profile.contactPhone.isEmpty {
                        Label(
                            "Add a phone or email in Contact Info to identify your scorecards.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Settings") {
                    NavigationLink {
                        APISettingsView()
                    } label: {
                        Label("API Settings", systemImage: "gearshape.2")
                    }
                    #if DEBUG
                    Toggle("Pro Tier (Debug)", isOn: Binding(
                        get: { subscriptionManager.debugTierOverride == .paid },
                        set: { subscriptionManager.debugTierOverride = $0 ? .paid : nil }
                    ))
                    Text("Current tier: \(subscriptionManager.tier == .paid ? "Pro" : "Free")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Remote Logging", isOn: Binding(
                        get: { LoggingService.shared.isEnabled },
                        set: { LoggingService.shared.isEnabled = $0 }
                    ))
                    #endif

                    if subscriptionManager.tier == .paid {
                        Toggle("Image Analysis (BETA)", isOn: $store.profile.betaImageAnalysis)
                    }
                }

                Section {
                    NavigationLink {
                        ContactInfoView()
                    } label: {
                        Label("Contact Info", systemImage: "envelope.fill")
                    }
                }
            }
            .navigationTitle("Profile")
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                AdBannerSection()
            }
        }
    }
}

#Preview {
    ProfileView()
        .environment(ProfileStore())
        .environment(APIUsageStore())
        .environment(SubscriptionManager())
}
