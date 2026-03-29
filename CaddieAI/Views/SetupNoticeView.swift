//
//  SetupNoticeView.swift
//  CaddieAI
//
//  One-time configuration notice shown after the splash screen
//  to inform users about API key requirements.
//

import SwiftUI

struct SetupNoticeView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon
            Image("SubcultureLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .padding(.bottom, 24)

            Text("Welcome to CaddieAI")
                .font(.title.bold())
                .padding(.bottom, 8)

            Text("Your AI-powered golf caddie")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)

            // Requirement cards
            VStack(spacing: 16) {
                requirementCard(
                    icon: "key.fill",
                    title: "LLM API Key Required",
                    description: "To use the AI caddie, you'll need an API key from one of the supported providers: OpenAI, Claude, or Gemini. You can add your key in the Profile tab under API Settings.",
                    iconColor: .orange
                )

                requirementCard(
                    icon: "star.fill",
                    title: "Or Upgrade to Pro",
                    description: "CaddieAI Pro ($4.99/mo) includes hosted AI caddie access with no API key needed, plus an ad-free experience. Upgrade anytime in API Settings.",
                    iconColor: .purple
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(Color(.systemBackground))
    }

    private func requirementCard(
        icon: String,
        title: String,
        description: String,
        iconColor: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    SetupNoticeView(onDismiss: {})
}
