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
            LoggingService.shared.error(.network, "LLM proxy HTTP \(httpResponse.statusCode)", metadata: [
                "statusCode": "\(httpResponse.statusCode)",
                "error": errorMessage,
            ])
            throw ProxyError.apiError(errorMessage)
        }

        return try extractContentAndUsage(from: data)
    }

    // MARK: - Streaming Chat Completion

    /// Streaming result containing the accumulated text and optional usage.
    struct StreamResult: Sendable {
        var text: String = ""
        var usage: OpenAIService.TokenUsage?
    }

    /// Send a streaming chat completion through the backend proxy.
    /// Calls `onChunk` on the main actor with each accumulated text string.
    /// Returns the final accumulated text and token usage.
    func chatCompletionStream(
        messages: [[String: Any]],
        maxTokens: Int = 500,
        temperature: Double = 0.7,
        onChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (String, OpenAIService.TokenUsage?) {
        guard let endpoint, let apiKey else {
            throw ProxyError.notConfigured
        }

        let body: [String: Any] = [
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": true,
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProxyError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            // Collect error body
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let errorMessage = parseErrorMessage(from: errorData)
                ?? "Proxy error: HTTP \(httpResponse.statusCode)"
            throw ProxyError.apiError(errorMessage)
        }

        var accumulated = ""
        var tokenUsage: OpenAIService.TokenUsage?

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data: ") else { continue }
            let payload = String(trimmed.dropFirst(6))

            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let content = json["content"] as? String {
                accumulated += content
                await onChunk(accumulated)
            }

            if let usage = json["usage"] as? [String: Any],
               let prompt = usage["prompt_tokens"] as? Int,
               let completion = usage["completion_tokens"] as? Int,
               let total = usage["total_tokens"] as? Int {
                tokenUsage = OpenAIService.TokenUsage(
                    promptTokens: prompt, completionTokens: completion, totalTokens: total
                )
            }
        }

        return (accumulated, tokenUsage)
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
