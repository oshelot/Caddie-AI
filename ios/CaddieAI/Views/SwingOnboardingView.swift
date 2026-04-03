//
//  SwingOnboardingView.swift
//  CaddieAI
//
//  Full-screen 4-step swing onboarding shown after the contact prompt.
//  Step 0: Handicap  |  Step 1: Stock shapes  |  Step 2: Short game  |  Step 3: Your Bag prompt
//

import SwiftUI

struct SwingOnboardingView: View {
    @Environment(ProfileStore.self) private var profileStore
    var onDismiss: () -> Void

    @State private var step = 0

    // Step 0 — Handicap
    @State private var handicapText: String = ""
    @State private var showHandicapError = false

    // Step 1 — Stock shapes
    @State private var woodsShape: StockShape = .straight
    @State private var ironsShape: StockShape = .straight
    @State private var hybridsShape: StockShape = .straight

    // Step 2 — Short game
    @State private var missTendency: MissTendency = .straight
    @State private var bunkerConfidence: SelfConfidence = .average
    @State private var wedgeConfidence: SelfConfidence = .average
    @State private var chipStyle: ChipStyle = .noPreference

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<4) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color(.systemGray4))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)

            switch step {
            case 0:
                handicapStep
            case 1:
                stockShapeStep
            case 2:
                shortGameStep
            default:
                bagPromptStep
            }
        }
        .background(Color(.systemBackground))
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: - Step 0: Handicap

    private var handicapStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "figure.golf")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .padding(.bottom, 20)

            Text("Let's Learn Your Swing")
                .font(.title.bold())
                .padding(.bottom, 6)

            Text("What's your handicap?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)

            TextField("15.0", text: $handicapText)
                .font(.system(size: 48, weight: .semibold))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
                .padding(.bottom, 8)

            Text("Enter a number from 0 to 54")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                if validateHandicap() {
                    profileStore.profile.handicap = Double(handicapText)!
                    step = 1
                } else {
                    showHandicapError = true
                }
            } label: {
                Text("Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .alert("Invalid Handicap", isPresented: $showHandicapError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter a number between 0 and 54 with at most one decimal place (e.g. 15.3).")
        }
    }

    // MARK: - Step 1: Stock Shapes

    private var stockShapeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "arrow.up.right.and.arrow.down.left")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .padding(.bottom, 20)

            Text("Your Shot Shape")
                .font(.title.bold())
                .padding(.bottom, 6)

            Text("What's your typical ball flight for each club type?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

            VStack(spacing: 16) {
                shapePicker(label: "Woods", selection: $woodsShape)
                shapePicker(label: "Irons", selection: $ironsShape)
                shapePicker(label: "Hybrids", selection: $hybridsShape)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                profileStore.profile.woodsStockShape = woodsShape
                profileStore.profile.ironsStockShape = ironsShape
                profileStore.profile.hybridsStockShape = hybridsShape
                step = 2
            } label: {
                Text("Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Button {
                step = 0
            } label: {
                Text("Back")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 2: Short Game

    private var shortGameStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "flag.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
                .padding(.bottom, 20)

            Text("Short Game")
                .font(.title.bold())
                .padding(.bottom, 6)

            Text("Help your caddie understand your tendencies around the green.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

            VStack(spacing: 16) {
                pickerRow(label: "Miss Tendency", selection: $missTendency, cases: MissTendency.allCases)
                pickerRow(label: "Bunker Confidence", selection: $bunkerConfidence, cases: SelfConfidence.allCases)
                pickerRow(label: "Wedge Confidence", selection: $wedgeConfidence, cases: SelfConfidence.allCases)
                pickerRow(label: "Chip Style", selection: $chipStyle, cases: ChipStyle.allCases)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                saveShortGame()
            } label: {
                Text("Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Button {
                step = 1
            } label: {
                Text("Back")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 3: Your Bag Prompt

    private var bagPromptStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "bag.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
                .padding(.bottom, 20)

            Text("Set Up Your Bag")
                .font(.title.bold())
                .padding(.bottom, 6)

            Text("Head to **Profile → Your Bag** to select your clubs and set your carry distances. This helps your caddie recommend the right club.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

            Spacer()

            Button {
                profileStore.profile.hasConfiguredBag = true
                finishOnboarding()
            } label: {
                Text("Go to My Bag")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Button {
                finishOnboarding()
            } label: {
                Text("I'll do it later")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Helpers

    private func shapePicker(label: String, selection: Binding<StockShape>) -> some View {
        HStack {
            Text(label)
                .font(.headline)
                .frame(width: 80, alignment: .leading)
            Picker(label, selection: selection) {
                ForEach(StockShape.allCases) { shape in
                    Text(shape.displayName).tag(shape)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func pickerRow<T: CaseIterable & Identifiable & Hashable>(
        label: String,
        selection: Binding<T>,
        cases: [T]
    ) -> some View where T: RawRepresentable, T.RawValue == String {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Picker(label, selection: selection) {
                ForEach(cases) { item in
                    Text((item as? any DisplayNameProviding)?.displayName ?? "\(item)")
                        .tag(item)
                }
            }
            .labelsHidden()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func validateHandicap() -> Bool {
        let trimmed = handicapText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard let value = Double(trimmed) else { return false }
        guard value >= 0 && value <= 54 else { return false }
        // Max 1 decimal place
        if let dotIndex = trimmed.firstIndex(of: ".") {
            let decimals = trimmed[trimmed.index(after: dotIndex)...]
            if decimals.count > 1 { return false }
        }
        return true
    }

    private func saveShortGame() {
        profileStore.profile.missTendency = missTendency
        profileStore.profile.bunkerConfidence = bunkerConfidence
        profileStore.profile.wedgeConfidence = wedgeConfidence
        profileStore.profile.preferredChipStyle = chipStyle
        step = 3
    }

    private func finishOnboarding() {
        profileStore.profile.hasCompletedSwingOnboarding = true
        onDismiss()
    }
}

// MARK: - Display Name Protocol

private protocol DisplayNameProviding {
    var displayName: String { get }
}

extension MissTendency: DisplayNameProviding {}
extension SelfConfidence: DisplayNameProviding {}
extension ChipStyle: DisplayNameProviding {}

#Preview {
    SwingOnboardingView(onDismiss: {})
        .environment(ProfileStore())
}
