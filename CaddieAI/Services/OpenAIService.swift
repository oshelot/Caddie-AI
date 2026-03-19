//
//  OpenAIService.swift
//  CaddieAI
//

import Foundation
import UIKit

final class OpenAIService: Sendable {

    static let shared = OpenAIService()

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    // MARK: - Error Type

    struct APIError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Message Type for Conversation History

    struct ChatMessage: Sendable {
        let role: String  // "system", "user", "assistant"
        let content: String
        let imageData: Data?

        init(role: String, content: String, imageData: Data? = nil) {
            self.role = role
            self.content = content
            self.imageData = imageData
        }

        func toAPIFormat() -> [String: Any] {
            if let imageData, role == "user" {
                let base64 = imageData.base64EncodedString()
                return [
                    "role": role,
                    "content": [
                        ["type": "text", "text": content],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)", "detail": "low"]]
                    ] as [[String: Any]]
                ]
            }
            return ["role": role, "content": content]
        }
    }

    // MARK: - Get Recommendation (with optional image)

    func getRecommendation(
        context: ShotContext,
        profile: PlayerProfile,
        deterministicAnalysis: DeterministicAnalysis,
        imageData: Data? = nil,
        voiceNotes: String? = nil
    ) async throws -> ShotRecommendation {
        let trimmedKey = profile.apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else {
            throw APIError(message: "OpenAI API key not configured. Set it in your Profile tab.")
        }

        let systemPrompt = Self.caddieSystemPrompt
        let userMessage = Self.buildUserMessage(
            context: context,
            profile: profile,
            analysis: deterministicAnalysis,
            voiceNotes: voiceNotes
        )

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        let userMsg = ChatMessage(role: "user", content: userMessage, imageData: imageData)
        messages.append(userMsg.toAPIFormat())

        return try await sendRequest(messages: messages, apiKey: trimmedKey)
    }

    // MARK: - Follow-up Conversation

    func askFollowUp(
        question: String,
        conversationHistory: [ChatMessage],
        apiKey: String
    ) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else {
            throw APIError(message: "OpenAI API key not configured.")
        }

        var messages = conversationHistory.map { $0.toAPIFormat() }
        messages.append(["role": "user", "content": question])

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "temperature": 0.7,
            "max_tokens": 500,
            "messages": messages
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = Self.parseErrorMessage(from: data) ?? "Follow-up failed."
            throw APIError(message: errorMessage)
        }

        return try Self.parseTextResponse(from: data)
    }

    // MARK: - Network Request

    private func sendRequest(messages: [[String: Any]], apiKey: String) async throws -> ShotRecommendation {
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "temperature": 0.7,
            "max_tokens": 1500,
            "response_format": ["type": "json_object"],
            "messages": messages
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError(message: "Invalid response from server.")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = Self.parseErrorMessage(from: data)
                ?? "API error: HTTP \(httpResponse.statusCode)"
            throw APIError(message: errorMessage)
        }

        return try Self.parseRecommendation(from: data)
    }

    // MARK: - Response Parsing

    private static func parseRecommendation(from data: Data) throws -> ShotRecommendation {
        let content = try extractContent(from: data)
        guard let contentData = content.data(using: .utf8) else {
            throw APIError(message: "Could not encode response content.")
        }
        do {
            return try JSONDecoder().decode(ShotRecommendation.self, from: contentData)
        } catch {
            throw APIError(message: "Could not decode recommendation: \(error.localizedDescription)")
        }
    }

    private static func parseTextResponse(from data: Data) throws -> String {
        try extractContent(from: data)
    }

    private static func extractContent(from data: Data) throws -> String {
        guard let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = responseJSON["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw APIError(message: "Could not parse API response structure.")
        }
        return content
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorInfo = errorBody["error"] as? [String: Any],
              let message = errorInfo["message"] as? String
        else {
            return nil
        }
        return message
    }

    // MARK: - System Prompt

    static let caddieSystemPrompt = """
        You are an expert golf caddie AI assistant. You have deep knowledge of course \
        management, club selection, shot shaping, and risk/reward decision-making comparable \
        to a PGA Tour caddie with 20+ years of experience.

        Your role is to analyze the shot situation and the deterministic analysis provided, \
        then give a confident, clear recommendation covering BOTH shot strategy and shot \
        execution guidance. You speak with the calm authority of a trusted caddie — concise, \
        specific, and reassuring.

        STRATEGY guidelines:
        - Trust the deterministic distance calculations provided. Do not recalculate effective distance.
        - Focus on: target selection nuance, risk assessment, and mental approach.
        - Consider the player's handicap, miss tendency, and stock shape when choosing targets.
        - For higher handicaps (15+), favor safer plays and larger targets.
        - For lower handicaps (<8), you can suggest more aggressive lines when appropriate.
        - Always provide a conservative option for difficult or risky shots.
        - Rationale should be 2-4 concise bullet points explaining your recommendation.
        - If hazard notes mention specific dangers (water, OB, bunkers), factor them prominently.

        IMAGE guidelines:
        - If an image is attached, use it to supplement your understanding of the lie, stance, \
          and obstacles. Do NOT rely solely on the image — prioritize the structured inputs.
        - If you can see useful details (rough depth, slope, bunker lip, tree canopy), mention \
          them briefly in the rationale.
        - If the image is unclear or doesn't add useful info, ignore it and rely on structured data.

        VOICE NOTES guidelines:
        - If the player provides voice notes, incorporate any extra context they mention \
          (e.g., "I don't love this lie", "pin is tucked right") into your recommendation.
        - Voice notes supplement structured data; they do not replace it.

        EXECUTION guidelines:
        - You will receive a structured execution plan from the deterministic engine. Use it as \
          the foundation. You may refine the phrasing to be more natural and caddie-like, but \
          do NOT contradict the structured template values.
        - Execution guidance must be simple, practical, and usable on the course.
        - Do NOT become a swing coach. No biomechanics. No deep mechanical overhauls.
        - Use plain golfer language: "ball a touch back", "favor your lead side", "shorter finish".
        - Keep it to 1-3 actionable setup/swing cues.
        - The setupSummary should be a single calm sentence summarizing how to set up.
        - The swingThought should be ONE specific, actionable thought.
        - The mistakeToAvoid should be ONE common mistake for this shot type.

        You MUST respond with valid JSON matching this exact schema:
        {
          "club": "string (e.g., '7 Iron', 'Pitching Wedge')",
          "effectiveDistanceYards": number,
          "target": "string describing where to aim",
          "preferredMiss": "string describing the safe miss area",
          "riskLevel": "low" | "medium" | "high",
          "confidence": "high" | "medium" | "low",
          "rationale": ["string bullet 1", "string bullet 2", ...],
          "conservativeOption": "string or null",
          "swingThought": "string - one specific, actionable thought",
          "executionPlan": {
            "archetype": "string (shot archetype name)",
            "setupSummary": "string - one calm sentence",
            "ballPosition": "string",
            "weightDistribution": "string",
            "stanceWidth": "string",
            "alignment": "string",
            "clubface": "string",
            "shaftLean": "string",
            "backswingLength": "string (use: tiny/short/quarter/waist high/half/chest high/three-quarter/full)",
            "followThrough": "string (use: short finish/controlled finish/chest-high finish/full finish/hold-off finish)",
            "tempo": "string",
            "strikeIntention": "string",
            "swingThought": "string",
            "mistakeToAvoid": "string"
          }
        }

        Respond ONLY with the JSON object. No markdown, no explanation outside the JSON.
        """

    // MARK: - User Message Builder

    static func buildUserMessage(
        context: ShotContext,
        profile: PlayerProfile,
        analysis: DeterministicAnalysis,
        voiceNotes: String? = nil,
        historyInsight: String? = nil
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let contextJSON = (try? String(data: encoder.encode(context), encoding: .utf8)) ?? "{}"
        let analysisJSON = (try? String(data: encoder.encode(analysis), encoding: .utf8)) ?? "{}"

        // Build a profile summary without the API key
        let clubList = profile.clubDistances
            .map { "\($0.club.shortName): \($0.carryYards) yards" }
            .joined(separator: ", ")

        let profileSummary = """
            Handicap: \(profile.handicap)
            Stock shape: \(profile.stockShape.displayName)
            Miss tendency: \(profile.missTendency.displayName)
            Default aggressiveness: \(profile.defaultAggressiveness.displayName)
            Bunker confidence: \(profile.bunkerConfidence.displayName)
            Wedge confidence: \(profile.wedgeConfidence.displayName)
            Preferred chip style: \(profile.preferredChipStyle.displayName)
            Swing tendency: \(profile.swingTendency.displayName)
            Club distances: \(clubList)
            """

        let executionJSON = (try? String(data: encoder.encode(analysis.executionPlan), encoding: .utf8)) ?? "{}"

        var message = """
            Shot situation:
            \(contextJSON)

            Player profile:
            \(profileSummary)

            Deterministic analysis (trust these calculations):
            \(analysisJSON)

            Execution template from engine (use as foundation, refine the phrasing):
            \(executionJSON)
            """

        if let voiceNotes, !voiceNotes.isEmpty {
            message += "\n\nPlayer's voice notes: \"\(voiceNotes)\""
        }

        if let historyInsight, !historyInsight.isEmpty {
            message += "\n\nShot history insight: \(historyInsight)"
        }

        message += "\n\nBased on this analysis, provide your caddie recommendation with execution plan as JSON."

        return message
    }

    // MARK: - History Insight Builder

    static func buildHistoryInsight(
        context: ShotContext,
        recommendedClub: Club,
        historyStore: ShotHistoryStore
    ) -> String? {
        var insights: [String] = []

        // Check if the player has overridden this club before
        let overrides = historyStore.commonOverrides(for: recommendedClub.displayName)
        if let topOverride = overrides.first, topOverride.count >= 2 {
            insights.append("Player has switched from \(recommendedClub.displayName) to \(topOverride.club) \(topOverride.count) times in similar situations.")
        }

        // Check average outcome with the recommended club
        if let avgOutcome = historyStore.averageOutcomeForClub(recommendedClub.displayName) {
            let description: String
            if avgOutcome >= 4.0 {
                description = "great"
            } else if avgOutcome >= 3.0 {
                description = "decent"
            } else {
                description = "below average"
            }
            insights.append("Player's historical results with \(recommendedClub.displayName): \(description) (avg \(String(format: "%.1f", avgOutcome))/5).")
        }

        // Check club usage for this shot type and distance range
        let distRange = max(0, context.distanceYards - 15)...(context.distanceYards + 15)
        let stats = historyStore.clubUsageStats(shotType: context.shotType, distanceRange: distRange)
        if !stats.isEmpty {
            let top = stats.prefix(2).map { "\($0.club) (\($0.count)x)" }.joined(separator: ", ")
            insights.append("For similar shots (\(context.shotType.displayName), ~\(context.distanceYards) yds), player has used: \(top).")
        }

        return insights.isEmpty ? nil : insights.joined(separator: " ")
    }
}
