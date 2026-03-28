//
//  LLMRouter.swift
//  CaddieAI
//
//  Routes LLM calls to the correct provider service based on the user's profile settings.
//

import Foundation

final class LLMRouter: Sendable {

    static let shared = LLMRouter()

    // MARK: - Get Recommendation

    func getRecommendation(
        context: ShotContext,
        profile: PlayerProfile,
        deterministicAnalysis: DeterministicAnalysis,
        imageData: Data? = nil,
        voiceNotes: String? = nil
    ) async throws -> (ShotRecommendation, OpenAIService.TokenUsage?) {
        switch profile.llmProvider {
        case .openAI:
            return try await OpenAIService.shared.getRecommendation(
                context: context, profile: profile,
                deterministicAnalysis: deterministicAnalysis,
                model: profile.llmModel.rawValue,
                imageData: imageData, voiceNotes: voiceNotes
            )
        case .claude:
            return try await ClaudeService.shared.getRecommendation(
                context: context, profile: profile,
                deterministicAnalysis: deterministicAnalysis,
                model: profile.llmModel,
                imageData: imageData, voiceNotes: voiceNotes
            )
        case .gemini:
            return try await GeminiService.shared.getRecommendation(
                context: context, profile: profile,
                deterministicAnalysis: deterministicAnalysis,
                model: profile.llmModel,
                imageData: imageData, voiceNotes: voiceNotes
            )
        }
    }

    // MARK: - Hole Analysis

    func getHoleAnalysis(
        hole: NormalizedHole,
        analysis: HoleAnalysis,
        course: NormalizedCourse,
        profile: PlayerProfile
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        switch profile.llmProvider {
        case .openAI:
            return try await OpenAIService.shared.getHoleAnalysis(
                hole: hole, analysis: analysis, course: course,
                profile: profile, model: profile.llmModel.rawValue
            )
        case .claude:
            return try await ClaudeService.shared.getHoleAnalysis(
                hole: hole, analysis: analysis, course: course,
                profile: profile, model: profile.llmModel
            )
        case .gemini:
            return try await GeminiService.shared.getHoleAnalysis(
                hole: hole, analysis: analysis, course: course,
                profile: profile, model: profile.llmModel
            )
        }
    }

    // MARK: - Follow-Up

    func askFollowUp(
        question: String,
        conversationHistory: [OpenAIService.ChatMessage],
        apiKey: String,
        provider: LLMProvider,
        model: LLMModel
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        switch provider {
        case .openAI:
            return try await OpenAIService.shared.askFollowUp(
                question: question, conversationHistory: conversationHistory,
                apiKey: apiKey, model: model.rawValue
            )
        case .claude:
            return try await ClaudeService.shared.askFollowUp(
                question: question, conversationHistory: conversationHistory,
                apiKey: apiKey, model: model
            )
        case .gemini:
            return try await GeminiService.shared.askFollowUp(
                question: question, conversationHistory: conversationHistory,
                apiKey: apiKey, model: model
            )
        }
    }

    // MARK: - Hole Follow-Up

    func askHoleFollowUp(
        question: String,
        conversationHistory: [OpenAIService.ChatMessage],
        apiKey: String,
        provider: LLMProvider,
        model: LLMModel
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        switch provider {
        case .openAI:
            return try await OpenAIService.shared.askHoleFollowUp(
                question: question, conversationHistory: conversationHistory,
                apiKey: apiKey, model: model.rawValue
            )
        case .claude:
            return try await ClaudeService.shared.askHoleFollowUp(
                question: question, conversationHistory: conversationHistory,
                apiKey: apiKey, model: model
            )
        case .gemini:
            return try await GeminiService.shared.askHoleFollowUp(
                question: question, conversationHistory: conversationHistory,
                apiKey: apiKey, model: model
            )
        }
    }
}
