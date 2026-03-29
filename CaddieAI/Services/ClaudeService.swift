//
//  ClaudeService.swift
//  CaddieAI
//
//  Anthropic Claude Messages API integration.
//

import Foundation

final class ClaudeService: Sendable {

    static let shared = ClaudeService()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    // MARK: - Get Recommendation (JSON response)

    func getRecommendation(
        context: ShotContext,
        profile: PlayerProfile,
        deterministicAnalysis: DeterministicAnalysis,
        model: LLMModel,
        imageData: Data? = nil,
        voiceNotes: String? = nil
    ) async throws -> (ShotRecommendation, OpenAIService.TokenUsage?) {
        let apiKey = profile.claudeApiKey.trimmingCharacters(in: .whitespaces)
        guard !apiKey.isEmpty else {
            throw OpenAIService.APIError(message: "Claude API key not configured. Set it in Profile → API Settings.")
        }

        let systemPrompt = OpenAIService.caddieSystemPrompt
        let userMessage = OpenAIService.buildUserMessage(
            context: context, profile: profile,
            analysis: deterministicAnalysis,
            voiceNotes: voiceNotes
        )

        // Build user content parts
        var contentParts: [[String: Any]] = []
        if let imageData {
            let base64 = imageData.base64EncodedString()
            contentParts.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64
                ] as [String: Any]
            ])
        }
        contentParts.append(["type": "text", "text": userMessage])

        let messages: [[String: Any]] = [
            ["role": "user", "content": contentParts]
        ]

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 1500,
            "system": systemPrompt,
            "messages": messages
        ]

        let data = try await performRequest(body: requestBody, apiKey: apiKey)
        return try Self.parseRecommendation(from: data)
    }

    // MARK: - Hole Analysis (text response)

    func getHoleAnalysis(
        hole: NormalizedHole,
        analysis: HoleAnalysis,
        course: NormalizedCourse,
        profile: PlayerProfile,
        model: LLMModel,
        selectedTee: String? = nil
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        let apiKey = profile.claudeApiKey.trimmingCharacters(in: .whitespaces)
        guard !apiKey.isEmpty else {
            throw OpenAIService.APIError(message: "Claude API key not configured.")
        }

        let systemPrompt = OpenAIService.holeAnalysisSystemPrompt
        let userMessage = OpenAIService.buildHoleAnalysisMessage(
            hole: hole, analysis: analysis, course: course, profile: profile,
            selectedTee: selectedTee
        )

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 500,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMessage]]
        ]

        let data = try await performRequest(body: requestBody, apiKey: apiKey)
        return try Self.parseTextResponse(from: data)
    }

    // MARK: - Follow-Up

    func askFollowUp(
        question: String,
        conversationHistory: [OpenAIService.ChatMessage],
        apiKey: String,
        model: LLMModel
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else {
            throw OpenAIService.APIError(message: "Claude API key not configured.")
        }

        // Claude requires system prompt separate from messages
        var systemPrompt = ""
        var messages: [[String: Any]] = []
        for msg in conversationHistory {
            if msg.role == "system" {
                systemPrompt += msg.content + "\n"
            } else {
                messages.append(Self.toClaude(msg))
            }
        }
        messages.append(["role": "user", "content": question])

        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 500,
            "messages": messages
        ]
        if !systemPrompt.isEmpty {
            requestBody["system"] = systemPrompt
        }

        let data = try await performRequest(body: requestBody, apiKey: trimmedKey)
        return try Self.parseTextResponse(from: data)
    }

    func askHoleFollowUp(
        question: String,
        conversationHistory: [OpenAIService.ChatMessage],
        apiKey: String,
        model: LLMModel
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        try await askFollowUp(
            question: question,
            conversationHistory: conversationHistory,
            apiKey: apiKey,
            model: model
        )
    }

    // MARK: - Network

    private func performRequest(body: [String: Any], apiKey: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = Self.parseErrorMessage(from: data) ?? "Claude API error."
            throw OpenAIService.APIError(message: errorMessage)
        }

        return data
    }

    // MARK: - Response Parsing

    private static func parseRecommendation(from data: Data) throws -> (ShotRecommendation, OpenAIService.TokenUsage?) {
        let (content, usage) = try extractContentAndUsage(from: data)
        // Claude may wrap JSON in markdown code fences — strip them
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let contentData = cleaned.data(using: .utf8) else {
            throw OpenAIService.APIError(message: "Could not encode Claude response content.")
        }
        let recommendation = try JSONDecoder().decode(ShotRecommendation.self, from: contentData)
        return (recommendation, usage)
    }

    private static func parseTextResponse(from data: Data) throws -> (String, OpenAIService.TokenUsage?) {
        try extractContentAndUsage(from: data)
    }

    private static func extractContentAndUsage(from data: Data) throws -> (String, OpenAIService.TokenUsage?) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String
        else {
            throw OpenAIService.APIError(message: "Could not parse Claude response structure.")
        }

        var tokenUsage: OpenAIService.TokenUsage?
        if let usage = json["usage"] as? [String: Any],
           let input = usage["input_tokens"] as? Int,
           let output = usage["output_tokens"] as? Int {
            tokenUsage = OpenAIService.TokenUsage(
                promptTokens: input,
                completionTokens: output,
                totalTokens: input + output
            )
        }

        return (text, tokenUsage)
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return nil }
        return message
    }

    // MARK: - Helpers

    private static func toClaude(_ msg: OpenAIService.ChatMessage) -> [String: Any] {
        if let imageData = msg.imageData, msg.role == "user" {
            let base64 = imageData.base64EncodedString()
            return [
                "role": msg.role,
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64] as [String: Any]],
                    ["type": "text", "text": msg.content]
                ] as [[String: Any]]
            ]
        }
        return ["role": msg.role, "content": msg.content]
    }
}
