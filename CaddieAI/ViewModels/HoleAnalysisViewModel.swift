//
//  HoleAnalysisViewModel.swift
//  CaddieAI
//
//  Orchestrates hole geometry analysis (Tier 1) and
//  OpenAI caddie narrative (Tier 2) with follow-up support.
//

import Foundation

@Observable
class HoleAnalysisViewModel {
    var analysis: HoleAnalysis?
    var isAnalyzing = false
    var error: String?
    var followUpResponse: String?
    var isAskingFollowUp = false

    private var conversationHistory: [OpenAIService.ChatMessage] = []

    // MARK: - Analyze Hole

    func analyzeHole(
        _ hole: NormalizedHole,
        course: NormalizedCourse,
        profile: PlayerProfile
    ) async {
        isAnalyzing = true
        error = nil
        followUpResponse = nil
        conversationHistory = []

        // Tier 1: Deterministic analysis (instant, on-device)
        var result = HoleAnalysisEngine.analyze(
            hole: hole,
            course: course,
            profile: profile
        )
        analysis = result

        // Tier 2: OpenAI caddie narrative (async)
        let trimmedKey = profile.apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else {
            // No API key — use deterministic summary only
            isAnalyzing = false
            return
        }

        do {
            let advice = try await OpenAIService.shared.getHoleAnalysis(
                hole: hole,
                analysis: result,
                course: course,
                profile: profile
            )
            result.strategicAdvice = advice
            analysis = result

            // Store conversation history for follow-ups
            conversationHistory = [
                OpenAIService.ChatMessage(
                    role: "system",
                    content: OpenAIService.holeAnalysisSystemPrompt
                ),
                OpenAIService.ChatMessage(
                    role: "user",
                    content: OpenAIService.buildHoleAnalysisMessage(
                        hole: hole,
                        analysis: result,
                        course: course,
                        profile: profile
                    )
                ),
                OpenAIService.ChatMessage(
                    role: "assistant",
                    content: advice
                )
            ]
        } catch {
            // Tier 2 failed — deterministic summary is still available
            self.error = "AI advice unavailable: \(error.localizedDescription)"
        }

        isAnalyzing = false
    }

    // MARK: - Follow-up

    func askFollowUp(_ question: String, profile: PlayerProfile) async {
        guard !conversationHistory.isEmpty else {
            followUpResponse = "Run hole analysis first before asking follow-up questions."
            return
        }

        isAskingFollowUp = true
        followUpResponse = nil

        do {
            let response = try await OpenAIService.shared.askHoleFollowUp(
                question: question,
                conversationHistory: conversationHistory,
                apiKey: profile.apiKey
            )
            followUpResponse = response

            // Append to history for multi-turn
            conversationHistory.append(
                OpenAIService.ChatMessage(role: "user", content: question)
            )
            conversationHistory.append(
                OpenAIService.ChatMessage(role: "assistant", content: response)
            )
        } catch {
            followUpResponse = "Could not get follow-up: \(error.localizedDescription)"
        }

        isAskingFollowUp = false
    }
}
