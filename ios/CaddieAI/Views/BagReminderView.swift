//
//  BagReminderView.swift
//  CaddieAI
//
//  Full-screen reminder shown on launch if the user hasn't configured their bag yet.
//

import SwiftUI

struct BagReminderView: View {
    @Environment(ProfileStore.self) private var profileStore
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "bag.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
                .padding(.bottom, 20)

            Text("Set Up Your Bag")
                .font(.title.bold())
                .padding(.bottom, 6)

            Text("Your caddie needs your club distances to make accurate recommendations. Head to **Profile → Your Bag** to select your clubs and set carry distances.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

            Spacer()

            Button {
                profileStore.profile.hasConfiguredBag = true
                onDismiss()
            } label: {
                Text("Got it, I'll set it up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Button {
                onDismiss()
            } label: {
                Text("Remind me next time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 48)
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    BagReminderView(onDismiss: {})
        .environment(ProfileStore())
}
