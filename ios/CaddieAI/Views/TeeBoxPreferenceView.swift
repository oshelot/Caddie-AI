//
//  TeeBoxPreferenceView.swift
//  CaddieAI
//
//  Default tee box preference — used for auto-selecting tees when a course loads.
//

import SwiftUI

struct TeeBoxPreferenceView: View {
    @Environment(ProfileStore.self) private var profileStore

    var body: some View {
        @Bindable var store = profileStore

        Form {
            Section {
                ForEach(TeeBoxPreference.allCases) { tee in
                    Button {
                        store.profile.preferredTeeBox = tee
                    } label: {
                        HStack {
                            Text(tee.displayName)
                            Spacer()
                            if store.profile.preferredTeeBox == tee {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .tint(.primary)
                }
            } footer: {
                Text("Your preferred tee will be auto-selected when loading a course. If the exact tee isn't available, the closest match will be used. You can always change the tee from the course map toolbar.")
            }
        }
        .navigationTitle("Tee Box Preference")
    }
}

#Preview {
    NavigationStack {
        TeeBoxPreferenceView()
            .environment(ProfileStore())
    }
}
