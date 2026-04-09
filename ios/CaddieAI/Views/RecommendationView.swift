//
//  RecommendationView.swift
//  CaddieAI
//

import SwiftUI

struct RecommendationView: View {
    let onNewShot: () -> Void

    @Environment(ShotAdvisorViewModel.self) private var viewModel
    @Environment(ProfileStore.self) private var profileStore
    @Environment(TextToSpeechService.self) private var ttsService
    @Environment(ShotHistoryStore.self) private var historyStore
    @State private var followUpText = ""
    @State private var hasSavedToHistory = false
    @State private var showOutcomeSection = false
    @State private var selectedOutcome: ShotOutcome?
    @State private var actualClub: String = ""

    private var recommendation: ShotRecommendation {
        viewModel.recommendation ?? .mock
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Loading skeleton while LLM is processing
                    if viewModel.phase == .loading {
                        SkeletonView()
                            .transition(.opacity)
                    }

                    // Error banner when LLM failed (showing fallback)
                    if case .error(let msg) = viewModel.phase {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text("AI unavailable — showing analysis-only recommendation.")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            Text(msg)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // SECTION 1: Hero — Club + Distance + Target/Miss
                    if viewModel.revealStep >= 1 {
                        heroSection
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // SECTION 2: How to Hit It (progressive field reveal)
                    if viewModel.revealStep >= 2, let plan = recommendation.executionPlan {
                        ProgressiveExecutionPlanCard(plan: plan)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // SECTION 3: Why This Club
                    if viewModel.revealStep >= 3 {
                        rationaleSection
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Follow-Up Questions (available after reveal completes)
                    if viewModel.phase == .complete || viewModel.phase.isError {
                        FollowUpSection(
                            followUpText: $followUpText,
                            messages: viewModel.followUpMessages,
                            isLoading: viewModel.isAskingFollowUp
                        ) {
                            let question = followUpText
                            followUpText = ""
                            Task {
                                await viewModel.askFollowUp(
                                    question: question,
                                    profile: profileStore.profile
                                )
                            }
                        }
                    }

                    // Outcome Feedback
                    if viewModel.phase == .complete || viewModel.phase.isError {
                        outcomeSection
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.35), value: viewModel.revealStep)
                .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
            }
            .navigationTitle("Recommendation")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                // Sticky "New Shot" button — always visible
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        ttsService.stop()
                        onNewShot()
                    } label: {
                        Text("New Shot")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
            .onAppear {
                if !hasSavedToHistory, viewModel.recommendation != nil {
                    viewModel.saveToHistory(historyStore: historyStore)
                    actualClub = recommendation.club
                    hasSavedToHistory = true
                }
            }
            .onChange(of: viewModel.phase) { _, newPhase in
                // Save to history once recommendation arrives
                if !hasSavedToHistory, viewModel.recommendation != nil,
                   newPhase == .complete || newPhase.isError {
                    viewModel.saveToHistory(historyStore: historyStore)
                    actualClub = recommendation.club
                    hasSavedToHistory = true
                }
            }
        }
    }

    // MARK: - Hero Section

    @ViewBuilder
    private var heroSection: some View {
        VStack(spacing: 8) {
            Text(recommendation.club)
                .font(.system(size: 36, weight: .bold))
            Text("\(recommendation.effectiveDistanceYards) yards effective")
                .font(.title3)
                .foregroundStyle(.secondary)

            // Target & Preferred Miss (compact)
            VStack(spacing: 4) {
                Label(recommendation.target, systemImage: "target")
                    .font(.callout)
                Label(recommendation.preferredMiss, systemImage: "arrow.uturn.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            Button {
                if ttsService.isSpeaking {
                    ttsService.stop()
                } else {
                    ttsService.speak(spokenSummary)
                }
            } label: {
                Label(
                    ttsService.isSpeaking ? "Stop" : "Read Aloud",
                    systemImage: ttsService.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.circle.fill"
                )
                .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .padding(.top, 4)

            #if DEBUG
            debugLatencyLabel(engine: viewModel.engineLatencyMs, llm: viewModel.llmLatencyMs)
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Rationale Section

    @ViewBuilder
    private var rationaleSection: some View {
        GroupBox("Why This Club") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(recommendation.rationale, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\u{2022}")
                            .foregroundStyle(.secondary)
                        Text(bullet)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Outcome Section

    @ViewBuilder
    private var outcomeSection: some View {
        if showOutcomeSection {
            GroupBox("How Did It Go?") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ForEach(ShotOutcome.allCases) { outcome in
                            Button {
                                selectedOutcome = outcome
                            } label: {
                                VStack(spacing: 2) {
                                    Text(verbatim: outcome.emoji)
                                        .font(.system(size: 24))
                                    Text(outcome.displayName)
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    selectedOutcome == outcome ? Color.accentColor.opacity(0.2) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedOutcome == outcome ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Picker("Club Used", selection: $actualClub) {
                        Text("Same as recommended").tag(recommendation.club)
                        ForEach(Club.shotClubs) { club in
                            if club.displayName != recommendation.club {
                                Text(club.displayName).tag(club.displayName)
                            }
                        }
                    }
                    .pickerStyle(.menu)

                    if let outcome = selectedOutcome {
                        Button("Save Result") {
                            viewModel.updateOutcome(
                                outcome: outcome,
                                actualClub: actualClub,
                                notes: "",
                                historyStore: historyStore
                            )
                            showOutcomeSection = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        } else {
            Button {
                showOutcomeSection = true
            } label: {
                Label("Log Shot Result", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Spoken Summary

    private var spokenSummary: String {
        var text = "\(recommendation.club). \(recommendation.effectiveDistanceYards) yards effective. "
        text += "Target: \(recommendation.target). "
        text += "Preferred miss: \(recommendation.preferredMiss). "
        if let exec = recommendation.executionPlan {
            text += exec.setupSummary + " "
            text += "Swing thought: \(exec.swingThought)."
        } else {
            text += "Swing thought: \(recommendation.swingThought)."
        }
        return text
    }

    #if DEBUG
    @ViewBuilder
    private func debugLatencyLabel(engine: Int?, llm: Int?) -> some View {
        if engine != nil || llm != nil {
            let parts = [
                engine.map { "Engine: \($0)ms" },
                llm.map { "LLM: \(formattedMs($0))" }
            ].compactMap { $0 }
            Text(parts.joined(separator: " | "))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func formattedMs(_ ms: Int) -> String {
        if ms >= 1000 {
            let formatted = String(format: "%.1f", Double(ms) / 1000.0)
            return "\(formatted)s"
        }
        return "\(ms)ms"
    }
    #endif
}

// MARK: - Skeleton View

private struct SkeletonView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 24) {
            // Pulsing golf icon
            Image(systemName: "figure.golf")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.4))
                .scaleEffect(pulse ? 1.08 : 0.95)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

            Text("Analyzing your shot...")
                .font(.headline)
                .foregroundStyle(.secondary)

            ProgressView()
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .onAppear { pulse = true }
    }
}

// MARK: - Follow-Up Section

private struct FollowUpSection: View {
    @Binding var followUpText: String
    let messages: [FollowUpMessage]
    let isLoading: Bool
    let onSend: () -> Void
    @State private var showOffTopicAlert = false

    // Quick question suggestions
    private let quickQuestions = [
        "Where in my stance?",
        "How much weight left?",
        "Full swing or less?",
        "What's the safe miss?"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask Your Caddie")
                .font(.headline)

            // Quick question chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickQuestions, id: \.self) { question in
                        Button(question) {
                            followUpText = question
                            onSend()
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }

            // Conversation messages
            ForEach(messages) { msg in
                HStack(alignment: .top, spacing: 8) {
                    if msg.role == .user {
                        Spacer()
                        Text(msg.text)
                            .font(.callout)
                            .padding(10)
                            .background(.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "figure.golf")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(msg.text)
                            .font(.callout)
                            .padding(10)
                            .background(.green.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Spacer()
                    }
                }
            }

            if isLoading {
                HStack(spacing: 8) {
                    Image(systemName: "figure.golf")
                        .foregroundStyle(.green)
                        .font(.caption)
                    ProgressView()
                    Text("Thinking...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Text input
            HStack {
                TextField("Ask a follow-up...", text: $followUpText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: followUpText) { _, new in
                        var capped = new
                        InputGuard.enforceLimit(&capped)
                        if capped != new { followUpText = capped }
                    }
                Button {
                    if InputGuard.isGolfRelated(followUpText) {
                        onSend()
                    } else {
                        showOffTopicAlert = true
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .disabled(followUpText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .alert("Off Topic", isPresented: $showOffTopicAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(PromptService.shared.offTopicResponse)
        }
    }
}

#Preview {
    let vm = ShotAdvisorViewModel()
    // Set a mock recommendation so the preview renders
    vm.recommendation = .mock
    vm.phase = .complete
    vm.revealStep = 3
    return RecommendationView(
        onNewShot: {}
    )
    .environment(vm)
    .environment(ProfileStore())
    .environment(TextToSpeechService())
    .environment(ShotHistoryStore())
}
