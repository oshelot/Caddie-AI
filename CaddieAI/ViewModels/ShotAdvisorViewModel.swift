//
//  ShotAdvisorViewModel.swift
//  CaddieAI
//

import SwiftUI
import UIKit

@Observable
final class ShotAdvisorViewModel {

    // MARK: - Input State

    var shotContext: ShotContext = .default
    var voiceNotes: String = ""
    var selectedImage: UIImage?

    // MARK: - Output State

    var recommendation: ShotRecommendation?
    var deterministicAnalysis: DeterministicAnalysis?
    var isLoading = false
    var errorMessage: String?

    // MARK: - Conversation State

    var conversationHistory: [OpenAIService.ChatMessage] = []
    var followUpMessages: [FollowUpMessage] = []
    var isAskingFollowUp = false

    // MARK: - Dependencies

    private let openAIService = OpenAIService.shared
    var apiUsageStore: APIUsageStore?

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
        isLoading = true
        errorMessage = nil
        recommendation = nil
        followUpMessages = []
        conversationHistory = []

        // Step 1: Deterministic analysis (instant, on-device)
        let analysis = GolfLogicEngine.analyze(
            context: shotContext,
            profile: profile
        )
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

        // Step 2: LLM enrichment (network call)
        do {
            var (result, usage) = try await openAIService.getRecommendation(
                context: shotContext,
                profile: profile,
                deterministicAnalysis: analysis,
                imageData: imageData,
                voiceNotes: voiceNotes.isEmpty ? nil : voiceNotes
            )
            if let usage, let store = apiUsageStore {
                await MainActor.run {
                    store.recordOpenAIUsage(
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens,
                        totalTokens: usage.totalTokens,
                        method: "getRecommendation"
                    )
                }
            }
            // If LLM didn't return an execution plan, use the deterministic one
            if result.executionPlan == nil {
                result.executionPlan = analysis.executionPlan
            }
            recommendation = result

            // Store conversation history for follow-ups
            let userMessage = OpenAIService.buildUserMessage(
                context: shotContext,
                profile: profile,
                analysis: analysis,
                voiceNotes: voiceNotes.isEmpty ? nil : voiceNotes,
                historyInsight: historyInsight
            )
            conversationHistory = [
                OpenAIService.ChatMessage(role: "system", content: OpenAIService.caddieSystemPrompt
                    + "\n\nFor follow-up questions, respond in plain conversational English. "
                    + "Be concise, calm, and caddie-like. 1-3 sentences max. "
                    + "Answer from the shot context and execution plan. Do not use JSON."),
                OpenAIService.ChatMessage(role: "user", content: userMessage, imageData: imageData),
                OpenAIService.ChatMessage(role: "assistant", content: recommendationSummary(result))
            ]
        } catch {
            errorMessage = error.localizedDescription
            recommendation = buildFallbackRecommendation(from: analysis)
        }

        isLoading = false
    }

    // MARK: - Follow-Up Question

    func askFollowUp(question: String, apiKey: String) async {
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isAskingFollowUp = true
        followUpMessages.append(FollowUpMessage(role: .user, text: question))

        do {
            let (answer, usage) = try await openAIService.askFollowUp(
                question: question,
                conversationHistory: conversationHistory,
                apiKey: apiKey
            )
            if let usage, let store = apiUsageStore {
                await MainActor.run {
                    store.recordOpenAIUsage(
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens,
                        totalTokens: usage.totalTokens,
                        method: "askFollowUp"
                    )
                }
            }
            followUpMessages.append(FollowUpMessage(role: .caddie, text: answer))

            // Update conversation history
            conversationHistory.append(OpenAIService.ChatMessage(role: "user", content: question))
            conversationHistory.append(OpenAIService.ChatMessage(role: "assistant", content: answer))
        } catch {
            followUpMessages.append(FollowUpMessage(role: .caddie, text: "Sorry, I couldn't process that. \(error.localizedDescription)"))
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
        conversationHistory = []
        followUpMessages = []
        lastSavedRecordID = nil
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
