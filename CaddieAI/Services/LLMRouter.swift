//
//  LLMRouter.swift
//  CaddieAI
//
//  Routes LLM calls to the correct provider service based on the user's
//  profile settings and subscription tier.
//
//  Free tier  → client-side call using the user's own API key (OpenAI / Claude / Gemini).
//  Paid tier  → backend proxy (forces gpt-4o-mini, no user key required).
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
        voiceNotes: String? = nil,
        tier: UserTier = .free
    ) async throws -> (ShotRecommendation, OpenAIService.TokenUsage?) {
        if tier == .paid {
            return try await proxyRecommendation(
                context: context, profile: profile,
                deterministicAnalysis: deterministicAnalysis,
                imageData: imageData, voiceNotes: voiceNotes
            )
        }

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
        profile: PlayerProfile,
        tier: UserTier = .free,
        selectedTee: String? = nil
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        if tier == .paid {
            return try await proxyHoleAnalysis(
                hole: hole, analysis: analysis,
                course: course, profile: profile,
                selectedTee: selectedTee
            )
        }

        switch profile.llmProvider {
        case .openAI:
            return try await OpenAIService.shared.getHoleAnalysis(
                hole: hole, analysis: analysis, course: course,
                profile: profile, model: profile.llmModel.rawValue,
                selectedTee: selectedTee
            )
        case .claude:
            return try await ClaudeService.shared.getHoleAnalysis(
                hole: hole, analysis: analysis, course: course,
                profile: profile, model: profile.llmModel,
                selectedTee: selectedTee
            )
        case .gemini:
            return try await GeminiService.shared.getHoleAnalysis(
                hole: hole, analysis: analysis, course: course,
                profile: profile, model: profile.llmModel,
                selectedTee: selectedTee
            )
        }
    }

    // MARK: - Follow-Up

    func askFollowUp(
        question: String,
        conversationHistory: [OpenAIService.ChatMessage],
        apiKey: String,
        provider: LLMProvider,
        model: LLMModel,
        tier: UserTier = .free
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        if tier == .paid {
            return try await proxyFollowUp(
                question: question,
                conversationHistory: conversationHistory
            )
        }

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
        model: LLMModel,
        tier: UserTier = .free
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        if tier == .paid {
            return try await proxyFollowUp(
                question: question,
                conversationHistory: conversationHistory
            )
        }

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

    // MARK: - Proxy Helpers

    private func proxyRecommendation(
        context: ShotContext,
        profile: PlayerProfile,
        deterministicAnalysis: DeterministicAnalysis,
        imageData: Data?,
        voiceNotes: String?
    ) async throws -> (ShotRecommendation, OpenAIService.TokenUsage?) {
        let userMessage = OpenAIService.buildUserMessage(
            context: context, profile: profile,
            analysis: deterministicAnalysis, voiceNotes: voiceNotes
        )

        var messages: [[String: Any]] = [
            ["role": "system", "content": OpenAIService.caddieSystemPrompt(persona: profile.caddiePersona)]
        ]

        let userMsg = OpenAIService.ChatMessage(role: "user", content: userMessage, imageData: imageData)
        messages.append(userMsg.toAPIFormat())

        return try await LLMProxyService.shared.chatCompletionJSON(messages: messages)
    }

    private func proxyHoleAnalysis(
        hole: NormalizedHole,
        analysis: HoleAnalysis,
        course: NormalizedCourse,
        profile: PlayerProfile,
        selectedTee: String? = nil
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        let userMessage = OpenAIService.buildHoleAnalysisMessage(
            hole: hole, analysis: analysis,
            course: course, profile: profile,
            selectedTee: selectedTee
        )

        let messages: [[String: Any]] = [
            ["role": "system", "content": OpenAIService.holeAnalysisSystemPrompt(persona: profile.caddiePersona)],
            ["role": "user", "content": userMessage]
        ]

        return try await LLMProxyService.shared.chatCompletion(
            messages: messages, maxTokens: 500
        )
    }

    private func proxyFollowUp(
        question: String,
        conversationHistory: [OpenAIService.ChatMessage]
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        var messages = conversationHistory.map { $0.toAPIFormat() }
        messages.append(["role": "user", "content": question])

        return try await LLMProxyService.shared.chatCompletion(
            messages: messages, maxTokens: 500
        )
    }
}
