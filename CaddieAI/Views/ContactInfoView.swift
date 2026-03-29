//
//  ContactInfoView.swift
//  CaddieAI
//

import SwiftUI

struct ContactInfoView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var showValidationError = false
    @State private var hasSaved = false

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        return !trimmedName.isEmpty && (!trimmedEmail.isEmpty || !trimmedPhone.isEmpty)
    }

    var body: some View {
        Form {
            Section {
                Text("We'd love to keep you in the loop on new features, tips, and updates. Your info is stored on your device and shared only with our mailing list if you choose to submit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()

                TextField("Phone", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            } header: {
                Text("Your Info")
            } footer: {
                Text("Name is required. Please provide at least an email or phone number.")
            }

            Section {
                Button {
                    if isValid {
                        save()
                    } else {
                        showValidationError = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(hasSaved ? "Update" : "Submit")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!isValid && !showValidationError)
            }

            if hasSaved {
                Section {
                    Button(role: .destructive) {
                        clear()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Remove My Info")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle("Stay in Touch")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .alert("Missing Info", isPresented: $showValidationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter your name and at least an email or phone number.")
        }
        .onAppear {
            let profile = profileStore.profile
            name = profile.contactName
            email = profile.contactEmail
            phone = profile.contactPhone
            hasSaved = !profile.contactName.isEmpty
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)

        profileStore.profile.contactName = trimmedName
        profileStore.profile.contactEmail = trimmedEmail
        profileStore.profile.contactPhone = trimmedPhone

        TelemetryService.shared.recordContactInfoSubmitted(
            name: trimmedName,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            phone: trimmedPhone.isEmpty ? nil : trimmedPhone
        )

        hasSaved = true
        dismiss()
    }

    private func clear() {
        profileStore.profile.contactName = ""
        profileStore.profile.contactEmail = ""
        profileStore.profile.contactPhone = ""
        name = ""
        email = ""
        phone = ""
        hasSaved = false
    }
}

#Preview {
    NavigationStack {
        ContactInfoView()
            .environment(ProfileStore())
    }
}
