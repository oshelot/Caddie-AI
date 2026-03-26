//
//  YourBagView.swift
//  CaddieAI
//
//  Club distances editor on a dedicated page.
//

import SwiftUI

struct YourBagView: View {
    @Environment(ProfileStore.self) private var profileStore

    var body: some View {
        @Bindable var store = profileStore

        Form {
            Section("Club Distances (Carry Yards)") {
                ClubDistanceEditor(clubDistances: $store.profile.clubDistances)
            }
        }
        .navigationTitle("Your Bag")
        .scrollDismissesKeyboard(.interactively)
    }
}

#Preview {
    NavigationStack {
        YourBagView()
            .environment(ProfileStore())
    }
}
