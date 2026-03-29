//
//  LLMProxyService.swift
//  CaddieAI
//
//  Client for the backend LLM proxy. Used by paid-tier users so they don't
//  need to supply their own API key. The proxy forces gpt-4o-mini and injects
//  the server-side OpenAI key.
//

import Foundation

final class LLMProxyService: Sendable {

    static let shared = LLMProxyService()

    private let endpoint: URL?
    private let apiKey: String?

    private init() {
        if let urlString = Secrets.llmProxyEndpoint {
            endpoint = URL(string: urlString)
        } else {
            endpoint = nil
        }
        apiKey = Secrets.llmProxyApiKey
    }

    /// Whether the proxy is configured and available for use.
    var isAvailable: Bool {
        endpoint != nil && apiKey != nil && !(apiKey?.isEmpty ?? true)
    }

    // MARK: - Chat Completion

    /// Send a chat completion request through the backend proxy.
    /// Returns the raw OpenAI-format response body.
    func chatCompletion(
        messages: [[String: Any]],
        responseFormat: [String: Any]? = nil,
        maxTokens: Int = 1500,
        temperature: Double = 0.7
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        guard let endpoint, let apiKey else {
            throw ProxyError.notConfigured
        }

        var body: [String: Any] = [
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature,
        ]
        if let responseFormat {
            body["response_format"] = responseFormat
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProxyError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = parseErrorMessage(from: data)
                ?? "Proxy error: HTTP \(httpResponse.statusCode)"
            throw ProxyError.apiError(errorMessage)
        }

        return try extractContentAndUsage(from: data)
    }

    // MARK: - JSON Response (for structured output like ShotRecommendation)

    /// Send a chat completion and decode the content as a ShotRecommendation.
    func chatCompletionJSON(
        messages: [[String: Any]],
        maxTokens: Int = 1500,
        temperature: Double = 0.7
    ) async throws -> (ShotRecommendation, OpenAIService.TokenUsage?) {
        let (content, usage) = try await chatCompletion(
            messages: messages,
            responseFormat: ["type": "json_object"],
            maxTokens: maxTokens,
            temperature: temperature
        )

        guard let contentData = content.data(using: .utf8) else {
            throw ProxyError.apiError("Could not encode response content.")
        }

        let recommendation = try JSONDecoder().decode(ShotRecommendation.self, from: contentData)
        return (recommendation, usage)
    }

    // MARK: - Response Parsing

    private func extractContentAndUsage(from data: Data) throws -> (String, OpenAIService.TokenUsage?) {
        guard let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = responseJSON["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw ProxyError.apiError("Could not parse proxy response structure.")
        }

        var tokenUsage: OpenAIService.TokenUsage?
        if let usage = responseJSON["usage"] as? [String: Any],
           let prompt = usage["prompt_tokens"] as? Int,
           let completion = usage["completion_tokens"] as? Int,
           let total = usage["total_tokens"] as? Int {
            tokenUsage = OpenAIService.TokenUsage(
                promptTokens: prompt, completionTokens: completion, totalTokens: total
            )
        }

        return (content, tokenUsage)
    }

    private func parseErrorMessage(from data: Data) -> String? {
        guard let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = errorBody["error"] as? String
        else {
            return nil
        }
        return error
    }

    // MARK: - Errors

    enum ProxyError: Error, LocalizedError {
        case notConfigured
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "LLM proxy is not configured."
            case .invalidResponse: return "Invalid response from proxy."
            case .apiError(let msg): return msg
            }
        }
    }
}
