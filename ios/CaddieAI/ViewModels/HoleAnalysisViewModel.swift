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
    var weather: WeatherData?
    var weatherError: String?
    var apiUsageStore: APIUsageStore?
    var subscriptionManager: SubscriptionManager?

    /// LLM round-trip latency in milliseconds (debug builds only).
    var llmLatencyMs: Int?
    /// Deterministic engine latency in milliseconds (debug builds only).
    var engineLatencyMs: Int?

    private var conversationHistory: [OpenAIService.ChatMessage] = []

    // MARK: - Analyze Hole

    func analyzeHole(
        _ hole: NormalizedHole,
        course: NormalizedCourse,
        profile: PlayerProfile,
        selectedTee: String? = nil
    ) async {
        LoggingService.shared.info(.course, "Hole analysis started", metadata: [
            "hole": "\(hole.number)",
            "par": "\(hole.par)",
            "course": course.name,
        ])

        isAnalyzing = true
        error = nil
        followUpResponse = nil
        conversationHistory = []
        weatherError = nil
        llmLatencyMs = nil
        engineLatencyMs = nil

        // Fetch weather (best-effort)
        let weatherData: WeatherData?
        do {
            weatherData = try await WeatherService.fetchWeather(
                latitude: course.centroid.latitude,
                longitude: course.centroid.longitude
            )
            weather = weatherData
        } catch {
            weatherData = nil
            weatherError = "Weather unavailable"
            LoggingService.shared.warning(.weather, "Weather fetch failed for hole analysis: \(error.localizedDescription)")
        }

        // Compute hole-specific weather context
        let weatherContext: HoleWeatherContext?
        if let wd = weatherData {
            weatherContext = HoleAnalysisEngine.buildWeatherContext(
                weather: wd,
                hole: hole
            )
        } else {
            weatherContext = nil
        }

        // Tier 1: Deterministic analysis (instant, on-device)
        let engineStart = CFAbsoluteTimeGetCurrent()
        var result = HoleAnalysisEngine.analyze(
            hole: hole,
            course: course,
            profile: profile,
            weatherContext: weatherContext,
            selectedTee: selectedTee
        )
        engineLatencyMs = Int((CFAbsoluteTimeGetCurrent() - engineStart) * 1000)
        analysis = result

        // Tier 2: LLM caddie narrative (async)
        let trimmedKey = profile.activeLLMApiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else {
            // No API key — use deterministic summary only
            isAnalyzing = false
            return
        }

        let llmStart = CFAbsoluteTimeGetCurrent()
        do {
            let tier = subscriptionManager?.tier ?? .free
            let (advice, usage) = try await LLMRouter.shared.getHoleAnalysis(
                hole: hole,
                analysis: result,
                course: course,
                profile: profile,
                tier: tier,
                selectedTee: selectedTee
            )
            if let usage, let store = apiUsageStore {
                await MainActor.run {
                    store.recordLLMUsage(
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens,
                        totalTokens: usage.totalTokens,
                        method: "getHoleAnalysis",
                        provider: profile.llmProvider
                    )
                }
                TelemetryService.shared.recordLLMCall(
                    provider: profile.llmProvider.rawValue,
                    model: profile.llmModel.rawValue,
                    method: "getHoleAnalysis",
                    promptTokens: usage.promptTokens,
                    completionTokens: usage.completionTokens,
                    totalTokens: usage.totalTokens
                )
            }
            llmLatencyMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1000)
            result.strategicAdvice = advice
            analysis = result

            // Store conversation history for follow-ups
            conversationHistory = [
                OpenAIService.ChatMessage(
                    role: "system",
                    content: OpenAIService.holeAnalysisSystemPrompt(persona: profile.caddiePersona)
                ),
                OpenAIService.ChatMessage(
                    role: "user",
                    content: OpenAIService.buildHoleAnalysisMessage(
                        hole: hole,
                        analysis: result,
                        course: course,
                        profile: profile,
                        selectedTee: selectedTee
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
            LoggingService.shared.error(.llm, "getHoleAnalysis failed: \(error.localizedDescription)", metadata: [
                "provider": profile.llmProvider.rawValue,
                "model": profile.llmModel.rawValue,
                "tier": (subscriptionManager?.tier ?? .free).rawValue,
                "hole": "\(hole.number)",
            ])
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
            let tier = subscriptionManager?.tier ?? .free
            let (response, usage) = try await LLMRouter.shared.askHoleFollowUp(
                question: question,
                conversationHistory: conversationHistory,
                apiKey: profile.activeLLMApiKey,
                provider: profile.llmProvider,
                model: profile.llmModel,
                tier: tier
            )
            if let usage, let store = apiUsageStore {
                await MainActor.run {
                    store.recordLLMUsage(
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens,
                        totalTokens: usage.totalTokens,
                        method: "askHoleFollowUp",
                        provider: profile.llmProvider
                    )
                }
                TelemetryService.shared.recordLLMCall(
                    provider: profile.llmProvider.rawValue,
                    model: profile.llmModel.rawValue,
                    method: "askHoleFollowUp",
                    promptTokens: usage.promptTokens,
                    completionTokens: usage.completionTokens,
                    totalTokens: usage.totalTokens
                )
            }
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
            LoggingService.shared.error(.llm, "askHoleFollowUp failed: \(error.localizedDescription)", metadata: [
                "provider": profile.llmProvider.rawValue,
                "model": profile.llmModel.rawValue,
            ])
        }

        isAskingFollowUp = false
    }
}
