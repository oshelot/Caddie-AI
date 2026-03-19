//
//  RecommendationView.swift
//  CaddieAI
//

import SwiftUI

struct RecommendationView: View {
    let recommendation: ShotRecommendation
    let analysis: DeterministicAnalysis?
    let errorMessage: String?
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Error banner when LLM failed
                    if let error = errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text("AI unavailable — showing analysis-only recommendation.")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Hero: Club + Effective Distance + TTS button
                    VStack(spacing: 8) {
                        Text(recommendation.club)
                            .font(.system(size: 36, weight: .bold))
                        Text("\(recommendation.effectiveDistanceYards) yards effective")
                            .font(.title3)
                            .foregroundStyle(.secondary)

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
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Target & Preferred Miss
                    GroupBox("Target") {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(recommendation.target, systemImage: "target")
                            Label(recommendation.preferredMiss, systemImage: "arrow.uturn.right")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Risk & Confidence
                    HStack(spacing: 12) {
                        GroupBox("Risk") {
                            Text(recommendation.riskLevel.displayName)
                                .font(.headline)
                                .foregroundStyle(riskColor)
                                .frame(maxWidth: .infinity)
                        }
                        GroupBox("Confidence") {
                            Text(recommendation.confidence.displayName)
                                .font(.headline)
                                .foregroundStyle(confidenceColor)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Rationale
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

                    // Adjustments from deterministic engine
                    if let analysis, !analysis.adjustments.isEmpty {
                        GroupBox("Distance Adjustments") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(analysis.adjustments, id: \.self) { adj in
                                    Text(adj)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Conservative Option
                    if let conservative = recommendation.conservativeOption {
                        GroupBox("Conservative Option") {
                            Text(conservative)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Execution Plan
                    if let plan = recommendation.executionPlan {
                        ExecutionPlanCard(plan: plan)
                    }

                    // Swing Thought
                    VStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text(recommendation.swingThought)
                            .font(.title3)
                            .italic()
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Follow-Up Questions
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
                                apiKey: profileStore.profile.apiKey
                            )
                        }
                    }

                    // Outcome Feedback
                    if showOutcomeSection {
                        GroupBox("How Did It Go?") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    ForEach(ShotOutcome.allCases) { outcome in
                                        Button {
                                            selectedOutcome = outcome
                                        } label: {
                                            VStack(spacing: 2) {
                                                Text(outcome.emoji)
                                                    .font(.title3)
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

                    // New Shot button
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
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Recommendation")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !hasSavedToHistory {
                    viewModel.saveToHistory(historyStore: historyStore)
                    actualClub = recommendation.club
                    hasSavedToHistory = true
                }
            }
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

    private var riskColor: Color {
        switch recommendation.riskLevel {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private var confidenceColor: Color {
        switch recommendation.confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}

// MARK: - Follow-Up Section

private struct FollowUpSection: View {
    @Binding var followUpText: String
    let messages: [FollowUpMessage]
    let isLoading: Bool
    let onSend: () -> Void

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
                Button {
                    onSend()
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
    }
}

#Preview {
    RecommendationView(
        recommendation: .mock,
        analysis: nil,
        errorMessage: nil,
        onNewShot: {}
    )
    .environment(ShotAdvisorViewModel())
    .environment(ProfileStore())
    .environment(TextToSpeechService())
    .environment(ShotHistoryStore())
}
