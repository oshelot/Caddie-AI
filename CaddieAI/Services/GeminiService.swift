//
//  GeminiService.swift
//  CaddieAI
//
//  Google Gemini API integration.
//

import Foundation

final class GeminiService: Sendable {

    static let shared = GeminiService()

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/"

    // MARK: - Get Recommendation (JSON response)

    func getRecommendation(
        context: ShotContext,
        profile: PlayerProfile,
        deterministicAnalysis: DeterministicAnalysis,
        model: LLMModel,
        imageData: Data? = nil,
        voiceNotes: String? = nil
    ) async throws -> (ShotRecommendation, OpenAIService.TokenUsage?) {
        let apiKey = profile.geminiApiKey.trimmingCharacters(in: .whitespaces)
        guard !apiKey.isEmpty else {
            throw OpenAIService.APIError(message: "Gemini API key not configured. Set it in Profile → API Settings.")
        }

        let systemPrompt = OpenAIService.caddieSystemPrompt
        let userMessage = OpenAIService.buildUserMessage(
            context: context, profile: profile,
            analysis: deterministicAnalysis,
            voiceNotes: voiceNotes
        )

        var parts: [[String: Any]] = []
        if let imageData {
            let base64 = imageData.base64EncodedString()
            parts.append([
                "inlineData": [
                    "mimeType": "image/jpeg",
                    "data": base64
                ] as [String: Any]
            ])
        }
        parts.append(["text": userMessage])

        let requestBody: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 1500,
                "responseMimeType": "application/json"
            ] as [String: Any]
        ]

        let url = try buildURL(model: model, apiKey: apiKey)
        let data = try await performRequest(url: url, body: requestBody)
        return try Self.parseRecommendation(from: data)
    }

    // MARK: - Hole Analysis (text response)

    func getHoleAnalysis(
        hole: NormalizedHole,
        analysis: HoleAnalysis,
        course: NormalizedCourse,
        profile: PlayerProfile,
        model: LLMModel
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        let apiKey = profile.geminiApiKey.trimmingCharacters(in: .whitespaces)
        guard !apiKey.isEmpty else {
            throw OpenAIService.APIError(message: "Gemini API key not configured.")
        }

        let systemPrompt = OpenAIService.holeAnalysisSystemPrompt
        let userMessage = OpenAIService.buildHoleAnalysisMessage(
            hole: hole, analysis: analysis, course: course, profile: profile
        )

        let requestBody: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": userMessage]]]],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 1000
            ] as [String: Any]
        ]

        let url = try buildURL(model: model, apiKey: apiKey)
        let data = try await performRequest(url: url, body: requestBody)
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
            throw OpenAIService.APIError(message: "Gemini API key not configured.")
        }

        // Gemini uses "user" and "model" roles. System goes to systemInstruction.
        var systemText = ""
        var contents: [[String: Any]] = []
        for msg in conversationHistory {
            if msg.role == "system" {
                systemText += msg.content + "\n"
            } else {
                let geminiRole = msg.role == "assistant" ? "model" : "user"
                var parts: [[String: Any]] = [["text": msg.content]]
                if let imageData = msg.imageData, msg.role == "user" {
                    parts.insert([
                        "inlineData": ["mimeType": "image/jpeg", "data": imageData.base64EncodedString()] as [String: Any]
                    ], at: 0)
                }
                contents.append(["role": geminiRole, "parts": parts])
            }
        }
        contents.append(["role": "user", "parts": [["text": question]]])

        var requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 500
            ] as [String: Any]
        ]
        if !systemText.isEmpty {
            requestBody["systemInstruction"] = ["parts": [["text": systemText]]]
        }

        let url = try buildURL(model: model, apiKey: trimmedKey)
        let data = try await performRequest(url: url, body: requestBody)
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

    private func buildURL(model: LLMModel, apiKey: String) throws -> URL {
        guard let url = URL(string: "\(baseURL)\(model.rawValue):generateContent?key=\(apiKey)") else {
            throw OpenAIService.APIError(message: "Invalid Gemini API URL.")
        }
        return url
    }

    private func performRequest(url: URL, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = Self.parseErrorMessage(from: data) ?? "Gemini API error."
            throw OpenAIService.APIError(message: errorMessage)
        }

        return data
    }

    // MARK: - Response Parsing

    private static func parseRecommendation(from data: Data) throws -> (ShotRecommendation, OpenAIService.TokenUsage?) {
        let (content, usage) = try extractContentAndUsage(from: data)
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let contentData = cleaned.data(using: .utf8) else {
            throw OpenAIService.APIError(message: "Could not encode Gemini response content.")
        }
        let recommendation = try JSONDecoder().decode(ShotRecommendation.self, from: contentData)
        return (recommendation, usage)
    }

    private static func parseTextResponse(from data: Data) throws -> (String, OpenAIService.TokenUsage?) {
        try extractContentAndUsage(from: data)
    }

    private static func extractContentAndUsage(from data: Data) throws -> (String, OpenAIService.TokenUsage?) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else {
            throw OpenAIService.APIError(message: "Could not parse Gemini response structure.")
        }

        var tokenUsage: OpenAIService.TokenUsage?
        if let meta = json["usageMetadata"] as? [String: Any],
           let prompt = meta["promptTokenCount"] as? Int,
           let completion = meta["candidatesTokenCount"] as? Int,
           let total = meta["totalTokenCount"] as? Int {
            tokenUsage = OpenAIService.TokenUsage(
                promptTokens: prompt,
                completionTokens: completion,
                totalTokens: total
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
}
