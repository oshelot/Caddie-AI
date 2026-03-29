//
//  OnboardingContactView.swift
//  CaddieAI
//
//  Full-screen prompt shown after splash/setup to collect contact info.
//  Shown up to 3 times with at least 30 days between each prompt.
//

import SwiftUI

struct OnboardingContactView: View {
    @Environment(ProfileStore.self) private var profileStore
    var onDismiss: () -> Void

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var showValidationError = false

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        return !trimmedName.isEmpty && (!trimmedEmail.isEmpty || !trimmedPhone.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "envelope.open.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .padding(.bottom, 20)

            Text("Stay in Touch")
                .font(.title.bold())
                .padding(.bottom, 6)

            Text("Get notified about new features, tips, and updates. Your info is stored on your device and shared only with our mailing list.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

            // Form fields
            VStack(spacing: 12) {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                TextField("Phone", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)

            Text("Name + at least email or phone required.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer()

            // Continue button
            Button {
                if isValid {
                    submit()
                } else {
                    showValidationError = true
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Skip button
            Button {
                skip()
            } label: {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 48)
        }
        .background(Color(.systemBackground))
        .alert("Missing Info", isPresented: $showValidationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter your name and at least an email or phone number.")
        }
        .onAppear {
            profileStore.profile.contactPromptLastShown = Date()
        }
    }

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)

        profileStore.profile.contactName = trimmedName
        profileStore.profile.contactEmail = trimmedEmail
        profileStore.profile.contactPhone = trimmedPhone
        // Mark as fully completed so we never show again
        profileStore.profile.contactPromptSkipCount = 3

        TelemetryService.shared.recordContactInfoSubmitted(
            name: trimmedName,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            phone: trimmedPhone.isEmpty ? nil : trimmedPhone
        )

        onDismiss()
    }

    private func skip() {
        profileStore.profile.contactPromptSkipCount += 1
        onDismiss()
    }
}

#Preview {
    OnboardingContactView(onDismiss: {})
        .environment(ProfileStore())
}
