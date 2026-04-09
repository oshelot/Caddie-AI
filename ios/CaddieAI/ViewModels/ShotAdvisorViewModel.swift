//
//  ShotAdvisorViewModel.swift
//  CaddieAI
//

import SwiftUI
import UIKit

// MARK: - Advisor Phase

enum AdvisorPhase: Equatable {
    case idle
    case loading
    case revealing
    case complete
    case error(String)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

@Observable
final class ShotAdvisorViewModel {

    // MARK: - Input State

    var shotContext: ShotContext = .default
    var voiceNotes: String = ""
    var selectedImage: UIImage?

    // MARK: - Output State

    var recommendation: ShotRecommendation?
    var deterministicAnalysis: DeterministicAnalysis?
    var phase: AdvisorPhase = .idle
    var errorMessage: String?

    /// Progressive reveal step: 0 = nothing, 1 = hero, 2 = execution plan, 3 = rationale
    var revealStep: Int = 0
    static let totalRevealSteps = 3

    /// Backward-compat computed properties for code that still references these.
    var isLoading: Bool { phase == .loading }
    var isEnriching: Bool { false }

    /// LLM round-trip latency in milliseconds (debug builds only).
    var llmLatencyMs: Int?
    /// Deterministic engine latency in milliseconds (debug builds only).
    var engineLatencyMs: Int?

    // MARK: - Conversation State

    var conversationHistory: [OpenAIService.ChatMessage] = []
    var followUpMessages: [FollowUpMessage] = []
    var isAskingFollowUp = false

    // MARK: - Timing

    /// Set when voice recording starts; used to measure voice-to-result latency.
    var voiceStartTime: CFAbsoluteTime?

    // MARK: - Dependencies

    private let llmRouter = LLMRouter.shared
    var apiUsageStore: APIUsageStore?
    var subscriptionManager: SubscriptionManager?

    // MARK: - Auto-populate Wind from Weather

    /// Applies live weather data to the shot context wind fields.
    func applyWeather(
        _ weather: WeatherData,
        holeBearingDegrees: Double? = nil
    ) {
        shotContext.windStrength = weather.windStrength

        if let bearing = holeBearingDegrees {
            shotContext.windDirection = weather.relativeWindDirection(
                holeBearingDegrees: bearing
            )
        } else {
            // Without hole context, default to "into" for safety
            shotContext.windDirection = .into
        }
    }

    // MARK: - Get Advice

    func getAdvice(profile: PlayerProfile, historyStore: ShotHistoryStore? = nil) async {
        LoggingService.shared.info(.llm, "Get Advice tapped", metadata: [
            "distance": "\(shotContext.distanceYards)",
            "shotType": shotContext.shotType.rawValue,
            "lie": shotContext.lieType.rawValue,
        ])

        phase = .loading
        errorMessage = nil
        recommendation = nil
        revealStep = 0
        followUpMessages = []
        conversationHistory = []
        llmLatencyMs = nil
        engineLatencyMs = nil

        // Step 1: Deterministic analysis (instant, on-device) — feeds LLM context + fallback
        let engineStart = CFAbsoluteTimeGetCurrent()
        let analysis = GolfLogicEngine.analyze(
            context: shotContext,
            profile: profile
        )
        engineLatencyMs = Int((CFAbsoluteTimeGetCurrent() - engineStart) * 1000)
        deterministicAnalysis = analysis

        // Prepare image data for API
        let imageData = selectedImage?.jpegData(compressionQuality: 0.5)

        // Build history insight for LLM context
        let historyInsight: String?
        if let historyStore {
            historyInsight = OpenAIService.buildHistoryInsight(
                context: shotContext,
                recommendedClub: analysis.recommendedClub,
                historyStore: historyStore
            )
        } else {
            historyInsight = nil
        }

        // Step 2: LLM call — the primary source of recommendation
        let llmStart = CFAbsoluteTimeGetCurrent()
        do {
            let tier = subscriptionManager?.tier ?? .free
            var (result, usage) = try await llmRouter.getRecommendation(
                context: shotContext,
                profile: profile,
                deterministicAnalysis: analysis,
                imageData: imageData,
                voiceNotes: voiceNotes.isEmpty ? nil : voiceNotes,
                tier: tier
            )
            if let usage, let store = apiUsageStore {
                await MainActor.run {
                    store.recordLLMUsage(
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens,
                        totalTokens: usage.totalTokens,
                        method: "getRecommendation",
                        provider: profile.llmProvider
                    )
                }
                TelemetryService.shared.recordLLMCall(
                    provider: profile.llmProvider.rawValue,
                    model: profile.llmModel.rawValue,
                    method: "getRecommendation",
                    promptTokens: usage.promptTokens,
                    completionTokens: usage.completionTokens,
                    totalTokens: usage.totalTokens
                )
            }
            llmLatencyMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1000)

            // Merge deterministic execution plan if LLM didn't provide one
            if result.executionPlan == nil {
                result.executionPlan = analysis.executionPlan
            }
            recommendation = result

            // Log voice-to-result if this flow started from voice
            if let vStart = voiceStartTime {
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - vStart) * 1000)
                LoggingService.shared.info(.llm, "voice_to_result", metadata: [
                    "latencyMs": "\(totalMs)",
                ])
                voiceStartTime = nil
            }

            // Transition to progressive reveal
            phase = .revealing
            await startProgressiveReveal()

            // Store conversation history for follow-ups
            let userMessage = OpenAIService.buildUserMessage(
                context: shotContext,
                profile: profile,
                analysis: analysis,
                voiceNotes: voiceNotes.isEmpty ? nil : voiceNotes,
                historyInsight: historyInsight
            )
            conversationHistory = [
                OpenAIService.ChatMessage(role: "system", content: OpenAIService.caddieSystemPrompt(persona: profile.caddiePersona)
                    + PromptService.shared.followUpAugmentation),
                OpenAIService.ChatMessage(role: "user", content: userMessage, imageData: imageData),
                OpenAIService.ChatMessage(role: "assistant", content: recommendationSummary(result))
            ]
        } catch {
            errorMessage = error.localizedDescription
            // Build fallback from deterministic and show everything immediately
            recommendation = buildFallbackRecommendation(from: analysis)
            revealStep = Self.totalRevealSteps
            phase = .error(error.localizedDescription)
            LoggingService.shared.error(.llm, "getRecommendation failed: \(error.localizedDescription)", metadata: [
                "provider": profile.llmProvider.rawValue,
                "model": profile.llmModel.rawValue,
                "tier": (subscriptionManager?.tier ?? .free).rawValue,
            ])
        }
    }

    // MARK: - Progressive Reveal

    @MainActor
    private func startProgressiveReveal() async {
        // Step 1: Show hero section (club + distance + target/miss) with a brief pause
        // so the skeleton-to-content transition is visible
        try? await Task.sleep(for: .milliseconds(300))
        guard phase == .revealing else { return }
        withAnimation(.easeOut(duration: 0.4)) {
            revealStep = 1
        }

        // Step 2: Show "How to Hit It" — noticeable gap so user reads the club first
        try? await Task.sleep(for: .milliseconds(800))
        guard phase == .revealing else { return }
        withAnimation(.easeOut(duration: 0.4)) {
            revealStep = 2
        }

        // Wait for execution plan field-by-field animation to mostly finish
        // (13 fields * 120ms = ~1.56s)
        try? await Task.sleep(for: .milliseconds(1800))
        guard phase == .revealing else { return }

        // Step 3: Show "Why This Club" rationale
        withAnimation(.easeOut(duration: 0.4)) {
            revealStep = 3
        }

        // Mark complete after rationale animates in
        try? await Task.sleep(for: .milliseconds(500))
        guard phase == .revealing else { return }
        phase = .complete
    }

    // MARK: - Follow-Up Question

    func askFollowUp(question: String, profile: PlayerProfile) async {
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isAskingFollowUp = true
        followUpMessages.append(FollowUpMessage(role: .user, text: question))

        // Add a placeholder caddie message that will be updated as chunks stream in
        let placeholderIndex = followUpMessages.count
        followUpMessages.append(FollowUpMessage(role: .caddie, text: ""))

        do {
            let tier = subscriptionManager?.tier ?? .free
            let (answer, usage) = try await llmRouter.askFollowUpStreaming(
                question: question,
                conversationHistory: conversationHistory,
                apiKey: profile.activeLLMApiKey,
                provider: profile.llmProvider,
                model: profile.llmModel,
                tier: tier
            ) { [weak self] accumulated in
                guard let self else { return }
                self.followUpMessages[placeholderIndex] = FollowUpMessage(role: .caddie, text: accumulated)
            }
            if let usage, let store = apiUsageStore {
                await MainActor.run {
                    store.recordLLMUsage(
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens,
                        totalTokens: usage.totalTokens,
                        method: "askFollowUp",
                        provider: profile.llmProvider
                    )
                }
                TelemetryService.shared.recordLLMCall(
                    provider: profile.llmProvider.rawValue,
                    model: profile.llmModel.rawValue,
                    method: "askFollowUp",
                    promptTokens: usage.promptTokens,
                    completionTokens: usage.completionTokens,
                    totalTokens: usage.totalTokens
                )
            }
            // Set the final complete answer
            followUpMessages[placeholderIndex] = FollowUpMessage(role: .caddie, text: answer)

            // Update conversation history
            conversationHistory.append(OpenAIService.ChatMessage(role: "user", content: question))
            conversationHistory.append(OpenAIService.ChatMessage(role: "assistant", content: answer))
        } catch {
            followUpMessages[placeholderIndex] = FollowUpMessage(role: .caddie, text: "Sorry, I couldn't process that. \(error.localizedDescription)")
            LoggingService.shared.error(.llm, "askFollowUp failed: \(error.localizedDescription)", metadata: [
                "provider": profile.llmProvider.rawValue,
                "model": profile.llmModel.rawValue,
            ])
        }

        isAskingFollowUp = false
    }

    // MARK: - Shot History

    var lastSavedRecordID: UUID?

    func saveToHistory(historyStore: ShotHistoryStore) {
        guard let rec = recommendation else { return }
        let record = ShotRecord(
            context: shotContext,
            recommendedClub: rec.club,
            effectiveDistance: rec.effectiveDistanceYards,
            target: rec.target
        )
        historyStore.addRecord(record)
        lastSavedRecordID = record.id
    }

    func updateOutcome(
        outcome: ShotOutcome,
        actualClub: String?,
        notes: String,
        historyStore: ShotHistoryStore
    ) {
        guard let recordID = lastSavedRecordID,
              var record = historyStore.records.first(where: { $0.id == recordID })
        else { return }
        record.outcome = outcome
        record.actualClubUsed = actualClub
        record.notes = notes
        historyStore.updateRecord(record)
    }

    // MARK: - Reset

    func resetForNewShot() {
        shotContext = .default
        voiceNotes = ""
        selectedImage = nil
        recommendation = nil
        deterministicAnalysis = nil
        errorMessage = nil
        phase = .idle
        revealStep = 0
        conversationHistory = []
        followUpMessages = []
        lastSavedRecordID = nil
        llmLatencyMs = nil
        engineLatencyMs = nil
    }

    // MARK: - Fallback

    private func buildFallbackRecommendation(
        from analysis: DeterministicAnalysis
    ) -> ShotRecommendation {
        ShotRecommendation(
            club: analysis.recommendedClub.displayName,
            effectiveDistanceYards: analysis.effectiveDistanceYards,
            target: analysis.targetStrategy.target,
            preferredMiss: analysis.targetStrategy.preferredMiss,
            riskLevel: .medium,
            confidence: .medium,
            rationale: analysis.adjustments + [analysis.targetStrategy.reasoning],
            conservativeOption: nil,
            swingThought: analysis.executionPlan.swingThought,
            executionPlan: analysis.executionPlan
        )
    }

    // MARK: - Helpers

    private func recommendationSummary(_ rec: ShotRecommendation) -> String {
        var summary = "Recommendation: \(rec.club), \(rec.effectiveDistanceYards) yards effective. "
        summary += "Target: \(rec.target). Preferred miss: \(rec.preferredMiss). "
        summary += "Risk: \(rec.riskLevel.displayName). "
        summary += rec.rationale.joined(separator: " ")
        if let exec = rec.executionPlan {
            summary += " Setup: \(exec.setupSummary)"
            summary += " Ball position: \(exec.ballPosition)."
            summary += " Weight: \(exec.weightDistribution)."
            summary += " Backswing: \(exec.backswingLength)."
            summary += " Swing thought: \(exec.swingThought)."
        }
        return summary
    }
}

// MARK: - Follow-Up Message

struct FollowUpMessage: Identifiable {
    let id = UUID()
    let role: FollowUpRole
    let text: String
}

enum FollowUpRole {
    case user
    case caddie
}
