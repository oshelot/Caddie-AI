//
//  ProfileView.swift
//  CaddieAI
//

import SwiftUI

struct ProfileView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(APIUsageStore.self) private var apiUsageStore

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

                Section("Caddie Voice") {
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
                }

                Section {
                    NavigationLink {
                        YourBagView()
                    } label: {
                        Label("Your Bag", systemImage: "bag.fill")
                    }

                    NavigationLink {
                        APISettingsView()
                    } label: {
                        Label("API Settings & Usage", systemImage: "gearshape.2")
                    }
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
        .environment(APIUsageStore())
}
