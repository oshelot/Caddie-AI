//
//  APIUsageStore.swift
//  CaddieAI
//
//  Tracks API usage for OpenAI and Golf Course API with persistence.
//

import Foundation

// MARK: - Usage Records

struct OpenAIUsageRecord: Codable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let timestamp: Date
    let method: String
}

struct GolfAPIUsageRecord: Codable, Sendable {
    let timestamp: Date
    let method: String
}

// MARK: - Aggregated Data

struct APIUsageData: Codable {
    var openAICalls: [OpenAIUsageRecord] = []
    var golfAPICalls: [GolfAPIUsageRecord] = []
    var golfAPIRateLimitEnabled: Bool = false
    var golfAPIMonthlyLimit: Int = 300

    // MARK: OpenAI Computed

    var openAITotalCalls: Int { openAICalls.count }

    var openAITotalPromptTokens: Int {
        openAICalls.reduce(0) { $0 + $1.promptTokens }
    }

    var openAITotalCompletionTokens: Int {
        openAICalls.reduce(0) { $0 + $1.completionTokens }
    }

    var openAITotalTokens: Int {
        openAICalls.reduce(0) { $0 + $1.totalTokens }
    }

    // MARK: Golf API Computed

    var golfAPITotalCalls: Int { golfAPICalls.count }

    var golfAPICallsThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return golfAPICalls.count
        }
        return golfAPICalls.filter { $0.timestamp >= startOfMonth }.count
    }

    var isGolfAPIOverLimit: Bool {
        golfAPIRateLimitEnabled && golfAPICallsThisMonth >= golfAPIMonthlyLimit
    }

    // MARK: Pruning

    mutating func pruneOldRecords(keepingMonths months: Int = 3) {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .month, value: -months, to: Date()) else { return }
        openAICalls.removeAll { $0.timestamp < cutoff }
        golfAPICalls.removeAll { $0.timestamp < cutoff }
    }
}

// MARK: - Observable Store

@Observable
@MainActor
final class APIUsageStore {
    private static let storageKey = "apiUsageData"

    var data: APIUsageData {
        didSet { save() }
    }

    let sessionStartDate: Date

    init() {
        sessionStartDate = Date()
        if let saved = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(APIUsageData.self, from: saved) {
            data = decoded
        } else {
            data = APIUsageData()
        }
        data.pruneOldRecords()
    }

    // MARK: - Recording

    func recordOpenAIUsage(promptTokens: Int, completionTokens: Int, totalTokens: Int, method: String) {
        let record = OpenAIUsageRecord(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            timestamp: Date(),
            method: method
        )
        data.openAICalls.append(record)
    }

    func recordGolfAPICall(method: String) {
        let record = GolfAPIUsageRecord(timestamp: Date(), method: method)
        data.golfAPICalls.append(record)
    }

    // MARK: - Rate Limiting

    var canMakeGolfAPICall: Bool {
        !data.isGolfAPIOverLimit
    }

    // MARK: - Session Stats

    var openAISessionCalls: Int {
        data.openAICalls.filter { $0.timestamp >= sessionStartDate }.count
    }

    var openAISessionTokens: Int {
        data.openAICalls.filter { $0.timestamp >= sessionStartDate }
            .reduce(0) { $0 + $1.totalTokens }
    }

    // MARK: - Reset

    func resetAll() {
        data = APIUsageData(golfAPIRateLimitEnabled: data.golfAPIRateLimitEnabled,
                            golfAPIMonthlyLimit: data.golfAPIMonthlyLimit)
    }

    // MARK: - Persistence

    private func save() {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.storageKey)
    }
}
