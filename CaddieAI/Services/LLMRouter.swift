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
        let provider = tier == .paid ? "proxy" : profile.llmProvider.rawValue
        let model = tier == .paid ? "gpt-4o-mini" : profile.llmModel.rawValue
        LoggingService.shared.info(.llm, "LLM request started", metadata: [
            "method": "getRecommendation", "provider": provider,
            "model": model, "tier": tier.rawValue,
        ])
        let start = CFAbsoluteTimeGetCurrent()

        do {
            let result: (ShotRecommendation, OpenAIService.TokenUsage?)
            if tier == .paid {
                result = try await proxyRecommendation(
                    context: context, profile: profile,
                    deterministicAnalysis: deterministicAnalysis,
                    imageData: imageData, voiceNotes: voiceNotes
                )
            } else {
                switch profile.llmProvider {
                case .openAI:
                    result = try await OpenAIService.shared.getRecommendation(
                        context: context, profile: profile,
                        deterministicAnalysis: deterministicAnalysis,
                        model: profile.llmModel.rawValue,
                        imageData: imageData, voiceNotes: voiceNotes
                    )
                case .claude:
                    result = try await ClaudeService.shared.getRecommendation(
                        context: context, profile: profile,
                        deterministicAnalysis: deterministicAnalysis,
                        model: profile.llmModel,
                        imageData: imageData, voiceNotes: voiceNotes
                    )
                case .gemini:
                    result = try await GeminiService.shared.getRecommendation(
                        context: context, profile: profile,
                        deterministicAnalysis: deterministicAnalysis,
                        model: profile.llmModel,
                        imageData: imageData, voiceNotes: voiceNotes
                    )
                }
            }

            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            var meta = ["method": "getRecommendation", "provider": provider,
                        "model": model, "tier": tier.rawValue,
                        "latencyMs": "\(latencyMs)"]
            if let usage = result.1 {
                meta["promptTokens"] = "\(usage.promptTokens)"
                meta["completionTokens"] = "\(usage.completionTokens)"
            }
            LoggingService.shared.info(.llm, "LLM response received", metadata: meta)
            return result
        } catch {
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            LoggingService.shared.error(.llm, "LLM request failed: \(error.localizedDescription)", metadata: [
                "method": "getRecommendation", "provider": provider,
                "model": model, "tier": tier.rawValue,
                "latencyMs": "\(latencyMs)",
            ])
            throw error
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
        let provider = tier == .paid ? "proxy" : profile.llmProvider.rawValue
        let model = tier == .paid ? "gpt-4o-mini" : profile.llmModel.rawValue
        LoggingService.shared.info(.llm, "LLM request started", metadata: [
            "method": "getHoleAnalysis", "provider": provider,
            "model": model, "tier": tier.rawValue,
            "hole": "\(hole.number)",
        ])
        let start = CFAbsoluteTimeGetCurrent()

        do {
            let result: (String, OpenAIService.TokenUsage?)
            if tier == .paid {
                result = try await proxyHoleAnalysis(
                    hole: hole, analysis: analysis,
                    course: course, profile: profile,
                    selectedTee: selectedTee
                )
            } else {
                switch profile.llmProvider {
                case .openAI:
                    result = try await OpenAIService.shared.getHoleAnalysis(
                        hole: hole, analysis: analysis, course: course,
                        profile: profile, model: profile.llmModel.rawValue,
                        selectedTee: selectedTee
                    )
                case .claude:
                    result = try await ClaudeService.shared.getHoleAnalysis(
                        hole: hole, analysis: analysis, course: course,
                        profile: profile, model: profile.llmModel,
                        selectedTee: selectedTee
                    )
                case .gemini:
                    result = try await GeminiService.shared.getHoleAnalysis(
                        hole: hole, analysis: analysis, course: course,
                        profile: profile, model: profile.llmModel,
                        selectedTee: selectedTee
                    )
                }
            }

            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            var meta = ["method": "getHoleAnalysis", "provider": provider,
                        "model": model, "tier": tier.rawValue,
                        "latencyMs": "\(latencyMs)"]
            if let usage = result.1 {
                meta["promptTokens"] = "\(usage.promptTokens)"
                meta["completionTokens"] = "\(usage.completionTokens)"
            }
            LoggingService.shared.info(.llm, "LLM response received", metadata: meta)
            return result
        } catch {
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            LoggingService.shared.error(.llm, "LLM request failed: \(error.localizedDescription)", metadata: [
                "method": "getHoleAnalysis", "provider": provider,
                "model": model, "tier": tier.rawValue,
                "latencyMs": "\(latencyMs)",
                "hole": "\(hole.number)",
            ])
            throw error
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
        LoggingService.shared.info(.llm, "LLM request started", metadata: [
            "method": "askFollowUp",
            "provider": tier == .paid ? "proxy" : provider.rawValue,
            "model": tier == .paid ? "gpt-4o-mini" : model.rawValue,
            "tier": tier.rawValue,
        ])

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
        LoggingService.shared.info(.llm, "LLM request started", metadata: [
            "method": "askHoleFollowUp",
            "provider": tier == .paid ? "proxy" : provider.rawValue,
            "model": tier == .paid ? "gpt-4o-mini" : model.rawValue,
            "tier": tier.rawValue,
        ])

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
